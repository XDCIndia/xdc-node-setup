/**
 * LFG (Live Fleet Gateway) - Auto-peer injection
 * 
 * Automatically fetches healthy peers from SkyNet when local peer count
 * drops below the MIN_PEERS threshold.
 */

const SKYNET_URL = process.env.SKYNET_API_URL || 'https://skynet.xdcindia.com/api/v1';
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
 * Add a single peer to local XDC node via admin_addPeer RPC
 */
async function addSinglePeer(rpcUrl: string, enode: string): Promise<boolean> {
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
    return data.result === true;
  } catch {
    return false;
  }
}

// Cooldown: don't re-trigger LFG within 10 minutes of last run
const LFG_COOLDOWN_MS = 10 * 60 * 1000;
const MAX_PEERS_PER_BATCH = 3;
let lastLFGRun = 0;

/**
 * Main LFG check - triggers peer injection if peer count is below threshold
 * Non-blocking: adds peers with short delays (2-5s), completes quickly
 */
export async function lfgCheck(
  rpcUrl: string, 
  currentPeers: number
): Promise<LFGResult> {
  // Don't trigger if we have enough peers
  if (currentPeers >= MIN_PEERS) {
    return { triggered: false, added: 0, failed: 0 };
  }

  // Don't trigger if in cooldown
  if (Date.now() - lastLFGRun < LFG_COOLDOWN_MS) {
    return { triggered: false, added: 0, failed: 0 };
  }
  
  lastLFGRun = Date.now();
  
  console.log(`[LFG] Peer count ${currentPeers} < ${MIN_PEERS}, fetching healthy peers...`);
  
  const enodes = await fetchHealthyPeers();
  if (enodes.length === 0) {
    console.log('[LFG] No healthy peers available from SkyNet');
    return { triggered: true, added: 0, failed: 0, enodesFetched: 0 };
  }
  
  // Shuffle and pick a small batch
  const shuffled = enodes.sort(() => Math.random() - 0.5);
  const enodesToAdd = shuffled.slice(0, MAX_PEERS_PER_BATCH);
  console.log(`[LFG] Adding ${enodesToAdd.length} peers from ${enodes.length} available...`);
  
  // Add peers with short delays (2-5s) — fast enough to not block metrics polls
  let added = 0;
  let failed = 0;
  for (const enode of enodesToAdd) {
    const ok = await addSinglePeer(rpcUrl, enode);
    if (ok) {
      added++;
      console.log(`[LFG] ✅ Added ${enode.slice(0, 50)}...`);
    } else {
      failed++;
    }
    // Short delay between adds (2-5s)
    if (added + failed < enodesToAdd.length) {
      await new Promise(r => setTimeout(r, 2000 + Math.random() * 3000));
    }
  }
  
  console.log(`[LFG] Done: ${added} added, ${failed} failed. Cooldown ${LFG_COOLDOWN_MS / 60000}min.`);
  
  return { triggered: true, added, failed, enodesFetched: enodes.length };
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
