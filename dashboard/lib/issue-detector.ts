/**
 * Issue Detection Engine
 * Analyzes metrics and detects node health problems
 */

export interface DetectedIssue {
  type: string;
  severity: 'critical' | 'high' | 'medium' | 'low';
  title: string;
  description: string;
  diagnostics: {
    blockHeight: number;
    peers: number;
    cpu: number;
    memory: number;
    disk: number;
    syncPercent: number;
    containerStatus: string;
    recentErrors: string[];
    clientType: string;
    nodeType: string;
    clientVersion: string;
    uptime: number;
    rpcUrl: string;
    ipv4: string;
  };
  detectedAt: string;
}

interface MetricsSnapshot {
  timestamp: string;
  blockHeight: number;
  peers: number;
  cpu: number;
  memory: number;
  disk: number;
  syncPercent: number;
  txPoolPending: number;
}

// Track consecutive high CPU checks
let highCpuCount = 0;

/**
 * Detect issues from current metrics compared to previous state
 */
export function detectIssues(
  currentMetrics: any,
  previousMetrics: any | null,
  metricsHistory: MetricsSnapshot[]
): DetectedIssue[] {
  const issues: DetectedIssue[] = [];
  const now = new Date().toISOString();

  // Helper to build diagnostics object
  const buildDiagnostics = () => ({
    blockHeight: currentMetrics.blockchain?.blockHeight || 0,
    peers: currentMetrics.blockchain?.peers || 0,
    cpu: currentMetrics.server?.cpuUsage || 0,
    memory: currentMetrics.server?.memoryTotal > 0
      ? (currentMetrics.server.memoryUsed / currentMetrics.server.memoryTotal) * 100
      : 0,
    disk: currentMetrics.server?.diskTotal > 0
      ? (currentMetrics.server.diskUsed / currentMetrics.server.diskTotal) * 100
      : 0,
    syncPercent: currentMetrics.blockchain?.syncPercent || 0,
    containerStatus: currentMetrics.diagnostics?.containerStatus || 'unknown',
    recentErrors: currentMetrics.diagnostics?.errors || [],
    clientType: currentMetrics.blockchain?.clientType || 'unknown',
    nodeType: currentMetrics.nodeConfig?.nodeType || 'full',
    clientVersion: currentMetrics.blockchain?.clientVersion || 'unknown',
    uptime: currentMetrics.blockchain?.uptime || 0,
    rpcUrl: currentMetrics.rpcUrl || '',
    ipv4: currentMetrics.ipv4 || '0.0.0.0',
  });

  // 1. RPC Error
  if (!currentMetrics.rpcConnected || currentMetrics.rpcError) {
    issues.push({
      type: 'rpc_error',
      severity: 'critical',
      title: 'RPC Connection Failed',
      description: `Cannot connect to XDC node RPC endpoint. Error: ${currentMetrics.rpcError || 'Connection refused'}`,
      diagnostics: buildDiagnostics(),
      detectedAt: now,
    });
  }

  // 2. Container Crash
  const containerStatus = currentMetrics.diagnostics?.containerStatus || '';
  if (!containerStatus.includes('running') && containerStatus !== 'unknown') {
    issues.push({
      type: 'container_crash',
      severity: 'critical',
      title: 'Container Not Running',
      description: `XDC node container status: ${containerStatus}. The node may have crashed or been stopped.`,
      diagnostics: buildDiagnostics(),
      detectedAt: now,
    });
  }

  // 3. Bad Block Detection
  const recentErrors = currentMetrics.diagnostics?.errors || [];
  if (recentErrors.some((e: string) => e.includes('BAD BLOCK'))) {
    issues.push({
      type: 'bad_block',
      severity: 'critical',
      title: 'Bad Block Detected',
      description: 'Node detected a BAD BLOCK in the chain. This may indicate chain corruption or network consensus issues.',
      diagnostics: buildDiagnostics(),
      detectedAt: now,
    });
  }

  // 4. Sync Stall (block height hasn't increased in 5+ minutes)
  if (previousMetrics && currentMetrics.blockchain) {
    const currentBlock = currentMetrics.blockchain.blockHeight || 0;
    const prevBlock = previousMetrics.blockchain?.blockHeight || 0;
    const timeDiff = new Date(currentMetrics.timestamp).getTime() - new Date(previousMetrics.timestamp).getTime();
    const minutesSinceUpdate = timeDiff / (1000 * 60);

    if (currentBlock === prevBlock && currentBlock > 0 && minutesSinceUpdate >= 5) {
      issues.push({
        type: 'sync_stall',
        severity: 'high',
        title: 'Synchronization Stalled',
        description: `Block height has not increased for ${Math.round(minutesSinceUpdate)} minutes. Stuck at block ${currentBlock}.`,
        diagnostics: buildDiagnostics(),
        detectedAt: now,
      });
    }
  }

  // 5. Peer Drop
  const peers = currentMetrics.blockchain?.peers || 0;
  if (peers === 0) {
    issues.push({
      type: 'peer_drop',
      severity: 'critical',
      title: 'No Network Peers',
      description: 'Node has 0 connected peers. Network isolation detected.',
      diagnostics: buildDiagnostics(),
      detectedAt: now,
    });
  } else if (peers < 3) {
    issues.push({
      type: 'peer_drop',
      severity: 'high',
      title: 'Low Peer Count',
      description: `Node has only ${peers} peer(s) connected. Recommend at least 3 peers for healthy operation.`,
      diagnostics: buildDiagnostics(),
      detectedAt: now,
    });
  }

  // 6. Sync Slow (when syncing, rate below 10 blocks/min)
  if (currentMetrics.blockchain?.isSyncing && metricsHistory.length >= 2) {
    const recent = metricsHistory.slice(-2);
    if (recent.length === 2) {
      const blockDiff = recent[1].blockHeight - recent[0].blockHeight;
      const timeDiff = new Date(recent[1].timestamp).getTime() - new Date(recent[0].timestamp).getTime();
      const blocksPerMin = (blockDiff / timeDiff) * 60000;
      
      if (blocksPerMin < 10 && blocksPerMin >= 0) {
        issues.push({
          type: 'sync_slow',
          severity: 'medium',
          title: 'Slow Sync Rate',
          description: `Syncing at ${blocksPerMin.toFixed(1)} blocks/min (expected >10). Sync may take longer than normal.`,
          diagnostics: buildDiagnostics(),
          detectedAt: now,
        });
      }
    }
  }

  // 7. High CPU (>90% for 3+ consecutive checks)
  const cpu = currentMetrics.server?.cpuUsage || 0;
  if (cpu > 90) {
    highCpuCount++;
    if (highCpuCount >= 3) {
      issues.push({
        type: 'high_cpu',
        severity: 'medium',
        title: 'High CPU Usage',
        description: `CPU usage at ${cpu}% for multiple checks. System may be under heavy load.`,
        diagnostics: buildDiagnostics(),
        detectedAt: now,
      });
    }
  } else {
    highCpuCount = 0;
  }

  // 8. High Memory (>90%)
  const memoryPercent = currentMetrics.server?.memoryTotal > 0
    ? (currentMetrics.server.memoryUsed / currentMetrics.server.memoryTotal) * 100
    : 0;
  if (memoryPercent > 90) {
    issues.push({
      type: 'high_memory',
      severity: 'high',
      title: 'High Memory Usage',
      description: `Memory usage at ${memoryPercent.toFixed(1)}%. System may run out of memory.`,
      diagnostics: buildDiagnostics(),
      detectedAt: now,
    });
  }

  // 9. Disk Critical (>85%)
  const diskPercent = currentMetrics.server?.diskTotal > 0
    ? (currentMetrics.server.diskUsed / currentMetrics.server.diskTotal) * 100
    : 0;
  if (diskPercent > 95) {
    issues.push({
      type: 'disk_full',
      severity: 'critical',
      title: 'Disk Almost Full',
      description: `Disk usage at ${diskPercent.toFixed(1)}%. Critical — node will stop when disk is full!`,
      diagnostics: buildDiagnostics(),
      detectedAt: now,
    });
  } else if (diskPercent > 85) {
    issues.push({
      type: 'disk_critical',
      severity: 'high',
      title: 'Disk Space Critical',
      description: `Disk usage at ${diskPercent.toFixed(1)}%. Approaching full capacity.`,
      diagnostics: buildDiagnostics(),
      detectedAt: now,
    });
  }

  return issues;
}
