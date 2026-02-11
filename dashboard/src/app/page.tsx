import { getLatestReport } from '@/lib/reports';
import StatusIndicator from '@/components/StatusIndicator';
import AlertBadge from '@/components/AlertBadge';
import Link from 'next/link';

async function getData() {
  const report = await getLatestReport();
  return report;
}

export default async function OverviewPage() {
  const report = await getData();

  if (!report) {
    return (
      <div className="flex items-center justify-center h-96">
        <div className="text-center">
          <h2 className="text-xl text-white mb-2">No Data Available</h2>
          <p className="text-gray-400 mb-4">Run a health check to generate data.</p>
          <RunHealthCheckButton />
        </div>
      </div>
    );
  }

  const { summary, nodes, networkBlockHeight, timestamp } = report;
  
  // Get recent alerts from all nodes
  const recentAlerts = nodes
    .flatMap(n => n.alerts.map(a => ({ ...a, nodeName: n.hostname })))
    .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
    .slice(0, 10);

  return (
    <div className="animate-fadeIn">
      <div className="flex justify-between items-center mb-8">
        <div>
          <h1 className="text-3xl font-bold text-white">Overview</h1>
          <p className="text-gray-400 mt-1">
            Last updated: {new Date(timestamp).toLocaleString()}
          </p>
        </div>
        <div className="flex gap-3">
          <RunHealthCheckButton />
          <CheckVersionsButton />
        </div>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <SummaryCard
          title="Total Nodes"
          value={summary.total}
          icon="🖥️"
          color="text-white"
        />
        <SummaryCard
          title="Healthy"
          value={summary.healthy}
          icon="✅"
          color="text-status-healthy"
        />
        <SummaryCard
          title="Warning"
          value={summary.warning}
          icon="⚠️"
          color="text-status-warning"
        />
        <SummaryCard
          title="Critical"
          value={summary.critical}
          icon="🚨"
          color="text-status-critical"
        />
      </div>

      {/* Network Stats */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
        <div className="bg-xdc-card border border-xdc-border rounded-xl p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Network Statistics</h2>
          <div className="space-y-4">
            <div className="flex justify-between items-center">
              <span className="text-gray-400">Mainnet Block Height</span>
              <span className="text-white font-mono text-lg">
                {networkBlockHeight.toLocaleString()}
              </span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-gray-400">Average Sync Progress</span>
              <span className="text-xdc-primary font-semibold">
                {summary.avgSyncProgress.toFixed(1)}%
              </span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-gray-400">Active Nodes</span>
              <span className="text-white">
                {nodes.filter(n => n.status !== 'offline').length} / {summary.total}
              </span>
            </div>
          </div>
        </div>

        {/* Node Status Grid */}
        <div className="bg-xdc-card border border-xdc-border rounded-xl p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Node Status</h2>
          <div className="grid grid-cols-2 gap-3">
            {nodes.slice(0, 6).map((node) => (
              <Link
                key={node.id}
                href={`/nodes/${node.id}`}
                className="flex items-center justify-between p-3 bg-xdc-dark rounded-lg hover:bg-xdc-border transition-colors"
              >
                <span className="text-sm text-white truncate">{node.hostname}</span>
                <StatusIndicator status={node.status} size="sm" />
              </Link>
            ))}
          </div>
          {nodes.length > 6 && (
            <Link
              href="/nodes"
              className="block text-center text-xdc-primary text-sm mt-3 hover:underline"
            >
              View all {nodes.length} nodes →
            </Link>
          )}
        </div>
      </div>

      {/* Recent Alerts */}
      <div className="bg-xdc-card border border-xdc-border rounded-xl p-6">
        <div className="flex justify-between items-center mb-4">
          <h2 className="text-lg font-semibold text-white">Recent Alerts</h2>
          <Link href="/alerts" className="text-xdc-primary text-sm hover:underline">
            View all →
          </Link>
        </div>
        {recentAlerts.length === 0 ? (
          <p className="text-gray-400 text-center py-8">No alerts. All systems operational.</p>
        ) : (
          <div className="space-y-3">
            {recentAlerts.map((alert) => (
              <div
                key={alert.id}
                className="flex items-center justify-between p-3 bg-xdc-dark rounded-lg"
              >
                <div className="flex items-center gap-3">
                  <AlertBadge level={alert.level} size="sm" />
                  <div>
                    <p className="text-sm text-white">{alert.message}</p>
                    <p className="text-xs text-gray-500">{alert.nodeName}</p>
                  </div>
                </div>
                <span className="text-xs text-gray-500">
                  {new Date(alert.timestamp).toLocaleTimeString()}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function SummaryCard({
  title,
  value,
  icon,
  color,
}: {
  title: string;
  value: number;
  icon: string;
  color: string;
}) {
  return (
    <div className="bg-xdc-card border border-xdc-border rounded-xl p-6">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-gray-400 text-sm">{title}</p>
          <p className={`text-3xl font-bold mt-1 ${color}`}>{value}</p>
        </div>
        <span className="text-3xl">{icon}</span>
      </div>
    </div>
  );
}

function RunHealthCheckButton() {
  return (
    <form action="/api/health" method="POST">
      <button
        type="submit"
        className="px-4 py-2 bg-xdc-primary text-white rounded-lg hover:bg-xdc-secondary transition-colors font-medium"
      >
        🏥 Run Health Check
      </button>
    </form>
  );
}

function CheckVersionsButton() {
  return (
    <form action="/api/versions" method="POST">
      <button
        type="submit"
        className="px-4 py-2 bg-xdc-border text-white rounded-lg hover:bg-xdc-primary transition-colors font-medium"
      >
        📦 Check Versions
      </button>
    </form>
  );
}
