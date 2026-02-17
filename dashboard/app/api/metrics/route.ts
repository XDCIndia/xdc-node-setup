import { NextResponse } from 'next/server';
import { execFile } from 'child_process';
import { promisify } from 'util';
import { pushToSkyNet } from '@/lib/skynet-bridge';
import { addSnapshot, getRawHistory } from '@/lib/metrics-history';
import { detectIssues, DetectedIssue } from '@/lib/issue-detector';
import { reportIssues } from '@/lib/issue-reporter';
import { lfgCheck } from '@/lib/lfg';

const execFileAsync = promisify(execFile);

export const dynamic = 'force-dynamic';
export const revalidate = 0;

// Module-level storage for issue detection
let previousMetrics: any = null;

// Global type declaration for updateActiveIssues
declare global {
  var updateActiveIssues: ((issues: DetectedIssue[]) => void) | undefined;
}

function getRpcUrl() { return process.env.RPC_URL || 'http://xdc-node:8545'; }
function getMainnetRpc() { return process.env.MAINNET_RPC || 'https://erpc.xinfin.network'; }

/**
 * Read watchdog state for stall tracking
 */
async function getWatchdogState(): Promise<{ stallHours: number; stalledAtBlock: number }> {
  try {
    const fs = await import('fs');
    const stateFile = '/tmp/xdc-watchdog-state.json';
    if (fs.existsSync(stateFile)) {
      const content = fs.readFileSync(stateFile, 'utf-8');
      const state = JSON.parse(content);
      const now = Math.floor(Date.now() / 1000);
      const stallStart = state.stallStartTime || 0;
      const stalledAtBlock = state.stalledAtBlock || 0;
      
      if (stallStart > 0 && stalledAtBlock > 0) {
        const stallDuration = now - stallStart;
        const stallHours = stallDuration / 3600;
        return { stallHours, stalledAtBlock };
      }
    }
  } catch {}
  return { stallHours: 0, stalledAtBlock: 0 };
}

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

function parseClientType(clientName: string): 'geth' | 'erigon' | 'geth-pr5' | 'nethermind' | 'unknown' {
  const lower = clientName.toLowerCase();
  if (lower.includes('nethermind')) return 'nethermind';
  if (lower.includes('erigon')) return 'erigon';
  if (lower.includes('pr5') || lower.includes('pr-5')) return 'geth-pr5';
  if (lower.includes('xdc') || lower.includes('geth')) return 'geth';
  return 'unknown';
}

function parseNetworkName(chainId: string | number): string {
  const id = typeof chainId === 'string' ? parseInt(chainId) : chainId;
  if (id === 50) return 'XDC Mainnet';
  if (id === 51) return 'XDC Apothem Testnet';
  if (id === 551) return 'XDC Devnet';
  return `Chain ${id}`;
}

function parseSyncMode(clientVersion: string, clientType: string): string {
  // For Nethermind, check config-based sync mode
  if (clientType === 'nethermind') {
    return process.env.SYNC_MODE || 'full';
  }
  // For geth/erigon, check env or default
  return process.env.SYNC_MODE || 'full';
}

interface StorageMetrics {
  chainDataSize: number;
  databaseSize: number;
  dataDir: string;
  mountPoint: string;
  filesystem: string;
  device: string;
  mountTotal: number;
  mountUsed: number;
  mountAvail: number;
  mountPercent: number;
  allMounts: Array<{ device: string; mount: string; total: number; used: number; avail: number; percent: number; filesystem: string }>;
}

// Allowed paths for disk usage checks (whitelist)
const ALLOWED_DATA_PATHS = ['/work/xdcchain', '/work/xdcchain/XDC', '/work/xdcchain/XDC/chaindata', '/work/xdcchain/chaindata', '/data'];

async function getStorageMetrics(): Promise<StorageMetrics> {
  let chainDataSize = 0;
  let databaseSize = 0;
  let dataDir = '';
  let mountPoint = '';
  let filesystem = '';
  let device = '';
  let mountTotal = 0, mountUsed = 0, mountAvail = 0, mountPercent = 0;
  const allMounts: StorageMetrics['allMounts'] = [];
  const fs = await import('fs');
  
  try {
    // Try different paths for chaindata using Node.js fs (safe, no shell)
    for (const p of ALLOWED_DATA_PATHS) {
      try {
        if (fs.existsSync(p)) {
          // Use find with hardcoded args for safer size calculation
          const { stdout } = await execFileAsync('find', [p, '-type', 'f', '-printf', '%s\n'], { timeout: 10000 });
          const sizes = stdout.trim().split('\n').filter(Boolean);
          const size = sizes.reduce((sum, s) => sum + parseInt(s, 10), 0);
          
          if (size > 0 && p.includes('chaindata')) {
            chainDataSize = size;
            dataDir = p;
            break;
          }
        }
      } catch {}
    }
    if (!dataDir) dataDir = ALLOWED_DATA_PATHS[0];
    
    // Get total DB directory size using find (safe)
    try {
      const { stdout } = await execFileAsync('find', [ALLOWED_DATA_PATHS[0], '-type', 'f', '-printf', '%s\n'], { timeout: 10000 });
      const sizes = stdout.trim().split('\n').filter(Boolean);
      databaseSize = sizes.reduce((sum, s) => sum + parseInt(s, 10), 0);
    } catch {}
    
    // Get mount info for the chaindata directory using df with safe args
    try {
      const { stdout } = await execFileAsync('df', ['-BG', dataDir], { timeout: 3000 });
      const lines = stdout.trim().split('\n');
      if (lines.length >= 2) {
        const dataLine = lines[1];
        const parts = dataLine.split(/\s+/);
        if (parts.length >= 6) {
          device = parts[0];
          mountTotal = parseFloat(parts[1]) * 1024 * 1024 * 1024; // G to bytes
          mountUsed = parseFloat(parts[2]) * 1024 * 1024 * 1024;
          mountAvail = parseFloat(parts[3]) * 1024 * 1024 * 1024;
          mountPercent = parseInt(parts[4]);
          mountPoint = parts[5];
        }
      }
    } catch {}
    
    // Get filesystem type using mount command with safe parsing
    try {
      if (mountPoint) {
        const { stdout } = await execFileAsync('mount', [], { timeout: 3000 });
        const lines = stdout.split('\n');
        for (const line of lines) {
          if (line.includes(` on ${mountPoint} `)) {
            const fsMatch = line.match(/type (\S+)/);
            if (fsMatch) {
              filesystem = fsMatch[1];
              break;
            }
          }
        }
      }
    } catch {}
    
    // Get all mounted storage volumes using df with safe args
    try {
      const { stdout } = await execFileAsync('df', ['-BG', '-T'], { timeout: 3000 });
      const lines = stdout.trim().split('\n').slice(1); // Skip header
      for (const line of lines) {
        const p = line.trim().split(/\s+/);
        if (p.length >= 7 && !p[0].startsWith('none') && !['tmpfs', 'devtmpfs', 'overlay'].includes(p[1])) {
          allMounts.push({
            device: p[0],
            filesystem: p[1],
            total: parseFloat(p[2]) * 1024 * 1024 * 1024,
            used: parseFloat(p[3]) * 1024 * 1024 * 1024,
            avail: parseFloat(p[4]) * 1024 * 1024 * 1024,
            percent: parseInt(p[5]),
            mount: p[6],
          });
        }
      }
    } catch {}
  } catch {}
  
  return { chainDataSize, databaseSize, dataDir, mountPoint, filesystem, device, mountTotal, mountUsed, mountAvail, mountPercent, allMounts };
}

async function getServerStats() {
  const fs = await import('fs');
  const procPath = fs.existsSync('/host/proc/stat') ? '/host/proc' : '/proc';
  let cpuUsage = 0, memUsed = 0, memTotal = 0, diskUsed = 0, diskTotal = 0;
  let storageType = 'unknown', storageModel = '';
  
  // CPU from /proc/stat (works on Linux host + bind-mounted /host/proc)
  try {
    const stat = fs.readFileSync(`${procPath}/stat`, 'utf8');
    const cpuLine = stat.split('\n')[0].split(/\s+/);
    const user = parseInt(cpuLine[1]), system = parseInt(cpuLine[3]), idle = parseInt(cpuLine[4]);
    const total = user + parseInt(cpuLine[2]) + system + idle + parseInt(cpuLine[5]) + parseInt(cpuLine[6]) + parseInt(cpuLine[7]);
    cpuUsage = Math.round(((total - idle) / total) * 100);
  } catch {}
  
  // Fallback: use `top` for CPU in container (macOS Docker) - uses execFile safely
  if (cpuUsage === 0) {
    try {
      const { stdout } = await execFileAsync('top', ['-bn1'], { timeout: 3000 });
      const cpuMatch = stdout.match(/(\d+\.?\d*)%?\s*id/);
      if (cpuMatch) cpuUsage = Math.round(100 - parseFloat(cpuMatch[1]));
    } catch {}
  }
  
  // Memory from /proc/meminfo
  try {
    const meminfo = fs.readFileSync(`${procPath}/meminfo`, 'utf8');
    const totalMatch = meminfo.match(/MemTotal:\s+(\d+)/);
    const availMatch = meminfo.match(/MemAvailable:\s+(\d+)/);
    if (totalMatch) memTotal = parseInt(totalMatch[1]) * 1024;
    if (availMatch) memUsed = memTotal - (parseInt(availMatch[1]) * 1024);
  } catch {}
  
  // Fallback: free command (works in Alpine container) - uses execFile safely
  if (memTotal === 0) {
    try {
      const { stdout } = await execFileAsync('free', ['-b'], { timeout: 3000 });
      const memLine = stdout.split('\n').find((l: string) => l.startsWith('Mem:'));
      if (memLine) {
        const parts = memLine.split(/\s+/);
        memTotal = parseInt(parts[1]) || 0;
        memUsed = parseInt(parts[2]) || 0;
      }
    } catch {}
  }
  
  // Disk usage using df with safe args
  try {
    const { stdout } = await execFileAsync('df', ['-B1', '/'], { timeout: 3000 });
    const parts = stdout.split('\n')[1]?.split(/\s+/);
    if (parts) { diskTotal = parseInt(parts[1]) || 0; diskUsed = parseInt(parts[2]) || 0; }
  } catch {}
  
  // Storage type detection (SSD/HDD/NVMe) using lsblk with safe args
  try {
    const { stdout } = await execFileAsync('lsblk', ['-dno', 'NAME,ROTA,MODEL,TRAN'], { timeout: 3000 });
    if (stdout) {
      const lines = stdout.split('\n').filter((l: string) => l.trim());
      for (const line of lines) {
        const parts = line.trim().split(/\s+/);
        const name = parts[0];
        const rota = parts[1];
        const model = parts.slice(2, -1).join(' ');
        const transport = parts[parts.length - 1] || '';
        if (name && !name.startsWith('loop')) {
          storageModel = model || '';
          if (transport === 'nvme' || name.startsWith('nvme')) {
            storageType = 'NVMe SSD';
          } else if (rota === '0') {
            storageType = 'SSD';
          } else if (rota === '1') {
            storageType = 'HDD';
          }
          break;
        }
      }
    }
  } catch {}
  
  // Method 2: macOS / Docker Desktop detection using mount with safe args
  if (storageType === 'unknown') {
    try {
      const { stdout } = await execFileAsync('mount', [], { timeout: 3000 });
      const rootDev = stdout.split('\n').find((l: string) => l.includes(' on / '));
      if (rootDev) {
        const devMatch = rootDev.match(/^(\S+)/);
        if (devMatch && (devMatch[1].includes('vda') || devMatch[1].includes('sda'))) {
          storageType = 'SSD (VM)';
        }
      }
    } catch {}
  }
  
  // IOPS benchmark (quick 4K random read test - runs once, cached)
  let iopsEstimate = 0;
  try {
    // Quick dd-based test: 1000 x 4K blocks - uses execFile safely
    const { stdout, stderr } = await execFileAsync('dd', ['if=/dev/zero', 'of=/tmp/.iops-test', 'bs=4k', 'count=1000', 'oflag=dsync'], { timeout: 10000 });
    const output = stdout + stderr;
    const speedMatch = output.match(/([\d.]+)\s*(MB|kB|GB)\/s/);
    if (speedMatch) {
      let speedMB = parseFloat(speedMatch[1]);
      if (speedMatch[2] === 'kB') speedMB /= 1024;
      if (speedMatch[2] === 'GB') speedMB *= 1024;
      // Estimate IOPS from sequential 4K write speed
      iopsEstimate = Math.round((speedMB * 1024) / 4); // 4K blocks
    }
    await execFileAsync('rm', ['-f', '/tmp/.iops-test'], { timeout: 1000 });
  } catch {}
  
  return { cpuUsage, memUsed, memTotal, diskUsed, diskTotal, storageType, storageModel, iopsEstimate };
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
      chainIdRes,
      mainnetBlockRes,
    ] = await Promise.all([
      rpcCall(getRpcUrl(), 'eth_blockNumber'),
      rpcCall(getRpcUrl(), 'eth_syncing'),
      rpcCall(getRpcUrl(), 'net_peerCount'),
      rpcCall(getRpcUrl(), 'admin_nodeInfo'),
      rpcCall(getRpcUrl(), 'eth_coinbase'),
      rpcCall(getRpcUrl(), 'txpool_status'),
      rpcCall(getRpcUrl(), 'admin_peers'),
      rpcCall(getRpcUrl(), 'net_version'),
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
    
    // Sync info — use SkyNet network height for accurate sync percentage
    let isSyncing = false;
    let highestBlock = mainnetHeight || blockHeight;
    if (syncingRes.result && typeof syncingRes.result === 'object') {
      isSyncing = true;
      const syncData = syncingRes.result as Record<string, string>;
      highestBlock = hexToNumber(syncData.highestBlock) || highestBlock;
    }
    
    // Fetch network height from SkyNet for accurate comparison
    const skynetUrl = process.env.SKYNET_API_URL || 'https://net.xdc.network/api/v1';
    try {
      const skynetRes = await fetch(`${skynetUrl}/network/health`, {
        signal: AbortSignal.timeout(3000),
      }).then(r => r.json()).catch(() => null);
      const networkHeight = skynetRes?.data?.maxBlockHeight || skynetRes?.maxBlockHeight || 0;
      if (networkHeight > highestBlock) {
        highestBlock = networkHeight;
      }
    } catch {}
    
    if (highestBlock <= blockHeight && blockHeight > 0) {
      // Node reports equal or higher — check if truly synced
      isSyncing = false;
    }
    const syncPercent = highestBlock > 0 ? Math.min(100, (blockHeight / highestBlock) * 100) : (blockHeight === 0 ? 0 : 100);
    
    // Peer breakdown
    const inbound = peersList.filter(p => p.network?.inbound === true).length;
    const outbound = peersList.length - inbound;
    
    // Server stats - now async
    const server = await getServerStats();
    
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
    
    // Get storage metrics - now async
    const storageMetrics = await getStorageMetrics();
    
    // Get watchdog stall state
    const watchdogState = await getWatchdogState();
    
    // Node config from environment + detected values
    const chainIdStr = String(chainIdRes.result || '50');
    const chainIdNum = parseInt(chainIdStr.startsWith('0x') ? String(parseInt(chainIdStr, 16)) : chainIdStr);
    const networkName = parseNetworkName(chainIdNum);
    const syncMode = parseSyncMode((nodeInfo.name as string) || '', clientType);
    const nodeConfig = {
      clientType,
      clientVersion: (nodeInfo.name as string) || '',
      nodeType: (process.env.NODE_TYPE || syncMode) as 'full' | 'fast' | 'snap' | 'archive',
      syncMode,
      networkName,
      chainId: chainIdNum,
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
        networkHeight: highestBlock,
        syncPercent: Math.round(syncPercent * 10) / 10,
        isSyncing,
        peers,
        peersInbound: inbound,
        peersOutbound: outbound,
        uptime: 0,
        chainId: String(chainIdRes.result || '50'),
        coinbase: coinbase ? coinbase.replace('0x', 'xdc') : '',
        ethstatsName: process.env.NODE_NAME || '',
        clientVersion: (nodeInfo.name as string) || '',
        clientType,
        stallHours: watchdogState.stallHours,
        stalledAtBlock: watchdogState.stalledAtBlock,
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
        cpuPercent: server.cpuUsage,
        memoryPercent: server.memTotal > 0 ? Math.round((server.memUsed / server.memTotal) * 100) : 0,
        diskPercent: server.diskTotal > 0 ? Math.round((server.diskUsed / server.diskTotal) * 100) : 0,
        diskUsedGb: Math.round(server.diskUsed / (1024 * 1024 * 1024) * 10) / 10,
        diskTotalGb: Math.round(server.diskTotal / (1024 * 1024 * 1024) * 10) / 10,
        goroutines: 0, sysLoad: 0, procLoad: 0,
        storageType: server.storageType,
        storageModel: server.storageModel,
        iopsEstimate: server.iopsEstimate,
      },
      storage: { 
        chainDataSize: storageMetrics.chainDataSize,
        databaseSize: storageMetrics.databaseSize,
        storageType: server.storageType,
        storageModel: server.storageModel,
        iopsEstimate: server.iopsEstimate,
        dataDir: storageMetrics.dataDir,
        mountPoint: storageMetrics.mountPoint,
        filesystem: storageMetrics.filesystem,
        device: storageMetrics.device,
        mountTotal: storageMetrics.mountTotal,
        mountUsed: storageMetrics.mountUsed,
        mountAvail: storageMetrics.mountAvail,
        mountPercent: storageMetrics.mountPercent,
        allMounts: storageMetrics.allMounts,
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
    
    // Update active issues tracker via global function
    if (typeof global !== 'undefined' && global.updateActiveIssues) {
      global.updateActiveIssues(detectedIssues);
    }
    
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
    pushToSkyNet(responseWithIssues, peersList).catch(() => {});

    // === LFG (Live Fleet Gateway) Auto-Peer Injection ===
    // Check if peer count is below threshold and fetch healthy peers from SkyNet
    let lfgResult = null;
    if (rpcConnected && peers < 10) {
      try {
        lfgResult = await lfgCheck(getRpcUrl(), peers);
      } catch (e) {
        // LFG is best-effort, don't fail the whole request
        console.error('[LFG] Error during peer injection:', e);
      }
    }

    // Add LFG result to response if triggered
    const finalResponse = lfgResult?.triggered 
      ? { ...responseWithIssues, lfg: lfgResult }
      : responseWithIssues;

    return NextResponse.json(finalResponse);
  } catch (error) {
    // Even on total failure, return diagnostics
    const diagnostics = await getNodeDiagnostics();
    const server = await getServerStats();
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
      blockchain: { blockHeight: 0, highestBlock: 0, networkHeight: 0, syncPercent: 0, isSyncing: false, peers: 0, peersInbound: 0, peersOutbound: 0, uptime: 0, chainId: 'unknown', coinbase: '', ethstatsName: '', clientVersion: '', clientType: 'unknown' },
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
