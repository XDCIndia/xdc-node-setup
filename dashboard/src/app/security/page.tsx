'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import type { NodeReport, HealthReport } from '@/lib/types';
import SecurityScore from '@/components/SecurityScore';

export default function SecurityPage() {
  const [nodes, setNodes] = useState<NodeReport[]>([]);
  const [loading, setLoading] = useState(true);
  const [runningAudit, setRunningAudit] = useState(false);

  useEffect(() => {
    fetchData();
  }, []);

  async function fetchData() {
    try {
      const res = await fetch('/api/security');
      const data = await res.json();
      setNodes(data.nodes || []);
    } catch (error) {
      console.error('Failed to fetch security data:', error);
    } finally {
      setLoading(false);
    }
  }

  async function runAudit() {
    setRunningAudit(true);
    try {
      await fetch('/api/security', { method: 'POST' });
      await fetchData();
    } catch (error) {
      console.error('Failed to run audit:', error);
    } finally {
      setRunningAudit(false);
    }
  }

  const avgScore = nodes.length > 0
    ? nodes.reduce((sum, n) => sum + n.securityScore, 0) / nodes.length
    : 0;

  // Collect all failed checks across nodes
  const failedChecks = nodes.flatMap(node =>
    node.securityChecks
      .filter(check => !check.passed)
      .map(check => ({
        ...check,
        nodeId: node.id,
        nodeName: node.hostname,
      }))
  );

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
          <h1 className="text-3xl font-bold text-white">Security</h1>
          <p className="text-gray-400 mt-1">Security posture across all nodes</p>
        </div>
        <button
          onClick={runAudit}
          disabled={runningAudit}
          className="px-4 py-2 bg-xdc-primary text-white rounded-lg hover:bg-xdc-secondary transition-colors font-medium disabled:opacity-50"
        >
          {runningAudit ? '🔄 Running...' : '🔒 Run Audit'}
        </button>
      </div>

      {/* Fleet Overview */}
      <div className="bg-xdc-card border border-xdc-border rounded-xl p-6 mb-8">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-lg font-semibold text-white mb-2">Fleet Security Score</h2>
            <p className="text-gray-400 text-sm">Average security score across {nodes.length} nodes</p>
          </div>
          <SecurityScore score={avgScore} size="lg" />
        </div>
        <div className="mt-6 h-4 bg-xdc-border rounded-full overflow-hidden">
          <div 
            className={`h-full rounded-full transition-all ${
              avgScore >= 80 ? 'bg-status-healthy' :
              avgScore >= 60 ? 'bg-status-warning' : 'bg-status-critical'
            }`}
            style={{ width: `${avgScore}%` }}
          />
        </div>
      </div>

      {/* Per-Node Scores */}
      <div className="bg-xdc-card border border-xdc-border rounded-xl p-6 mb-8">
        <h2 className="text-lg font-semibold text-white mb-4">Node Security Scores</h2>
        <div className="space-y-4">
          {nodes.map((node) => (
            <Link
              key={node.id}
              href={`/nodes/${node.id}`}
              className="flex items-center justify-between p-4 bg-xdc-dark rounded-lg hover:bg-xdc-border transition-colors"
            >
              <div className="flex items-center gap-4">
                <SecurityScore score={node.securityScore} size="sm" showLabel={false} />
                <div>
                  <p className="text-white font-medium">{node.hostname}</p>
                  <p className="text-gray-500 text-sm">{node.ip}</p>
                </div>
              </div>
              <div className="flex-1 mx-8 max-w-md">
                <div className="h-3 bg-xdc-border rounded-full overflow-hidden">
                  <div 
                    className={`h-full rounded-full ${
                      node.securityScore >= 80 ? 'bg-status-healthy' :
                      node.securityScore >= 60 ? 'bg-status-warning' : 'bg-status-critical'
                    }`}
                    style={{ width: `${node.securityScore}%` }}
                  />
                </div>
              </div>
              <span className={`text-lg font-bold ${
                node.securityScore >= 80 ? 'text-status-healthy' :
                node.securityScore >= 60 ? 'text-status-warning' : 'text-status-critical'
              }`}>
                {node.securityScore}%
              </span>
            </Link>
          ))}
        </div>
      </div>

      {/* Security Checklist */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
        {nodes.map((node) => (
          <div key={node.id} className="bg-xdc-card border border-xdc-border rounded-xl p-6">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-white font-semibold">{node.hostname}</h3>
              <span className={`text-sm font-medium ${
                node.securityScore >= 80 ? 'text-status-healthy' :
                node.securityScore >= 60 ? 'text-status-warning' : 'text-status-critical'
              }`}>
                {node.securityScore}%
              </span>
            </div>
            <div className="grid grid-cols-2 gap-2">
              {node.securityChecks.map((check, i) => (
                <div
                  key={i}
                  className="flex items-center gap-2 p-2 rounded bg-xdc-dark text-sm"
                  title={check.description}
                >
                  <span className={check.passed ? 'text-status-healthy' : 'text-status-critical'}>
                    {check.passed ? '✓' : '✗'}
                  </span>
                  <span className={check.passed ? 'text-gray-400' : 'text-white'}>
                    {check.name}
                  </span>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>

      {/* Recommendations */}
      {failedChecks.length > 0 && (
        <div className="bg-xdc-card border border-xdc-border rounded-xl p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Recommendations</h2>
          <div className="space-y-3">
            {failedChecks.map((check, i) => (
              <div
                key={i}
                className="flex items-start gap-3 p-4 bg-status-critical/10 border border-status-critical/30 rounded-lg"
              >
                <span className="text-status-critical text-lg">⚠️</span>
                <div>
                  <p className="text-white font-medium">{check.name}</p>
                  <p className="text-gray-400 text-sm">{check.description}</p>
                  <p className="text-gray-500 text-xs mt-1">Node: {check.nodeName}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
