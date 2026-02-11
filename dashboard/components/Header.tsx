'use client';

import { useState } from 'react';
import { RefreshCw, Users } from 'lucide-react';

interface HeaderProps {
  lastUpdated: string | null;
  connected: boolean;
  nextRefresh: number;
  refreshInterval?: number;
  blockHeight?: number;
  peers?: number;
  isSyncing?: boolean;
}

export default function Header({ 
  lastUpdated, 
  connected, 
  nextRefresh,
  refreshInterval = 10,
  blockHeight = 0,
  peers = 0,
  isSyncing = false,
}: HeaderProps) {
  const [isSpinning, setIsSpinning] = useState(false);

  const handleRefreshClick = () => {
    setIsSpinning(true);
    setTimeout(() => setIsSpinning(false), 1000);
    window.location.reload();
  };

  return (
    <header className="header-obsidian sticky top-0 z-50">
      <div className="max-w-[1440px] mx-auto flex items-center justify-between px-4 lg:px-6 py-3">
        {/* Left: Logo + Title */}
        <div className="flex items-center gap-3">
          {/* XDC Logo SVG */}
          <div className="w-10 h-10 rounded-full bg-gradient-to-br from-[#1E90FF]/20 to-[#10B981]/20 flex items-center justify-center border border-[#1E90FF]/20">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
              <circle cx="12" cy="12" r="10" stroke="#1E90FF" strokeWidth="2"/>
              <path d="M8 8L16 16M16 8L8 16" stroke="#1E90FF" strokeWidth="2" strokeLinecap="round"/>
            </svg>
          </div>
          <div>
            <h1 className="text-lg lg:text-xl font-semibold text-[#F9FAFB]" style={{ fontFamily: 'var(--font-fira-sans)' }}>
              Node Dashboard
            </h1>
            <div className="hidden sm:flex items-center gap-2 text-xs">
              <span className="text-[#6B7280]">Mainnet</span>
              <span className="text-[#1E90FF]">Chain ID: 50</span>
            </div>
          </div>
        </div>

        {/* Center: Live Status Pill */}
        <div className="hidden md:flex items-center gap-3 px-4 py-2 rounded-full bg-[#111827] border border-[rgba(255,255,255,0.06)]">
          <div className="flex items-center gap-2">
            <span className={`status-dot ${isSyncing ? 'syncing' : connected ? 'active' : 'inactive'}`} />
            <span className={`text-sm font-medium ${isSyncing ? 'text-[#F59E0B]' : connected ? 'text-[#10B981]' : 'text-[#EF4444]'}`}>
              {isSyncing ? 'Syncing' : connected ? 'Synced' : 'Disconnected'}
            </span>
          </div>
          {blockHeight > 0 && (
            <>
              <span className="text-[#6B7280]">|</span>
              <span className="text-sm font-mono-nums text-[#F9FAFB]">
                #{blockHeight.toLocaleString()}
              </span>
            </>
          )}
        </div>

        {/* Right: Auto-refresh + Peers */}
        <div className="flex items-center gap-4">
          {/* Auto-refresh indicator */}
          <div className="flex items-center gap-2">
            <button 
              onClick={handleRefreshClick}
              className="p-2 rounded-lg hover:bg-[rgba(30,144,255,0.1)] transition-colors"
              aria-label="Refresh"
            >
              <RefreshCw 
                className={`w-4 h-4 text-[#1E90FF] ${isSpinning ? 'animate-spin' : ''}`}
                style={{ animationDuration: isSpinning ? '1s' : '10s' }}
              />
            </button>
            <span className="hidden sm:block text-xs text-[#6B7280]">
              {nextRefresh}s
            </span>
          </div>

          {/* Peers badge */}
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-[#111827] border border-[rgba(255,255,255,0.06)]">
            <Users className="w-4 h-4 text-[#1E90FF]" />
            <span className="text-sm font-medium text-[#F9FAFB]">{peers || '—'}</span>
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
