'use client';

import { useEffect, useState, useCallback } from 'react';
import Header from '@/components/Header';
import Dock from '@/components/Dock';
import BlockchainCard from '@/components/BlockchainCard';
import ConsensusPanel from '@/components/ConsensusPanel';
import SyncPanel from '@/components/SyncPanel';
import TxPoolPanel from '@/components/TxPoolPanel';
import ServerStats from '@/components/ServerStats';
import StoragePanel from '@/components/StoragePanel';
import PeerMap from '@/components/PeerMap';
import type { MetricsData, PeersData } from '@/lib/types';

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
  },
  consensus: {
    epoch: 98000,
    epochProgress: 65,
    masternodeStatus: 'Active',
    signingRate: 98.5,
    stakeAmount: 10000000,
    walletBalance: 10500000,
    totalRewards: 500000,
    penalties: 0,
  },
  sync: {
    syncRate: 125,
    reorgsAdd: 12,
    reorgsDrop: 3,
  },
  txpool: {
    pending: 150,
    queued: 45,
    slots: 8000,
    valid: 1200,
    invalid: 5,
    underpriced: 8,
  },
  server: {
    cpuUsage: 35,
    memoryUsed: 8 * 1024 * 1024 * 1024,
    memoryTotal: 16 * 1024 * 1024 * 1024,
    diskUsed: 250 * 1024 * 1024 * 1024,
    diskTotal: 500 * 1024 * 1024 * 1024,
    goroutines: 1250,
    sysLoad: 2.5,
    procLoad: 1.8,
  },
  storage: {
    chainDataSize: 120 * 1024 * 1024 * 1024,
    diskReadRate: 15 * 1024 * 1024,
    diskWriteRate: 8 * 1024 * 1024,
    compactTime: 0.5,
    trieCacheHitRate: 92.5,
    trieCacheMiss: 1250,
  },
  network: {
    totalPeers: 25,
    inboundTraffic: 5 * 1024 * 1024,
    outboundTraffic: 3 * 1024 * 1024,
    dialSuccess: 45,
    dialTotal: 50,
    eth100Traffic: 50 * 1024 * 1024,
    eth63Traffic: 20 * 1024 * 1024,
    connectionErrors: 2,
  },
  timestamp: new Date().toISOString(),
};

const defaultPeers: PeersData = {
  peers: [],
  countries: {},
  totalPeers: 0,
};

export default function Home() {
  const [metrics, setMetrics] = useState<MetricsData>(defaultMetrics);
  const [peers, setPeers] = useState<PeersData>(defaultPeers);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [connected, setConnected] = useState(false);
  const [countdown, setCountdown] = useState(REFRESH_INTERVAL);

  const fetchData = useCallback(async () => {
    try {
      setError(null);

      const [metricsRes, peersRes] = await Promise.all([
        fetch('/api/metrics', { cache: 'no-store' }),
        fetch('/api/peers', { cache: 'no-store' }),
      ]);

      if (!metricsRes.ok) {
        throw new Error(`Metrics API error: ${metricsRes.status}`);
      }

      const metricsData = await metricsRes.json();

      if (metricsData.error) {
        throw new Error(metricsData.error);
      }

      setMetrics(metricsData);
      setConnected(true);

      if (peersRes.ok) {
        const peersData = await peersRes.json();
        setPeers(peersData);
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
    return (
      <div className="min-h-screen bg-[#0B1120] flex items-center justify-center">
        <div className="text-center">
          <div className="w-16 h-16 border-4 border-[#1E90FF] border-t-transparent rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-[#8B8CA7]">Connecting to XDC node...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[#0B1120]">
      <Header
        lastUpdated={metrics.timestamp}
        connected={connected}
        nextRefresh={countdown}
        refreshInterval={REFRESH_INTERVAL}
      />

      <Dock />

      <main className="px-3 py-4 sm:px-4 lg:px-6">
        {error && (
          <div className="mb-6 p-4 rounded-xl bg-[#FF4560]/10 border border-[#FF4560]/30 text-[#FF4560] animate-fade-in">
            <div className="flex items-center gap-2">
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span>{error}</span>
            </div>
          </div>
        )}

        {/* Grid Layout - Mobile-first, Blockchain Data First, World Map Last */}
        <div className="grid grid-cols-1 md:grid-cols-12 gap-4 sm:gap-6">
          {/* 1. Hero - Blockchain Status */}
          <div className="md:col-span-12">
            <BlockchainCard data={metrics.blockchain} />
          </div>

          {/* 2. XDPoS Consensus */}
          <div className="md:col-span-12 xl:col-span-8">
            <ConsensusPanel data={metrics.consensus} />
          </div>

          {/* 3. Sync & Performance */}
          <div className="md:col-span-12 xl:col-span-4">
            <SyncPanel data={metrics.sync} blockchain={metrics.blockchain} />
          </div>

          {/* 4. Transaction Pool */}
          <div className="md:col-span-12 lg:col-span-6 xl:col-span-5">
            <TxPoolPanel data={metrics.txpool} />
          </div>

          {/* 5. Server Stats */}
          <div className="md:col-span-12 lg:col-span-6 xl:col-span-7">
            <ServerStats data={metrics.server} />
          </div>

          {/* 6. Storage & Database */}
          <div className="md:col-span-12">
            <StoragePanel data={metrics.storage} />
          </div>

          {/* 7. World Peer Map - LAST (Full Width) */}
          <div className="md:col-span-12">
            <PeerMap peers={peers} />
          </div>
        </div>
      </main>

      <footer className="border-t border-[#2a3352] mt-8 py-6">
        <div className="px-4 text-center text-sm text-[#8B8CA7]">
          <p>XDC Node Dashboard &copy; {new Date().getFullYear()}</p>
          <p className="mt-1">Built with Next.js 14 + ECharts &middot; Auto-refresh every {REFRESH_INTERVAL}s</p>
        </div>
      </footer>
    </div>
  );
}
