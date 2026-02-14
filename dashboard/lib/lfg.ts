/**
 * LFG (Live Fleet Gateway) - Auto-peer injection
 * 
 * Automatically fetches healthy peers from SkyNet when local peer count
 * drops below the MIN_PEERS threshold.
 */

const SKYNET_URL = process.env.SKYNET_API_URL || 'https://net.xdc.network/api/v1';
const MIN_PEERS = parseInt(process.env.MIN_PEERS || '5');

interface LFGResult {
  triggered: boolean;
  added: number;
  failed: number;
  enodesFetched?: number;
}

/**
 * Fetch healthy peers from SkyNet's LFG endpoint
 */
export async function fetchHealthyPeers(): Promise<string[]> {
  try {
    const res = await fetch(`${SKYNET_URL}/peers/healthy?format=json`, {
      signal: AbortSignal.timeout(10000),
    });
    
    if (!res.ok) {
      console.error(`[LFG] SkyNet returned ${res.status}`);
      return [];
    }
    
    const data = await res.json();
    return data.enodes || [];
  } catch (error) {
    console.error('[LFG] Failed to fetch healthy peers:', error);
    return [];
  }
}

/**
 * Add peers to local XDC node via admin_addPeer RPC
 */
export async function addPeers(rpcUrl: string, enodes: string[]): Promise<{ added: number; failed: number }> {
  let added = 0;
  let failed = 0;
  
  for (const enode of enodes) {
    try {
      const res = await fetch(rpcUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          jsonrpc: '2.0', 
          method: 'admin_addPeer', 
          params: [enode], 
          id: 1 
        }),
        signal: AbortSignal.timeout(5000),
      });
      
      const data = await res.json();
      if (data.result === true) {
        added++;
      } else {
        failed++;
        console.log(`[LFG] addPeer returned false for ${enode.slice(0, 40)}...`);
      }
    } catch (error) {
      failed++;
      console.error(`[LFG] addPeer failed for ${enode.slice(0, 40)}...:`, error);
    }
    
    // Small delay between requests to avoid overwhelming the node
    if (added + failed < enodes.length) {
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }
  
  return { added, failed };
}

/**
 * Main LFG check - triggers peer injection if peer count is below threshold
 */
export async function lfgCheck(
  rpcUrl: string, 
  currentPeers: number
): Promise<LFGResult> {
  // Don't trigger if we have enough peers
  if (currentPeers >= MIN_PEERS) {
    return { triggered: false, added: 0, failed: 0 };
  }
  
  console.log(`[LFG] Peer count ${currentPeers} < ${MIN_PEERS}, fetching healthy peers...`);
  
  const enodes = await fetchHealthyPeers();
  if (enodes.length === 0) {
    console.log('[LFG] No healthy peers available from SkyNet');
    return { triggered: true, added: 0, failed: 0, enodesFetched: 0 };
  }
  
  console.log(`[LFG] Fetched ${enodes.length} healthy peers, adding up to 20...`);
  
  // Add up to 20 peers at a time to avoid overwhelming the node
  const enodesToAdd = enodes.slice(0, 20);
  const result = await addPeers(rpcUrl, enodesToAdd);
  
  console.log(`[LFG] Added ${result.added} peers, ${result.failed} failed`);
  
  return { 
    triggered: true, 
    ...result,
    enodesFetched: enodes.length 
  };
}

/**
 * Get LFG configuration info
 */
export function getLFGConfig(): { minPeers: number; skyNetUrl: string } {
  return {
    minPeers: MIN_PEERS,
    skyNetUrl: SKYNET_URL,
  };
}
