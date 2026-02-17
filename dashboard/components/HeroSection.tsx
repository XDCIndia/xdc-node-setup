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
  if (clientType === 'nethermind') return '🟣';
  if (clientType === 'erigon') return '🔶';
  if (clientType === 'geth-pr5') return '🟢';
  return '🔷';
}

function getClientName(clientType?: string, clientVersion?: string): string {
  if (clientType === 'nethermind') {
    // Extract version: "Nethermind/v1.36.0-unstable+912e7f8c/linux-x64/dotnet9.0.13"
    const match = clientVersion?.match(/Nethermind\/v([\d.]+[^\s/]*)/i);
    return match ? `Nethermind ${match[1]}` : 'Nethermind';
  }
  if (clientType === 'erigon') {
    const match = clientVersion?.match(/erigon\/([\d.]+[^\s/]*)/i);
    return match ? `Erigon ${match[1]}` : 'Erigon';
  }
  if (clientType === 'geth-pr5') return 'Geth PR5';
  // For geth/XDC, show actual version: "XDC/v2.6.8-stable/linux-amd64/go1.23.12"
  if (clientVersion) {
    const match = clientVersion.match(/XDC\/(v[\d.]+[^\s/]*)/i);
    if (match) return `XDC ${match[1]}`;
    const gethMatch = clientVersion.match(/Geth\/(v[\d.]+[^\s/]*)/i);
    if (gethMatch) return `Geth ${gethMatch[1]}`;
  }
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
  const remainingBlocks = (data.networkHeight || data.highestBlock) - data.blockHeight;
  const estimatedMinutes = blocksPerMinute > 0 ? remainingBlocks / blocksPerMinute : 0;
  const showETA = data.isSyncing && blocksPerMinute > 0 && estimatedMinutes > 0;
  
  return (
    <div className="card-hero">
      {/* Node Type Badge */}
      {nodeConfig && (
        <div className="mb-4 flex flex-wrap items-center gap-3">
          <div className="flex items-center gap-2 px-4 py-2 rounded-xl bg-[var(--accent-blue-glow)] border border-[var(--border-blue-glow)]">
            <span className="text-xl">{getClientIcon(nodeConfig.clientType)}</span>
            <span className="text-sm font-semibold text-[var(--accent-blue)]">{getClientName(nodeConfig.clientType, nodeConfig.clientVersion)}</span>
          </div>
          <div className="px-4 py-2 rounded-xl bg-[var(--bg-hover)] border border-[var(--border-subtle)]">
            <span className="text-sm font-medium text-[var(--text-secondary)]">{getNodeTypeLabel(nodeConfig.nodeType)}</span>
          </div>
          {nodeConfig.networkName && (
          <div className="px-4 py-2 rounded-xl bg-[var(--accent-blue-glow)] border border-[var(--border-blue-glow)]">
            <span className="text-sm font-medium text-[var(--accent-blue)]">🌐 {nodeConfig.networkName}</span>
          </div>
          )}
        </div>
      )}
      
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 lg:gap-8">
        {/* Left: Block Height */}
        <div className="lg:col-span-4 flex flex-col justify-center">
          <div className="section-header mb-2">Current Block Height</div>
          <div className="text-4xl lg:text-5xl font-bold font-mono-nums text-[var(--text-primary)] mb-2">
            {data.blockHeight > 0 ? displayBlockHeight.toLocaleString() : '—'}
          </div>
          <div className="flex items-center gap-2 text-sm mb-2">
            <span className="text-[var(--text-tertiary)]">Network:</span>
            <span className="font-mono-nums text-[var(--text-secondary)]">
              {(data.networkHeight || data.highestBlock) > 0 ? (data.networkHeight || data.highestBlock).toLocaleString() : '—'}
            </span>
          </div>
          
          {/* Block Increase */}
          {blockIncrease > 0 && (
            <div className="flex items-center gap-3 text-sm mb-1">
              <span className="text-[var(--success)] font-semibold">+{blockIncrease} blocks</span>
              <span className="text-[var(--text-tertiary)]">since last update</span>
            </div>
          )}
          
          {/* Blocks Per Minute */}
          {blocksPerMinute > 0 && (
            <div className="flex items-center gap-2 text-sm mb-2">
              <span className="text-[var(--accent-blue)] font-semibold">~{blocksPerMinute} blocks/min</span>
              <span className="text-[var(--text-tertiary)]">sync speed</span>
            </div>
          )}
          
          {/* Sync ETA */}
          {showETA && (
            <div className="mt-2 px-3 py-2 rounded-lg bg-[var(--accent-blue-glow)] border border-[var(--border-blue-glow)]">
              <div className="text-xs text-[var(--text-tertiary)] mb-1">Estimated time remaining</div>
              <div className="text-lg font-bold text-[var(--accent-blue)]">{formatSyncETA(estimatedMinutes)}</div>
              <div className="text-xs text-[var(--text-secondary)] mt-1">{getSyncDescription(nodeConfig?.nodeType, data.isSyncing)}</div>
            </div>
          )}
          
          {/* Coinbase Address */}
          {data.coinbase && (
            <div className="mt-2 flex items-center gap-2">
              <span className="text-[10px] uppercase tracking-wider text-[var(--text-tertiary)]">Coinbase</span>
              <span className="font-mono text-xs text-[var(--accent-blue)] bg-[var(--accent-blue-glow)] px-2 py-0.5 rounded" title={data.coinbase}>
                {data.coinbase}
              </span>
            </div>
          )}
          
          {/* Ethstats Name */}
          {data.ethstatsName && (
            <div className="mt-1 flex items-center gap-2">
              <span className="text-[10px] uppercase tracking-wider text-[var(--text-tertiary)]">Ethstats</span>
              <span className="text-xs text-[var(--success)] font-medium bg-[rgba(16,185,129,0.08)] px-2 py-0.5 rounded flex items-center gap-1">
                <span className="w-1.5 h-1.5 rounded-full bg-[var(--success)] animate-pulse" />
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
              <span className="text-xs text-[var(--text-tertiary)]">Syncing in progress...</span>
            </div>
          )}
        </div>
        
        {/* Right: Peers + Uptime + Network */}
        <div className="lg:col-span-4 grid grid-cols-1 gap-4">
          <div className="flex items-center justify-between p-4 rounded-xl bg-[var(--accent-blue-glow)] border border-[var(--border-blue-glow)]">
            <div>
              <div className="section-header mb-1">Peers Connected</div>
              <div className="text-3xl font-bold font-mono-nums text-[var(--accent-blue)]">
                {data.peers > 0 ? displayPeers.toLocaleString() : '—'}
              </div>
            </div>
            <div className="text-right text-xs">
              <div className="text-[var(--success)]">↓ {data.peersInbound || 0}</div>
              <div className="text-[var(--accent-blue)]">↑ {data.peersOutbound || 0}</div>
            </div>
          </div>
          
          <div className="grid grid-cols-2 gap-4">
            <div className="p-4 rounded-xl bg-[var(--bg-hover)]">
              <div className="section-header mb-1">Uptime</div>
              <div className="text-lg font-semibold text-[var(--text-primary)]">
                {data.uptime > 0 ? formatDurationLong(data.uptime) : '—'}
              </div>
            </div>
            
            <div className="p-4 rounded-xl bg-[var(--bg-hover)]">
              <div className="section-header mb-1">Network ID</div>
              <div className="text-lg font-semibold font-mono-nums text-[var(--text-primary)]">
                {data.chainId || '50'}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
