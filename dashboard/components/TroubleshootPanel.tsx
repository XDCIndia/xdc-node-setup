'use client';

import { useState, useEffect, useCallback } from 'react';
import { 
  AlertTriangle, 
  AlertCircle,
  CheckCircle2,
  Terminal,
  Wrench,
  Activity,
  HardDrive,
  Cpu,
  Network,
  Settings,
  ChevronDown,
  ChevronUp,
  Play,
  RefreshCw,
} from 'lucide-react';

interface DiagnosticResult {
  name: string;
  category: string;
  status: 'pass' | 'warn' | 'fail';
  message: string;
  details?: string;
}

interface DiagnosticsData {
  results: DiagnosticResult[];
  summary: {
    pass: number;
    warn: number;
    fail: number;
  };
  timestamp: string;
}

const categoryIcons: Record<string, React.ComponentType<{ className?: string }>> = {
  infrastructure: HardDrive,
  node: Activity,
  network: Network,
  resources: Cpu,
  configuration: Settings,
};

const categoryLabels: Record<string, string> = {
  infrastructure: 'Infrastructure',
  node: 'Node Status',
  network: 'Network',
  resources: 'Resources',
  configuration: 'Configuration',
};

export default function TroubleshootPanel() {
  const [data, setData] = useState<DiagnosticsData | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expandedChecks, setExpandedChecks] = useState<Set<string>>(new Set());
  const [lastRun, setLastRun] = useState<Date | null>(null);

  const runDiagnostics = useCallback(async () => {
    setLoading(true);
    setError(null);
    
    try {
      const res = await fetch('/api/diagnostics', { cache: 'no-store' });
      
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      
      const diagData = await res.json();
      setData(diagData);
      setLastRun(new Date());
    } catch (err) {
      console.error('Failed to run diagnostics:', err);
      setError(err instanceof Error ? err.message : 'Failed to run diagnostics');
    } finally {
      setLoading(false);
    }
  }, []);

  // Run diagnostics on mount
  useEffect(() => {
    runDiagnostics();
  }, [runDiagnostics]);

  const toggleExpand = (name: string) => {
    setExpandedChecks(prev => {
      const next = new Set(prev);
      if (next.has(name)) {
        next.delete(name);
      } else {
        next.add(name);
      }
      return next;
    });
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'pass':
        return <CheckCircle2 className="w-5 h-5 text-green-500" />;
      case 'warn':
        return <AlertTriangle className="w-5 h-5 text-amber-500" />;
      case 'fail':
        return <AlertCircle className="w-5 h-5 text-red-500" />;
      default:
        return <Activity className="w-5 h-5 text-gray-500" />;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'pass':
        return 'bg-green-500/10 border-green-500/20 text-green-400';
      case 'warn':
        return 'bg-amber-500/10 border-amber-500/20 text-amber-400';
      case 'fail':
        return 'bg-red-500/10 border-red-500/20 text-red-400';
      default:
        return 'bg-gray-500/10 border-gray-500/20 text-gray-400';
    }
  };

  // Group results by category
  const groupedResults = data?.results.reduce((acc, result) => {
    if (!acc[result.category]) {
      acc[result.category] = [];
    }
    acc[result.category].push(result);
    return acc;
  }, {} as Record<string, DiagnosticResult[]>) || {};

  const overallStatus = data?.summary 
    ? data.summary.fail > 0 ? 'fail' : data.summary.warn > 0 ? 'warn' : 'pass'
    : null;

  return (
    <div className="card-xdc">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[var(--warning)]/20 to-[var(--critical)]/10 flex items-center justify-center">
            <Wrench className="w-5 h-5 text-[var(--warning)]" />
          </div>
          <div>
            <h2 className="text-lg font-semibold text-[var(--text-primary)]">Diagnostics</h2>
            <p className="text-sm text-[var(--text-tertiary)]">
              {lastRun 
                ? `Last run: ${lastRun.toLocaleTimeString()}` 
                : 'System health checks'}
            </p>
          </div>
        </div>

        <button
          onClick={runDiagnostics}
          disabled={loading}
          className="flex items-center gap-2 px-4 py-2 rounded-lg bg-[var(--bg-hover)] hover:bg-[var(--bg-card-hover)] text-[var(--text-primary)] text-sm transition-colors disabled:opacity-50"
        >
          {loading ? (
            <>
              <RefreshCw className="w-4 h-4 animate-spin" />
              Running...
            </>
          ) : (
            <>
              <Play className="w-4 h-4" />
              Run Diagnostics
            </>
          )}
        </button>
      </div>

      {/* Summary Cards */}
      {data?.summary && (
        <div className="grid grid-cols-3 gap-3 mb-6">
          <div className="p-3 rounded-lg bg-green-500/10 border border-green-500/20 text-center">
            <div className="text-2xl font-bold text-green-400">{data.summary.pass}</div>
            <div className="text-xs text-green-500/70">Passing</div>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/20 text-center">
            <div className="text-2xl font-bold text-amber-400">{data.summary.warn}</div>
            <div className="text-xs text-amber-500/70">Warnings</div>
          </div>
          <div className="p-3 rounded-lg bg-red-500/10 border border-red-500/20 text-center">
            <div className="text-2xl font-bold text-red-400">{data.summary.fail}</div>
            <div className="text-xs text-red-500/70">Failed</div>
          </div>
        </div>
      )}

      {/* Overall Status */}
      {overallStatus && (
        <div className={`p-4 rounded-lg mb-6 flex items-center gap-3 ${getStatusColor(overallStatus)}`}>
          {getStatusIcon(overallStatus)}
          <div>
            <div className="font-medium">
              {overallStatus === 'pass' ? 'All systems operational'
                : overallStatus === 'warn' ? 'Some issues detected'
                : 'Critical issues found'}
            </div>
            <div className="text-sm opacity-70">
              {data?.summary?.fail && data.summary.fail > 0 
                ? `${data?.summary?.fail ?? 0} check(s) failed` 
                : data?.summary?.warn && data.summary.warn > 0 
                ? `${data?.summary?.warn ?? 0} warning(s)` 
                : 'All checks passed'}
            </div>
          </div>
        </div>
      )}

      {/* Error State */}
      {error && (
        <div className="p-4 rounded-lg bg-red-500/10 border border-red-500/20 text-red-400 mb-4">
          <div className="flex items-center gap-2">
            <AlertCircle className="w-5 h-5" />
            <span>Failed to run diagnostics: {error}</span>
          </div>
        </div>
      )}

      {/* Results by Category */}
      <div className="space-y-4">
        {Object.entries(groupedResults).map(([category, results]) => {
          const Icon = categoryIcons[category] || Terminal;
          const hasIssues = results.some(r => r.status === 'fail' || r.status === 'warn');
          
          return (
            <div key={category} className="border border-[var(--border-subtle)] rounded-lg overflow-hidden">
              <div className={`flex items-center gap-2 px-4 py-3 bg-[var(--bg-hover)] ${hasIssues ? 'border-l-2 border-l-amber-500' : ''}`}>
                <Icon className="w-4 h-4 text-[var(--accent-blue)]" />
                <span className="font-medium text-[var(--text-primary)] capitalize">
                  {categoryLabels[category] || category}
                </span>
                <span className="text-xs text-[var(--text-tertiary)] ml-auto">
                  {results.filter(r => r.status === 'pass').length}/{results.length} passing
                </span>
              </div>
              
              <div className="divide-y divide-[var(--border-subtle)]">
                {results.map((result) => (
                  <div key={result.name} className="bg-[var(--bg-body)]">
                    <button
                      onClick={() => toggleExpand(result.name)}
                      className="w-full flex items-center justify-between px-4 py-3 hover:bg-[var(--bg-hover)] transition-colors"
                    >
                      <div className="flex items-center gap-3">
                        {getStatusIcon(result.status)}
                        <div className="text-left">
                          <div className="text-sm font-medium text-[var(--text-primary)]">
                            {result.name}
                          </div>
                          <div className="text-xs text-[var(--text-tertiary)]">
                            {result.message}
                          </div>
                        </div>
                      </div>
                      
                      {result.details && (
                        expandedChecks.has(result.name) ? (
                          <ChevronUp className="w-4 h-4 text-[var(--text-tertiary)]" />
                        ) : (
                          <ChevronDown className="w-4 h-4 text-[var(--text-tertiary)]" />
                        )
                      )}
                    </button>
                    
                    {expandedChecks.has(result.name) && result.details && (
                      <div className="px-4 pb-3">
                        <div className="p-3 rounded bg-[var(--bg-card)] text-xs text-[var(--text-secondary)] font-mono">
                          {result.details}
                        </div>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          );
        })}
      </div>

      {loading && !data && (
        <div className="text-center py-8 text-[var(--text-tertiary)]">
          Running diagnostics...
        </div>
      )}
    </div>
  );
}
