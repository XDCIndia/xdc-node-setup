import { NextResponse } from 'next/server';
import { execSync } from 'child_process';
import os from 'os';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

function getRpcUrl() { return process.env.RPC_URL || 'http://xdc-node:8545'; }
function getMainnetRpc() { return process.env.MAINNET_RPC || 'https://erpc.xinfin.network'; }

async function rpcCall(url: string, method: string, params: unknown[] = []): Promise<unknown> {
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', method, params, id: 1 }),
      signal: AbortSignal.timeout(5000),
    });
    const data = await res.json();
    return data.result;
  } catch { return null; }
}

function hexToNumber(hex: string | null | undefined): number {
  if (!hex || hex === '0x' || hex === 'null') return 0;
  return parseInt(hex as string, 16) || 0;
}

function getServerStats() {
  // Try reading from /host/proc (Docker mount) first, then /proc
  const procPath = require('fs').existsSync('/host/proc/stat') ? '/host/proc' : '/proc';
  
  let cpuUsage = 0;
  let memUsed = 0;
  let memTotal = 0;
  let diskUsed = 0;
  let diskTotal = 0;
  
  try {
    // CPU from /proc/stat
    const stat = require('fs').readFileSync(`${procPath}/stat`, 'utf8');
    const cpuLine = stat.split('\n')[0].split(/\s+/);
    const user = parseInt(cpuLine[1]);
    const system = parseInt(cpuLine[3]);
    const idle = parseInt(cpuLine[4]);
    const total = user + parseInt(cpuLine[2]) + system + idle + parseInt(cpuLine[5]) + parseInt(cpuLine[6]) + parseInt(cpuLine[7]);
    cpuUsage = Math.round(((total - idle) / total) * 100);
  } catch {}
  
  try {
    // Memory from /proc/meminfo
    const meminfo = require('fs').readFileSync(`${procPath}/meminfo`, 'utf8');
    const totalMatch = meminfo.match(/MemTotal:\s+(\d+)/);
    const availMatch = meminfo.match(/MemAvailable:\s+(\d+)/);
    if (totalMatch) memTotal = parseInt(totalMatch[1]) * 1024; // KB to bytes
    if (availMatch) memUsed = memTotal - (parseInt(availMatch[1]) * 1024);
  } catch {}
  
  try {
    // Disk usage
    const df = execSync('df -B1 / 2>/dev/null', { timeout: 3000 }).toString();
    const parts = df.split('\n')[1]?.split(/\s+/);
    if (parts) {
      diskTotal = parseInt(parts[1]) || 0;
      diskUsed = parseInt(parts[2]) || 0;
    }
  } catch {}
  
  return { cpuUsage, memUsed, memTotal, diskUsed, diskTotal };
}

export async function GET() {
  try {
    // Parallel RPC calls
    const [
      blockNumberResult,
      syncingResult,
      peerCountResult,
      nodeInfoResult,
      coinbaseResult,
      txpoolResult,
      peersResult,
      mainnetBlockResult,
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

    const blockHeight = hexToNumber(blockNumberResult as string);
    const mainnetHeight = hexToNumber(mainnetBlockResult as string);
    const peers = hexToNumber(peerCountResult as string);
    const nodeInfo = (nodeInfoResult || {}) as Record<string, any>;
    const coinbase = (coinbaseResult as string) || '';
    const txpool = (txpoolResult || {}) as Record<string, string>;
    const peersList = (peersResult || []) as Array<Record<string, any>>;
    
    // Sync info
    let isSyncing = false;
    let highestBlock = mainnetHeight || blockHeight;
    if (syncingResult && typeof syncingResult === 'object') {
      isSyncing = true;
      const syncData = syncingResult as Record<string, string>;
      highestBlock = hexToNumber(syncData.highestBlock) || highestBlock;
    }
    const syncPercent = highestBlock > 0 ? Math.min(100, (blockHeight / highestBlock) * 100) : 100;
    
    // Peer breakdown
    const inbound = peersList.filter(p => p.network?.inbound === true).length;
    const outbound = peersList.length - inbound;
    
    // Server stats from /proc
    const server = getServerStats();
    
    // Epoch estimate (XDPoS: ~900 blocks per epoch)
    const epoch = Math.floor(blockHeight / 900);
    const epochProgress = ((blockHeight % 900) / 900) * 100;
    
    const response = {
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
        signingRate: 0,
        stakeAmount: 0,
        walletBalance: 0,
        totalRewards: 0,
        penalties: 0,
      },
      sync: {
        syncRate: 0,
        reorgsAdd: 0,
        reorgsDrop: 0,
      },
      txpool: {
        pending: hexToNumber(txpool.pending),
        queued: hexToNumber(txpool.queued),
        slots: 0,
        valid: 0,
        invalid: 0,
        underpriced: 0,
      },
      server: {
        cpuUsage: server.cpuUsage,
        memoryUsed: server.memUsed,
        memoryTotal: server.memTotal,
        diskUsed: server.diskUsed,
        diskTotal: server.diskTotal,
        goroutines: 0,
        sysLoad: 0,
        procLoad: 0,
      },
      storage: {
        chainDataSize: 0,
        diskReadRate: 0,
        diskWriteRate: 0,
        compactTime: 0,
        trieCacheHitRate: 0,
        trieCacheMiss: 0,
      },
      network: {
        totalPeers: peers,
        inboundTraffic: 0,
        outboundTraffic: 0,
        dialSuccess: 0,
        dialTotal: 0,
        eth100Traffic: 0,
        eth63Traffic: 0,
        connectionErrors: 0,
      },
      timestamp: new Date().toISOString(),
    };

    return NextResponse.json(response);
  } catch (error) {
    console.error('Error fetching metrics:', error);
    return NextResponse.json(
      { error: 'Failed to fetch metrics', timestamp: new Date().toISOString() },
      { status: 500 }
    );
  }
}
