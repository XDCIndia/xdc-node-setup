'use client';

import { useState, useEffect } from 'react';
import type { VersionConfig, ClientVersion } from '@/lib/types';

export default function VersionsPage() {
  const [config, setConfig] = useState<VersionConfig | null>(null);
  const [loading, setLoading] = useState(true);
  const [checking, setChecking] = useState(false);

  useEffect(() => {
    fetchVersions();
  }, []);

  async function fetchVersions() {
    try {
      const res = await fetch('/api/versions');
      const data = await res.json();
      setConfig(data);
    } catch (error) {
      console.error('Failed to fetch versions:', error);
    } finally {
      setLoading(false);
    }
  }

  async function checkVersions() {
    setChecking(true);
    try {
      await fetch('/api/versions', { method: 'POST' });
      await fetchVersions();
    } catch (error) {
      console.error('Failed to check versions:', error);
    } finally {
      setChecking(false);
    }
  }

  async function toggleAutoUpdate(client: string) {
    if (!config) return;
    
    const updated = {
      ...config,
      clients: config.clients.map(c =>
        c.client === client ? { ...c, autoUpdate: !c.autoUpdate } : c
      ),
    };
    
    try {
      await fetch('/api/versions', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updated),
      });
      setConfig(updated);
    } catch (error) {
      console.error('Failed to update config:', error);
    }
  }

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
          <h1 className="text-3xl font-bold text-white">Version Management</h1>
          <p className="text-gray-400 mt-1">
            Last checked: {config?.lastChecked ? new Date(config.lastChecked).toLocaleString() : 'Never'}
          </p>
        </div>
        <button
          onClick={checkVersions}
          disabled={checking}
          className="px-4 py-2 bg-xdc-primary text-white rounded-lg hover:bg-xdc-secondary transition-colors font-medium disabled:opacity-50"
        >
          {checking ? '🔄 Checking...' : '🔍 Check Versions'}
        </button>
      </div>

      {/* Version Table */}
      <div className="bg-xdc-card border border-xdc-border rounded-xl overflow-hidden mb-8">
        <table className="w-full">
          <thead className="bg-xdc-dark">
            <tr>
              <th className="text-left px-6 py-4 text-gray-400 font-medium">Client</th>
              <th className="text-left px-6 py-4 text-gray-400 font-medium">Current</th>
              <th className="text-left px-6 py-4 text-gray-400 font-medium">Latest</th>
              <th className="text-left px-6 py-4 text-gray-400 font-medium">Status</th>
              <th className="text-left px-6 py-4 text-gray-400 font-medium">Nodes</th>
              <th className="text-left px-6 py-4 text-gray-400 font-medium">Auto-Update</th>
              <th className="text-left px-6 py-4 text-gray-400 font-medium">Action</th>
            </tr>
          </thead>
          <tbody>
            {config?.clients.map((client) => (
              <tr key={client.client} className="border-t border-xdc-border">
                <td className="px-6 py-4">
                  <span className="text-white font-medium">{client.client}</span>
                </td>
                <td className="px-6 py-4">
                  <span className="font-mono text-gray-300">{client.current}</span>
                </td>
                <td className="px-6 py-4">
                  <span className="font-mono text-gray-300">{client.latest}</span>
                </td>
                <td className="px-6 py-4">
                  {client.current === client.latest ? (
                    <span className="px-2 py-1 bg-status-healthy/20 text-status-healthy rounded text-sm">
                      ✓ Up to date
                    </span>
                  ) : (
                    <span className="px-2 py-1 bg-status-warning/20 text-status-warning rounded text-sm">
                      ⚠ Update available
                    </span>
                  )}
                </td>
                <td className="px-6 py-4">
                  <span className="text-white">{client.nodeCount}</span>
                </td>
                <td className="px-6 py-4">
                  <button
                    onClick={() => toggleAutoUpdate(client.client)}
                    className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                      client.autoUpdate ? 'bg-xdc-primary' : 'bg-xdc-border'
                    }`}
                  >
                    <span
                      className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                        client.autoUpdate ? 'translate-x-6' : 'translate-x-1'
                      }`}
                    />
                  </button>
                </td>
                <td className="px-6 py-4">
                  {client.current !== client.latest && (
                    <button className="px-3 py-1 bg-xdc-primary text-white rounded text-sm hover:bg-xdc-secondary transition-colors">
                      Update
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Release Info */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
        {config?.clients.map((client) => (
          <div key={client.client} className="bg-xdc-card border border-xdc-border rounded-xl p-6">
            <h3 className="text-lg font-semibold text-white mb-3">{client.client}</h3>
            <div className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-gray-400">Release Date:</span>
                <span className="text-white">{new Date(client.releaseDate).toLocaleDateString()}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-400">Changelog:</span>
                <a
                  href={client.changelogUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-xdc-primary hover:underline"
                >
                  View on GitHub →
                </a>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Update History */}
      <div className="bg-xdc-card border border-xdc-border rounded-xl p-6">
        <h2 className="text-lg font-semibold text-white mb-4">Update History</h2>
        {config?.updateHistory && config.updateHistory.length > 0 ? (
          <div className="space-y-3">
            {config.updateHistory.map((entry, i) => (
              <div
                key={i}
                className="flex items-center justify-between p-3 bg-xdc-dark rounded-lg"
              >
                <div className="flex items-center gap-3">
                  <span className={entry.success ? 'text-status-healthy' : 'text-status-critical'}>
                    {entry.success ? '✓' : '✗'}
                  </span>
                  <div>
                    <p className="text-white text-sm">
                      {entry.client}: {entry.fromVersion} → {entry.toVersion}
                    </p>
                    <p className="text-gray-500 text-xs">Node: {entry.nodeId}</p>
                  </div>
                </div>
                <span className="text-gray-500 text-sm">
                  {new Date(entry.timestamp).toLocaleString()}
                </span>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-gray-400 text-center py-8">No update history available.</p>
        )}
      </div>
    </div>
  );
}
