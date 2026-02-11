const PROMETHEUS_URL = process.env.PROMETHEUS_URL || 'http://127.0.0.1:19090';

interface PrometheusResponse {
  status: string;
  data?: {
    resultType: string;
    result: Array<{
      metric: Record<string, string>;
      value: [number, string];
    }>;
  };
  error?: string;
}

export async function queryPrometheus(query: string): Promise<number | null> {
  try {
    const url = new URL('/api/v1/query', PROMETHEUS_URL);
    url.searchParams.append('query', query);
    
    const response = await fetch(url.toString(), {
      method: 'GET',
      headers: { 'Accept': 'application/json' },
      next: { revalidate: 0 }
    });
    
    if (!response.ok) return null;
    
    const data: PrometheusResponse = await response.json();
    
    if (data.status !== 'success' || !data.data?.result?.length) return null;
    
    const value = parseFloat(data.data.result[0].value[1]);
    return isNaN(value) ? null : value;
  } catch (error) {
    console.error(`Prometheus query error for "${query}":`, error);
    return null;
  }
}

export async function queryPrometheusMultiple(queries: Record<string, string>): Promise<Record<string, number | null>> {
  const results: Record<string, number | null> = {};
  await Promise.all(
    Object.entries(queries).map(async ([key, query]) => {
      results[key] = await queryPrometheus(query);
    })
  );
  return results;
}

// Actual metric names from the XDC node Prometheus endpoints
export const PROMETHEUS_QUERIES = {
  // Blockchain — from xdc-node job (:6060)
  blockHeight: 'chain_head_block{job="xdc-node"}',
  highestBlock: 'xdc_node_highest_block{job="node-exporter"}',
  syncPercent: 'xdc_node_sync_percent{job="node-exporter"}',
  isSyncing: 'xdc_node_is_syncing{job="node-exporter"}',
  peers: 'p2p_peers{job="xdc-node"}',
  peersInbound: 'xdc_node_peer_inbound{job="node-exporter"}',
  peersOutbound: 'xdc_node_peer_outbound{job="node-exporter"}',
  uptime: 'xdc_node_uptime_seconds{job="node-exporter"}',
  
  // Consensus — from textfile collector
  epoch: 'xdc_chain_epoch_number{job="node-exporter"}',
  epochProgress: 'xdc_chain_epoch_progress{job="node-exporter"}',
  signingRate: 'xdc_masternode_signing_rate{job="node-exporter"}',
  stakeAmount: 'xdc_masternode_stake_xdc{job="node-exporter"}',
  walletBalance: 'xdc_masternode_balance_xdc{job="node-exporter"}',
  totalRewards: 'xdc_masternode_rewards_total{job="node-exporter"}',
  penalties: 'xdc_masternode_penalties{job="node-exporter"}',
  masternodeStatus: 'xdc_masternode_status{job="node-exporter"}',
  
  // Sync — from xdc-node
  syncRate: 'rate(chain_head_block{job="xdc-node"}[5m]) * 60',
  reorgsAdd: 'chain_reorg_add{job="xdc-node"}',
  reorgsDrop: 'chain_reorg_drop{job="xdc-node"}',
  
  // TxPool — from xdc-node
  txPending: 'txpool_pending{job="xdc-node"}',
  txQueued: 'txpool_queued{job="xdc-node"}',
  txSlots: 'txpool_slots{job="xdc-node"}',
  txValid: 'txpool_valid{job="xdc-node"}',
  txInvalid: 'txpool_invalid{job="xdc-node"}',
  txUnderpriced: 'txpool_underpriced{job="xdc-node"}',
  
  // Server — from xdc-node + node-exporter
  cpuUsage: 'system_cpu_procload{job="xdc-node"} * 100',
  memoryUsed: 'system_memory_used{job="xdc-node"}',
  memoryTotal: 'system_memory_held{job="xdc-node"}',
  diskUsed: 'node_filesystem_size_bytes{job="node-exporter",mountpoint="/"} - node_filesystem_avail_bytes{job="node-exporter",mountpoint="/"}',
  diskTotal: 'node_filesystem_size_bytes{job="node-exporter",mountpoint="/"}',
  goroutines: 'system_cpu_goroutines{job="xdc-node"}',
  sysLoad: 'system_cpu_sysload{job="xdc-node"}',
  procLoad: 'system_cpu_procload{job="xdc-node"}',
  
  // Storage — from xdc-node + textfile
  chainDataSize: 'eth_db_chaindata_disk_size{job="xdc-node"}',
  diskReadRate: 'rate(system_disk_readbytes{job="xdc-node"}[5m])',
  diskWriteRate: 'rate(system_disk_writebytes{job="xdc-node"}[5m])',
  compactTime: 'eth_db_chaindata_compact_time{job="xdc-node"}',
  trieCacheHitRate: 'trie_memcache_clean_hit{job="xdc-node"} / (trie_memcache_clean_hit{job="xdc-node"} + trie_memcache_clean_miss{job="xdc-node"}) * 100',
  trieCacheMiss: 'trie_memcache_clean_miss{job="xdc-node"}',
  
  // Network — from xdc-node
  inboundTraffic: 'p2p_InboundTraffic{job="xdc-node"}',
  outboundTraffic: 'p2p_OutboundTraffic{job="xdc-node"}',
  dialSuccess: 'p2p_dials_success{job="xdc-node"}',
  dialTotal: 'p2p_dials{job="xdc-node"}',
  eth100Traffic: 'p2p_ingress_eth_100_0x04{job="xdc-node"} + p2p_egress_eth_100_0x04{job="xdc-node"}',
  eth63Traffic: 'p2p_ingress_eth_63_0x00{job="xdc-node"} + p2p_egress_eth_63_0x00{job="xdc-node"}',
  connectionErrors: 'p2p_dials_error_connection{job="xdc-node"}',
};
