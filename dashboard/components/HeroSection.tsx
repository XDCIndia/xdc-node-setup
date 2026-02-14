'use client';

import { useAnimatedNumber } from '@/lib/animations';
import { formatDurationLong, getSyncColor } from '@/lib/formatters';
import type { BlockchainData, NodeConfig } from '@/lib/types';
import { Sparkline } from '@/components/charts/Sparkline';

interface HeroSectionProps {
  data: BlockchainData;
  nodeConfig?: NodeConfig;
  blockHeightHistory?: number[];
  blockIncrease?: number;
  blocksPerMinute?: number;
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

function getClientIcon(clientType?: string): string {
  if (clientType === 'erigon') return '🔶';
  if (clientType === 'geth-pr5') return '🟢';
  return '🔷';
}

function getClientName(clientType?: string): string {
  if (clientType === 'erigon') return 'Erigon';
  if (clientType === 'geth-pr5') return 'Geth PR5';
  return 'Geth';
}

function getNodeTypeLabel(nodeType?: string): string {
  if (nodeType === 'archive') return 'Archive Node';
  if (nodeType === 'fast') return 'Fast Sync';
  if (nodeType === 'snap') return 'Snap Sync';
  return 'Full Node';
}

function formatSyncETA(minutes: number): string {
  if (minutes < 60) return `~${Math.round(minutes)}m`;
  const hours = Math.floor(minutes / 60);
  const mins = Math.round(minutes % 60);
  if (hours < 24) return `~${hours}h ${mins}m`;
  const days = Math.floor(hours / 24);
  const remainingHours = hours % 24;
  return `~${days}d ${remainingHours}h`;
}

function getSyncDescription(nodeType?: string, isSyncing?: boolean): string {
  if (!isSyncing) return '';
  if (nodeType === 'archive') return 'Archive sync — all historical states preserved';
  if (nodeType === 'fast' || nodeType === 'snap') return 'Fast sync — downloading state';
  return 'Full sync — verifying all blocks';
}

export default function HeroSection({ data, nodeConfig, blockHeightHistory = [], blockIncrease = 0, blocksPerMinute = 0 }: HeroSectionProps) {
  const displayBlockHeight = useAnimatedNumber(data.blockHeight, 1500);
  const displayPeers = useAnimatedNumber(data.peers, 1000);
  
  const syncColor = getSyncColor(data.syncPercent);
  
  // Only show sparkline if we have sufficient historical data
  const showSparkline = blockHeightHistory.length >= 2;
  
  // Calculate sync ETA
  const remainingBlocks = data.highestBlock - data.blockHeight;
  const estimatedMinutes = blocksPerMinute > 0 ? remainingBlocks / blocksPerMinute : 0;
  const showETA = data.isSyncing && blocksPerMinute > 0 && estimatedMinutes > 0;
  
  return (
    <div className="card-hero">
      {/* Node Type Badge */}
      {nodeConfig && (
        <div className="mb-4 flex flex-wrap items-center gap-3">
          <div className="flex items-center gap-2 px-4 py-2 rounded-xl bg-[rgba(30,144,255,0.1)] border border-[rgba(30,144,255,0.2)]">
            <span className="text-xl">{getClientIcon(nodeConfig.clientType)}</span>
            <span className="text-sm font-semibold text-[#1E90FF]">{getClientName(nodeConfig.clientType)}</span>
          </div>
          <div className="px-4 py-2 rounded-xl bg-[rgba(255,255,255,0.05)] border border-[rgba(255,255,255,0.1)]">
            <span className="text-sm font-medium text-[#9CA3AF]">{getNodeTypeLabel(nodeConfig.nodeType)}</span>
          </div>
        </div>
      )}
      
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8">
        {/* Left: Block Height */}
        <div className="lg:col-span-4 flex flex-col justify-center">
          <div className="section-header mb-2">Current Block Height</div>
          <div className="text-4xl lg:text-5xl font-bold font-mono-nums text-[#F9FAFB] mb-2">
            {data.blockHeight > 0 ? displayBlockHeight.toLocaleString() : '—'}
          </div>
          <div className="flex items-center gap-2 text-sm mb-2">
            <span className="text-[#6B7280]">Highest:</span>
            <span className="font-mono-nums text-[#9CA3AF]">
              {data.highestBlock > 0 ? data.highestBlock.toLocaleString() : '—'}
            </span>
          </div>
          
          {/* Block Increase */}
          {blockIncrease > 0 && (
            <div className="flex items-center gap-3 text-sm mb-1">
              <span className="text-[#10B981] font-semibold">+{blockIncrease} blocks</span>
              <span className="text-[#6B7280]">since last update</span>
            </div>
          )}
          
          {/* Blocks Per Minute */}
          {blocksPerMinute > 0 && (
            <div className="flex items-center gap-2 text-sm mb-2">
              <span className="text-[#1E90FF] font-semibold">~{blocksPerMinute} blocks/min</span>
              <span className="text-[#6B7280]">sync speed</span>
            </div>
          )}
          
          {/* Sync ETA */}
          {showETA && (
            <div className="mt-2 px-3 py-2 rounded-lg bg-[rgba(30,144,255,0.08)] border border-[rgba(30,144,255,0.15)]">
              <div className="text-xs text-[#6B7280] mb-1">Estimated time remaining</div>
              <div className="text-lg font-bold text-[#1E90FF]">{formatSyncETA(estimatedMinutes)}</div>
              <div className="text-xs text-[#9CA3AF] mt-1">{getSyncDescription(nodeConfig?.nodeType, data.isSyncing)}</div>
            </div>
          )}
          
          {/* Coinbase Address */}
          {data.coinbase && (
            <div className="mt-2 flex items-center gap-2">
              <span className="text-[10px] uppercase tracking-wider text-[#6B7280]">Coinbase</span>
              <span className="font-mono text-xs text-[#1E90FF] bg-[rgba(30,144,255,0.08)] px-2 py-0.5 rounded" title={data.coinbase}>
                {data.coinbase}
              </span>
            </div>
          )}
          
          {/* Ethstats Name */}
          {data.ethstatsName && (
            <div className="mt-1 flex items-center gap-2">
              <span className="text-[10px] uppercase tracking-wider text-[#6B7280]">Ethstats</span>
              <span className="text-xs text-[#10B981] font-medium bg-[rgba(16,185,129,0.08)] px-2 py-0.5 rounded flex items-center gap-1">
                <span className="w-1.5 h-1.5 rounded-full bg-[#10B981] animate-pulse" />
                {data.ethstatsName}
              </span>
            </div>
          )}
          
          {/* Sparkline - only show with real historical data */}
          {showSparkline && (
            <div className="mt-4">
              <Sparkline data={blockHeightHistory} color={syncColor} width={200} height={40} />
            </div>
          )}
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
