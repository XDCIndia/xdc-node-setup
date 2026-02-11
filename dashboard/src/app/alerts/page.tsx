'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import type { Alert, AlertLevel } from '@/lib/types';
import AlertBadge from '@/components/AlertBadge';

export default function AlertsPage() {
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState({
    level: 'all' as 'all' | AlertLevel,
    nodeId: 'all',
    acknowledged: 'all' as 'all' | 'true' | 'false',
  });

  useEffect(() => {
    fetchAlerts();
  }, []);

  async function fetchAlerts() {
    try {
      const res = await fetch('/api/alerts');
      const data = await res.json();
      setAlerts(data.alerts || []);
    } catch (error) {
      console.error('Failed to fetch alerts:', error);
    } finally {
      setLoading(false);
    }
  }

  async function acknowledgeAlert(alertId: string) {
    try {
      await fetch('/api/alerts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ alertId, action: 'acknowledge' }),
      });
      setAlerts(alerts.map(a =>
        a.id === alertId ? { ...a, acknowledged: true, acknowledgedAt: new Date().toISOString() } : a
      ));
    } catch (error) {
      console.error('Failed to acknowledge alert:', error);
    }
  }

  async function dismissAlert(alertId: string) {
    try {
      await fetch('/api/alerts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ alertId, action: 'dismiss' }),
      });
      setAlerts(alerts.filter(a => a.id !== alertId));
    } catch (error) {
      console.error('Failed to dismiss alert:', error);
    }
  }

  const filteredAlerts = alerts.filter((alert) => {
    if (filter.level !== 'all' && alert.level !== filter.level) return false;
    if (filter.nodeId !== 'all' && alert.nodeId !== filter.nodeId) return false;
    if (filter.acknowledged !== 'all' && String(alert.acknowledged) !== filter.acknowledged) return false;
    return true;
  });

  const uniqueNodes = [...new Set(alerts.map(a => a.nodeId))];

  const criticalCount = alerts.filter(a => a.level === 'critical' && !a.acknowledged).length;
  const warningCount = alerts.filter(a => a.level === 'warning' && !a.acknowledged).length;

  if (loading) {
    return (
      <div className="flex items-center justify-center h-96">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-xdc-primary"></div>
      </div>
    );
  }

  return (
    <div className="animate-fadeIn">
      <div className="flex justify-between items-center mb-8">
        <div>
          <h1 className="text-3xl font-bold text-white">Alerts</h1>
          <p className="text-gray-400 mt-1">
            {criticalCount > 0 && <span className="text-status-critical">{criticalCount} critical</span>}
            {criticalCount > 0 && warningCount > 0 && ', '}
            {warningCount > 0 && <span className="text-status-warning">{warningCount} warnings</span>}
            {criticalCount === 0 && warningCount === 0 && 'No active alerts'}
          </p>
        </div>
        <Link
          href="/settings"
          className="px-4 py-2 bg-xdc-border text-white rounded-lg hover:bg-xdc-primary transition-colors font-medium"
        >
          🔔 Notification Settings
        </Link>
      </div>

      {/* Filters */}
      <div className="bg-xdc-card border border-xdc-border rounded-xl p-4 mb-6">
        <div className="flex flex-wrap gap-4">
          <div>
            <label className="block text-sm text-gray-400 mb-1">Level</label>
            <select
              value={filter.level}
              onChange={(e) => setFilter({ ...filter, level: e.target.value as any })}
              className="bg-xdc-dark border border-xdc-border rounded-lg px-3 py-2 text-white text-sm focus:outline-none focus:border-xdc-primary"
            >
              <option value="all">All Levels</option>
              <option value="critical">Critical</option>
              <option value="warning">Warning</option>
              <option value="info">Info</option>
            </select>
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Node</label>
            <select
              value={filter.nodeId}
              onChange={(e) => setFilter({ ...filter, nodeId: e.target.value })}
              className="bg-xdc-dark border border-xdc-border rounded-lg px-3 py-2 text-white text-sm focus:outline-none focus:border-xdc-primary"
            >
              <option value="all">All Nodes</option>
              {uniqueNodes.map(nodeId => (
                <option key={nodeId} value={nodeId}>{nodeId}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Status</label>
            <select
              value={filter.acknowledged}
              onChange={(e) => setFilter({ ...filter, acknowledged: e.target.value as any })}
              className="bg-xdc-dark border border-xdc-border rounded-lg px-3 py-2 text-white text-sm focus:outline-none focus:border-xdc-primary"
            >
              <option value="all">All</option>
              <option value="false">Unacknowledged</option>
              <option value="true">Acknowledged</option>
            </select>
          </div>
        </div>
      </div>

      {/* Alert Timeline */}
      {filteredAlerts.length === 0 ? (
        <div className="bg-xdc-card border border-xdc-border rounded-xl p-12 text-center">
          <span className="text-5xl mb-4 block">✅</span>
          <h2 className="text-xl text-white mb-2">No Alerts</h2>
          <p className="text-gray-400">All systems are operating normally.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {filteredAlerts.map((alert) => (
            <div
              key={alert.id}
              className={`bg-xdc-card border rounded-xl p-4 ${
                alert.acknowledged ? 'border-xdc-border opacity-60' : 
                alert.level === 'critical' ? 'border-status-critical/50' :
                alert.level === 'warning' ? 'border-status-warning/50' : 'border-xdc-border'
              }`}
            >
              <div className="flex items-start justify-between">
                <div className="flex items-start gap-4">
                  <AlertBadge level={alert.level} />
                  <div>
                    <p className="text-white font-medium">{alert.message}</p>
                    <div className="flex items-center gap-4 mt-2 text-sm">
                      <Link
                        href={`/nodes/${alert.nodeId}`}
                        className="text-xdc-primary hover:underline"
                      >
                        {alert.nodeName}
                      </Link>
                      <span className="text-gray-500">
                        {new Date(alert.timestamp).toLocaleString()}
                      </span>
                      {alert.acknowledged && (
                        <span className="text-gray-500">
                          Acknowledged {new Date(alert.acknowledgedAt!).toLocaleString()}
                        </span>
                      )}
                    </div>
                  </div>
                </div>
                
                <div className="flex gap-2">
                  {!alert.acknowledged && (
                    <button
                      onClick={() => acknowledgeAlert(alert.id)}
                      className="px-3 py-1 bg-xdc-border text-white rounded text-sm hover:bg-xdc-primary transition-colors"
                    >
                      Acknowledge
                    </button>
                  )}
                  <button
                    onClick={() => dismissAlert(alert.id)}
                    className="px-3 py-1 bg-xdc-border text-gray-400 rounded text-sm hover:bg-status-critical hover:text-white transition-colors"
                  >
                    Dismiss
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
