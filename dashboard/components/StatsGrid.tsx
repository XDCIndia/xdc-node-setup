'use client';

import { Blocks, Users, FileText, Zap, TrendingUp, TrendingDown } from 'lucide-react';
import { useAnimatedNumber } from '@/lib/animations';
import type { MetricsData } from '@/lib/types';

interface StatsGridProps {
  metrics: MetricsData;
}

interface StatCardProps {
  icon: React.ReactNode;
  label: string;
  value: number;
  change?: number;
  changeType?: 'positive' | 'negative' | 'neutral';
  suffix?: string;
  format?: 'number' | 'compact';
}

function StatCard({ icon, label, value, change, changeType = 'neutral', suffix = '', format = 'number' }: StatCardProps) {
  const displayValue = useAnimatedNumber(value, 1000);
  
  const formatValue = (val: number) => {
    if (format === 'compact' && val >= 1000) {
      return (val / 1000).toFixed(1) + 'K';
    }
    return val.toLocaleString();
  };
  
  const getChangeColor = () => {
    if (changeType === 'positive') return 'text-[#10B981]';
    if (changeType === 'negative') return 'text-[#EF4444]';
    return 'text-[#6B7280]';
  };
  
  const ChangeIcon = change && change >= 0 ? TrendingUp : TrendingDown;
  
  return (
    <div className="card-xdc">
      <div className="flex items-start justify-between mb-3">
        <div className="w-10 h-10 rounded-xl bg-[rgba(30,144,255,0.1)] flex items-center justify-center text-[#1E90FF]">
          {icon}
        </div>
        {change !== undefined && (
          <div className={`flex items-center gap-1 text-xs ${getChangeColor()}`}>
            <ChangeIcon className="w-3 h-3" />
            <span>{Math.abs(change)}%</span>
          </div>
        )}
      </div>
      
      <div className="section-header mb-1">{label}</div>
      <div className="flex items-baseline gap-1">
        <span className="stat-value font-mono-nums">
          {value > 0 ? formatValue(displayValue) : '—'}
        </span>
        {suffix && <span className="text-sm text-[#6B7280]">{suffix}</span>}
      </div>
    </div>
  );
}

export default function StatsGrid({ metrics }: StatsGridProps) {
  const syncRatePerMin = (metrics.sync?.syncRate || 0) * 60;
  
  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
      <StatCard
        icon={<Blocks className="w-5 h-5" />}
        label="Block Height"
        value={metrics.blockchain.blockHeight}
        change={2.4}
        changeType="positive"
      />
      
      <StatCard
        icon={<Users className="w-5 h-5" />}
        label="Peers Connected"
        value={metrics.blockchain.peers}
        change={metrics.blockchain.peers > 20 ? 5.2 : -2.1}
        changeType={metrics.blockchain.peers > 20 ? 'positive' : 'negative'}
      />
      
      <StatCard
        icon={<FileText className="w-5 h-5" />}
        label="TX Pool Pending"
        value={metrics.txpool.pending}
        change={-1.5}
        changeType="neutral"
      />
      
      <StatCard
        icon={<Zap className="w-5 h-5" />}
        label="Sync Rate"
        value={Math.round(syncRatePerMin)}
        suffix="b/min"
        change={syncRatePerMin > 100 ? 12.5 : -5.3}
        changeType={syncRatePerMin > 100 ? 'positive' : 'negative'}
      />
    </div>
  );
}
