'use client';

import { useState } from 'react';
import { RefreshCw, Users, Sun, Moon } from 'lucide-react';
import { useTheme } from 'next-themes';

interface HeaderProps {
  lastUpdated: string | null;
  connected: boolean;
  nextRefresh: number;
  refreshInterval?: number;
  blockHeight?: number;
  peers?: number;
  isSyncing?: boolean;
  coinbase?: string;
  ethstatsName?: string;
}

export default function Header({ 
  lastUpdated, 
  connected, 
  nextRefresh,
  refreshInterval = 10,
  blockHeight = 0,
  peers = 0,
  isSyncing = false,
  coinbase = '',
  ethstatsName = '',
}: HeaderProps) {
  const [isSpinning, setIsSpinning] = useState(false);
  const { theme, setTheme } = useTheme();

  const handleRefreshClick = () => {
    setIsSpinning(true);
    setTimeout(() => setIsSpinning(false), 1000);
    window.location.reload();
  };

  const toggleTheme = () => {
    setTheme(theme === 'dark' ? 'light' : 'dark');
  };

  return (
    <header className="sticky top-0 z-50 bg-[var(--bg-body)]/85 backdrop-blur-[20px] border-b border-[var(--border-subtle)]">
      <div className="max-w-[1440px] mx-auto flex items-center justify-between px-4 lg:px-6 py-3">
        {/* Left: Logo + Title */}
        <div className="flex items-center gap-3">
          {/* XDC Logo SVG */}
          <div className="w-10 h-10 rounded-full bg-gradient-to-br from-[var(--accent-blue)]/20 to-[var(--success)]/20 flex items-center justify-center border border-[var(--accent-blue)]/20">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
              <circle cx="12" cy="12" r="10" stroke="var(--accent-blue)" strokeWidth="2"/>
              <path d="M8 8L16 16M16 8L8 16" stroke="var(--accent-blue)" strokeWidth="2" strokeLinecap="round"/>
            </svg>
          </div>
          <div>
            <h1 className="text-lg lg:text-xl font-semibold text-[var(--text-primary)]" style={{ fontFamily: 'var(--font-fira-sans)' }}>
              Node Dashboard
            </h1>
            <div className="hidden sm:flex items-center gap-2 text-xs flex-wrap">
              {ethstatsName && (
                <>
                  <span className="text-[var(--success)] font-medium">{ethstatsName}</span>
                  <span className="text-[var(--text-tertiary)]">·</span>
                </>
              )}
              <span className="text-[var(--text-tertiary)]">XDC Mainnet</span>
              {coinbase && (
                <>
                  <span className="text-[var(--text-tertiary)]">·</span>
                  <span className="text-[var(--text-secondary)] font-mono text-[10px]" title={coinbase}>
                    {coinbase.slice(0, 8)}...{coinbase.slice(-6)}
                  </span>
                </>
              )}
            </div>
          </div>
        </div>

        {/* Center: Live Status Pill */}
        <div className="hidden md:flex items-center gap-3 px-4 py-2 rounded-full bg-[var(--bg-card)] border border-[var(--border-subtle)]">
          <div className="flex items-center gap-2">
            <span className={`status-dot ${isSyncing ? 'syncing' : connected ? 'active' : 'inactive'}`} />
            <span className={`text-sm font-medium ${isSyncing ? 'text-[var(--warning)]' : connected ? 'text-[var(--success)]' : 'text-[var(--critical)]'}`}>
              {isSyncing ? 'Syncing' : connected ? 'Synced' : 'Disconnected'}
            </span>
          </div>
          {blockHeight > 0 && (
            <>
              <span className="text-[var(--text-tertiary)]">|</span>
              <span className="text-sm font-mono-nums text-[var(--text-primary)]">
                #{blockHeight.toLocaleString()}
              </span>
            </>
          )}
        </div>

        {/* Right: Auto-refresh + Peers + Theme Toggle */}
        <div className="flex items-center gap-4">
          {/* Theme Toggle */}
          <button 
            onClick={toggleTheme}
            className="p-2 rounded-lg hover:bg-[var(--bg-hover)] transition-colors"
            aria-label={theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode'}
            title={theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode'}
          >
            {theme === 'dark' ? (
              <Sun className="w-4 h-4 text-[var(--accent-blue)]" />
            ) : (
              <Moon className="w-4 h-4 text-[var(--accent-blue)]" />
            )}
          </button>

          {/* Auto-refresh indicator */}
          <div className="flex items-center gap-2">
            <button 
              onClick={handleRefreshClick}
              className="p-2 rounded-lg hover:bg-[var(--bg-hover)] transition-colors"
              aria-label="Refresh"
            >
              <RefreshCw 
                className={`w-4 h-4 text-[var(--accent-blue)] ${isSpinning ? 'animate-spin' : ''}`}
                style={{ animationDuration: isSpinning ? '1s' : '10s' }}
              />
            </button>
            <span className="hidden sm:block text-xs text-[var(--text-tertiary)]">
              {nextRefresh}s
            </span>
          </div>

          {/* Peers badge */}
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-[var(--bg-card)] border border-[var(--border-subtle)]">
            <Users className="w-4 h-4 text-[var(--accent-blue)]" />
            <span className="text-sm font-medium text-[var(--text-primary)]">{peers || '—'}</span>
          </div>

          {/* Mobile status dot */}
          <div className="md:hidden">
            <span className={`status-dot ${isSyncing ? 'syncing' : connected ? 'active' : 'inactive'}`} />
          </div>
        </div>
      </div>
    </header>
  );
}
