'use client';

import { useMemo } from 'react';
import { RefreshCw, Clock, Zap, GitBranch, CheckCircle2 } from 'lucide-react';
import { useAnimatedNumber } from '@/lib/animations';
import { formatNumber, formatDurationLong, getSyncColor } from '@/lib/formatters';
import type { SyncData, BlockchainData } from '@/lib/types';

interface SyncPanelProps {
  data: SyncData;
  blockchain?: BlockchainData;
}

function Sparkline({ data, color = '#1E90FF' }: { data: number[]; color?: string }) {
  if (data.length < 2) return null;
  
  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;
  const width = 300;
  const height = 60;
  const padding = 5;
  
  const points = data.map((val, i) => {
    const x = (i / (data.length - 1)) * width;
    const y = height - padding - ((val - min) / range) * (height - 2 * padding);
    return `${x},${y}`;
  }).join(' ');
  
  return (
    <svg width="100%" height={height} viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none">
      <defs>
        <linearGradient id="sparkline-gradient" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.4"/>
          <stop offset="100%" stopColor={color} stopOpacity="0"/>
        </linearGradient>
      </defs>
      <polyline
        fill="none"
        stroke={color}
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        points={points}
        style={{ filter: `drop-shadow(0 0 4px ${color}60)` }}
      />
      <polygon
        fill="url(#sparkline-gradient)"
        points={`0,${height} ${points} ${width},${height}`}
      />
    </svg>
  );
}

function ETACountdown({ eta }: { eta: number }) {
  const hours = Math.floor(eta / 60);
  const minutes = Math.floor(eta % 60);
  
  return (
    <div className="flex items-center gap-3 p-4 rounded-xl bg-[rgba(30,144,255,0.05)] border border-[rgba(30,144,255,0.15)]">
      <div className="w-12 h-12 rounded-full border-4 border-[#1E90FF] border-t-transparent animate-spin">
        <Clock className="w-5 h-5 text-[#1E90FF] absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2" />
      </div>
      <div>
        <div className="section-header mb-1">Estimated Time to Sync</div>
        <div className="text-2xl font-bold font-mono-nums text-[#1E90FF]">
          {hours > 0 && <span>{hours}h </span>}
          {minutes > 0 && <span>{minutes}m</span>}
          {hours === 0 && minutes === 0 && <span>< 1m</span>}
        </div>
      </div>
    </div>
  );
}

export default function SyncPanel({ data, blockchain }: SyncPanelProps) {
  const syncRatePerMin = (data.syncRate || 0) * 60;
  const displaySyncRate = useAnimatedNumber(Math.round(syncRatePerMin), 1000);
  
  // Calculate ETA
  const eta = useMemo(() => {
    if (!blockchain || blockchain.syncPercent >= 99.9) return null;
    
    const currentBlock = blockchain.blockHeight || 0;
    const highestBlock = blockchain.highestBlock || currentBlock;
    const blocksRemaining = highestBlock - currentBlock;
    
    if (blocksRemaining <= 0) return null;
    
    const syncRatePerMin = (data.syncRate || 0) * 60;
    if (syncRatePerMin <= 0) return null;
    
    return blocksRemaining / syncRatePerMin;
  }, [data.syncRate, blockchain]);
  
  // Generate sparkline data based on sync rate
  const sparklineData = useMemo(() => {
    const base = syncRatePerMin || 100;
    return Array.from({ length: 20 }, (_, i) => 
      base + Math.sin(i / 3) * base * 0.3 + Math.random() * base * 0.1
    );
  }, [syncRatePerMin]);
  
  const syncColor = getSyncColor(blockchain?.syncPercent || 0);
  
  return (
    <div id="sync" className="card-xdc">
      {/* Header */}
      <div className="flex items-center gap-3 mb-5">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#1E90FF]/20 to-[#1E90FF]/10 flex items-center justify-center">
          <RefreshCw className="w-5 h-5 text-[#1E90FF]" />
        </div>
        <div>
          <h2 className="text-lg font-semibold text-[#F9FAFB]">Sync & Performance</h2>
          <div className="text-sm text-[#6B7280]">Block synchronization metrics</div>
        </div>
      </div>
      
      {/* ETA or Fully Synced */}
      {eta !== null && eta > 0 && blockchain?.isSyncing ? (
        <ETACountdown eta={eta} />
      ) : (blockchain?.syncPercent ?? 0) >= 99.9 ? (
        <div className="flex items-center gap-3 p-4 rounded-xl bg-[rgba(16,185,129,0.05)] border border-[rgba(16,185,129,0.15)]">
          <div className="w-12 h-12 rounded-full bg-[rgba(16,185,129,0.1)] flex items-center justify-center">
            <CheckCircle2 className="w-6 h-6 text-[#10B981]" />
          </div>
          <div>
            <div className="section-header mb-1">Status</div>
            <div className="text-2xl font-bold text-[#10B981]">Fully Synced</div>
          </div>
        </div>
      ) : null}
      
      {/* Block Trend Sparkline */}
      <div className="mt-5">
        <div className="flex items-center justify-between mb-2">
          <span className="section-header">Block Trend (20 min)</span>
        </div>
        <Sparkline data={sparklineData} color={syncColor} />
      </div>
      
      {/* Stats Grid */}
      <div className="grid grid-cols-2 gap-4 mt-5">
        <div className="p-4 rounded-xl bg-[rgba(255,255,255,0.02)]">
          <div className="section-header mb-2 flex items-center gap-1">
            <Zap className="w-3 h-3" /> Sync Rate
          </div>
          <div className="flex items-baseline gap-1">
            <span className="text-2xl font-bold font-mono-nums text-[#F9FAFB]">
              {syncRatePerMin > 0 ? formatNumber(displaySyncRate) : '—'}
            </span>
            <span className="text-sm text-[#6B7280]">b/min</span>
          </div>
        </div>
        
        <div className="p-4 rounded-xl bg-[rgba(255,255,255,0.02)]">
          <div className="section-header mb-2 flex items-center gap-1">
            <GitBranch className="w-3 h-3" /> Reorgs
          </div>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-1">
              <span className="text-[#10B981]">+</span>
              <span className="text-lg font-semibold font-mono-nums">{data.reorgsAdd || 0}</span>
            </div>
            <div className="flex items-center gap-1">
              <span className="text-[#EF4444]">-</span>
              <span className="text-lg font-semibold font-mono-nums">{data.reorgsDrop || 0}</span>
            </div>
          </div>
        </div>
      </div>
      
      {/* Sync Progress Bar */}
      {blockchain?.isSyncing && blockchain.syncPercent < 99.9 && (
        <div className="mt-5 p-4 rounded-xl bg-[rgba(255,255,255,0.02)]">
          <div className="flex items-center justify-between mb-2">
            <span className="section-header">Sync Progress</span>
            <span className="text-sm font-medium font-mono-nums" style={{ color: syncColor }}>
              {blockchain.syncPercent.toFixed(2)}%
            </span>
          </div>
          <div className="w-full h-2 bg-[rgba(255,255,255,0.06)] rounded-full overflow-hidden">
            <div 
              className="h-full rounded-full transition-all duration-500"
              style={{
                width: `${Math.min(100, blockchain.syncPercent)}%`,
                background: `linear-gradient(90deg, ${syncColor}, ${syncColor}80)`,
                boxShadow: `0 0 10px ${syncColor}50`,
              }}
            />
          </div>
          <div className="flex justify-between mt-2 text-xs text-[#6B7280]">
            <span className="font-mono-nums">{formatNumber(blockchain.blockHeight || 0)}</span>
            <span className="font-mono-nums">{formatNumber(blockchain.highestBlock || 0)}</span>
          </div>
        </div>
      )}
    </div>
  );
}
