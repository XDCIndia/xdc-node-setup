'use client';

import { useState, useMemo, useEffect, useCallback } from 'react';
import DashboardLayout from '@/components/DashboardLayout';
import PeerMap from '@/components/PeerMap';
import { 
  Globe, 
  ArrowDownLeft, 
  ArrowUpRight,
  Network,
  MapPin,
  RefreshCw,
  Activity
} from 'lucide-react';

interface Peer {
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

interface PeersData {
  peers: Peer[];
  countries: Record<string, { name: string; count: number }>;
  totalPeers: number;
}

export default function PeersPage() {
  const [peersData, setPeersData] = useState<PeersData>({ peers: [], countries: {}, totalPeers: 0 });
  const [loading, setLoading] = useState(true);
  const [sortField, setSortField] = useState<keyof Peer>('country');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');

  const fetchPeers = useCallback(async () => {
    try {
      const res = await fetch('/api/peers', { cache: 'no-store' });
      if (res.ok) {
        const data = await res.json();
        setPeersData(data);
      }
    } catch (err) {
      console.error('Failed to fetch peers:', err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchPeers();
    const interval = setInterval(fetchPeers, 30000);
    return () => clearInterval(interval);
  }, [fetchPeers]);

  const sortedPeers = useMemo(() => {
    const sorted = [...peersData.peers];
    sorted.sort((a, b) => {
      const aVal = String(a[sortField] ?? '');
      const bVal = String(b[sortField] ?? '');
      const comparison = aVal.localeCompare(bVal);
      return sortDirection === 'asc' ? comparison : -comparison;
    });
    return sorted;
  }, [peersData.peers, sortField, sortDirection]);

  const geoStats = useMemo(() => {
    const countryCount = Object.keys(peersData.countries).length;
    const byContinent: Record<string, number> = {};
    
    const continentMap: Record<string, string> = {
      US: 'North America', CA: 'North America', MX: 'North America',
      DE: 'Europe', GB: 'Europe', FR: 'Europe', NL: 'Europe', IT: 'Europe', ES: 'Europe',
      SG: 'Asia', JP: 'Asia', KR: 'Asia', IN: 'Asia', CN: 'Asia', HK: 'Asia',
      AU: 'Oceania', NZ: 'Oceania',
      BR: 'South America', AR: 'South America',
    };

    for (const [code, info] of Object.entries(peersData.countries)) {
      const continent = continentMap[code.toUpperCase()] || 'Other';
      byContinent[continent] = (byContinent[continent] || 0) + info.count;
    }

    return {
      uniqueCountries: countryCount,
      byContinent,
      score: Math.min(100, countryCount * 10 + Object.keys(byContinent).length * 15),
    };
  }, [peersData.countries]);

  const handleSort = (field: keyof Peer) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  };

  return (
    <DashboardLayout>
      <div className="space-y-8">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-semibold text-[var(--text-primary)]">Peer Connections</h1>
            <p className="text-[var(--text-tertiary)] mt-1">Monitor your node's network topology</p>
          </div>
          <button
            onClick={fetchPeers}
            className="p-2 hover:bg-[var(--bg-hover)] rounded-lg transition-colors"
            title="Refresh"
          >
            <RefreshCw className={`w-4 h-4 text-[var(--text-tertiary)] ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>

        {/* Quick Stats */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="card-xdc">
            <div className="section-header mb-1">Total Peers</div>
            <div className="text-2xl font-bold font-mono-nums">{peersData.totalPeers}</div>
          </div>
          <div className="card-xdc">
            <div className="section-header mb-1 text-[var(--success)]">Inbound</div>
            <div className="text-2xl font-bold font-mono-nums text-[var(--success)]">
              {peersData.peers.filter(p => p.inbound).length}
            </div>
          </div>
          <div className="card-xdc">
            <div className="section-header mb-1 text-[var(--accent-blue)]">Outbound</div>
            <div className="text-2xl font-bold font-mono-nums text-[var(--accent-blue)]">
              {peersData.peers.filter(p => !p.inbound).length}
            </div>
          </div>
          <div className="card-xdc">
            <div className="section-header mb-1">Countries</div>
            <div className="text-2xl font-bold font-mono-nums">{geoStats.uniqueCountries}</div>
          </div>
        </div>

        {/* Peer Map */}
        <PeerMap peers={peersData} />

        {/* Secondary Stats */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="card-xdc">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-xl bg-[rgba(16,185,129,0.1)] flex items-center justify-center text-[var(--success)]">
                <MapPin className="w-5 h-5" />
              </div>
              <div>
                <h2 className="text-lg font-semibold text-[var(--text-primary)]">Geo Diversity</h2>
                <p className="text-xs text-[var(--text-tertiary)]">Network decentralization</p>
              </div>
            </div>
            
            <div className="text-center mb-4">
              <div className="text-4xl font-bold font-mono-nums" style={{ 
                color: geoStats.score >= 80 ? 'var(--success)' : geoStats.score >= 50 ? 'var(--warning)' : 'var(--critical)' 
              }}>
                {geoStats.score}
              </div>
              <div className="text-xs text-[var(--text-tertiary)]">Diversity Score</div>
            </div>
            
            <div className="space-y-3">
              <div className="flex justify-between text-sm">
                <span className="text-[var(--text-tertiary)]">Countries</span>
                <span>{geoStats.uniqueCountries}</span>
              </div>
            </div>
            
            <div className="mt-4 pt-4 border-t border-[var(--border-subtle)]">
              <div className="text-xs font-medium mb-2">Distribution</div>
              {Object.entries(geoStats.byContinent).map(([continent, count]) => (
                <div key={continent} className="flex items-center justify-between text-sm mb-1">
                  <span className="text-[var(--text-tertiary)]">{continent}</span>
                  <span>{count}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="card-xdc">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-xl bg-[rgba(139,92,246,0.1)] flex items-center justify-center text-[var(--purple)]">
                <Activity className="w-5 h-5" />
              </div>
              <div>
                <h2 className="text-lg font-semibold text-[var(--text-primary)]">Connection Status</h2>
                <p className="text-xs text-[var(--text-tertiary)]">Peer network health</p>
              </div>
            </div>
            
            <div className="space-y-3">
              <div className="flex justify-between text-sm">
                <span className="text-[var(--text-tertiary)]">Inbound</span>
                <span className="text-[var(--success)]">{peersData.peers.filter(p => p.inbound).length}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-[var(--text-tertiary)]">Outbound</span>
                <span className="text-[var(--accent-blue)]">{peersData.peers.filter(p => !p.inbound).length}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-[var(--text-tertiary)]">Total</span>
                <span>{peersData.totalPeers}</span>
              </div>
            </div>
          </div>

          <div className="card-xdc">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-xl bg-[rgba(30,144,255,0.1)] flex items-center justify-center text-[var(--accent-blue)]">
                <Network className="w-5 h-5" />
              </div>
              <div>
                <h2 className="text-lg font-semibold text-[var(--text-primary)]">Top Locations</h2>
                <p className="text-xs text-[var(--text-tertiary)]">Peer concentration</p>
              </div>
            </div>
            
            <div className="space-y-2">
              {Object.entries(peersData.countries)
                .sort((a, b) => b[1].count - a[1].count)
                .slice(0, 5)
                .map(([code, info], idx) => (
                  <div key={code} className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className="text-xs text-[var(--text-tertiary)] w-4">{idx + 1}.</span>
                      <span className="w-5 h-5 rounded-full bg-[#1E90FF]/20 flex items-center justify-center text-[9px] font-bold text-[#1E90FF]">
                        {code.toUpperCase()}
                      </span>
                      <span className="text-sm text-[var(--text-primary)]">{info.name}</span>
                    </div>
                    <span className="text-sm font-mono-nums">{info.count}</span>
                  </div>
                ))}
              {Object.keys(peersData.countries).length === 0 && (
                <div className="text-sm text-[var(--text-tertiary)] text-center py-4">No location data</div>
              )}
            </div>
          </div>
        </div>
      </div>
    </DashboardLayout>
  );
}
