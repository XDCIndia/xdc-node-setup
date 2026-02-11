'use client';

import { Monitor, Cpu, MemoryStick, HardDrive, Activity } from 'lucide-react';
import { useAnimatedNumber } from '@/lib/animations';
import { formatBytes, formatNumber, getUsageColor } from '@/lib/formatters';
import type { ServerData } from '@/lib/types';

interface ServerStatsProps {
  data: ServerData;
}

function CircularGauge({ 
  value, 
  label, 
  color,
  size = 80,
  strokeWidth = 6
}: { 
  value: number; 
  label: string; 
  color: string;
  size?: number;
  strokeWidth?: number;
}) {
  const radius = (size - strokeWidth) / 2;
  const circumference = radius * 2 * Math.PI;
  const offset = circumference - (value / 100) * circumference;
  
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
          <span className="text-lg font-bold font-mono-nums" style={{ color }}>
            {Math.round(value)}%
          </span>
        </div>
      </div>
      <span className="section-header mt-2">{label}</span>
    </div>
  );
}

function ResourceBar({ label, used, total, icon: Icon }: { label: string; used: number; total: number; icon: any }) {
  const percentage = total > 0 ? (used / total) * 100 : 0;
  const color = getUsageColor(percentage);
  
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Icon className="w-4 h-4 text-[#6B7280]" />
          <span className="text-sm text-[#9CA3AF]">{label}</span>
        </div>
        <div className="text-right">
          <span className="text-sm font-medium text-[#F9FAFB]">{formatBytes(used)}</span>
          <span className="text-xs text-[#6B7280] ml-1">/ {formatBytes(total)}</span>
        </div>
      </div>
      <div className="w-full h-2 bg-[rgba(255,255,255,0.06)] rounded-full overflow-hidden">
        <div 
          className="h-full rounded-full transition-all duration-500"
          style={{
            width: `${Math.min(100, percentage)}%`,
            backgroundColor: color,
            boxShadow: `0 0 8px ${color}50`,
          }}
        />
      </div>
    </div>
  );
}

export default function ServerStats({ data }: ServerStatsProps) {
  const memoryPercent = data.memoryTotal > 0 ? (data.memoryUsed / data.memoryTotal) * 100 : 0;
  const diskPercent = data.diskTotal > 0 ? (data.diskUsed / data.diskTotal) * 100 : 0;
  
  const cpuColor = getUsageColor(data.cpuUsage);
  const memColor = getUsageColor(memoryPercent);
  const diskColor = getUsageColor(diskPercent);
  
  const displayGoroutines = useAnimatedNumber(data.goroutines, 1000);
  
  return (
    <div id="server" className="card-xdc">
      {/* Header */}
      <div className="flex items-center gap-3 mb-5">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#EF4444]/20 to-[#F59E0B]/10 flex items-center justify-center">
          <Monitor className="w-5 h-5 text-[#EF4444]" />
        </div>
        <div>
          <h2 className="text-lg font-semibold text-[#F9FAFB]">Server Resources</h2>
          <div className="text-sm text-[#6B7280]">System performance metrics</div>
        </div>
      </div>
      
      {/* Gauges */}
      <div className="grid grid-cols-3 gap-4 mb-6">
        <CircularGauge 
          value={data.cpuUsage} 
          label="CPU" 
          color={cpuColor}
        />
        <CircularGauge 
          value={memoryPercent} 
          label="Memory" 
          color={memColor}
        />
        <CircularGauge 
          value={diskPercent} 
          label="Disk" 
          color={diskColor}
        />
      </div>
      
      {/* Resource Bars */}
      <div className="space-y-4">
        <ResourceBar
          label="Memory Usage"
          used={data.memoryUsed}
          total={data.memoryTotal}
          icon={MemoryStick}
        />
        
        <ResourceBar
          label="Disk Usage"
          used={data.diskUsed}
          total={data.diskTotal}
          icon={HardDrive}
        />
      </div>
      
      {/* Stats Grid */}
      <div className="grid grid-cols-3 gap-3 mt-5">
        <div className="p-3 rounded-xl bg-[rgba(255,255,255,0.02)] text-center">
          <div className="section-header mb-1">Goroutines</div>
          <div className="text-lg font-semibold font-mono-nums text-[#F9FAFB]">
            {formatNumber(displayGoroutines)}
          </div>
        </div>
        
        <div className="p-3 rounded-xl bg-[rgba(255,255,255,0.02)] text-center">
          <div className="section-header mb-1">Sys Load</div>
          <div className="text-lg font-semibold font-mono-nums text-[#F9FAFB]">
            {data.sysLoad.toFixed(2)}
          </div>
        </div>
        
        <div className="p-3 rounded-xl bg-[rgba(255,255,255,0.02)] text-center">
          <div className="section-header mb-1">Proc Load</div>
          <div className="text-lg font-semibold font-mono-nums text-[#F9FAFB]">
            {data.procLoad.toFixed(2)}
          </div>
        </div>
      </div>
    </div>
  );
}
