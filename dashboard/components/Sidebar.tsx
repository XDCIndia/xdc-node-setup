'use client';

import { useState, useEffect } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import {
  LayoutDashboard,
  Globe,
  Bell,
  ChevronLeft,
  ChevronRight,
  BarChart3,
  Menu,
  X,
  Users,
  Activity,
  Settings,
} from 'lucide-react';

interface NavItem {
  id: string;
  label: string;
  icon: React.ReactNode;
  path: string;
  section?: string;
}

const navItems: NavItem[] = [
  { id: 'dashboard', label: 'Dashboard', icon: <LayoutDashboard className="w-5 h-5" />, path: '/', section: 'Overview' },
  { id: 'network', label: 'Network', icon: <BarChart3 className="w-5 h-5" />, path: '/network', section: 'Monitoring' },
  { id: 'peers', label: 'Peers', icon: <Globe className="w-5 h-5" />, path: '/peers', section: 'Monitoring' },
  { id: 'alerts', label: 'Alerts', icon: <Bell className="w-5 h-5" />, path: '/alerts', section: 'Monitoring' },
];

interface NetworkStatus {
  blockHeight: number;
  online: boolean;
}

interface HeartbeatStatus {
  enabled: boolean;
  connected: boolean;
  lastHeartbeat: string | null;
  lastHeartbeatSeconds: number | null;
  statusText: string;
  nodeId: string | null;
}

function formatBlock(num: number): string {
  if (num >= 1e6) return (num / 1e6).toFixed(1) + 'M';
  if (num >= 1e3) return (num / 1e3).toFixed(1) + 'K';
  return num.toString();
}

function formatTimeAgoShort(ts: number): string {
  const diff = Math.floor((Date.now() - ts) / 1000);
  if (diff < 60) return `${diff}s ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  return `${Math.floor(diff / 3600)}h ago`;
}

export default function Sidebar() {
  const [collapsed, setCollapsed] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const pathname = usePathname();
  const router = useRouter();
  const [networkStatus, setNetworkStatus] = useState<NetworkStatus | null>(null);
  const [heartbeatStatus, setHeartbeatStatus] = useState<HeartbeatStatus | null>(null);
  const [lastFetched, setLastFetched] = useState<number>(0);
  const [, setTick] = useState(0);

  const fetchNetworkStatus = async () => {
    try {
      const res = await fetch('/api/metrics', { cache: 'no-store' });
      if (res.ok) {
        const data = await res.json();
        setNetworkStatus({ blockHeight: data.blockchain.blockHeight, online: true });
        setLastFetched(Date.now());
      }
    } catch {
      setNetworkStatus(prev => prev ? { ...prev, online: false } : null);
    }
  };

  const fetchHeartbeatStatus = async () => {
    try {
      const res = await fetch('/api/heartbeat', { cache: 'no-store' });
      if (res.ok) {
        const data = await res.json();
        setHeartbeatStatus({
          enabled: data.enabled,
          connected: data.connected,
          lastHeartbeat: data.lastHeartbeat,
          lastHeartbeatSeconds: data.lastHeartbeatSeconds,
          statusText: data.statusText,
          nodeId: data.nodeId,
        });
      }
    } catch {
      setHeartbeatStatus(null);
    }
  };

  useEffect(() => {
    fetchNetworkStatus();
    fetchHeartbeatStatus();
    const interval = setInterval(() => {
      fetchNetworkStatus();
      fetchHeartbeatStatus();
    }, 30000);
    return () => clearInterval(interval);
  }, []);

  // Tick every 10s to update "last updated" display
  useEffect(() => {
    const interval = setInterval(() => setTick(t => t + 1), 10000);
    return () => clearInterval(interval);
  }, []);

  // Close mobile menu on navigation
  useEffect(() => {
    setMobileOpen(false);
  }, [pathname]);

  // Close mobile menu on escape key
  useEffect(() => {
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setMobileOpen(false);
    };
    window.addEventListener('keydown', handleEscape);
    return () => window.removeEventListener('keydown', handleEscape);
  }, []);

  const sections = Array.from(new Set(navItems.map(i => i.section)));

  const handleNavClick = (path: string) => {
    router.push(path);
    setMobileOpen(false);
  };

  const SidebarContent = ({ isMobile = false }: { isMobile?: boolean }) => (
    <>
      {/* Logo */}
      <div className="flex items-center gap-3 px-4 py-5 border-b border-[var(--border-subtle)]">
        <div className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 overflow-hidden">
          <img src="https://s2.coinmarketcap.com/static/img/coins/200x200/2634.png" alt="XDC" width={36} height={36} className="rounded-lg" />
        </div>
        {(!collapsed || isMobile) && (
          <div className="overflow-hidden">
            <h1 className="text-sm font-bold text-[var(--text-primary)] whitespace-nowrap">XDC SkyOne</h1>
            <p className="text-[10px] text-[var(--text-tertiary)] whitespace-nowrap">Node Dashboard</p>
          </div>
        )}
        {isMobile && (
          <button
            onClick={() => setMobileOpen(false)}
            className="ml-auto p-2 hover:bg-[var(--bg-hover)] rounded-lg"
          >
            <X className="w-5 h-5 text-[var(--text-secondary)]" />
          </button>
        )}
      </div>

      {/* Network Status */}
      {(!collapsed || isMobile) && networkStatus && (
        <div className="px-4 py-3 border-b border-[var(--border-subtle)]">
          <div className="flex items-center gap-2 text-xs">
            <span className={`w-2 h-2 rounded-full ${networkStatus.online ? 'bg-[var(--success)]' : 'bg-[var(--critical)]'}`} />
            <span className="text-[var(--text-secondary)]">XDC Mainnet</span>
          </div>
          <div className="text-xs text-[var(--text-tertiary)] mt-1">
            Block #{formatBlock(networkStatus.blockHeight)}
            <span className="mx-1">•</span>
            <span className={networkStatus.online ? 'text-[var(--success)]' : 'text-[var(--critical)]'}>
              {networkStatus.online ? 'Online' : 'Offline'}
            </span>
          </div>
        </div>
      )}
      {!isMobile && collapsed && networkStatus && (
        <div className="flex justify-center py-2 border-b border-[var(--border-subtle)]">
          <span className={`w-2.5 h-2.5 rounded-full ${networkStatus.online ? 'bg-[var(--success)]' : 'bg-[var(--critical)]'}`} title={`Block #${networkStatus.blockHeight.toLocaleString()}`} />
        </div>
      )}

      {/* SkyNet Heartbeat Status */}
      {(!collapsed || isMobile) && heartbeatStatus?.enabled && (
        <div className="px-4 py-3 border-b border-[var(--border-subtle)]">
          <div className="flex items-center gap-2 text-xs">
            <span className={`w-2 h-2 rounded-full ${
              heartbeatStatus.statusText === 'connected' ? 'bg-[var(--success)] animate-pulse' :
              heartbeatStatus.statusText === 'pending' ? 'bg-yellow-500' :
              heartbeatStatus.statusText === 'offline' ? 'bg-[var(--critical)]' :
              heartbeatStatus.statusText === 'disabled' ? 'bg-gray-500' :
              'bg-orange-500'
            }`} />
            <span className="text-[var(--text-secondary)]">SkyNet {
              heartbeatStatus.statusText === 'connected' ? 'Connected' :
              heartbeatStatus.statusText === 'pending' ? 'Pending' :
              heartbeatStatus.statusText === 'offline' ? 'Offline' :
              heartbeatStatus.statusText === 'disabled' ? 'Disabled' :
              'Error'
            }</span>
          </div>
          {heartbeatStatus.lastHeartbeatSeconds !== null && (
            <div className="text-xs text-[var(--text-tertiary)] mt-1">
              Last heartbeat: {formatTimeAgoShort(Date.now() - (heartbeatStatus.lastHeartbeatSeconds * 1000))}
            </div>
          )}
        </div>
      )}
      {!isMobile && collapsed && heartbeatStatus?.enabled && (
        <div className="flex justify-center py-2 border-b border-[var(--border-subtle)]">
          <span className={`w-2.5 h-2.5 rounded-full ${
            heartbeatStatus.statusText === 'connected' ? 'bg-[var(--success)] animate-pulse' :
            heartbeatStatus.statusText === 'pending' ? 'bg-yellow-500' :
            heartbeatStatus.statusText === 'offline' ? 'bg-[var(--critical)]' :
            'bg-gray-500'
          }`} title={`SkyNet ${heartbeatStatus.statusText}`} />
        </div>
      )}

      {/* Navigation */}
      <nav className="flex-1 overflow-y-auto py-3 px-2">
        {sections.map(section => (
          <div key={section} className="mb-3">
            {(!collapsed || isMobile) && (
              <p className="px-3 mb-1.5 text-[10px] font-semibold uppercase tracking-wider text-[var(--text-muted)]">
                {section}
              </p>
            )}
            {navItems
              .filter(i => i.section === section)
              .map(item => {
                const isActive = pathname === item.path || 
                  (item.path !== '/' && pathname.startsWith(item.path));
                return (
                  <button
                    key={item.id}
                    onClick={() => handleNavClick(item.path)}
                    className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg mb-0.5 transition-all text-left ${
                      isActive
                        ? 'bg-[var(--bg-active)] text-[var(--accent-blue)] border border-[var(--accent-blue)]/20'
                        : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-hover)] border border-transparent'
                    }`}
                    title={collapsed && !isMobile ? item.label : undefined}
                  >
                    <span className="flex-shrink-0">{item.icon}</span>
                    {(!collapsed || isMobile) && (
                      <span className="text-sm font-medium truncate">{item.label}</span>
                    )}
                  </button>
                );
              })}
          </div>
        ))}
      </nav>

      {/* Last Updated */}
      {(!collapsed || isMobile) && lastFetched > 0 && (
        <div className="px-4 py-2 border-t border-[var(--border-subtle)]">
          <p className="text-[10px] text-[var(--text-tertiary)]">Last updated: {formatTimeAgoShort(lastFetched)}</p>
        </div>
      )}

      {/* Collapse Toggle (Desktop Only) */}
      {!isMobile && (
        <button
          onClick={() => setCollapsed(!collapsed)}
          className="flex items-center justify-center py-3 border-t border-[var(--border-subtle)] text-[var(--text-tertiary)] hover:text-[var(--text-primary)] transition-colors"
        >
          {collapsed ? <ChevronRight className="w-4 h-4" /> : <ChevronLeft className="w-4 h-4" />}
        </button>
      )}
    </>
  );

  return (
    <>
      {/* Mobile Header Bar */}
      <header className="lg:hidden fixed top-0 left-0 right-0 z-40 bg-[var(--bg-sidebar)]/95 backdrop-blur-xl border-b border-[var(--border-subtle)]">
        <div className="flex items-center justify-between px-4 py-3">
          <div className="flex items-center gap-3">
            <button
              onClick={() => setMobileOpen(true)}
              className="p-2 -ml-2 hover:bg-[var(--bg-hover)] rounded-lg"
              aria-label="Open menu"
            >
              <Menu className="w-6 h-6 text-[var(--text-secondary)]" />
            </button>
            <div className="flex items-center gap-2">
              <div className="w-7 h-7 rounded-lg flex items-center justify-center overflow-hidden">
                <img src="https://s2.coinmarketcap.com/static/img/coins/200x200/2634.png" alt="XDC" width={28} height={28} className="rounded-lg" />
              </div>
              <span className="text-sm font-bold text-[var(--text-primary)]">XDC SkyOne</span>
            </div>
          </div>
          
          {networkStatus && (
            <div className="flex items-center gap-2">
              <span className={`w-2 h-2 rounded-full ${networkStatus.online ? 'bg-[var(--success)]' : 'bg-[var(--critical)]'}`} />
              <span className="text-xs text-[var(--text-tertiary)]">#{formatBlock(networkStatus.blockHeight)}</span>
            </div>
          )}
        </div>
      </header>

      {/* Mobile Sidebar Overlay */}
      {mobileOpen && (
        <div 
          className="lg:hidden fixed inset-0 z-50 bg-black/50 backdrop-blur-sm"
          onClick={() => setMobileOpen(false)}
        />
      )}

      {/* Mobile Sidebar */}
      <aside
        className={`lg:hidden fixed left-0 top-0 h-screen z-50 w-[280px] bg-[var(--bg-sidebar)] border-r border-[var(--border-subtle)] transform transition-transform duration-300 ease-out ${
          mobileOpen ? 'translate-x-0' : '-translate-x-full'
        }`}
      >
        <div className="flex flex-col h-full">
          <SidebarContent isMobile />
        </div>
      </aside>

      {/* Desktop Sidebar */}
      <aside
        className={`hidden lg:flex flex-col fixed left-0 top-0 h-screen z-50 transition-all duration-300 ${
          collapsed ? 'w-[68px]' : 'w-[220px]'
        } bg-[var(--bg-sidebar)] border-r border-[var(--border-subtle)]`}
      >
        <SidebarContent />
      </aside>

      {/* Mobile Bottom Spacer (for fixed header) */}
      <div className="lg:hidden h-14" />
    </>
  );
}
