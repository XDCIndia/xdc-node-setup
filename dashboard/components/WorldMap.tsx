'use client';

import { useState, useMemo } from 'react';

interface PeerLocation {
  id: string;
  lat: number;
  lon: number;
  country: string;
  city: string;
  inbound: boolean;
}

interface CountryInfo {
  name: string;
  count: number;
}

interface WorldMapProps {
  peers: PeerLocation[];
  countries: Record<string, CountryInfo>;
  width?: number;
  height?: number;
}

// Simplified world map paths - major regions
const WORLD_PATHS = {
  // North America
  us: 'M 120 140 L 250 140 L 280 200 L 250 260 L 200 280 L 150 250 L 120 200 Z',
  ca: 'M 120 80 L 280 80 L 300 140 L 120 140 Z',
  mx: 'M 150 260 L 200 280 L 220 320 L 180 340 L 140 300 Z',
  
  // South America  
  br: 'M 220 360 L 300 360 L 320 450 L 280 520 L 240 480 L 200 420 Z',
  ar: 'M 240 480 L 280 520 L 260 580 L 220 560 Z',
  co: 'M 200 360 L 220 360 L 220 400 L 200 380 Z',
  
  // Europe
  gb: 'M 420 120 L 450 120 L 460 150 L 440 160 L 420 150 Z',
  fr: 'M 440 160 L 480 160 L 480 200 L 450 210 L 430 190 Z',
  de: 'M 480 150 L 510 150 L 520 180 L 490 190 L 480 170 Z',
  it: 'M 490 190 L 510 190 L 520 230 L 500 240 L 480 210 Z',
  es: 'M 430 210 L 470 210 L 470 250 L 430 250 Z',
  nl: 'M 470 140 L 490 140 L 490 160 L 470 160 Z',
  ru: 'M 520 80 L 750 80 L 780 150 L 700 180 L 600 170 L 520 140 Z',
  
  // Asia
  cn: 'M 600 180 L 720 180 L 740 250 L 680 280 L 620 260 L 580 220 Z',
  in: 'M 580 260 L 640 260 L 660 320 L 620 340 L 580 300 Z',
  jp: 'M 760 180 L 800 180 L 790 220 L 750 210 Z',
  kr: 'M 740 200 L 770 200 L 765 230 L 740 220 Z',
  sg: 'M 680 320 L 700 320 L 695 340 L 675 335 Z',
  id: 'M 650 340 L 750 340 L 760 400 L 680 390 Z',
  th: 'M 640 300 L 680 300 L 670 340 L 630 330 Z',
  vn: 'M 660 280 L 690 280 L 680 320 L 650 310 Z',
  
  // Oceania
  au: 'M 700 420 L 820 420 L 840 500 L 780 540 L 720 520 L 680 480 Z',
  nz: 'M 820 500 L 860 500 L 850 540 L 810 530 Z',
  
  // Africa
  za: 'M 480 420 L 540 420 L 550 500 L 510 520 L 470 480 Z',
  ng: 'M 460 320 L 500 320 L 510 360 L 470 370 L 450 340 Z',
  eg: 'M 500 260 L 550 260 L 540 300 L 500 300 Z',
  ke: 'M 530 360 L 560 360 L 555 400 L 525 390 Z',
  
  // Middle East
  ae: 'M 560 280 L 600 280 L 595 310 L 555 300 Z',
  sa: 'M 520 260 L 600 260 L 610 320 L 540 310 Z',
  il: 'M 530 260 L 550 260 L 545 280 L 530 275 Z',
  
  // Southeast Asia
  my: 'M 640 320 L 680 320 L 675 360 L 635 350 Z',
  ph: 'M 720 280 L 750 280 L 740 340 L 710 330 Z',
};

export default function WorldMap({ peers, countries, width = 900, height = 450 }: WorldMapProps) {
  const [hoveredCountry, setHoveredCountry] = useState<string | null>(null);
  const [tooltip, setTooltip] = useState<{ x: number; y: number; content: string } | null>(null);

  const countryColors = useMemo(() => {
    const maxCount = Math.max(...Object.values(countries).map(c => c.count), 1);
    const colors: Record<string, string> = {};
    
    for (const [code, info] of Object.entries(countries)) {
      const intensity = info.count / maxCount;
      const alpha = 0.3 + intensity * 0.7;
      colors[code] = `rgba(30, 144, 255, ${alpha})`;
    }
    
    return colors;
  }, [countries]);

  const peerDots = useMemo(() => {
    return peers
      .filter(p => p.lat !== 0 && p.lon !== 0)
      .map(peer => {
        // Simple equirectangular projection
        const x = ((peer.lon + 180) / 360) * width;
        const y = ((90 - peer.lat) / 180) * height;
        return { ...peer, x, y };
      });
  }, [peers, width, height]);

  const handleCountryHover = (code: string, event: React.MouseEvent) => {
    setHoveredCountry(code);
    const info = countries[code];
    if (info) {
      setTooltip({
        x: event.clientX,
        y: event.clientY - 40,
        content: `${info.name}: ${info.count} peer${info.count !== 1 ? 's' : ''}`,
      });
    }
  };

  const handlePeerHover = (peer: PeerLocation, event: React.MouseEvent) => {
    setTooltip({
      x: event.clientX,
      y: event.clientY - 60,
      content: `${peer.city}, ${peer.country}${peer.inbound ? ' (inbound)' : ' (outbound)'}`,
    });
  };

  const handleMouseLeave = () => {
    setHoveredCountry(null);
    setTooltip(null);
  };

  return (
    <div className="relative">
      <svg 
        viewBox={`0 0 ${width} ${height}`}
        className="w-full h-auto"
        style={{ maxHeight: height }}
      >
        {/* Ocean background */}
        <rect width={width} height={height} fill="#0a0a1a" />
        
        {/* Grid lines */}
        <g stroke="#1a1a3a" strokeWidth={0.5} opacity={0.5}>
          {Array.from({ length: 13 }, (_, i) => (
            <line key={`v-${i}`} x1={i * (width / 12)} y1={0} x2={i * (width / 12)} y2={height} />
          ))}
          {Array.from({ length: 7 }, (_, i) => (
            <line key={`h-${i}`} x1={0} y1={i * (height / 6)} x2={width} y2={i * (height / 6)} />
          ))}
        </g>
        
        {/* Country shapes */}
        {Object.entries(WORLD_PATHS).map(([code, path]) => (
          <path
            key={code}
            d={path}
            fill={countryColors[code] || '#1a1a3a'}
            stroke={hoveredCountry === code ? '#1E90FF' : '#2a2a50'}
            strokeWidth={hoveredCountry === code ? 2 : 1}
            className="transition-all duration-300 cursor-pointer"
            onMouseEnter={(e) => handleCountryHover(code, e)}
            onMouseMove={(e) => handleCountryHover(code, e)}
            onMouseLeave={handleMouseLeave}
          />
        ))}
        
        {/* Peer dots */}
        {peerDots.map((peer) => (
          <g key={peer.id}>
            <circle
              cx={peer.x}
              cy={peer.y}
              r={3}
              fill={peer.inbound ? '#00ff88' : '#1E90FF'}
              stroke="#0a0a1a"
              strokeWidth={1}
              className="cursor-pointer"
              onMouseEnter={(e) => handlePeerHover(peer, e)}
              onMouseMove={(e) => handlePeerHover(peer, e)}
              onMouseLeave={handleMouseLeave}
            >
              <animate
                attributeName="r"
                values="3;5;3"
                dur="2s"
                repeatCount="indefinite"
              />
              <animate
                attributeName="opacity"
                values="1;0.7;1"
                dur="2s"
                repeatCount="indefinite"
              />
            </circle>
            <circle
              cx={peer.x}
              cy={peer.y}
              r={8}
              fill="none"
              stroke={peer.inbound ? '#00ff88' : '#1E90FF'}
              strokeWidth={1}
              opacity={0.3}
            >
              <animate
                attributeName="r"
                values="5;12;5"
                dur="2s"
                repeatCount="indefinite"
              />
              <animate
                attributeName="opacity"
                values="0.5;0;0.5"
                dur="2s"
                repeatCount="indefinite"
              />
            </circle>
          </g>
        ))}
      </svg>
      
      {/* Tooltip */}
      {tooltip && (
        <div
          className="fixed z-50 px-3 py-2 bg-[#151530] border border-[#2a2a50] rounded-lg text-sm text-white pointer-events-none shadow-xl"
          style={{ left: tooltip.x, top: tooltip.y }}
        >
          {tooltip.content}
        </div>
      )}
    </div>
  );
}
