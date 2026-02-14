import { NextResponse } from 'next/server';
import { execSync } from 'child_process';
import { pushToSkyNet } from '@/lib/skynet-bridge';
import { addSnapshot, getRawHistory } from '@/lib/metrics-history';
import { detectIssues } from '@/lib/issue-detector';
import { reportIssues } from '@/lib/issue-reporter';
import { updateActiveIssues } from '@/app/api/issues/route';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

// Module-level storage for issue detection
let previousMetrics: any = null;

function getRpcUrl() { return process.env.RPC_URL || 'http://xdc-node:8545'; }
function getMainnetRpc() { return process.env.MAINNET_RPC || 'https://erpc.xinfin.network'; }

/**
 * Get the public IPv4 address of the server
 * Prefers non-internal IPv4 addresses from network interfaces
 */
function getPublicIPv4(): string {
  try {
    const os = require('os');
    const nets = os.networkInterfaces();
    for (const name of Object.keys(nets)) {
      for (const net of nets[name]) {
        // Skip internal addresses and IPv6
        if (net.family === 'IPv4' && !net.internal) {
          return net.address;
        }
      }
    }
  } catch {}
  return '0.0.0.0';
}

async function rpcCall(url: string, method: string, params: unknown[] = []): Promise<{ result: unknown; error: string | null }> {
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', method, params, id: 1 }),
      signal: AbortSignal.timeout(5000),
    });
    const data = await res.json();
    if (data.error) return { result: null, error: data.error.message || JSON.stringify(data.error) };
    return { result: data.result, error: null };
  } catch (e) { return { result: null, error: (e as Error).message }; }
}

function hexToNumber(hex: string | null | undefined): number {
  if (!hex || hex === '0x' || hex === 'null') return 0;
  return parseInt(hex as string, 16) || 0;
}

function parseClientType(clientName: string): 'geth' | 'erigon' | 'geth-pr5' | 'unknown' {
  const lower = clientName.toLowerCase();
  if (lower.includes('erigon')) return 'erigon';
  if (lower.includes('pr5') || lower.includes('pr-5')) return 'geth-pr5';
  if (lower.includes('xdc') || lower.includes('geth')) return 'geth';
  return 'unknown';
}

function getStorageMetrics(): { chainDataSize: number; databaseSize: number } {
  let chainDataSize = 0;
  let databaseSize = 0;
  
  try {
    // Try different paths for chaindata
    const paths = ['/work/xdcchain/XDC/chaindata', '/work/xdcchain/chaindata', '/work/xdcchain'];
    for (const p of paths) {
      try {
        const size = execSync(`du -sb ${p} 2>/dev/null | cut -f1`, { timeout: 10000 }).toString().trim();
        if (size && parseInt(size) > 0) {
          if (p.includes('chaindata')) {
            chainDataSize = parseInt(size);
            break;
          }
        }
      } catch {}
    }
    
    // Get total DB directory size
    try {
      const dbSizeStr = execSync(`du -sb /work/xdcchain 2>/dev/null | cut -f1`, { timeout: 10000 }).toString().trim();
      if (dbSizeStr && parseInt(dbSizeStr) > 0) {
        databaseSize = parseInt(dbSizeStr);
      }
    } catch {}
  } catch {}
  
  return { chainDataSize, databaseSize };
}

function getServerStats() {
  const fs = require('fs');
  const procPath = fs.existsSync('/host/proc/stat') ? '/host/proc' : '/proc';
  let cpuUsage = 0, memUsed = 0, memTotal = 0, diskUsed = 0, diskTotal = 0;
  
  try {
    const stat = fs.readFileSync(`${procPath}/stat`, 'utf8');
    const cpuLine = stat.split('\n')[0].split(/\s+/);
    const user = parseInt(cpuLine[1]), system = parseInt(cpuLine[3]), idle = parseInt(cpuLine[4]);
    const total = user + parseInt(cpuLine[2]) + system + idle + parseInt(cpuLine[5]) + parseInt(cpuLine[6]) + parseInt(cpuLine[7]);
    cpuUsage = Math.round(((total - idle) / total) * 100);
  } catch {}
  
  try {
    const meminfo = fs.readFileSync(`${procPath}/meminfo`, 'utf8');
    const totalMatch = meminfo.match(/MemTotal:\s+(\d+)/);
    const availMatch = meminfo.match(/MemAvailable:\s+(\d+)/);
    if (totalMatch) memTotal = parseInt(totalMatch[1]) * 1024;
    if (availMatch) memUsed = memTotal - (parseInt(availMatch[1]) * 1024);
  } catch {}
  
  try {
    const df = execSync('df -B1 / 2>/dev/null', { timeout: 3000 }).toString();
    const parts = df.split('\n')[1]?.split(/\s+/);
    if (parts) { diskTotal = parseInt(parts[1]) || 0; diskUsed = parseInt(parts[2]) || 0; }
  } catch {}
  
  return { cpuUsage, memUsed, memTotal, diskUsed, diskTotal };
}

async function dockerApiGet(path: string): Promise<any> {
  // Call Docker API via unix socket using Node.js http module
  return new Promise((resolve) => {
    const http = require('http');
    const options = { socketPath: '/var/run/docker.sock', path, timeout: 5000 };
    const req = http.get(options, (res: any) => {
      let data = '';
      res.on('data', (chunk: string) => { data += chunk; });
      res.on('end', () => { try { resolve(JSON.parse(data)); } catch { resolve(null); } });
    });
    req.on('error', () => resolve(null));
    req.on('timeout', () => { req.destroy(); resolve(null); });
  });
}

async function getNodeDiagnostics(): Promise<{ containerStatus: string; recentLogs: string[]; errors: string[]; lastBlock: string }> {
  const diag = { containerStatus: 'unknown', recentLogs: [] as string[], errors: [] as string[], lastBlock: '' };
  
  try {
    // Get container status via Docker API
    const inspect = await dockerApiGet('/containers/xdc-node/json');
    if (inspect?.State) {
      const s = inspect.State;
      diag.containerStatus = `${s.Status}${s.Health ? ' (' + s.Health.Status + ')' : ''}`;
      if (s.Status === 'exited') diag.containerStatus += ` (exit code: ${s.ExitCode})`;
    }
  } catch { diag.containerStatus = 'unknown'; }
  
  try {
    // Get recent logs via Docker API
    const http = require('http');
    const logs: string = await new Promise((resolve) => {
      const options = { socketPath: '/var/run/docker.sock', path: '/containers/xdc-node/logs?stdout=1&stderr=1&tail=30', timeout: 5000 };
      const req = http.get(options, (res: any) => {
        let data = '';
        res.on('data', (chunk: Buffer) => { 
          // Docker log stream has 8-byte header per frame, strip it
          const str = chunk.toString('utf8');
          data += str;
        });
        res.on('end', () => resolve(data));
      });
      req.on('error', () => resolve(''));
      req.on('timeout', () => { req.destroy(); resolve(''); });
    });
    
    // Clean Docker stream headers (8-byte prefix per line) and filter
    diag.recentLogs = logs.split('\n')
      .map(l => l.replace(/^[\x00-\x08].{0,7}/, '').trim())
      .filter(l => l.length > 0)
      .slice(-20);
    
    // Extract errors
    diag.errors = diag.recentLogs.filter(l => 
      l.includes('ERROR') || l.includes('BAD BLOCK') || l.includes('FATAL') || l.includes('Synchronisation failed')
    );
    
    // Find last synced block from logs
    const allLogs = diag.recentLogs.join('\n');
    const blockMatch = allLogs.match(/Number:\s*(\d+)/);
    if (blockMatch) diag.lastBlock = blockMatch[1];
    const importMatch = allLogs.match(/Imported new chain segment.*number[= ]+(\d+)/);
    if (importMatch) diag.lastBlock = importMatch[1];
  } catch {}
  
  return diag;
}

export async function GET() {
  try {
    // Parallel RPC calls
    const [
      blockNumberRes,
      syncingRes,
      peerCountRes,
      nodeInfoRes,
      coinbaseRes,
      txpoolRes,
      peersRes,
      mainnetBlockRes,
    ] = await Promise.all([
      rpcCall(getRpcUrl(), 'eth_blockNumber'),
      rpcCall(getRpcUrl(), 'eth_syncing'),
      rpcCall(getRpcUrl(), 'net_peerCount'),
      rpcCall(getRpcUrl(), 'admin_nodeInfo'),
      rpcCall(getRpcUrl(), 'eth_coinbase'),
      rpcCall(getRpcUrl(), 'txpool_status'),
      rpcCall(getRpcUrl(), 'admin_peers'),
      rpcCall(getMainnetRpc(), 'eth_blockNumber'),
    ]);

    // Determine if RPC is reachable
    const rpcConnected = blockNumberRes.error === null;
    
    const blockHeight = hexToNumber(blockNumberRes.result as string);
    const mainnetHeight = hexToNumber(mainnetBlockRes.result as string);
    const peers = hexToNumber(peerCountRes.result as string);
    const nodeInfo = (nodeInfoRes.result || {}) as Record<string, any>;
    const coinbase = (coinbaseRes.result as string) || '';
    const txpool = (txpoolRes.result || {}) as Record<string, string>;
    const peersList = (peersRes.result || []) as Array<Record<string, any>>;
    
    // Sync info
    let isSyncing = false;
    let highestBlock = mainnetHeight || blockHeight;
    if (syncingRes.result && typeof syncingRes.result === 'object') {
      isSyncing = true;
      const syncData = syncingRes.result as Record<string, string>;
      highestBlock = hexToNumber(syncData.highestBlock) || highestBlock;
    }
    const syncPercent = highestBlock > 0 ? Math.min(100, (blockHeight / highestBlock) * 100) : (blockHeight === 0 ? 0 : 100);
    
    // Peer breakdown
    const inbound = peersList.filter(p => p.network?.inbound === true).length;
    const outbound = peersList.length - inbound;
    
    // Server stats
    const server = getServerStats();
    
    // Epoch
    const epoch = Math.floor(blockHeight / 900);
    const epochProgress = ((blockHeight % 900) / 900) * 100;
    
    // Determine masternode status based on coinbase
    const hasCoinbase = coinbase && coinbase !== '' && coinbase !== '0x' && coinbase !== '0x0000000000000000000000000000000000000000';
    const masternodeStatus = hasCoinbase ? 'Active' : 'Not Configured';
    
    // Estimate block time (XDC has 2 second block time)
    const blockTime = 2.0;
    
    // Get diagnostics (especially useful when RPC is down)
    const diagnostics = !rpcConnected ? await getNodeDiagnostics() : { containerStatus: 'running healthy', recentLogs: [], errors: [], lastBlock: '' };
    
    // Node status determination
    let nodeStatus: 'online' | 'syncing' | 'error' | 'offline' = 'online';
    if (!rpcConnected) {
      nodeStatus = 'offline';
    } else if (isSyncing || (mainnetHeight > 0 && blockHeight < mainnetHeight * 0.99)) {
      nodeStatus = 'syncing';
    }
    if (diagnostics.errors.length > 0) {
      nodeStatus = 'error';
    }
    
    // Parse client type from nodeInfo
    const clientType = parseClientType((nodeInfo.name as string) || '');
    
    // Get storage metrics (may be slow, runs in background)
    const storageMetrics = getStorageMetrics();
    
    // Node config from environment
    const nodeConfig = {
      clientType,
      nodeType: (process.env.NODE_TYPE || 'full') as 'full' | 'fast' | 'snap' | 'archive',
      syncMode: process.env.SYNC_MODE || 'full',
    };

    const response = {
      // Node status overview
      nodeStatus,
      rpcConnected,
      rpcUrl: getRpcUrl(),
      rpcError: blockNumberRes.error,
      ipv4: getPublicIPv4(), // Public IPv4 address for display
      
      // Diagnostics (shows even when RPC is dead)
      diagnostics: {
        containerStatus: diagnostics.containerStatus,
        recentLogs: diagnostics.recentLogs,
        errors: diagnostics.errors,
        lastKnownBlock: diagnostics.lastBlock || (blockHeight > 0 ? String(blockHeight) : '0'),
      },
      
      // Node configuration
      nodeConfig,
      
      blockchain: {
        blockHeight,
        highestBlock,
        syncPercent: Math.round(syncPercent * 10) / 10,
        isSyncing,
        peers,
        peersInbound: inbound,
        peersOutbound: outbound,
        uptime: 0,
        chainId: '50',
        coinbase: coinbase ? coinbase.replace('0x', 'xdc') : '',
        ethstatsName: process.env.NODE_NAME || '',
        clientVersion: (nodeInfo.name as string) || '',
        clientType,
      },
      consensus: {
        epoch,
        epochProgress: Math.round(epochProgress * 10) / 10,
        masternodeStatus,
        coinbase: coinbase ? coinbase.replace('0x', 'xdc') : '',
        blockTime,
        signingRate: 0, stakeAmount: 0, walletBalance: 0, totalRewards: 0, penalties: 0,
      },
      sync: { syncRate: 0, reorgsAdd: 0, reorgsDrop: 0 },
      txpool: {
        pending: hexToNumber(txpool?.pending),
        queued: hexToNumber(txpool?.queued),
        isSyncing,
        available: txpoolRes.result !== null && txpoolRes.error === null,
        slots: 0, valid: 0, invalid: 0, underpriced: 0,
      },
      server: {
        cpuUsage: server.cpuUsage, memoryUsed: server.memUsed, memoryTotal: server.memTotal,
        diskUsed: server.diskUsed, diskTotal: server.diskTotal,
        goroutines: 0, sysLoad: 0, procLoad: 0,
      },
      storage: { 
        chainDataSize: storageMetrics.chainDataSize,
        databaseSize: storageMetrics.databaseSize,
        diskReadRate: 0, 
        diskWriteRate: 0, 
        compactTime: 0, 
        trieCacheHitRate: 0, 
        trieCacheMiss: 0 
      },
      network: {
        totalPeers: peers, inboundTraffic: 0, outboundTraffic: 0,
        dialSuccess: 0, dialTotal: 0, eth100Traffic: 0, eth63Traffic: 0, connectionErrors: 0,
      },
      timestamp: new Date().toISOString(),
    };

    // Add snapshot to history buffer
    addSnapshot({
      timestamp: response.timestamp,
      blockHeight: response.blockchain.blockHeight,
      peers: response.blockchain.peers,
      cpu: response.server.cpuUsage,
      memory: response.server.memoryTotal > 0 ? (response.server.memoryUsed / response.server.memoryTotal) * 100 : 0,
      disk: response.server.diskTotal > 0 ? (response.server.diskUsed / response.server.diskTotal) * 100 : 0,
      syncPercent: response.blockchain.syncPercent,
      txPoolPending: response.txpool.pending,
    });

    // Detect issues and report to SkyNet
    const metricsHistory = getRawHistory();
    const detectedIssues = detectIssues(response, previousMetrics, metricsHistory);
    
    // Update active issues tracker
    updateActiveIssues(detectedIssues);
    
    // Report to SkyNet (fire and forget)
    reportIssues(detectedIssues).catch(() => {});
    
    // Update previous metrics for next check
    previousMetrics = response;
    
    // Add active issues count to response
    const responseWithIssues = {
      ...response,
      activeIssues: detectedIssues.length,
    };

    // Push to SkyNet (fire and forget — don't await, don't block response)
    pushToSkyNet(responseWithIssues).catch(() => {});

    return NextResponse.json(responseWithIssues);
  } catch (error) {
    // Even on total failure, return diagnostics
    const diagnostics = await getNodeDiagnostics();
    const server = getServerStats();
    return NextResponse.json({
      nodeStatus: 'offline',
      rpcConnected: false,
      rpcUrl: getRpcUrl(),
      rpcError: (error as Error).message,
      ipv4: getPublicIPv4(),
      diagnostics: {
        containerStatus: diagnostics.containerStatus,
        recentLogs: diagnostics.recentLogs,
        errors: diagnostics.errors,
        lastKnownBlock: diagnostics.lastBlock || '0',
      },
      blockchain: { blockHeight: 0, highestBlock: 0, syncPercent: 0, isSyncing: false, peers: 0, peersInbound: 0, peersOutbound: 0, uptime: 0, chainId: '50', coinbase: '', ethstatsName: '', clientVersion: '', clientType: 'unknown' },
      consensus: { epoch: 0, epochProgress: 0, masternodeStatus: 'Not Configured', coinbase: '', blockTime: 0, signingRate: 0, stakeAmount: 0, walletBalance: 0, totalRewards: 0, penalties: 0 },
      sync: { syncRate: 0, reorgsAdd: 0, reorgsDrop: 0 },
      txpool: { pending: 0, queued: 0, isSyncing: false, available: false, slots: 0, valid: 0, invalid: 0, underpriced: 0 },
      server: { cpuUsage: server.cpuUsage, memoryUsed: server.memUsed, memoryTotal: server.memTotal, diskUsed: server.diskUsed, diskTotal: server.diskTotal, goroutines: 0, sysLoad: 0, procLoad: 0 },
      storage: { chainDataSize: 0, databaseSize: 0, diskReadRate: 0, diskWriteRate: 0, compactTime: 0, trieCacheHitRate: 0, trieCacheMiss: 0 },
      network: { totalPeers: 0, inboundTraffic: 0, outboundTraffic: 0, dialSuccess: 0, dialTotal: 0, eth100Traffic: 0, eth63Traffic: 0, connectionErrors: 0 },
      timestamp: new Date().toISOString(),
    });
  }
}
