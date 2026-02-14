import { NextResponse } from 'next/server';
import { execSync } from 'child_process';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

function getRpcUrl() { return process.env.RPC_URL || 'http://xdc-node:8545'; }
function getMainnetRpc() { return process.env.MAINNET_RPC || 'https://erpc.xinfin.network'; }

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

function getNodeDiagnostics(): { containerStatus: string; recentLogs: string[]; errors: string[]; lastBlock: string } {
  const diag = { containerStatus: 'unknown', recentLogs: [] as string[], errors: [] as string[], lastBlock: '' };
  
  try {
    // Get container status
    const status = execSync('docker inspect xdc-node --format "{{.State.Status}} {{.State.Health.Status}}" 2>/dev/null', { timeout: 3000 }).toString().trim();
    diag.containerStatus = status;
  } catch {
    try {
      // Maybe we're inside Docker and can't access docker socket — check if node process exists
      const ps = execSync('ps aux 2>/dev/null | grep -i "XDC\\|geth" | grep -v grep | head -1', { timeout: 2000 }).toString().trim();
      diag.containerStatus = ps ? 'running (process)' : 'not running';
    } catch { diag.containerStatus = 'unknown'; }
  }
  
  try {
    // Get recent logs (last 20 lines)
    const logs = execSync('docker logs xdc-node --tail 20 2>&1', { timeout: 5000 }).toString();
    diag.recentLogs = logs.split('\n').filter(l => l.trim()).slice(-15);
    
    // Extract errors
    diag.errors = diag.recentLogs.filter(l => 
      l.includes('ERROR') || l.includes('BAD BLOCK') || l.includes('FATAL') || l.includes('Synchronisation failed')
    );
    
    // Try to find last synced block from logs
    const blockMatch = logs.match(/Number:\s*(\d+)/);
    if (blockMatch) diag.lastBlock = blockMatch[1];
    
    // Also check for block height in imported logs
    const importMatch = logs.match(/Imported new chain segment.*number[= ]+(\d+)/);
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
    
    // Get diagnostics (especially useful when RPC is down)
    const diagnostics = !rpcConnected ? getNodeDiagnostics() : { containerStatus: 'running healthy', recentLogs: [], errors: [], lastBlock: '' };
    
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

    const response = {
      // Node status overview
      nodeStatus,
      rpcConnected,
      rpcUrl: getRpcUrl(),
      rpcError: blockNumberRes.error,
      
      // Diagnostics (shows even when RPC is dead)
      diagnostics: {
        containerStatus: diagnostics.containerStatus,
        recentLogs: diagnostics.recentLogs,
        errors: diagnostics.errors,
        lastKnownBlock: diagnostics.lastBlock || (blockHeight > 0 ? String(blockHeight) : '0'),
      },
      
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
      },
      consensus: {
        epoch,
        epochProgress: Math.round(epochProgress * 10) / 10,
        masternodeStatus: 'Inactive' as string,
        signingRate: 0, stakeAmount: 0, walletBalance: 0, totalRewards: 0, penalties: 0,
      },
      sync: { syncRate: 0, reorgsAdd: 0, reorgsDrop: 0 },
      txpool: {
        pending: hexToNumber(txpool.pending), queued: hexToNumber(txpool.queued),
        slots: 0, valid: 0, invalid: 0, underpriced: 0,
      },
      server: {
        cpuUsage: server.cpuUsage, memoryUsed: server.memUsed, memoryTotal: server.memTotal,
        diskUsed: server.diskUsed, diskTotal: server.diskTotal,
        goroutines: 0, sysLoad: 0, procLoad: 0,
      },
      storage: { chainDataSize: 0, diskReadRate: 0, diskWriteRate: 0, compactTime: 0, trieCacheHitRate: 0, trieCacheMiss: 0 },
      network: {
        totalPeers: peers, inboundTraffic: 0, outboundTraffic: 0,
        dialSuccess: 0, dialTotal: 0, eth100Traffic: 0, eth63Traffic: 0, connectionErrors: 0,
      },
      timestamp: new Date().toISOString(),
    };

    return NextResponse.json(response);
  } catch (error) {
    // Even on total failure, return diagnostics
    const diagnostics = getNodeDiagnostics();
    const server = getServerStats();
    return NextResponse.json({
      nodeStatus: 'offline',
      rpcConnected: false,
      rpcUrl: getRpcUrl(),
      rpcError: (error as Error).message,
      diagnostics: {
        containerStatus: diagnostics.containerStatus,
        recentLogs: diagnostics.recentLogs,
        errors: diagnostics.errors,
        lastKnownBlock: diagnostics.lastBlock || '0',
      },
      blockchain: { blockHeight: 0, highestBlock: 0, syncPercent: 0, isSyncing: false, peers: 0, peersInbound: 0, peersOutbound: 0, uptime: 0, chainId: '50', coinbase: '', ethstatsName: '', clientVersion: '' },
      consensus: { epoch: 0, epochProgress: 0, masternodeStatus: 'Inactive', signingRate: 0, stakeAmount: 0, walletBalance: 0, totalRewards: 0, penalties: 0 },
      sync: { syncRate: 0, reorgsAdd: 0, reorgsDrop: 0 },
      txpool: { pending: 0, queued: 0, slots: 0, valid: 0, invalid: 0, underpriced: 0 },
      server: { cpuUsage: server.cpuUsage, memoryUsed: server.memUsed, memoryTotal: server.memTotal, diskUsed: server.diskUsed, diskTotal: server.diskTotal, goroutines: 0, sysLoad: 0, procLoad: 0 },
      storage: { chainDataSize: 0, diskReadRate: 0, diskWriteRate: 0, compactTime: 0, trieCacheHitRate: 0, trieCacheMiss: 0 },
      network: { totalPeers: 0, inboundTraffic: 0, outboundTraffic: 0, dialSuccess: 0, dialTotal: 0, eth100Traffic: 0, eth63Traffic: 0, connectionErrors: 0 },
      timestamp: new Date().toISOString(),
    });
  }
}
