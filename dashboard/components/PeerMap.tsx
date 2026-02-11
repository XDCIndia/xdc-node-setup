'use client';

import { useState, useMemo } from 'react';
import dynamic from 'next/dynamic';
import { Globe, ArrowDownLeft, ArrowUpRight, Users } from 'lucide-react';
import type { PeersData } from '@/lib/types';

// Dynamically import PeerMapChart to avoid SSR issues with echarts
const PeerMapChart = dynamic(() => import('./PeerMapChart'), { 
  ssr: false,
  loading: () => (
    <div className="flex items-center justify-center h-[300px] sm:h-[350px] lg:h-[450px]">
      <div className="w-12 h-12 border-4 border-[#1E90FF] border-t-transparent rounded-full animate-spin"></div>
    </div>
  )
});

interface PeerMapProps {
  peers: PeersData;
}

export default function PeerMap({ peers }: PeerMapProps) {
  const [selectedCountry, setSelectedCountry] = useState<string | null>(null);
  const [sortBy, setSortBy] = useState<'country' | 'direction'>('country');

  // Top countries for sidebar
  const sortedCountries = useMemo(() => {
    return Object.entries(peers.countries || {})
      .sort((a, b) => b[1].count - a[1].count)
      .slice(0, 10);
  }, [peers.countries]);

  // Sort peers for table
  const sortedPeers = useMemo(() => {
    const list = [...(peers.peers || [])];
    if (sortBy === 'country') {
      return list.sort((a, b) => a.country.localeCompare(b.country));
    }
    return list.sort((a, b) => (a.inbound === b.inbound ? 0 : a.inbound ? -1 : 1));
  }, [peers.peers, sortBy]);

  // Stats
  const inboundCount = peers.peers?.filter(p => p.inbound).length || 0;
  const outboundCount = peers.peers?.filter(p => !p.inbound).length || 0;

  return (
    <div id="map" className="card-premium p-4 sm:p-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between mb-5 gap-4">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#00E396]/20 to-[#1E90FF]/20 flex items-center justify-center">
            <Globe className="w-5 h-5 text-[#00E396]" />
          </div>
          <div>
            <h2 className="text-lg font-bold text-[#E8E8F0]">Global Peer Distribution</h2>
            <div className="flex items-center gap-2">
              <span className="status-dot active" />
              <span className="text-sm text-[#8B8CA7]">Real-time peer locations</span>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-4 sm:gap-6">
          <div className="text-center sm:text-right">
            <div className="text-xs text-[#8B8CA7] flex items-center gap-1 justify-center sm:justify-end">
              <ArrowDownLeft className="w-3 h-3" /> Inbound
            </div>
            <div className="text-lg sm:text-xl font-bold text-[#00E396]">{inboundCount}</div>
          </div>
          <div className="text-center sm:text-right">
            <div className="text-xs text-[#8B8CA7] flex items-center gap-1 justify-center sm:justify-end">
              <ArrowUpRight className="w-3 h-3" /> Outbound
            </div>
            <div className="text-lg sm:text-xl font-bold text-[#1E90FF]">{outboundCount}</div>
          </div>
          <div className="text-center sm:text-right">
            <div className="text-2xl sm:text-3xl font-bold text-[#1E90FF]">{peers.totalPeers || 0}</div>
            <div className="text-xs sm:text-sm text-[#8B8CA7] flex items-center gap-1 justify-center sm:justify-end">
              <Users className="w-3 h-3" /> Total Peers
            </div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-5">
        {/* Map */}
        <div className="lg:col-span-3 relative">
          {/* Legend */}
          <div className="absolute top-2 left-2 z-10 flex flex-wrap gap-2 text-xs">
            <div className="flex items-center gap-1.5 bg-[#0B1120]/80 px-2 py-1 rounded-full border border-[#2a3352]">
              <span className="w-2 h-2 rounded-full bg-[#00E396] animate-pulse"></span>
              <span className="text-[#8B8CA7]">In</span>
            </div>
            <div className="flex items-center gap-1.5 bg-[#0B1120]/80 px-2 py-1 rounded-full border border-[#2a3352]">
              <span className="w-2 h-2 rounded-full bg-[#1E90FF] animate-pulse"></span>
              <span className="text-[#8B8CA7]">Out</span>
            </div>
          </div>

          <PeerMapChart peers={peers} />
        </div>

        {/* Country List */}
        <div className="lg:col-span-1">
          <div className="bg-[#0B1120]/50 rounded-xl p-4 h-full">
            <div className="section-title mb-4">Top Countries</div>

            {sortedCountries.length === 0 ? (
              <div className="text-center text-[#8B8CA7] py-8">
                No peer data available
              </div>
            ) : (
              <div className="space-y-2 max-h-[350px] overflow-y-auto scrollbar-thin">
                {sortedCountries.map(([code, info], index) => (
                  <div
                    key={code}
                    className={`flex items-center justify-between p-2 sm:p-3 rounded-lg cursor-pointer transition-all ${
                      selectedCountry === code
                        ? 'bg-[#1E90FF]/20 border border-[#1E90FF]/50'
                        : 'hover:bg-[#2a3352]/50 border border-transparent'
                    }`}
                    onClick={() => setSelectedCountry(selectedCountry === code ? null : code)}
                  >
                    <div className="flex items-center gap-2 sm:gap-3">
                      <span className="w-5 h-5 sm:w-6 sm:h-6 rounded-full bg-[#1a2035] flex items-center justify-center text-xs font-bold text-[#8B8CA7]">
                        {index + 1}
                      </span>
                      <span className="inline-flex">{getCountryFlag(code)}</span>
                      <span className="text-xs sm:text-sm text-[#E8E8F0] truncate max-w-[60px] sm:max-w-[80px]">{info.name}</span>
                    </div>
                    <span className="text-sm font-bold text-[#1E90FF]">{info.count}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Peer List Table */}
      <div className="mt-6">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between mb-4 gap-3">
          <h3 className="text-lg font-semibold text-[#E8E8F0]">Connected Peers</h3>
          <div className="flex items-center gap-2">
            <span className="text-sm text-[#8B8CA7]">Sort by:</span>
            <button
              onClick={() => setSortBy('country')}
              className={`px-3 py-1 rounded-lg text-sm transition-colors ${
                sortBy === 'country' 
                  ? 'bg-[#1E90FF]/20 text-[#1E90FF]' 
                  : 'text-[#8B8CA7] hover:text-[#E8E8F0]'
              }`}
            >
              Country
            </button>
            <button
              onClick={() => setSortBy('direction')}
              className={`px-3 py-1 rounded-lg text-sm transition-colors ${
                sortBy === 'direction' 
                  ? 'bg-[#1E90FF]/20 text-[#1E90FF]' 
                  : 'text-[#8B8CA7] hover:text-[#E8E8F0]'
              }`}
            >
              Direction
            </button>
          </div>
        </div>

        <div className="overflow-x-auto -mx-4 sm:mx-0">
          <table className="w-full min-w-[600px]">
            <thead>
              <tr className="border-b border-[#2a3352]">
                <th className="text-left py-3 px-4 text-xs sm:text-sm font-medium text-[#8B8CA7]">#</th>
                <th className="text-left py-3 px-4 text-xs sm:text-sm font-medium text-[#8B8CA7]">IP Address</th>
                <th className="text-left py-3 px-4 text-xs sm:text-sm font-medium text-[#8B8CA7]">Country</th>
                <th className="text-left py-3 px-4 text-xs sm:text-sm font-medium text-[#8B8CA7]">City</th>
                <th className="text-left py-3 px-4 text-xs sm:text-sm font-medium text-[#8B8CA7]">Direction</th>
                <th className="text-left py-3 px-4 text-xs sm:text-sm font-medium text-[#8B8CA7]">Client</th>
              </tr>
            </thead>
            <tbody>
              {sortedPeers.length === 0 ? (
                <tr>
                  <td colSpan={6} className="py-8 text-center text-[#8B8CA7]">
                    No peers connected
                  </td>
                </tr>
              ) : (
                sortedPeers.slice(0, 20).map((peer, index) => (
                  <tr 
                    key={peer.id} 
                    className="border-b border-[#2a3352]/50 hover:bg-[#1a2035]/50 transition-colors"
                  >
                    <td className="py-2 sm:py-3 px-4 text-xs sm:text-sm text-[#8B8CA7]">{index + 1}</td>
                    <td className="py-2 sm:py-3 px-4 text-xs sm:text-sm font-mono text-[#E8E8F0]">{peer.ip}:{peer.port}</td>
                    <td className="py-2 sm:py-3 px-4 text-xs sm:text-sm text-[#E8E8F0]">
                      <span className="mr-1 sm:mr-2 inline-flex align-middle">{getCountryFlag(peer.countryCode)}</span>
                      <span className="hidden sm:inline">{peer.country}</span>
                    </td>
                    <td className="py-2 sm:py-3 px-4 text-xs sm:text-sm text-[#8B8CA7]">{peer.city}</td>
                    <td className="py-2 sm:py-3 px-4">
                      <span className={`text-xs px-2 py-1 rounded-full ${
                        peer.inbound 
                          ? 'bg-[#00E396]/10 text-[#00E396]' 
                          : 'bg-[#1E90FF]/10 text-[#1E90FF]'
                      }`}>
                        {peer.inbound ? 'In' : 'Out'}
                      </span>
                    </td>
                    <td className="py-2 sm:py-3 px-4 text-xs sm:text-sm text-[#8B8CA7] truncate max-w-[100px] sm:max-w-[200px]">
                      {peer.name}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
        {sortedPeers.length > 20 && (
          <div className="text-center mt-4 text-sm text-[#8B8CA7]">
            Showing 20 of {sortedPeers.length} peers
          </div>
        )}
      </div>
    </div>
  );
}

function getCountryFlag(countryCode: string): React.ReactNode {
  if (!countryCode) {
    return (
      <span className="w-5 h-5 rounded-full bg-[#2a3352] flex items-center justify-center text-[10px] text-[#8B8CA7]">
        ?
      </span>
    );
  }
  return (
    <span className="w-5 h-5 rounded-full bg-[#1E90FF]/20 flex items-center justify-center text-[9px] font-bold text-[#1E90FF]">
      {countryCode.toUpperCase()}
    </span>
  );
}
