'use client';

import { HardDrive, Database, TrendingUp, Gauge, ArrowUpDown } from 'lucide-react';
import { useAnimatedNumber } from '@/lib/animations';
import { formatBytes, formatNumber } from '@/lib/formatters';
import type { StorageData } from '@/lib/types';

interface StoragePanelProps {
  data: StorageData;
}

function CacheHitGauge({ rate }: { rate: number }) {
  const size = 100;
  const strokeWidth = 8;
  const radius = (size - strokeWidth) / 2;
  const circumference = radius * 2 * Math.PI;
  const offset = circumference - (rate / 100) * circumference;
  
  const color = rate >= 90 ? '#10B981' : rate >= 70 ? '#F59E0B' : '#EF4444';
  
  return (
    <div className="flex flex-col items-center">
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
            style={{
              transition: 'stroke-dashoffset 0.5s ease-out',
              filter: `drop-shadow(0 0 4px ${color}50)`,
            }}
          />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-xl font-bold font-mono-nums" style={{ color }}>
            {rate.toFixed(0)}%
          </span>
        </div>
      </div>
      <span className="section-header mt-2">Cache Hit Rate</span>
    </div>
  );
}

function DistributionBar({ label, value, color, max }: { label: string; value: number; color: string; max: number }) {
  const percentage = max > 0 ? (value / max) * 100 : 0;
  
  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between">
        <span className="text-sm text-[#9CA3AF]">{label}</span>
        <span className="text-sm font-medium font-mono-nums text-[#F9FAFB]">{formatBytes(value)}</span>
      </div>
      <div className="w-full h-2 bg-[rgba(255,255,255,0.06)] rounded-full overflow-hidden">
        <div 
          className="h-full rounded-full transition-all duration-500"
          style={{
            width: `${Math.min(100, percentage)}%`,
            backgroundColor: color,
          }}
        />
      </div>
    </div>
  );
}

export default function StoragePanel({ data }: StoragePanelProps) {
  const displayCacheMiss = useAnimatedNumber(data.trieCacheMiss, 1000);
  
  // Use actual database size if available, otherwise estimate
  const totalSize = data.databaseSize > 0 ? data.databaseSize : data.chainDataSize * 1.1;
  const metadataSize = totalSize - data.chainDataSize;
  
  return (
    <div id="storage" className="card-xdc">
      {/* Header */}
      <div className="flex items-center gap-3 mb-5">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#8B5CF6]/20 to-[#EC4899]/10 flex items-center justify-center">
          <HardDrive className="w-5 h-5 text-[#8B5CF6]" />
        </div>
        <div>
          <h2 className="text-lg font-semibold text-[#F9FAFB]">Storage & Database</h2>
          <div className="text-sm text-[#6B7280] flex items-center gap-2">
            <span>Chain data metrics</span>
            {(data as any).storageType && (data as any).storageType !== 'unknown' && (
              <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                (data as any).storageType?.includes('NVMe') ? 'bg-[#10B981]/10 text-[#10B981] border border-[#10B981]/20' :
                (data as any).storageType?.includes('SSD') ? 'bg-[#3B82F6]/10 text-[#3B82F6] border border-[#3B82F6]/20' :
                'bg-[#F59E0B]/10 text-[#F59E0B] border border-[#F59E0B]/20'
              }`}>
                {(data as any).storageType}
                {(data as any).iopsEstimate > 0 && ` · ~${((data as any).iopsEstimate / 1000).toFixed(1)}K IOPS`}
              </span>
            )}
          </div>
        </div>
      </div>
      
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left: Storage Stats */}
        <div className="lg:col-span-2 space-y-4">
          <div className="p-4 rounded-xl bg-[rgba(139,92,246,0.05)] border border-[rgba(139,92,246,0.1)]">
            <div className="flex items-center gap-3 mb-3">
              <Database className="w-5 h-5 text-[#8B5CF6]" />
              <div>
                <div className="section-header">Chain Data Size</div>
                <div className="text-2xl font-bold font-mono-nums text-[#F9FAFB]">
                  {data.chainDataSize > 0 ? formatBytes(data.chainDataSize) : <span className="text-[#6B7280]">Calculating...</span>}
                </div>
              </div>
            </div>
            {data.databaseSize > 0 && (
              <div className="text-sm text-[#9CA3AF]">
                Total DB: <span className="font-semibold text-[#F9FAFB]">{formatBytes(data.databaseSize)}</span>
              </div>
            )}
          </div>
          
          {/* Distribution Bars */}
          {data.chainDataSize > 0 && (
            <div className="space-y-3">
              <div className="section-header">Storage Distribution</div>            
              <DistributionBar
                label="Chain Data"
                value={data.chainDataSize}
                color="#8B5CF6"
                max={totalSize}
              />
              
              <DistributionBar
                label="Database Total"
                value={totalSize}
                color="#1E90FF"
                max={totalSize}
              />
            </div>
          )}
          
          {/* I/O Stats */}
          <div className="grid grid-cols-2 gap-4">
            <div className="p-3 rounded-xl bg-[rgba(255,255,255,0.02)]">
              <div className="flex items-center gap-2 mb-1">
                <ArrowUpDown className="w-4 h-4 text-[#1E90FF]" />
                <span className="section-header">Read Rate</span>
              </div>
              <div className="text-lg font-semibold font-mono-nums text-[#F9FAFB]">
                {formatBytes(data.diskReadRate)}/s
              </div>
            </div>
            
            <div className="p-3 rounded-xl bg-[rgba(255,255,255,0.02)]">
              <div className="flex items-center gap-2 mb-1">
                <ArrowUpDown className="w-4 h-4 text-[#10B981]" />
                <span className="section-header">Write Rate</span>
              </div>
              <div className="text-lg font-semibold font-mono-nums text-[#F9FAFB]">
                {formatBytes(data.diskWriteRate)}/s
              </div>
            </div>
          </div>
        </div>
        
        {/* Right: Cache Stats */}
        <div className="space-y-4">
          <div className="p-4 rounded-xl bg-[rgba(255,255,255,0.02)] flex flex-col items-center">
            <CacheHitGauge rate={data.trieCacheHitRate} />
          </div>
          
          <div className="p-4 rounded-xl bg-[rgba(255,255,255,0.02)]">
            <div className="flex items-center gap-2 mb-2">
              <Gauge className="w-4 h-4 text-[#F59E0B]" />
              <span className="section-header">Cache Misses</span>
            </div>
            <div className="text-2xl font-bold font-mono-nums text-[#F59E0B]">
              {formatNumber(displayCacheMiss)}
            </div>
          </div>
          
          <div className="p-4 rounded-xl bg-[rgba(255,255,255,0.02)]">
            <div className="section-header mb-2">Compaction Time</div>
            <div className="text-2xl font-bold font-mono-nums text-[#F9FAFB]">
              {data.compactTime.toFixed(2)}s
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
