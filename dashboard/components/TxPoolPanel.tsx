'use client';

import { FileText, CheckCircle2, XCircle, AlertTriangle, Layers, Loader2 } from 'lucide-react';
import { useAnimatedNumber } from '@/lib/animations';
import { formatNumber } from '@/lib/formatters';
import type { TxPoolData } from '@/lib/types';

interface TxPoolPanelProps {
  data: TxPoolData;
}

function DonutChart({ 
  data, 
  size = 120, 
  strokeWidth = 12 
}: { 
  data: { label: string; value: number; color: string }[];
  size?: number;
  strokeWidth?: number;
}) {
  const total = data.reduce((sum, item) => sum + item.value, 0);
  const radius = (size - strokeWidth) / 2;
  const circumference = radius * 2 * Math.PI;
  
  let currentOffset = 0;
  
  return (
    <div className="relative" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="transform -rotate-90">
        {data.map((item) => {
          const percentage = total > 0 ? item.value / total : 0;
          const dashArray = percentage * circumference;
          const offset = currentOffset;
          currentOffset += dashArray;
          
          return (
            <circle
              key={item.label}
              cx={size / 2}
              cy={size / 2}
              r={radius}
              fill="none"
              stroke={item.color}
              strokeWidth={strokeWidth}
              strokeDasharray={`${dashArray} ${circumference - dashArray}`}
              strokeDashoffset={-offset}
              style={{
                transition: 'all 0.5s ease-out',
              }}
            />
          );
        })}
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-xl font-bold font-mono-nums text-[#F9FAFB]">
          {formatNumber(total)}
        </span>
        <span className="text-xs text-[#6B7280]">Total</span>
      </div>
    </div>
  );
}

export default function TxPoolPanel({ data }: TxPoolPanelProps) {
  const { isSyncing, available = true } = data;
  
  // Determine display state
  const getState = () => {
    if (isSyncing) return 'syncing';
    if (!available) return 'unavailable';
    return 'ready';
  };
  
  const state = getState();
  
  const total = data.pending + data.queued + data.slots;
  const hasTransactions = total > 0;
  
  const donutData = [
    { label: 'Pending', value: data.pending, color: '#1E90FF' },
    { label: 'Queued', value: data.queued, color: '#F59E0B' },
    { label: 'Slots', value: data.slots, color: '#6B7280' },
  ];
  
  const displayPending = useAnimatedNumber(data.pending, 800);
  const displayQueued = useAnimatedNumber(data.queued, 800);
  const displayValid = useAnimatedNumber(data.valid, 800);
  
  // Render syncing state
  if (state === 'syncing') {
    return (
      <div id="transactions" className="card-xdc">
        {/* Header */}
        <div className="flex items-center gap-3 mb-5">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#1E90FF]/20 to-[#10B981]/10 flex items-center justify-center">
            <FileText className="w-5 h-5 text-[#1E90FF]" />
          </div>
          <div>
            <h2 className="text-lg font-semibold text-[#F9FAFB]">Transaction Pool</h2>
            <div className="flex items-center gap-2 text-sm text-[#F59E0B]">
              <Loader2 className="w-3 h-3 animate-spin" />
              <span>Node is syncing...</span>
            </div>
          </div>
        </div>
        
        <div className="flex flex-col items-center justify-center py-8 text-center">
          <Loader2 className="w-12 h-12 text-[#F59E0B] animate-spin mb-4" />
          <p className="text-[#9CA3AF]">Transaction pool data unavailable while syncing</p>
          <p className="text-sm text-[#6B7280] mt-2">TxPool will be available once sync is complete</p>
        </div>
      </div>
    );
  }
  
  // Render unavailable state
  if (state === 'unavailable') {
    return (
      <div id="transactions" className="card-xdc">
        {/* Header */}
        <div className="flex items-center gap-3 mb-5">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#1E90FF]/20 to-[#10B981]/10 flex items-center justify-center">
            <FileText className="w-5 h-5 text-[#1E90FF]" />
          </div>
          <div>
            <h2 className="text-lg font-semibold text-[#F9FAFB]">Transaction Pool</h2>
            <div className="flex items-center gap-2 text-sm text-[#EF4444]">
              <AlertTriangle className="w-3 h-3" />
              <span>TxPool not available</span>
            </div>
          </div>
        </div>
        
        <div className="flex flex-col items-center justify-center py-8 text-center">
          <AlertTriangle className="w-12 h-12 text-[#EF4444] mb-4" />
          <p className="text-[#9CA3AF]">Transaction pool data is not available</p>
          <p className="text-sm text-[#6B7280] mt-2">The node may not support txpool API or RPC connection may be limited</p>
        </div>
      </div>
    );
  }
  
  return (
    <div id="transactions" className="card-xdc">
      {/* Header */}
      <div className="flex items-center gap-3 mb-5">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#1E90FF]/20 to-[#10B981]/10 flex items-center justify-center">
          <FileText className="w-5 h-5 text-[#1E90FF]" />
        </div>
        <div>
          <h2 className="text-lg font-semibold text-[#F9FAFB]">Transaction Pool</h2>
          <div className="text-sm text-[#6B7280]">
            {hasTransactions ? `${formatNumber(total)} total transactions` : '0 transactions (empty pool)'}
          </div>
        </div>
      </div>
      
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Donut Chart */}
        <div className="flex items-center justify-center">
          <DonutChart data={donutData} size={140} strokeWidth={14} />
        </div>
        
        {/* Stats List */}
        <div className="space-y-3">
          {donutData.map((item) => (
            <div key={item.label} className="flex items-center justify-between p-3 rounded-lg bg-[rgba(255,255,255,0.02)]">
              <div className="flex items-center gap-2">
                <div 
                  className="w-3 h-3 rounded-full"
                  style={{ backgroundColor: item.color, boxShadow: `0 0 6px ${item.color}60` }}
                />
                <span className="text-sm text-[#9CA3AF]">{item.label}</span>
              </div>
              <span className="text-lg font-semibold font-mono-nums text-[#F9FAFB]">
                {item.value === 0 ? (
                  <span className="text-[#6B7280]">0</span>
                ) : (
                  formatNumber(item.value)
                )}
              </span>
            </div>
          ))}
        </div>
      </div>
      
      {/* TX Validation Stats */}
      <div className="grid grid-cols-3 gap-3 mt-5">
        <div className="p-3 rounded-xl bg-[rgba(16,185,129,0.05)] text-center">
          <div className="flex items-center justify-center gap-1 mb-1">
            <CheckCircle2 className="w-3 h-3 text-[#10B981]" />
            <span className="section-header">Valid</span>
          </div>
          <div className="text-lg font-semibold font-mono-nums text-[#10B981]">
            {data.valid === 0 ? (
              <span className="text-[#6B7280]">0</span>
            ) : (
              formatNumber(data.valid)
            )}
          </div>
        </div>
        
        <div className="p-3 rounded-xl bg-[rgba(239,68,68,0.05)] text-center">
          <div className="flex items-center justify-center gap-1 mb-1">
            <XCircle className="w-3 h-3 text-[#EF4444]" />
            <span className="section-header">Invalid</span>
          </div>
          <div className="text-lg font-semibold font-mono-nums text-[#EF4444]">
            {data.invalid === 0 ? (
              <span className="text-[#6B7280]">0</span>
            ) : (
              formatNumber(data.invalid)
            )}
          </div>
        </div>
        
        <div className="p-3 rounded-xl bg-[rgba(245,158,11,0.05)] text-center">
          <div className="flex items-center justify-center gap-1 mb-1">
            <AlertTriangle className="w-3 h-3 text-[#F59E0B]" />
            <span className="section-header">Underpriced</span>
          </div>
          <div className="text-lg font-semibold font-mono-nums text-[#F59E0B]">
            {data.underpriced === 0 ? (
              <span className="text-[#6B7280]">0</span>
            ) : (
              formatNumber(data.underpriced)
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
