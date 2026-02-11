'use client';

import Link from 'next/link';
import type { NodeReport } from '@/lib/types';
import StatusIndicator from './StatusIndicator';
import MetricGauge from './MetricGauge';
import VersionBadge from './VersionBadge';

interface NodeCardProps {
  node: NodeReport;
}

export default function NodeCard({ node }: NodeCardProps) {
  const formatUptime = (seconds: number): string => {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    if (days > 0) return `${days}d ${hours}h`;
    const minutes = Math.floor((seconds % 3600) / 60);
    return `${hours}h ${minutes}m`;
  };

  const getPeerColor = (count: number): string => {
    if (count > 5) return 'text-status-healthy';
    if (count >= 1) return 'text-status-warning';
    return 'text-status-critical';
  };

  return (
    <Link href={`/nodes/${node.id}`}>
      <div className="bg-xdc-card border border-xdc-border rounded-xl p-5 hover:border-xdc-primary transition-all cursor-pointer">
        <div className="flex items-start justify-between mb-4">
          <div>
            <h3 className="font-semibold text-white text-lg">{node.hostname}</h3>
            <p className="text-sm text-gray-400">{node.ip}</p>
          </div>
          <StatusIndicator status={node.status} />
        </div>

        <div className="flex items-center gap-2 mb-4">
          <span className="px-2 py-1 bg-xdc-border rounded text-xs text-gray-300 capitalize">
            {node.role}
          </span>
          <span className="px-2 py-1 bg-xdc-border rounded text-xs text-gray-300">
            {node.clientType}
          </span>
          <span className="px-2 py-1 bg-xdc-border rounded text-xs text-gray-300">
            {node.network}
          </span>
        </div>

        {/* Block Height & Sync */}
        <div className="mb-4">
          <div className="flex justify-between text-sm mb-1">
            <span className="text-gray-400">Block Height</span>
            <span className="text-white font-mono">{node.metrics.blockHeight.toLocaleString()}</span>
          </div>
          <div className="h-2 bg-xdc-border rounded-full overflow-hidden">
            <div 
              className="h-full bg-xdc-primary rounded-full transition-all"
              style={{ width: `${node.metrics.syncProgress}%` }}
            />
          </div>
          <p className="text-xs text-gray-500 mt-1">{node.metrics.syncProgress.toFixed(1)}% synced</p>
        </div>

        {/* Peers */}
        <div className="flex justify-between items-center mb-4">
          <span className="text-sm text-gray-400">Peers</span>
          <span className={`font-semibold ${getPeerColor(node.metrics.peerCount)}`}>
            {node.metrics.peerCount}
          </span>
        </div>

        {/* Resource Gauges */}
        <div className="grid grid-cols-3 gap-3 mb-4">
          <MetricGauge label="CPU" value={node.metrics.cpuUsage} />
          <MetricGauge label="RAM" value={node.metrics.ramUsage} />
          <MetricGauge label="Disk" value={node.metrics.diskUsage} />
        </div>

        {/* Version Badge */}
        <div className="flex justify-between items-center mb-3">
          <span className="text-sm text-gray-400">Version</span>
          <VersionBadge 
            current={node.clientVersion} 
            latest={node.latestVersion} 
          />
        </div>

        {/* Uptime */}
        <div className="flex justify-between items-center pt-3 border-t border-xdc-border">
          <span className="text-sm text-gray-400">Uptime</span>
          <span className="text-sm text-white">{formatUptime(node.uptime)}</span>
        </div>
      </div>
    </Link>
  );
}
