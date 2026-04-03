/**
 * SkyNet Bridge - Push SkyOne metrics to SkyNet for real-time monitoring
 * 
 * This module sends heartbeat updates from SkyOne dashboard to the central
 * SkyNet monitoring system at skynet.xdcindia.com
 */

const SKYNET_API_URL = process.env.SKYNET_API_URL || 'https://skynet.xdcindia.com/api/v1';
const SKYNET_NODE_ID = process.env.SKYNET_NODE_ID || '';
const SKYNET_API_KEY = process.env.SKYNET_API_KEY || '';

/**
 * Push metrics to SkyNet heartbeat endpoint
 * Fires and forgets - doesn't block or throw on failure
 */
export async function pushToSkyNet(metrics: any, peersList?: any[]): Promise<void> {
  // Skip if no node ID (API key optional — SkyNet accepts keyless heartbeats for registered nodes)
  if (!SKYNET_NODE_ID) {
    return;
  }
  
  try {
    // Format peers with enode for SkyNet peer_snapshots
    const peers = (peersList || []).slice(0, 50).map((p: any) => ({
      enode: p.enode || '',
      name: p.name || '',
      protocols: Object.keys(p.protocols || {}),
      direction: p.network?.inbound ? 'inbound' : 'outbound',
    }));

    const payload = {
      nodeId: SKYNET_NODE_ID,
      blockHeight: metrics.blockchain?.blockHeight || 0,
      syncing: metrics.blockchain?.isSyncing || false,
      syncProgress: metrics.blockchain?.syncPercent || 0,
      peerCount: metrics.blockchain?.peers || 0,
      clientType: metrics.nodeConfig?.clientType || metrics.blockchain?.clientType || 'geth',
      clientVersion: metrics.blockchain?.clientVersion || '',
      chainDataSize: metrics.storage?.chainDataSize ? Math.round(metrics.storage.chainDataSize / (1024 * 1024 * 1024) * 10) / 10 : 0,
      databaseSize: metrics.storage?.databaseSize ? Math.round(metrics.storage.databaseSize / (1024 * 1024 * 1024) * 10) / 10 : 0,
      storageType: metrics.storage?.storageType || metrics.server?.storageType || undefined,
      iopsEstimate: metrics.storage?.iopsEstimate || metrics.server?.iopsEstimate || undefined,
      mountPoint: metrics.storage?.mountPoint || undefined,
      mountPercent: metrics.storage?.mountPercent || undefined,
      peers,
      system: metrics.server || {},
      timestamp: new Date().toISOString(),
    };
    
    await fetch(`${SKYNET_API_URL}/nodes/heartbeat`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(SKYNET_API_KEY ? { 'Authorization': `Bearer ${SKYNET_API_KEY}` } : {}),
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(5000),
    });
  } catch (e) {
    // Silent fail — don't break metrics if SkyNet is down
    // In production, you might want to log this to a monitoring service
  }
}
