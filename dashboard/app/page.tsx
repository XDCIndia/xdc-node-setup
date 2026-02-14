'use client';

import { useEffect, useState, useCallback, useRef } from 'react';
import DashboardLayout from '@/components/DashboardLayout';
import IssueBanner from '@/components/IssueBanner';
import HeroSection from '@/components/HeroSection';
import StatsGrid from '@/components/StatsGrid';
import ConsensusPanel from '@/components/ConsensusPanel';
import SyncPanel from '@/components/SyncPanel';
import TxPoolPanel from '@/components/TxPoolPanel';
import ServerStats from '@/components/ServerStats';
import StoragePanel from '@/components/StoragePanel';
import PeerMap from '@/components/PeerMap';
import SkyNetStatus from '@/components/SkyNetStatus';
import { LFGBadge } from '@/components/LFGBadge';
import type { MetricsData, PeersData } from '@/lib/types';

interface MetricsHistory {
  timestamps: string[];
  blockHeight: number[];
  peers: number[];
  cpu: number[];
  memory: number[];
  disk: number[];
  syncPercent: number[];
  txPoolPending: number[];
}

const REFRESH_INTERVAL = parseInt(process.env.NEXT_PUBLIC_REFRESH_INTERVAL || '10');

const defaultMetrics: MetricsData = {
  blockchain: {
    blockHeight: 0,
    highestBlock: 0,
    syncPercent: 0,
    isSyncing: false,
    peers: 0,
    peersInbound: 0,
    peersOutbound: 0,
    uptime: 0,
    chainId: '50',
    coinbase: '',
    ethstatsName: '',
    clientVersion: '',
  },
  consensus: {
    epoch: 0,
    epochProgress: 0,
    masternodeStatus: 'Inactive',
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
    pending: 0,
    queued: 0,
    slots: 0,
    valid: 0,
    invalid: 0,
    underpriced: 0,
  },
  server: {
    cpuUsage: 0,
    memoryUsed: 0,
    memoryTotal: 16 * 1024 * 1024 * 1024,
    diskUsed: 0,
    diskTotal: 500 * 1024 * 1024 * 1024,
    goroutines: 0,
    sysLoad: 0,
    procLoad: 0,
  },
  storage: {
    chainDataSize: 0,
    databaseSize: 0,
    diskReadRate: 0,
    diskWriteRate: 0,
    compactTime: 0,
    trieCacheHitRate: 0,
    trieCacheMiss: 0,
  },
  network: {
    totalPeers: 0,
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

const defaultPeers: PeersData = {
  peers: [],
  countries: {},
  totalPeers: 0,
};

// Skeleton loading component
function Skeleton({ className }: { className?: string }) {
  return <div className={`skeleton ${className || ''}`} />;
}

function LoadingState() {
  return (
    <DashboardLayout>
      <div className="space-y-6">
        {/* Hero skeleton */}
        <div className="card-hero mb-8">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div>
              <Skeleton className="w-32 h-4 mb-3" />
              <Skeleton className="w-48 h-12 mb-2" />
              <Skeleton className="w-36 h-4" />
            </div>
            <div className="flex justify-center">
              <Skeleton className="w-32 h-32 rounded-full" />
            </div>
            <div className="space-y-4">
              <Skeleton className="w-full h-20 rounded-xl" />
              <div className="grid grid-cols-2 gap-4">
                <Skeleton className="h-16 rounded-xl" />
                <Skeleton className="h-16 rounded-xl" />
              </div>
            </div>
          </div>
        </div>
        
        {/* Stats grid skeleton */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          {[1, 2, 3, 4].map(i => (
            <div key={i} className="card-xdc">
              <Skeleton className="w-10 h-10 rounded-xl mb-3" />
              <Skeleton className="w-20 h-4 mb-2" />
              <Skeleton className="w-28 h-8" />
            </div>
          ))}
        </div>
        
        {/* Panels skeleton */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
          <div className="card-xdc">
            <div className="flex items-center gap-3 mb-5">
              <Skeleton className="w-10 h-10 rounded-xl" />
              <div>
                <Skeleton className="w-32 h-5 mb-1" />
                <Skeleton className="w-24 h-4" />
              </div>
            </div>
            <Skeleton className="w-full h-4 rounded-full mb-6" />
            <div className="grid grid-cols-2 gap-4">
              <Skeleton className="h-24 rounded-xl" />
              <Skeleton className="h-24 rounded-xl" />
            </div>
          </div>
          <div className="card-xdc">
            <div className="flex items-center gap-3 mb-5">
              <Skeleton className="w-10 h-10 rounded-xl" />
              <div>
                <Skeleton className="w-32 h-5 mb-1" />
                <Skeleton className="w-24 h-4" />
              </div>
            </div>
            <Skeleton className="w-full h-40 rounded-xl" />
          </div>
        </div>
        
        {/* Map skeleton */}
        <div className="card-xdc">
          <div className="flex items-center justify-between mb-5">
            <div className="flex items-center gap-3">
              <Skeleton className="w-10 h-10 rounded-xl" />
              <div>
                <Skeleton className="w-40 h-5 mb-1" />
                <Skeleton className="w-32 h-4" />
              </div>
            </div>
          </div>
          <Skeleton className="w-full h-[400px] rounded-xl" />
        </div>
      </div>
    </DashboardLayout>
  );
}

export default function Home() {
  const [metrics, setMetrics] = useState<MetricsData>(defaultMetrics);
  const [peers, setPeers] = useState<PeersData>(defaultPeers);
  const [history, setHistory] = useState<MetricsHistory>({
    timestamps: [],
    blockHeight: [],
    peers: [],
    cpu: [],
    memory: [],
    disk: [],
    syncPercent: [],
    txPoolPending: [],
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [connected, setConnected] = useState(false);
  const [countdown, setCountdown] = useState(REFRESH_INTERVAL);
  
  // Track block height changes
  const prevBlockHeightRef = useRef<number>(0);
  const lastUpdateTimeRef = useRef<number>(Date.now());
  const [blockIncrease, setBlockIncrease] = useState<number>(0);
  const [blocksPerMinute, setBlocksPerMinute] = useState<number>(0);

  const fetchData = useCallback(async () => {
    try {
      const [metricsRes, peersRes, historyRes] = await Promise.all([
        fetch('/api/metrics', { cache: 'no-store' }),
        fetch('/api/peers', { cache: 'no-store' }),
        fetch('/api/metrics/history', { cache: 'no-store' }),
      ]);

      if (!metricsRes.ok) {
        setError(`Metrics API error: ${metricsRes.status}`);
        setConnected(false);
        setLoading(false);
        return;
      }

      const metricsData = await metricsRes.json();

      // Always update metrics, even if RPC is down (diagnostics are still available)
      setMetrics(metricsData);
      setConnected(metricsData.rpcConnected !== false);

      // Clear error if RPC is connected
      if (metricsData.rpcConnected) {
        setError(null);
      } else if (metricsData.rpcError) {
        setError(metricsData.rpcError);
      }
      
      // Calculate block increase
      const currentBlock = metricsData.blockchain.blockHeight;
      const prevBlock = prevBlockHeightRef.current;
      const now = Date.now();
      const timeDelta = (now - lastUpdateTimeRef.current) / 1000; // seconds
      
      if (prevBlock > 0 && currentBlock > prevBlock && timeDelta > 0) {
        const increase = currentBlock - prevBlock;
        setBlockIncrease(increase);
        
        // Calculate blocks per minute
        const bpm = (increase / timeDelta) * 60;
        setBlocksPerMinute(Math.round(bpm * 10) / 10);
      }
      
      // Update refs
      prevBlockHeightRef.current = currentBlock;
      lastUpdateTimeRef.current = now;

      if (peersRes.ok) {
        const peersData = await peersRes.json();
        setPeers(peersData);
      }

      if (historyRes.ok) {
        const historyData = await historyRes.json();
        setHistory(historyData);
      }
    } catch (err) {
      console.error('Error fetching data:', err);
      setError(err instanceof Error ? err.message : 'Failed to fetch data');
      setConnected(false);
    } finally {
      setLoading(false);
      setCountdown(REFRESH_INTERVAL);
    }
  }, []);

  useEffect(() => {
    fetchData();
    const intervalId = setInterval(fetchData, REFRESH_INTERVAL * 1000);
    return () => clearInterval(intervalId);
  }, [fetchData]);

  useEffect(() => {
    const countdownId = setInterval(() => {
      setCountdown(prev => Math.max(0, prev - 1));
    }, 1000);
    return () => clearInterval(countdownId);
  }, []);

  if (loading) {
    return <LoadingState />;
  }

  return (
    <DashboardLayout>
      {/* Issue Banner - Shows active detected issues */}
      <IssueBanner />
      
      {/* LFG Badge - Shows when Live Fleet Gateway is active */}
      <LFGBadge />
      
      <div className="space-y-6">
        {/* Error Banner with Diagnostics - Show when node is unhealthy */}
        {(error || metrics.nodeStatus === 'error' || metrics.nodeStatus === 'offline' || !metrics.rpcConnected) && metrics.diagnostics && (
          <div className="card-xdc border-[var(--critical)] bg-[rgba(239,68,68,0.05)] animate-fade-in">
            <div className="flex items-start gap-3 mb-4">
              <div className="w-10 h-10 rounded-xl bg-[rgba(239,68,68,0.1)] flex items-center justify-center flex-shrink-0">
                <svg className="w-6 h-6 text-[var(--critical)]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
              </div>
              <div className="flex-1">
                <h3 className="text-lg font-semibold text-[var(--critical)] mb-1">
                  {metrics.nodeStatus === 'offline' ? 'Node Offline' : 'Node Error Detected'}
                </h3>
                <p className="text-[var(--text-secondary)] text-sm mb-3">
                  {error || metrics.rpcError || 'The XDC node is not responding. Diagnostics and system stats are shown below.'}
                </p>
                
                {/* Diagnostics Info */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
                  <div className="bg-[var(--bg-card)] rounded-lg p-3 border border-[var(--border-subtle)]">
                    <div className="text-xs text-[var(--text-tertiary)] uppercase mb-1">Container Status</div>
                    <div className="text-sm font-medium text-[var(--text-primary)]">
                      {metrics.diagnostics.containerStatus || 'Unknown'}
                    </div>
                  </div>
                  <div className="bg-[var(--bg-card)] rounded-lg p-3 border border-[var(--border-subtle)]">
                    <div className="text-xs text-[var(--text-tertiary)] uppercase mb-1">Last Known Block</div>
                    <div className="text-sm font-medium text-[var(--text-primary)]">
                      {metrics.diagnostics.lastKnownBlock || metrics.blockchain.blockHeight || 'N/A'}
                    </div>
                  </div>
                </div>

                {/* Error Messages */}
                {metrics.diagnostics.errors && metrics.diagnostics.errors.length > 0 && (
                  <div className="mb-4">
                    <div className="text-xs text-[var(--text-tertiary)] uppercase mb-2">Recent Errors</div>
                    <div className="space-y-1">
                      {metrics.diagnostics.errors.slice(0, 5).map((err, i) => (
                        <div key={i} className="text-xs text-[var(--critical)] bg-[rgba(239,68,68,0.05)] px-3 py-2 rounded border border-[rgba(239,68,68,0.2)] font-mono">
                          {err}
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Recent Logs Viewer */}
                {metrics.diagnostics.recentLogs && metrics.diagnostics.recentLogs.length > 0 && (
                  <div>
                    <div className="text-xs text-[var(--text-tertiary)] uppercase mb-2">Recent Logs (Last 20 lines)</div>
                    <div className="bg-[var(--bg-body)] rounded-lg p-3 border border-[var(--border-subtle)] max-h-64 overflow-y-auto scrollbar-thin">
                      <pre className="text-xs text-[var(--text-secondary)] whitespace-pre-wrap break-all font-mono">
                        {metrics.diagnostics.recentLogs.join('\n')}
                      </pre>
                    </div>
                  </div>
                )}
              </div>
            </div>
          </div>
        )}
        {/* Hero - Blockchain Status */}
        <HeroSection 
          data={metrics.blockchain}
          nodeConfig={metrics.nodeConfig}
          blockHeightHistory={history.blockHeight}
          blockIncrease={blockIncrease}
          blocksPerMinute={blocksPerMinute}
        />

        {/* Stats Grid */}
        <StatsGrid metrics={metrics} />

        {/* SkyNet Status */}
        <SkyNetStatus />

        {/* Consensus + Sync */}
        <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
          <div className="xl:col-span-2">
            <ConsensusPanel data={metrics.consensus} />
          </div>
          <div className="xl:col-span-1">
            <SyncPanel 
              data={metrics.sync} 
              blockchain={metrics.blockchain}
              syncHistory={history.syncPercent}
            />
          </div>
        </div>

        {/* Transaction Pool + Server Stats */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <TxPoolPanel data={metrics.txpool} />
          <ServerStats data={metrics.server} />
        </div>

        {/* Storage */}
        <StoragePanel data={metrics.storage} />

        {/* World Peer Map */}
        <PeerMap peers={peers} />

        {/* Footer */}
        <div className="border-t border-[var(--border-subtle)] pt-6 mt-8">
          <div className="text-center text-sm text-[var(--text-tertiary)]">
            <p>XDC SkyOne &copy; {new Date().getFullYear()}</p>
            <p className="mt-1">
              Built with Next.js 14 &middot; Auto-refresh every {REFRESH_INTERVAL}s
            </p>
          </div>
        </div>
      </div>
    </DashboardLayout>
  );
}
