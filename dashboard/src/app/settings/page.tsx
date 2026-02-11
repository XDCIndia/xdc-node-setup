'use client';

import { useState, useEffect } from 'react';
import type { Settings, NodeRegistration } from '@/lib/types';

export default function SettingsPage() {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [activeTab, setActiveTab] = useState<'notifications' | 'nodes' | 'api' | 'general'>('notifications');

  useEffect(() => {
    fetchSettings();
  }, []);

  async function fetchSettings() {
    try {
      const res = await fetch('/api/settings');
      const data = await res.json();
      setSettings(data);
    } catch (error) {
      console.error('Failed to fetch settings:', error);
    } finally {
      setLoading(false);
    }
  }

  async function saveSettings() {
    if (!settings) return;
    setSaving(true);
    try {
      await fetch('/api/settings', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(settings),
      });
    } catch (error) {
      console.error('Failed to save settings:', error);
    } finally {
      setSaving(false);
    }
  }

  if (loading || !settings) {
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
          <h1 className="text-3xl font-bold text-white">Settings</h1>
          <p className="text-gray-400 mt-1">Configure dashboard and notifications</p>
        </div>
        <button
          onClick={saveSettings}
          disabled={saving}
          className="px-4 py-2 bg-xdc-primary text-white rounded-lg hover:bg-xdc-secondary transition-colors font-medium disabled:opacity-50"
        >
          {saving ? '💾 Saving...' : '💾 Save Settings'}
        </button>
      </div>

      {/* Tabs */}
      <div className="border-b border-xdc-border mb-6">
        <div className="flex gap-4">
          {(['notifications', 'nodes', 'api', 'general'] as const).map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`px-4 py-3 font-medium capitalize transition-colors ${
                activeTab === tab
                  ? 'text-xdc-primary border-b-2 border-xdc-primary'
                  : 'text-gray-400 hover:text-white'
              }`}
            >
              {tab === 'api' ? 'API Keys' : tab}
            </button>
          ))}
        </div>
      </div>

      {/* Notifications Tab */}
      {activeTab === 'notifications' && (
        <div className="space-y-6">
          {/* Channels */}
          <div className="bg-xdc-card border border-xdc-border rounded-xl p-6">
            <h2 className="text-lg font-semibold text-white mb-4">Notification Channels</h2>
            <div className="space-y-4">
              {settings.notifications.channels.map((channel, i) => (
                <div key={i} className="flex items-center justify-between p-4 bg-xdc-dark rounded-lg">
                  <div className="flex items-center gap-3">
                    <span className="text-2xl">
                      {channel.type === 'telegram' ? '📱' :
                       channel.type === 'email' ? '📧' :
                       channel.type === 'slack' ? '💬' : '🔗'}
                    </span>
                    <div>
                      <p className="text-white font-medium capitalize">{channel.type}</p>
                      <p className="text-gray-500 text-sm">
                        {channel.enabled ? 'Configured' : 'Not configured'}
                      </p>
                    </div>
                  </div>
                  <button
                    onClick={() => {
                      const updated = { ...settings };
                      updated.notifications.channels[i].enabled = !channel.enabled;
                      setSettings(updated);
                    }}
                    className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                      channel.enabled ? 'bg-xdc-primary' : 'bg-xdc-border'
                    }`}
                  >
                    <span
                      className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                        channel.enabled ? 'translate-x-6' : 'translate-x-1'
                      }`}
                    />
                  </button>
                </div>
              ))}
            </div>
          </div>

          {/* Quiet Hours */}
          <div className="bg-xdc-card border border-xdc-border rounded-xl p-6">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-semibold text-white">Quiet Hours</h2>
              <button
                onClick={() => {
                  const updated = { ...settings };
                  updated.notifications.quietHours.enabled = !settings.notifications.quietHours.enabled;
                  setSettings(updated);
                }}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  settings.notifications.quietHours.enabled ? 'bg-xdc-primary' : 'bg-xdc-border'
                }`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    settings.notifications.quietHours.enabled ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm text-gray-400 mb-1">Start Time</label>
                <input
                  type="time"
                  value={settings.notifications.quietHours.start}
                  onChange={(e) => {
                    const updated = { ...settings };
                    updated.notifications.quietHours.start = e.target.value;
                    setSettings(updated);
                  }}
                  className="w-full bg-xdc-dark border border-xdc-border rounded-lg px-3 py-2 text-white"
                />
              </div>
              <div>
                <label className="block text-sm text-gray-400 mb-1">End Time</label>
                <input
                  type="time"
                  value={settings.notifications.quietHours.end}
                  onChange={(e) => {
                    const updated = { ...settings };
                    updated.notifications.quietHours.end = e.target.value;
                    setSettings(updated);
                  }}
                  className="w-full bg-xdc-dark border border-xdc-border rounded-lg px-3 py-2 text-white"
                />
              </div>
            </div>
          </div>

          {/* Alert Levels */}
          <div className="bg-xdc-card border border-xdc-border rounded-xl p-6">
            <h2 className="text-lg font-semibold text-white mb-4">Alert Levels</h2>
            <div className="space-y-3">
              {(['critical', 'warning', 'info'] as const).map((level) => (
                <div key={level} className="flex items-center justify-between p-3 bg-xdc-dark rounded-lg">
                  <span className="text-white capitalize">{level} alerts</span>
                  <button
                    onClick={() => {
                      const updated = { ...settings };
                      updated.notifications.levels[level] = !settings.notifications.levels[level];
                      setSettings(updated);
                    }}
                    className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                      settings.notifications.levels[level] ? 'bg-xdc-primary' : 'bg-xdc-border'
                    }`}
                  >
                    <span
                      className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                        settings.notifications.levels[level] ? 'translate-x-6' : 'translate-x-1'
                      }`}
                    />
                  </button>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Nodes Tab */}
      {activeTab === 'nodes' && (
        <div className="bg-xdc-card border border-xdc-border rounded-xl p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-semibold text-white">Registered Nodes</h2>
            <button className="px-4 py-2 bg-xdc-primary text-white rounded-lg hover:bg-xdc-secondary transition-colors text-sm">
              + Add Node
            </button>
          </div>
          
          {settings.nodes.length === 0 ? (
            <p className="text-gray-400 text-center py-8">No nodes registered. Add a node to get started.</p>
          ) : (
            <div className="space-y-3">
              {settings.nodes.map((node) => (
                <div key={node.id} className="flex items-center justify-between p-4 bg-xdc-dark rounded-lg">
                  <div>
                    <p className="text-white font-medium">{node.hostname}</p>
                    <p className="text-gray-500 text-sm">{node.ip}:{node.sshPort}</p>
                  </div>
                  <div className="flex items-center gap-3">
                    <button
                      onClick={() => {
                        const updated = { ...settings };
                        updated.nodes = settings.nodes.map(n =>
                          n.id === node.id ? { ...n, enabled: !n.enabled } : n
                        );
                        setSettings(updated);
                      }}
                      className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                        node.enabled ? 'bg-xdc-primary' : 'bg-xdc-border'
                      }`}
                    >
                      <span
                        className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                          node.enabled ? 'translate-x-6' : 'translate-x-1'
                        }`}
                      />
                    </button>
                    <button className="text-status-critical hover:underline text-sm">Remove</button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* API Keys Tab */}
      {activeTab === 'api' && (
        <div className="bg-xdc-card border border-xdc-border rounded-xl p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-semibold text-white">API Keys</h2>
            <button className="px-4 py-2 bg-xdc-primary text-white rounded-lg hover:bg-xdc-secondary transition-colors text-sm">
              + Generate Key
            </button>
          </div>
          <p className="text-gray-400 text-sm mb-4">
            API keys are required for write operations. Read operations are public.
          </p>
          
          {settings.apiKeys.length === 0 ? (
            <p className="text-gray-400 text-center py-8">No API keys generated.</p>
          ) : (
            <div className="space-y-3">
              {settings.apiKeys.map((key) => (
                <div key={key.id} className="flex items-center justify-between p-4 bg-xdc-dark rounded-lg">
                  <div>
                    <p className="text-white font-medium">{key.name}</p>
                    <p className="text-gray-500 text-sm font-mono">
                      {key.key.substring(0, 8)}...{key.key.substring(key.key.length - 4)}
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="text-gray-400 text-sm">Created: {new Date(key.createdAt).toLocaleDateString()}</p>
                    {key.lastUsed && (
                      <p className="text-gray-500 text-xs">Last used: {new Date(key.lastUsed).toLocaleDateString()}</p>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* General Tab */}
      {activeTab === 'general' && (
        <div className="space-y-6">
          <div className="bg-xdc-card border border-xdc-border rounded-xl p-6">
            <h2 className="text-lg font-semibold text-white mb-4">Appearance</h2>
            <div className="flex items-center justify-between p-3 bg-xdc-dark rounded-lg">
              <span className="text-white">Theme</span>
              <select
                value={settings.theme}
                onChange={(e) => setSettings({ ...settings, theme: e.target.value as 'dark' | 'light' })}
                className="bg-xdc-border border border-xdc-border rounded-lg px-3 py-2 text-white"
              >
                <option value="dark">Dark</option>
                <option value="light">Light</option>
              </select>
            </div>
          </div>

          <div className="bg-xdc-card border border-xdc-border rounded-xl p-6">
            <h2 className="text-lg font-semibold text-white mb-4">Export / Import</h2>
            <div className="flex gap-4">
              <button className="px-4 py-2 bg-xdc-border text-white rounded-lg hover:bg-xdc-primary transition-colors">
                📤 Export Config
              </button>
              <button className="px-4 py-2 bg-xdc-border text-white rounded-lg hover:bg-xdc-primary transition-colors">
                📥 Import Config
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
