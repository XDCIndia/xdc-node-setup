export interface NodeConfig {
  clientType: 'geth' | 'erigon' | 'geth-pr5' | 'unknown';
  nodeType: 'full' | 'fast' | 'snap' | 'archive';
  syncMode: string;
}

export interface BlockchainData {
  blockHeight: number;
  highestBlock: number;
  syncPercent: number;
  isSyncing: boolean;
  peers: number;
  peersInbound: number;
  peersOutbound: number;
  uptime: number;
  chainId: string;
  coinbase: string;
  ethstatsName: string;
  clientVersion: string;
  clientType?: 'geth' | 'erigon' | 'geth-pr5' | 'unknown';
}

export interface ConsensusData {
  epoch: number;
  epochProgress: number;
  masternodeStatus: 'Active' | 'Inactive' | 'Slashed' | 'Not Configured';
  coinbase?: string;
  blockTime?: number;
  signingRate: number;
  stakeAmount: number;
  walletBalance: number;
  totalRewards: number;
  penalties: number;
}

export interface SyncData {
  syncRate: number;
  reorgsAdd: number;
  reorgsDrop: number;
}

export interface TxPoolData {
  pending: number;
  queued: number;
  slots: number;
  valid: number;
  invalid: number;
  underpriced: number;
  isSyncing?: boolean;
  available?: boolean;
}

export interface ServerData {
  cpuUsage: number;
  memoryUsed: number;
  memoryTotal: number;
  diskUsed: number;
  diskTotal: number;
  goroutines: number;
  sysLoad: number;
  procLoad: number;
}

export interface StorageData {
  chainDataSize: number;
  databaseSize: number;
  diskReadRate: number;
  diskWriteRate: number;
  compactTime: number;
  trieCacheHitRate: number;
  trieCacheMiss: number;
}

export interface NetworkData {
  totalPeers: number;
  inboundTraffic: number;
  outboundTraffic: number;
  dialSuccess: number;
  dialTotal: number;
  eth100Traffic: number;
  eth63Traffic: number;
  connectionErrors: number;
}

export interface DiagnosticsData {
  containerStatus: string;
  recentLogs: string[];
  errors: string[];
  lastKnownBlock: string;
}

export interface MetricsData {
  nodeStatus?: 'online' | 'syncing' | 'error' | 'offline';
  rpcConnected?: boolean;
  rpcUrl?: string;
  rpcError?: string | null;
  diagnostics?: DiagnosticsData;
  nodeConfig?: NodeConfig;
  blockchain: BlockchainData;
  consensus: ConsensusData;
  sync: SyncData;
  txpool: TxPoolData;
  server: ServerData;
  storage: StorageData;
  network: NetworkData;
  timestamp: string;
}

export interface PeerInfo {
  id: string;
  name: string;
  ip: string;
  port: number;
  country: string;
  countryCode: string;
  city: string;
  lat: number;
  lon: number;
  isp: string;
  inbound: boolean;
}

export interface CountryInfo {
  name: string;
  count: number;
}

export interface PeersData {
  peers: PeerInfo[];
  countries: Record<string, CountryInfo>;
  totalPeers: number;
}
