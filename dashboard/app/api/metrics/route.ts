import { NextResponse } from 'next/server';
import { queryPrometheus, PROMETHEUS_QUERIES } from '@/lib/prometheus';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export async function GET() {
  try {
    // Query all metrics in parallel
    const results = await Promise.all([
      // Blockchain
      queryPrometheus(PROMETHEUS_QUERIES.blockHeight),
      queryPrometheus(PROMETHEUS_QUERIES.highestBlock),
      queryPrometheus(PROMETHEUS_QUERIES.peers),
      queryPrometheus(PROMETHEUS_QUERIES.peersInbound),
      queryPrometheus(PROMETHEUS_QUERIES.peersOutbound),
      queryPrometheus(PROMETHEUS_QUERIES.uptime),
      
      // Consensus
      queryPrometheus(PROMETHEUS_QUERIES.epoch),
      queryPrometheus(PROMETHEUS_QUERIES.epochProgress),
      queryPrometheus(PROMETHEUS_QUERIES.signingRate),
      queryPrometheus(PROMETHEUS_QUERIES.stakeAmount),
      queryPrometheus(PROMETHEUS_QUERIES.walletBalance),
      queryPrometheus(PROMETHEUS_QUERIES.totalRewards),
      queryPrometheus(PROMETHEUS_QUERIES.penalties),
      
      // Sync
      queryPrometheus(PROMETHEUS_QUERIES.syncRate),
      queryPrometheus(PROMETHEUS_QUERIES.reorgsAdd),
      queryPrometheus(PROMETHEUS_QUERIES.reorgsDrop),
      
      // TxPool
      queryPrometheus(PROMETHEUS_QUERIES.txPending),
      queryPrometheus(PROMETHEUS_QUERIES.txQueued),
      queryPrometheus(PROMETHEUS_QUERIES.txSlots),
      queryPrometheus(PROMETHEUS_QUERIES.txValid),
      queryPrometheus(PROMETHEUS_QUERIES.txInvalid),
      queryPrometheus(PROMETHEUS_QUERIES.txUnderpriced),
      
      // Server
      queryPrometheus(PROMETHEUS_QUERIES.cpuUsage),
      queryPrometheus(PROMETHEUS_QUERIES.memoryUsed),
      queryPrometheus(PROMETHEUS_QUERIES.memoryTotal),
      queryPrometheus(PROMETHEUS_QUERIES.diskUsed),
      queryPrometheus(PROMETHEUS_QUERIES.diskTotal),
      queryPrometheus(PROMETHEUS_QUERIES.goroutines),
      queryPrometheus(PROMETHEUS_QUERIES.sysLoad),
      queryPrometheus(PROMETHEUS_QUERIES.procLoad),
      
      // Storage
      queryPrometheus(PROMETHEUS_QUERIES.chainDataSize),
      queryPrometheus(PROMETHEUS_QUERIES.diskReadRate),
      queryPrometheus(PROMETHEUS_QUERIES.diskWriteRate),
      queryPrometheus(PROMETHEUS_QUERIES.compactTime),
      queryPrometheus(PROMETHEUS_QUERIES.trieCacheHitRate),
      queryPrometheus(PROMETHEUS_QUERIES.trieCacheMiss),
      
      // Network
      queryPrometheus(PROMETHEUS_QUERIES.inboundTraffic),
      queryPrometheus(PROMETHEUS_QUERIES.outboundTraffic),
      queryPrometheus(PROMETHEUS_QUERIES.dialSuccess),
      queryPrometheus(PROMETHEUS_QUERIES.dialTotal),
      queryPrometheus(PROMETHEUS_QUERIES.eth100Traffic),
      queryPrometheus(PROMETHEUS_QUERIES.eth63Traffic),
      queryPrometheus(PROMETHEUS_QUERIES.connectionErrors),
    ]);

    const [
      blockHeight, highestBlock, peers, peersInbound, peersOutbound, uptime,
      epoch, epochProgress, signingRate, stakeAmount, walletBalance, totalRewards, penalties,
      syncRate, reorgsAdd, reorgsDrop,
      txPending, txQueued, txSlots, txValid, txInvalid, txUnderpriced,
      cpuUsage, memoryUsed, memoryTotal, diskUsed, diskTotal, goroutines, sysLoad, procLoad,
      chainDataSize, diskReadRate, diskWriteRate, compactTime, trieCacheHitRate, trieCacheMiss,
      inboundTraffic, outboundTraffic, dialSuccess, dialTotal, eth100Traffic, eth63Traffic, connectionErrors,
    ] = results;

    // Calculate sync percentage
    const currentHeight = blockHeight || 0;
    const highest = highestBlock || currentHeight;
    const syncPercent = highest > 0 ? Math.min(100, (currentHeight / highest) * 100) : 100;
    const isSyncing = syncPercent < 99.9;

    // Determine masternode status (fallback logic)
    const signingRateVal = signingRate || 0;
    let masternodeStatus: 'Active' | 'Inactive' | 'Slashed' = 'Inactive';
    if (signingRateVal >= 90) masternodeStatus = 'Active';
    else if (signingRateVal > 0 && signingRateVal < 90) masternodeStatus = 'Slashed';

    const response = {
      blockchain: {
        blockHeight: Math.floor(currentHeight),
        highestBlock: Math.floor(highest),
        syncPercent: Math.round(syncPercent * 10) / 10,
        isSyncing,
        peers: Math.floor(peers || 0),
        peersInbound: Math.floor(peersInbound || 0),
        peersOutbound: Math.floor(peersOutbound || 0),
        uptime: uptime || 0,
        chainId: '50',
      },
      consensus: {
        epoch: Math.floor(epoch || 0),
        epochProgress: Math.round((epochProgress || 0) * 10) / 10,
        masternodeStatus,
        signingRate: Math.round((signingRate || 0) * 10) / 10,
        stakeAmount: stakeAmount || 0,
        walletBalance: walletBalance || 0,
        totalRewards: totalRewards || 0,
        penalties: Math.floor(penalties || 0),
      },
      sync: {
        syncRate: syncRate || 0,
        reorgsAdd: Math.floor(reorgsAdd || 0),
        reorgsDrop: Math.floor(reorgsDrop || 0),
      },
      txpool: {
        pending: Math.floor(txPending || 0),
        queued: Math.floor(txQueued || 0),
        slots: Math.floor(txSlots || 0),
        valid: Math.floor(txValid || 0),
        invalid: Math.floor(txInvalid || 0),
        underpriced: Math.floor(txUnderpriced || 0),
      },
      server: {
        cpuUsage: Math.round((cpuUsage || 0) * 10) / 10,
        memoryUsed: memoryUsed || 0,
        memoryTotal: memoryTotal || (memoryUsed ? memoryUsed * 2 : 16 * 1024 * 1024 * 1024),
        diskUsed: diskUsed || 0,
        diskTotal: diskTotal || (diskUsed ? diskUsed * 1.5 : 500 * 1024 * 1024 * 1024),
        goroutines: Math.floor(goroutines || 0),
        sysLoad: sysLoad || 0,
        procLoad: procLoad || 0,
      },
      storage: {
        chainDataSize: chainDataSize || 0,
        diskReadRate: diskReadRate || 0,
        diskWriteRate: diskWriteRate || 0,
        compactTime: compactTime || 0,
        trieCacheHitRate: Math.round((trieCacheHitRate || 0) * 10) / 10,
        trieCacheMiss: Math.floor(trieCacheMiss || 0),
      },
      network: {
        totalPeers: Math.floor(peers || 0),
        inboundTraffic: inboundTraffic || 0,
        outboundTraffic: outboundTraffic || 0,
        dialSuccess: Math.floor(dialSuccess || 0),
        dialTotal: Math.floor(dialTotal || 0),
        eth100Traffic: eth100Traffic || 0,
        eth63Traffic: eth63Traffic || 0,
        connectionErrors: Math.floor(connectionErrors || 0),
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
