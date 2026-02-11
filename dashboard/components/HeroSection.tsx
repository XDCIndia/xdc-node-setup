'use client';

import { useAnimatedNumber } from '@/lib/animations';
import { formatDurationLong, getSyncColor } from '@/lib/formatters';
import type { BlockchainData } from '@/lib/types';

interface HeroSectionProps {
  data: BlockchainData;
}

function CircularProgress({ percentage, size = 120, strokeWidth = 8 }: { percentage: number; size?: number; strokeWidth?: number }) {
  const radius = (size - strokeWidth) / 2;
  const circumference = radius * 2 * Math.PI;
  const offset = circumference - (percentage / 100) * circumference;
  const color = getSyncColor(percentage);
  
  return (
    <div className="relative" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="transform -rotate-90">
        {/* Background circle */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke="rgba(255, 255, 255, 0.06)"
          strokeWidth={strokeWidth}
        />
        {/* Progress circle */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke={color}
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={offset}
          style={{
            transition: 'stroke-dashoffset 0.5s ease-out, stroke 0.3s ease',
            filter: `drop-shadow(0 0 6px ${color}40)`,
          }}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-2xl font-bold font-mono-nums" style={{ color }}>
          {percentage.toFixed(1)}%
        </span>
        <span className="text-xs text-[#6B7280]">Sync</span>
      </div>
    </div>
  );
}

function Sparkline({ data, color = '#1E90FF' }: { data: number[]; color?: string }) {
  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;
  const width = 200;
  const height = 40;
  const points = data.map((val, i) => {
    const x = (i / (data.length - 1)) * width;
    const y = height - ((val - min) / range) * height;
    return `${x},${y}`;
  }).join(' ');
  
  return (
    <svg width="100%" height={height} viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none">
      <polyline
        fill="none"
        stroke={color}
        strokeWidth="2"
        points={points}
        style={{ filter: `drop-shadow(0 0 3px ${color}50)` }}
      />
      <defs>
        <linearGradient id={`sparkline-gradient-${color.replace('#', '')}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.3"/>
          <stop offset="100%" stopColor={color} stopOpacity="0"/>
        </linearGradient>
      </defs>
      <polygon
        fill={`url(#sparkline-gradient-${color.replace('#', '')})`}
        points={`0,${height} ${points} ${width},${height}`}
      />
    </svg>
  );
}

export default function HeroSection({ data }: HeroSectionProps) {
  const displayBlockHeight = useAnimatedNumber(data.blockHeight, 1500);
  const displayPeers = useAnimatedNumber(data.peers, 1000);
  
  // Generate mock sparkline data based on current block height
  const sparklineData = Array.from({ length: 20 }, (_, i) => 
    data.blockHeight - (19 - i) * 2
  );
  
  const syncColor = getSyncColor(data.syncPercent);
  
  return (
    <div className="card-hero">
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8">
        {/* Left: Block Height */}
        <div className="lg:col-span-4 flex flex-col justify-center">
          <div className="section-header mb-2">Current Block Height</div>
          <div className="text-4xl lg:text-5xl font-bold font-mono-nums text-[#F9FAFB] mb-2">
            {data.blockHeight > 0 ? displayBlockHeight.toLocaleString() : '—'}
          </div>
          <div className="flex items-center gap-2 text-sm">
            <span className="text-[#6B7280]">Highest:</span>
            <span className="font-mono-nums text-[#9CA3AF]">
              {data.highestBlock > 0 ? data.highestBlock.toLocaleString() : '—'}
            </span>
          </div>
          
          {/* Sparkline */}
          <div className="mt-4">
            <Sparkline data={sparklineData} color={syncColor} />
          </div>
        </div>
        
        {/* Center: Sync Progress */}
        <div className="lg:col-span-4 flex flex-col items-center justify-center">
          <CircularProgress percentage={data.syncPercent} size={140} strokeWidth={10} />
          
          {data.isSyncing && data.syncPercent < 99.9 && (
            <div className="mt-3 text-center">
              <span className="text-xs text-[#6B7280]">Syncing in progress...</span>
            </div>
          )}
        </div>
        
        {/* Right: Peers + Uptime + Network */}
        <div className="lg:col-span-4 grid grid-cols-1 gap-4">
          <div className="flex items-center justify-between p-4 rounded-xl bg-[rgba(30,144,255,0.05)] border border-[rgba(30,144,255,0.1)]">
            <div>
              <div className="section-header mb-1">Peers Connected</div>
              <div className="text-3xl font-bold font-mono-nums text-[#1E90FF]">
                {data.peers > 0 ? displayPeers.toLocaleString() : '—'}
              </div>
            </div>
            <div className="text-right text-xs">
              <div className="text-[#10B981]">↓ {data.peersInbound || 0}</div>
              <div className="text-[#1E90FF]">↑ {data.peersOutbound || 0}</div>
            </div>
          </div>
          
          <div className="grid grid-cols-2 gap-4">
            <div className="p-4 rounded-xl bg-[rgba(255,255,255,0.02)]">
              <div className="section-header mb-1">Uptime</div>
              <div className="text-lg font-semibold text-[#F9FAFB]">
                {data.uptime > 0 ? formatDurationLong(data.uptime) : '—'}
              </div>
            </div>
            
            <div className="p-4 rounded-xl bg-[rgba(255,255,255,0.02)]">
              <div className="section-header mb-1">Network ID</div>
              <div className="text-lg font-semibold font-mono-nums text-[#F9FAFB]">
                {data.chainId || '50'}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
