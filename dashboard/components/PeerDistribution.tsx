'use client';

import { useState, useMemo } from 'react';
import { Globe, Map, List, ArrowDownLeft, ArrowUpRight } from 'lucide-react';

interface Peer {
  ip?: string;
  country?: string;
  countryCode?: string;
  city?: string;
  lat?: number;
  lng?: number;
  direction?: string;
  client?: string;
  enode?: string;
}

interface PeerDistributionProps {
  peers: Peer[];
}

// Simple lat/lng to SVG x/y (Mercator-ish)
function geoToSvg(lat: number, lng: number): { x: number; y: number } {
  const x = ((lng + 180) / 360) * 1000;
  const y = ((90 - lat) / 180) * 500;
  return { x, y };
}

// Country flag emoji from code
function getFlag(code: string): string {
  if (!code || code.length !== 2) return '🌐';
  return String.fromCodePoint(...[...code.toUpperCase()].map(c => c.charCodeAt(0) + 127397));
}

// Simplified continent outlines (SVG paths)
const CONTINENTS = [
  // North America
  'M80,95 L120,75 L180,70 L220,80 L250,100 L240,130 L210,160 L180,180 L140,170 L100,160 L80,140 L60,120 Z',
  // South America
  'M160,210 L190,195 L210,220 L215,260 L200,300 L180,330 L160,345 L140,330 L130,290 L135,250 L145,220 Z',
  // Europe
  'M430,65 L470,55 L510,60 L530,80 L520,110 L500,130 L475,125 L450,115 L435,95 L425,80 Z',
  // Africa
  'M440,145 L480,135 L510,155 L520,200 L510,260 L490,300 L460,310 L430,295 L415,250 L410,200 L420,160 Z',
  // Asia
  'M540,50 L620,40 L720,45 L800,60 L840,100 L830,150 L790,180 L720,195 L650,185 L580,160 L550,120 L530,85 Z',
  // Oceania
  'M760,280 L810,270 L850,290 L860,320 L840,350 L800,360 L760,340 L745,310 Z',
];

export default function PeerDistribution({ peers }: PeerDistributionProps) {
  const [viewMode, setViewMode] = useState<'map' | 'list'>('map');
  const [hoveredCountry, setHoveredCountry] = useState<string | null>(null);

  // Geo-located peers (have lat/lng)
  const geoPeers = useMemo(() => peers.filter(p => p.lat && p.lng), [peers]);
  const hasGeo = geoPeers.length > 0;

  // Country stats
  const countryStats = useMemo(() => {
    const stats: Record<string, { name: string; code: string; count: number; inbound: number; outbound: number }> = {};
    peers.forEach(p => {
      const country = p.country || 'Unknown';
      const code = p.countryCode || '??';
      if (!stats[country]) stats[country] = { name: country, code, count: 0, inbound: 0, outbound: 0 };
      stats[country].count++;
      if (p.direction === 'inbound') stats[country].inbound++;
      else stats[country].outbound++;
    });
    return Object.entries(stats).sort((a, b) => b[1].count - a[1].count);
  }, [peers]);

  const inbound = peers.filter(p => p.direction === 'inbound').length;
  const outbound = peers.length - inbound;

  return (
    <div className="card-xdc">
      {/* Header */}
      <div className="flex items-center justify-between mb-5">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#1E90FF]/20 to-[#10B981]/10 flex items-center justify-center">
            <Globe className="w-5 h-5 text-[#1E90FF]" />
          </div>
          <div>
            <h2 className="text-lg font-semibold text-[#F9FAFB]">Global Peer Distribution</h2>
            <div className="text-sm text-[#6B7280]">
              {peers.length} peers · {countryStats.length} countries ·{' '}
              <span className="text-[#10B981]">{inbound} in</span> / <span className="text-[#1E90FF]">{outbound} out</span>
            </div>
          </div>
        </div>
        {/* View toggle */}
        <div className="flex items-center gap-1 bg-[#111827] rounded-lg p-1">
          <button
            onClick={() => setViewMode('map')}
            className={`p-1.5 rounded-md transition-colors ${viewMode === 'map' ? 'bg-[#1E90FF]/20 text-[#1E90FF]' : 'text-[#6B7280] hover:text-[#F9FAFB]'}`}
            title="Map view"
          >
            <Map className="w-4 h-4" />
          </button>
          <button
            onClick={() => setViewMode('list')}
            className={`p-1.5 rounded-md transition-colors ${viewMode === 'list' ? 'bg-[#1E90FF]/20 text-[#1E90FF]' : 'text-[#6B7280] hover:text-[#F9FAFB]'}`}
            title="List view"
          >
            <List className="w-4 h-4" />
          </button>
        </div>
      </div>

      {viewMode === 'map' ? (
        <div className="relative">
          {/* SVG World Map */}
          <div className="h-[300px] bg-gradient-to-b from-[#0A0E1A] to-[#111827] rounded-xl border border-[rgba(255,255,255,0.06)] overflow-hidden">
            <svg viewBox="0 0 1000 500" className="w-full h-full" preserveAspectRatio="xMidYMid meet">
              {/* Grid lines */}
              {[...Array(9)].map((_, i) => (
                <line key={`h${i}`} x1="0" y1={i * 62.5} x2="1000" y2={i * 62.5} stroke="rgba(255,255,255,0.03)" strokeWidth="0.5" />
              ))}
              {[...Array(13)].map((_, i) => (
                <line key={`v${i}`} x1={i * 83.3} y1="0" x2={i * 83.3} y2="500" stroke="rgba(255,255,255,0.03)" strokeWidth="0.5" />
              ))}

              {/* Continents */}
              {CONTINENTS.map((d, i) => (
                <path key={i} d={d} fill="rgba(255,255,255,0.04)" stroke="rgba(255,255,255,0.08)" strokeWidth="0.5" />
              ))}

              {/* Peer dots — use real geo if available, pseudo-random fallback */}
              {peers.slice(0, 50).map((peer, i) => {
                let cx: number, cy: number;
                if (peer.lat && peer.lng) {
                  const pos = geoToSvg(peer.lat, peer.lng);
                  cx = pos.x;
                  cy = pos.y;
                } else {
                  // Fallback: hash IP to position
                  const hash = (peer.ip || peer.enode || `p${i}`).split('').reduce((a, c) => a + c.charCodeAt(0), 0);
                  cx = (hash * 7 + i * 73) % 900 + 50;
                  cy = (hash * 13 + i * 37) % 400 + 50;
                }
                const isInbound = peer.direction === 'inbound';
                const isHovered = hoveredCountry && peer.country === hoveredCountry;
                return (
                  <g key={i}>
                    {/* Pulse ring */}
                    <circle cx={cx} cy={cy} r={isHovered ? 8 : 5} fill="none"
                      stroke={isInbound ? '#10B981' : '#1E90FF'} strokeWidth="0.5" opacity={0.3}>
                      <animate attributeName="r" from={isHovered ? 6 : 3} to={isHovered ? 12 : 8} dur="2s" repeatCount="indefinite" />
                      <animate attributeName="opacity" from="0.4" to="0" dur="2s" repeatCount="indefinite" />
                    </circle>
                    {/* Dot */}
                    <circle cx={cx} cy={cy} r={isHovered ? 4 : 2.5}
                      fill={isInbound ? '#10B981' : '#1E90FF'} opacity={isHovered ? 1 : 0.8} />
                  </g>
                );
              })}
            </svg>

            {/* No geo warning */}
            {!hasGeo && peers.length > 0 && (
              <div className="absolute bottom-2 left-2 px-2 py-1 rounded bg-[#111827]/80 text-[10px] text-[#6B7280] border border-[rgba(255,255,255,0.06)]">
                ⓘ Approximate positions — geo-location pending
              </div>
            )}
          </div>

          {/* Country bars below map */}
          {countryStats.length > 0 && (
            <div className="mt-4 grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
              {countryStats.slice(0, 8).map(([country, stat]) => (
                <div
                  key={country}
                  className={`p-2 rounded-lg cursor-pointer transition-all ${
                    hoveredCountry === country ? 'bg-[rgba(30,144,255,0.15)] border border-[rgba(30,144,255,0.3)]' : 'bg-[rgba(255,255,255,0.02)] border border-transparent hover:bg-[rgba(255,255,255,0.04)]'
                  }`}
                  onMouseEnter={() => setHoveredCountry(country)}
                  onMouseLeave={() => setHoveredCountry(null)}
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-1.5">
                      <span className="text-sm">{getFlag(stat.code)}</span>
                      <span className="text-xs text-[#F9FAFB] truncate max-w-[60px]">{stat.name}</span>
                    </div>
                    <span className="text-sm font-bold font-mono-nums text-[#1E90FF]">{stat.count}</span>
                  </div>
                  <div className="mt-1 w-full h-1 rounded-full bg-[rgba(255,255,255,0.06)]">
                    <div className="h-full rounded-full bg-[#1E90FF]"
                      style={{ width: `${Math.min(100, (stat.count / peers.length) * 100)}%` }} />
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      ) : (
        /* List/Table View — always accurate */
        <div>
          {countryStats.length === 0 ? (
            <div className="text-center text-[#6B7280] py-12">No peer data available</div>
          ) : (
            <div className="space-y-1 max-h-[400px] overflow-y-auto">
              {countryStats.map(([country, stat], i) => (
                <div key={country} className="flex items-center justify-between p-3 rounded-lg hover:bg-[rgba(255,255,255,0.03)] transition-colors">
                  <div className="flex items-center gap-3">
                    <span className="w-6 h-6 rounded-full bg-[#111827] flex items-center justify-center text-xs font-bold text-[#6B7280]">{i + 1}</span>
                    <span className="text-lg">{getFlag(stat.code)}</span>
                    <div>
                      <div className="text-sm font-medium text-[#F9FAFB]">{stat.name}</div>
                      <div className="text-xs text-[#6B7280]">
                        <span className="text-[#10B981]">{stat.inbound} <ArrowDownLeft className="w-3 h-3 inline" /></span>
                        {' · '}
                        <span className="text-[#1E90FF]">{stat.outbound} <ArrowUpRight className="w-3 h-3 inline" /></span>
                      </div>
                    </div>
                  </div>
                  <div className="flex items-center gap-3">
                    <div className="w-24 h-2 rounded-full bg-[rgba(255,255,255,0.06)]">
                      <div className="h-full rounded-full bg-gradient-to-r from-[#1E90FF] to-[#10B981]"
                        style={{ width: `${Math.min(100, (stat.count / peers.length) * 100)}%` }} />
                    </div>
                    <span className="text-lg font-bold font-mono-nums text-[#F9FAFB] w-8 text-right">{stat.count}</span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
