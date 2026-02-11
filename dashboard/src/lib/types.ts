// Node-related types
export interface NodeMetrics {
  cpuUsage: number;
  ramUsage: number;
  diskUsage: number;
  blockHeight: number;
  peerCount: number;
  syncProgress: number;
}

export interface SecurityCheck {
  name: string;
  passed: boolean;
  description: string;
}

export interface NodeReport {
  id: string;
  hostname: string;
  ip: string;
  role: 'masternode' | 'standby' | 'full' | 'archive';
  clientType: 'XDC' | 'XDC2' | 'XDPoS';
  clientVersion: string;
  latestVersion: string;
  network: 'mainnet' | 'testnet' | 'devnet';
  status: 'healthy' | 'syncing' | 'degraded' | 'offline';
  metrics: NodeMetrics;
  historicalMetrics?: HistoricalMetric[];
  securityScore: number;
  securityChecks: SecurityCheck[];
  uptime: number; // seconds
  lastSeen: string;
  alerts: Alert[];
}

export interface HistoricalMetric {
  timestamp: string;
  blockHeight: number;
  peerCount: number;
  cpuUsage: number;
  ramUsage: number;
  diskUsage: number;
}

export interface HealthReport {
  timestamp: string;
  version: string;
  networkBlockHeight: number;
  nodes: NodeReport[];
  summary: {
    total: number;
    healthy: number;
    warning: number;
    critical: number;
    avgSyncProgress: number;
  };
}

// Alert types
export type AlertLevel = 'critical' | 'warning' | 'info';

export interface Alert {
  id: string;
  nodeId: string;
  nodeName: string;
  level: AlertLevel;
  message: string;
  timestamp: string;
  acknowledged: boolean;
  acknowledgedAt?: string;
  acknowledgedBy?: string;
}

export interface AlertState {
  alerts: Alert[];
  lastUpdated: string;
}

// Version types
export interface ClientVersion {
  client: string;
  current: string;
  latest: string;
  releaseDate: string;
  changelogUrl: string;
  nodeCount: number;
  autoUpdate: boolean;
}

export interface VersionConfig {
  clients: ClientVersion[];
  lastChecked: string;
  updateHistory: UpdateHistoryEntry[];
}

export interface UpdateHistoryEntry {
  timestamp: string;
  client: string;
  fromVersion: string;
  toVersion: string;
  nodeId: string;
  success: boolean;
}

// Settings types
export interface NotificationChannel {
  type: 'telegram' | 'email' | 'webhook' | 'slack';
  enabled: boolean;
  config: Record<string, string>;
}

export interface NotificationSettings {
  channels: NotificationChannel[];
  quietHours: {
    enabled: boolean;
    start: string;
    end: string;
    timezone: string;
  };
  digest: {
    enabled: boolean;
    frequency: 'hourly' | 'daily' | 'weekly';
    time: string;
  };
  levels: {
    critical: boolean;
    warning: boolean;
    info: boolean;
  };
}

export interface Settings {
  notifications: NotificationSettings;
  nodes: NodeRegistration[];
  apiKeys: ApiKey[];
  theme: 'dark' | 'light';
}

export interface NodeRegistration {
  id: string;
  hostname: string;
  ip: string;
  sshPort: number;
  enabled: boolean;
  addedAt: string;
}

export interface ApiKey {
  id: string;
  name: string;
  key: string;
  permissions: string[];
  createdAt: string;
  lastUsed?: string;
}
