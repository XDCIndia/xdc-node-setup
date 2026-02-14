'use client';

import { useState, useEffect } from 'react';
import { Zap, X, Users, Settings } from 'lucide-react';

interface LFGResult {
  triggered: boolean;
  added: number;
  failed: number;
  enodesFetched?: number;
}

interface LFGConfig {
  minPeers: number;
  skyNetUrl: string;
}

export function LFGBadge() {
  const [lfgResult, setLfgResult] = useState<LFGResult | null>(null);
  const [lfgConfig, setLfgConfig] = useState<LFGConfig | null>(null);
  const [showDetails, setShowDetails] = useState(false);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    // Fetch LFG config on mount
    fetch('/api/lfg/config', { cache: 'no-store' })
      .then(res => res.ok ? res.json() : null)
      .then(data => {
        if (data) setLfgConfig(data);
      })
      .catch(() => {});

    // Check for LFG results in metrics endpoint
    const checkLFG = async () => {
      try {
        const res = await fetch('/api/metrics', { cache: 'no-store' });
        if (res.ok) {
          const data = await res.json();
          if (data.lfg?.triggered) {
            setLfgResult(data.lfg);
            setDismissed(false);
          }
        }
      } catch {}
    };

    // Check immediately and then every 30 seconds
    checkLFG();
    const interval = setInterval(checkLFG, 30000);
    return () => clearInterval(interval);
  }, []);

  // Auto-dismiss after 60 seconds
  useEffect(() => {
    if (lfgResult?.triggered) {
      const timeout = setTimeout(() => {
        setDismissed(true);
      }, 60000);
      return () => clearTimeout(timeout);
    }
  }, [lfgResult]);

  if (!lfgResult?.triggered || dismissed) return null;

  return (
    <div className="animate-fade-in">
      <div className="relative overflow-hidden rounded-xl border border-[#10B981]/30 bg-gradient-to-r from-[#10B981]/10 to-[#1E90FF]/10 p-4">
        {/* Animated background effect */}
        <div className="absolute inset-0 bg-gradient-to-r from-[#10B981]/5 via-[#1E90FF]/5 to-[#10B981]/5 animate-pulse" />
        
        <div className="relative flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="flex items-center justify-center w-10 h-10 rounded-xl bg-[#10B981]/20 border border-[#10B981]/30">
              <Zap className="w-5 h-5 text-[#10B981]" />
            </div>
            
            <div>
              <div className="flex items-center gap-2">
                <span className="font-semibold text-[#F9FAFB]">LFG Active</span>
                <span className="px-2 py-0.5 rounded-full bg-[#10B981]/20 text-[#10B981] text-xs font-medium">
                  +{lfgResult.added} peers
                </span>
              </div>
              <p className="text-sm text-[#9CA3AF]">
                Live Fleet Gateway auto-added peers from SkyNet
              </p>
            </div>
          </div>
          
          <div className="flex items-center gap-2">
            <button
              onClick={() => setShowDetails(!showDetails)}
              className="p-2 rounded-lg hover:bg-white/5 transition-colors text-[#6B7280] hover:text-[#F9FAFB]"
              title="Toggle details"
            >
              <Settings className="w-4 h-4" />
            </button>
            <button
              onClick={() => setDismissed(true)}
              className="p-2 rounded-lg hover:bg-white/5 transition-colors text-[#6B7280] hover:text-[#F9FAFB]"
              title="Dismiss"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        </div>
        
        {/* Expanded details */}
        {showDetails && (
          <div className="relative mt-4 pt-4 border-t border-white/10 animate-fade-in">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div className="bg-white/5 rounded-lg p-3">
                <div className="text-xs text-[#6B7280] mb-1">Peers Added</div>
                <div className="text-lg font-semibold text-[#10B981]">{lfgResult.added}</div>
              </div>
              
              <div className="bg-white/5 rounded-lg p-3">
                <div className="text-xs text-[#6B7280] mb-1">Failed</div>
                <div className={`text-lg font-semibold ${lfgResult.failed > 0 ? 'text-[#EF4444]' : 'text-[#10B981]'}`}>
                  {lfgResult.failed}
                </div>
              </div>
              
              <div className="bg-white/5 rounded-lg p-3">
                <div className="text-xs text-[#6B7280] mb-1">Available from SkyNet</div>
                <div className="text-lg font-semibold text-[#1E90FF]">{lfgResult.enodesFetched || '—'}</div>
              </div>
              
              <div className="bg-white/5 rounded-lg p-3">
                <div className="text-xs text-[#6B7280] mb-1">Min Peers Threshold</div>
                <div className="text-lg font-semibold text-[#F9FAFB]">{lfgConfig?.minPeers || '5'}</div>
              </div>
            </div>
            
            <div className="mt-3 text-xs text-[#6B7280]">
              <span className="inline-flex items-center gap-1">
                <Users className="w-3 h-3" />
                SkyNet Source: {lfgConfig?.skyNetUrl || 'https://net.xdc.network/api/v1'}
              </span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
