'use client';

import { Crown, TrendingUp, AlertTriangle, CheckCircle2 } from 'lucide-react';
import { useAnimatedNumber } from '@/lib/animations';
import { formatNumber, formatXDC } from '@/lib/formatters';
import type { ConsensusData } from '@/lib/types';

interface ConsensusPanelProps {
  data: ConsensusData;
}

function EpochProgressBar({ progress }: { progress: number }) {
  return (
    <div className="w-full">
      <div className="flex items-center justify-between mb-2">
        <span className="section-header">Epoch Progress</span>
        <span className="text-sm font-medium text-[#F9FAFB]">{progress.toFixed(1)}%</span>
      </div>
      <div className="w-full h-2 bg-[rgba(255,255,255,0.06)] rounded-full overflow-hidden">
        <div 
          className="h-full rounded-full transition-all duration-500 ease-out"
          style={{
            width: `${progress}%`,
            background: 'linear-gradient(90deg, #1E90FF, #10B981)',
            boxShadow: '0 0 10px rgba(30, 144, 255, 0.5)',
          }}
        />
      </div>
    </div>
  );
}

function ParticipationRing({ rate }: { rate: number }) {
  const size = 80;
  const strokeWidth = 6;
  const radius = (size - strokeWidth) / 2;
  const circumference = radius * 2 * Math.PI;
  const offset = circumference - (rate / 100) * circumference;
  
  let color = '#10B981';
  if (rate < 80) color = '#EF4444';
  else if (rate < 90) color = '#F59E0B';
  
  return (
    <div className="relative" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="transform -rotate-90">
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke="rgba(255, 255, 255, 0.06)"
          strokeWidth={strokeWidth}
        />
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
          style={{ transition: 'stroke-dashoffset 0.5s ease-out' }}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-lg font-bold font-mono-nums" style={{ color }}>
          {rate.toFixed(1)}%
        </span>
      </div>
    </div>
  );
}

export default function ConsensusPanel({ data }: ConsensusPanelProps) {
  const displayEpoch = useAnimatedNumber(data.epoch, 1000);
  const displayStake = useAnimatedNumber(Math.floor(data.stakeAmount / 1000000), 1000);
  
  const getStatusConfig = (status: string) => {
    switch (status) {
      case 'Active':
        return {
          icon: <CheckCircle2 className="w-4 h-4" />,
          color: 'text-[#10B981]',
          bg: 'bg-[rgba(16,185,129,0.1)]',
          border: 'border-[rgba(16,185,129,0.3)]',
        };
      case 'Slashed':
        return {
          icon: <AlertTriangle className="w-4 h-4" />,
          color: 'text-[#F59E0B]',
          bg: 'bg-[rgba(245,158,11,0.1)]',
          border: 'border-[rgba(245,158,11,0.3)]',
        };
      case 'Inactive':
      default:
        return {
          icon: <AlertTriangle className="w-4 h-4" />,
          color: 'text-[#EF4444]',
          bg: 'bg-[rgba(239,68,68,0.1)]',
          border: 'border-[rgba(239,68,68,0.3)]',
        };
    }
  };
  
  const status = getStatusConfig(data.masternodeStatus);
  
  return (
    <div id="consensus" className="card-xdc">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#F59E0B]/20 to-[#F59E0B]/10 flex items-center justify-center">
            <Crown className="w-5 h-5 text-[#F59E0B]" />
          </div>
          <div>
            <h2 className="text-lg font-semibold text-[#F9FAFB]">XDPoS Consensus</h2>
            <div className="text-sm font-mono-nums text-[#6B7280]">
              Epoch #{formatNumber(displayEpoch)}
            </div>
          </div>
        </div>
        
        <div className={`flex items-center gap-2 px-3 py-1.5 rounded-lg border ${status.bg} ${status.border} ${status.color}`}>
          {status.icon}
          <span className="text-sm font-medium">{data.masternodeStatus}</span>
        </div>
      </div>
      
      {/* Epoch Progress */}
      <div className="mb-6">
        <EpochProgressBar progress={data.epochProgress} />
      </div>
      
      {/* Stats Grid */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Signing Rate */}
        <div className="p-4 rounded-xl bg-[rgba(255,255,255,0.02)]">
          <div className="section-header mb-2">Signing Rate</div>
          <div className="flex items-center gap-2">
            <span className="text-2xl font-bold font-mono-nums text-[#10B981]">
              {data.signingRate.toFixed(1)}%
            </span>
            <TrendingUp className="w-4 h-4 text-[#10B981]" />
          </div>
        </div>
        
        {/* Participation */}
        <div className="p-4 rounded-xl bg-[rgba(255,255,255,0.02)] flex items-center gap-4">
          <ParticipationRing rate={data.signingRate} />
          <div>
            <div className="section-header mb-1">Participation</div>
            <div className="text-sm text-[#9CA3AF]">Network health</div>
          </div>
        </div>
        
        {/* Stake Amount */}
        <div className="p-4 rounded-xl bg-[rgba(255,255,255,0.02)]">
          <div className="section-header mb-2">Stake Amount</div>
          <div className="text-lg font-semibold text-[#F9FAFB]">
            {formatXDC(data.stakeAmount)}
          </div>
        </div>
        
        {/* Rewards / Penalties */}
        <div className="p-4 rounded-xl bg-[rgba(255,255,255,0.02)]">
          <div className="section-header mb-2">Total Rewards</div>
          <div className="flex items-center justify-between">
            <span className="text-lg font-semibold text-[#10B981]">
              +{formatXDC(data.totalRewards)}
            </span>
            {data.penalties > 0 && (
              <span className="text-sm text-[#EF4444]">
                -{data.penalties} penalties
              </span>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
