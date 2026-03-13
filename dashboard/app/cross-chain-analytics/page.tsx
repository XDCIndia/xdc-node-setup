'use client';

import { useEffect, useState, useCallback, useMemo } from 'react';
import DashboardLayout from '@/components/DashboardLayout';
import { 
  TrendingUp, 
  Activity, 
  Users, 
  Clock, 
  BarChart3, 
  Download, 
  Share2, 
  Filter,
  ChevronDown,
  Layers,
  Zap,
  DollarSign,
  ArrowUpRight,
  ArrowDownRight,
  Globe,
  Target
} from 'lucide-react';

// Types
interface ChainData {
  id: string;
  name: string;
  symbol: string;
  tvl: number;
  tvlChange24h: number;
  revenue24h: number;
  revenue7d: number;
  revenue30d: number;
  revenueChange24h: number;
  volume24h: number;
  volume7d: number;
  volume30d: number;
  volumeChange24h: number;
  transactions24h: number;
  transactions7d: number;
  transactions30d: number;
  avgConfirmationTime: number;
  activeUsers24h: number;
  activeUsers7d: number;
  activeUsers30d: number;
  marketCap: number;
  price: number;
  priceChange24h: number;
  fdv: number;
  psRatio: number;
  metrics: {
    gasFeeAverage: number;
    throughput: number;
    decentralizationScore: number;
  };
  rankings: {
    byRevenue: number;
    byTvl: number;
    byVolume: number;
    byUsers: number;
    bySpeed: number;
    byPsRatio: number;
    byActivity: number;
  };
  timeSeries: {
    dailyRevenue: { date: string; value: number }[];
    dailyTvl: { date: string; value: number }[];
    dailyUsers: { date: string; value: number }[];
    dailyVolume: { date: string; open: number; high: number; low: number; close: number }[];
  };
}

interface AggregateData {
  totalVolume: number;
  totalTransactions: number;
  totalRevenue: number;
  activeChainsCount: number;
  avgConfirmationTime: number;
}

type TimeRange = '24h' | '7d' | '30d' | '90d' | '1y';
type MetricType = 'all' | 'tvl' | 'revenue' | 'volume' | 'users' | 'transactions';
type RankingType = 'byRevenue' | 'bySpeed' | 'byUsers' | 'byPsRatio' | 'byTvl';

// Utility functions
const formatCurrency = (value: number, compact: boolean = true): string => {
  if (compact) {
    if (value >= 1e12) return `$${(value / 1e12).toFixed(2)}T`;
    if (value >= 1e9) return `$${(value / 1e9).toFixed(2)}B`;
    if (value >= 1e6) return `$${(value / 1e6).toFixed(2)}M`;
    if (value >= 1e3) return `$${(value / 1e3).toFixed(2)}K`;
    return `$${value.toFixed(2)}`;
  }
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);
};

const formatNumber = (value: number, compact: boolean = true): string => {
  if (compact) {
    if (value >= 1e9) return `${(value / 1e9).toFixed(2)}B`;
    if (value >= 1e6) return `${(value / 1e6).toFixed(2)}M`;
    if (value >= 1e3) return `${(value / 1e3).toFixed(2)}K`;
    return value.toString();
  }
  return new Intl.NumberFormat('en-US').format(value);
};

const formatPercentage = (value: number): string => {
  const sign = value >= 0 ? '+' : '';
  return `${sign}${value.toFixed(2)}%`;
};

// Loading Skeleton
function Skeleton({ className }: { className?: string }) {
  return <div className={`animate-pulse bg-[var(--bg-hover)] rounded ${className || ''}`} />;
}

// Stat Card Component
interface StatCardProps {
  title: string;
  value: string;
  change?: number;
  icon: React.ReactNode;
  subtitle?: string;
}

function StatCard({ title, value, change, icon, subtitle }: StatCardProps) {
  return (
    <div className="card-xdc p-5">
      <div className="flex items-start justify-between mb-4">
        <div className="w-12 h-12 rounded-xl bg-[var(--accent-blue)]/10 flex items-center justify-center">
          {icon}
        </div>
        {change !== undefined && (
          <div className={`flex items-center gap-1 text-sm font-medium ${
            change >= 0 ? 'text-[var(--success)]' : 'text-[var(--critical)]'
          }`}>
            {change >= 0 ? <ArrowUpRight className="w-4 h-4" /> : <ArrowDownRight className="w-4 h-4" />}
            {formatPercentage(change)}
          </div>
        )}
      </div>
      <div className="text-sm text-[var(--text-secondary)] mb-1">{title}</div>
      <div className="text-2xl font-bold text-[var(--text-primary)]">{value}</div>
      {subtitle && (
        <div className="text-xs text-[var(--text-tertiary)] mt-2">{subtitle}</div>
      )}
    </div>
  );
}

// Chart Components using SVG
function LineChart({ 
  data, 
  color = '#1E90FF', 
  height = 200,
  labels = [] 
}: { 
  data: number[]; 
  color?: string; 
  height?: number;
  labels?: string[];
}) {
  if (!data || data.length === 0) return null;

  const padding = { top: 10, right: 10, bottom: 30, left: 50 };
  const width = 600;
  const chartWidth = width - padding.left - padding.right;
  const chartHeight = height - padding.top - padding.bottom;

  const min = Math.min(...data);
  const max = Math.max(...data);
  const range = max - min || 1;

  const points = data.map((value, index) => ({
    x: padding.left + (index / (data.length - 1)) * chartWidth,
    y: padding.top + chartHeight - ((value - min) / range) * chartHeight,
  }));

  const linePath = points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x.toFixed(2)},${p.y.toFixed(2)}`).join(' ');
  const gradientId = `gradient-${Math.random().toString(36).substr(2, 9)}`;

  return (
    <svg viewBox={`0 0 ${width} ${height}`} className="w-full h-full" preserveAspectRatio="none">
      <defs>
        <linearGradient id={gradientId} x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stopColor={color} stopOpacity="0.3" />
          <stop offset="100%" stopColor={color} stopOpacity="0.05" />
        </linearGradient>
      </defs>
      
      {/* Grid lines */}
        {[0, 0.5, 1].map((fraction) => {
          const y = padding.top + chartHeight * (1 - fraction);
          return (
            <line
              key={fraction}
              x1={padding.left}
              y1={y}
              x2={padding.left + chartWidth}
              y2={y}
              stroke="var(--border-subtle)"
              strokeWidth={1}
              strokeDasharray="4,4"
            />
          );
        })}

      {/* Area */}
      <path
        d={`${linePath} L ${points[points.length - 1].x},${padding.top + chartHeight} L ${padding.left},${padding.top + chartHeight} Z`}
        fill={`url(#${gradientId})`}
      />

      {/* Line */}
      <path
        d={linePath}
        fill="none"
        stroke={color}
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
      />

      {/* Y-axis labels */}
      {[0, 0.5, 1].map((fraction) => {
        const y = padding.top + chartHeight * (1 - fraction);
        const value = min + range * fraction;
        return (
          <text
            key={fraction}
            x={padding.left - 10}
            y={y}
            textAnchor="end"
            alignmentBaseline="middle"
            fill="var(--text-tertiary)"
            fontSize="10"
          >
            {formatCurrency(value)}
          </text>
        );
      })}

      {/* X-axis labels */}
      {labels.length > 0 && points.map((point, index) => {
        if (index % Math.ceil(labels.length / 5) !== 0 && index !== labels.length - 1) return null;
        return (
          <text
            key={index}
            x={point.x}
            y={padding.top + chartHeight + 20}
            textAnchor="middle"
            fill="var(--text-tertiary)"
            fontSize="10"
          >
            {labels[index]}
          </text>
        );
      })}
    </svg>
  );
}

function BarChart({ 
  data, 
  color = '#1E90FF', 
  height = 200 
}: { 
  data: number[]; 
  color?: string; 
  height?: number;
}) {
  if (!data || data.length === 0) return null;

  const padding = { top: 10, right: 10, bottom: 30, left: 50 };
  const width = 600;
  const chartWidth = width - padding.left - padding.right;
  const chartHeight = height - padding.top - padding.bottom;

  const max = Math.max(...data);
  const barWidth = (chartWidth / data.length) * 0.7;
  const gap = (chartWidth / data.length) * 0.3;

  return (
    <svg viewBox={`0 0 ${width} ${height}`} className="w-full h-full" preserveAspectRatio="none">
      {/* Grid lines */}
      {[0, 0.5, 1].map((fraction) => {
        const y = padding.top + chartHeight * (1 - fraction);
        return (
          <line
            key={fraction}
            x1={padding.left}
            y1={y}
            x2={padding.left + chartWidth}
            y2={y}
            stroke="var(--border-subtle)"
            strokeWidth={1}
            strokeDasharray="4,4"
          />
        );
      })}

      {/* Bars */}
      {data.map((value, index) => {
        const barHeight = (value / max) * chartHeight;
        const x = padding.left + index * (barWidth + gap) + gap / 2;
        const y = padding.top + chartHeight - barHeight;

        return (
          <rect
            key={index}
            x={x}
            y={y}
            width={barWidth}
            height={barHeight}
            fill={color}
            rx={2}
            opacity={0.8}
          />
        );
      })}

      {/* Y-axis labels */}
      {[0, 0.5, 1].map((fraction) => {
        const y = padding.top + chartHeight * (1 - fraction);
        const value = max * fraction;
        return (
          <text
            key={fraction}
            x={padding.left - 10}
            y={y}
            textAnchor="end"
            alignmentBaseline="middle"
            fill="var(--text-tertiary)"
            fontSize="10"
          >
            {formatNumber(value)}
          </text>
        );
      })}
    </svg>
  );
}

function CandlestickChart({ 
  data, 
  height = 200 
}: { 
  data: { date: string; open: number; high: number; low: number; close: number }[]; 
  height?: number;
}) {
  if (!data || data.length === 0) return null;

  const padding = { top: 10, right: 10, bottom: 30, left: 60 };
  const width = 600;
  const chartWidth = width - padding.left - padding.right;
  const chartHeight = height - padding.top - padding.bottom;

  const allValues = data.flatMap(d => [d.high, d.low]);
  const min = Math.min(...allValues);
  const max = Math.max(...allValues);
  const range = max - min || 1;

  const candleWidth = (chartWidth / data.length) * 0.6;

  return (
    <svg viewBox={`0 0 ${width} ${height}`} className="w-full h-full" preserveAspectRatio="none">
      {/* Grid lines */}
      {[0, 0.5, 1].map((fraction) => {
        const y = padding.top + chartHeight * (1 - fraction);
        return (
          <line
            key={fraction}
            x1={padding.left}
            y1={y}
            x2={padding.left + chartWidth}
            y2={y}
            stroke="var(--border-subtle)"
            strokeWidth={1}
            strokeDasharray="4,4"
          />
        );
      })}

      {/* Candles */}
      {data.map((candle, index) => {
        const x = padding.left + (index / (data.length - 1)) * chartWidth;
        const isGreen = candle.close >= candle.open;
        const color = isGreen ? 'var(--success)' : 'var(--critical)';
        
        const highY = padding.top + chartHeight - ((candle.high - min) / range) * chartHeight;
        const lowY = padding.top + chartHeight - ((candle.low - min) / range) * chartHeight;
        const openY = padding.top + chartHeight - ((candle.open - min) / range) * chartHeight;
        const closeY = padding.top + chartHeight - ((candle.close - min) / range) * chartHeight;

        const bodyTop = Math.min(openY, closeY);
        const bodyBottom = Math.max(openY, closeY);
        const bodyHeight = Math.max(bodyBottom - bodyTop, 1);

        return (
          <g key={index}>
            {/* Wick */}
            <line
              x1={x}
              y1={highY}
              x2={x}
              y2={lowY}
              stroke={color}
              strokeWidth={1}
            />
            {/* Body */}
            <rect
              x={x - candleWidth / 2}
              y={bodyTop}
              width={candleWidth}
              height={bodyHeight}
              fill={color}
              rx={1}
            />
          </g>
        );
      })}

      {/* Y-axis labels */}
      {[0, 0.5, 1].map((fraction) => {
        const y = padding.top + chartHeight * (1 - fraction);
        const value = min + range * fraction;
        return (
          <text
            key={fraction}
            x={padding.left - 10}
            y={y}
            textAnchor="end"
            alignmentBaseline="middle"
            fill="var(--text-tertiary)"
            fontSize="10"
          >
            {formatCurrency(value)}
          </text>
        );
      })}
    </svg>
  );
}

// Heatmap Component
function Heatmap({ data }: { data: ChainData[] }) {
  const metrics = ['revenue', 'tvl', 'volume', 'users', 'transactions'];
  
  const getValue = (chain: ChainData, metric: string): number => {
    switch (metric) {
      case 'revenue': return chain.revenue24h;
      case 'tvl': return chain.tvl;
      case 'volume': return chain.volume24h;
      case 'users': return chain.activeUsers24h;
      case 'transactions': return chain.transactions24h;
      default: return 0;
    }
  };

  const getMaxValue = (metric: string): number => {
    return Math.max(...data.map(c => getValue(c, metric)));
  };

  const getIntensity = (value: number, max: number): string => {
    const intensity = value / max;
    if (intensity > 0.8) return 'bg-[var(--accent-blue)]';
    if (intensity > 0.6) return 'bg-[var(--accent-blue)]/70';
    if (intensity > 0.4) return 'bg-[var(--accent-blue)]/50';
    if (intensity > 0.2) return 'bg-[var(--accent-blue)]/30';
    return 'bg-[var(--accent-blue)]/10';
  };

  return (
    <div className="overflow-x-auto">
      <table className="w-full">
        <thead>
          <tr>
            <th className="text-left p-3 text-xs font-medium text-[var(--text-tertiary)] uppercase">Chain</th>
            {metrics.map(m => (
              <th key={m} className="text-center p-3 text-xs font-medium text-[var(--text-tertiary)] uppercase">
                {m}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {data.map(chain => (
            <tr key={chain.id} className="border-t border-[var(--border-subtle)]">
              <td className="p-3">
                <div className="flex items-center gap-2">
                  <div className="w-6 h-6 rounded-full bg-[var(--accent-blue)]/20 flex items-center justify-center text-xs font-bold">
                    {chain.symbol[0]}
                  </div>
                  <span className="text-sm font-medium text-[var(--text-primary)]">{chain.name}</span>
                </div>
              </td>
              {metrics.map(metric => {
                const value = getValue(chain, metric);
                const max = getMaxValue(metric);
                return (
                  <td key={metric} className="p-2">
                    <div className={`h-8 rounded ${getIntensity(value, max)} flex items-center justify-center`}>
                      <span className="text-xs font-medium text-[var(--text-primary)]">
                        {metric === 'revenue' || metric === 'tvl' || metric === 'volume' 
                          ? formatCurrency(value)
                          : formatNumber(value)}
                      </span>
                    </div>
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// Ranking Table Component
function RankingTable({ 
  data, 
  type 
}: { 
  data: ChainData[]; 
  type: RankingType;
}) {
  const getRankValue = (chain: ChainData): number => chain.rankings[type];
  
  const getTitle = (): string => {
    switch (type) {
      case 'byRevenue': return 'Top Chains by Revenue';
      case 'bySpeed': return 'Fastest Chains by Latency';
      case 'byUsers': return 'Most Active Chains by Users';
      case 'byPsRatio': return 'Best Value Chains by P/S Ratio';
      case 'byTvl': return 'Top Chains by TVL';
      default: return 'Chain Rankings';
    }
  };

  const getValue = (chain: ChainData): string => {
    switch (type) {
      case 'byRevenue': return formatCurrency(chain.revenue24h);
      case 'bySpeed': return `${chain.avgConfirmationTime}s`;
      case 'byUsers': return formatNumber(chain.activeUsers24h);
      case 'byPsRatio': return chain.psRatio.toFixed(2);
      case 'byTvl': return formatCurrency(chain.tvl);
      default: return '';
    }
  };

  const sortedData = [...data].sort((a, b) => {
    if (type === 'bySpeed') return a.avgConfirmationTime - b.avgConfirmationTime;
    if (type === 'byPsRatio') return a.psRatio - b.psRatio;
    return getRankValue(a) - getRankValue(b);
  }).slice(0, 5);

  return (
    <div className="card-xdc p-5">
      <h3 className="text-lg font-semibold text-[var(--text-primary)] mb-4">{getTitle()}</h3>
      <div className="space-y-3">
        {sortedData.map((chain, index) => (
          <div key={chain.id} className="flex items-center justify-between p-3 bg-[var(--bg-body)] rounded-lg">
            <div className="flex items-center gap-3">
              <div className={`w-7 h-7 rounded-full flex items-center justify-center text-sm font-bold ${
                index === 0 ? 'bg-yellow-500/20 text-yellow-500' :
                index === 1 ? 'bg-gray-400/20 text-gray-400' :
                index === 2 ? 'bg-orange-600/20 text-orange-600' :
                'bg-[var(--bg-hover)] text-[var(--text-secondary)]'
              }`}>
                {index + 1}
              </div>
              <div className="w-8 h-8 rounded-full bg-[var(--accent-blue)]/20 flex items-center justify-center text-xs font-bold">
                {chain.symbol[0]}
              </div>
              <div>
                <div className="text-sm font-medium text-[var(--text-primary)]">{chain.name}</div>
                <div className="text-xs text-[var(--text-tertiary)]">{chain.symbol}</div>
              </div>
            </div>
            <div className="text-right">
              <div className="text-sm font-semibold text-[var(--text-primary)]">{getValue(chain)}</div>
              {type !== 'byPsRatio' && type !== 'bySpeed' && (
                <div className={`text-xs ${
                  (chain.priceChange24h || 0) >= 0 ? 'text-[var(--success)]' : 'text-[var(--critical)]'
                }`}>
                  {formatPercentage(chain.priceChange24h || 0)}
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// Main Page Component
export default function CrossChainAnalytics() {
  const [chains, setChains] = useState<ChainData[]>([]);
  const [aggregates, setAggregates] = useState<AggregateData | null>(null);
  const [loading, setLoading] = useState(true);
  const [timeRange, setTimeRange] = useState<TimeRange>('24h');
  const [selectedChains, setSelectedChains] = useState<string[]>([]);
  const [metricType, setMetricType] = useState<MetricType>('all');
  const [showChainDropdown, setShowChainDropdown] = useState(false);

  const timeRanges: TimeRange[] = ['24h', '7d', '30d', '90d', '1y'];

  const fetchData = useCallback(async () => {
    try {
      setLoading(true);
      
      const chainParam = selectedChains.length > 0 ? `&chains=${selectedChains.join(',')}` : '';
      
      const [financialRes, comparisonRes] = await Promise.all([
        fetch(`/api/chains/financial?timeRange=${timeRange}${chainParam}`, { cache: 'no-store' }),
        fetch(`/api/chains/comparison?sortBy=byRevenue&limit=20${chainParam}`, { cache: 'no-store' }),
      ]);

      if (financialRes.ok) {
        const financialData = await financialRes.json();
        setAggregates(financialData.aggregates);
      }

      if (comparisonRes.ok) {
        const comparisonData = await comparisonRes.json();
        setChains(comparisonData.chains);
      }
    } catch (error) {
      console.error('Error fetching cross-chain data:', error);
    } finally {
      setLoading(false);
    }
  }, [timeRange, selectedChains]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  const toggleChain = (chainId: string) => {
    setSelectedChains(prev => 
      prev.includes(chainId) 
        ? prev.filter(id => id !== chainId)
        : [...prev, chainId]
    );
  };

  // Export functions
  const exportToCSV = () => {
    const headers = ['Chain', 'TVL', 'Revenue 24h', 'Volume 24h', 'Transactions 24h', 'Active Users 24h', 'Avg Confirmation Time'];
    const rows = chains.map(c => [
      c.name,
      c.tvl,
      c.revenue24h,
      c.volume24h,
      c.transactions24h,
      c.activeUsers24h,
      c.avgConfirmationTime
    ]);
    
    const csv = [headers.join(','), ...rows.map(r => r.join(','))].join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `cross-chain-analytics-${timeRange}-${new Date().toISOString().split('T')[0]}.csv`;
    a.click();
  };

  const generateShareLink = () => {
    const params = new URLSearchParams();
    params.set('timeRange', timeRange);
    if (selectedChains.length > 0) params.set('chains', selectedChains.join(','));
    params.set('metric', metricType);
    
    const url = `${window.location.origin}/cross-chain-analytics?${params.toString()}`;
    navigator.clipboard.writeText(url);
    alert('Share link copied to clipboard!');
  };

  // Filter data based on metric type
  const filteredChains = useMemo(() => {
    if (metricType === 'all') return chains;
    return chains.filter(c => {
      switch (metricType) {
        case 'tvl': return c.tvl > 0;
        case 'revenue': return c.revenue24h > 0;
        case 'volume': return c.volume24h > 0;
        case 'users': return c.activeUsers24h > 0;
        case 'transactions': return c.transactions24h > 0;
        default: return true;
      }
    });
  }, [chains, metricType]);

  // Chart data preparation
  const revenueChartData = useMemo(() => {
    const firstChain = filteredChains[0];
    if (!firstChain?.timeSeries?.dailyRevenue) return [];
    return firstChain.timeSeries.dailyRevenue.map(d => d.value);
  }, [filteredChains]);

  const revenueChartLabels = useMemo(() => {
    const firstChain = filteredChains[0];
    if (!firstChain?.timeSeries?.dailyRevenue) return [];
    return firstChain.timeSeries.dailyRevenue.map(d => d.date.slice(5));
  }, [filteredChains]);

  const tvlChartData = useMemo(() => {
    const firstChain = filteredChains[0];
    if (!firstChain?.timeSeries?.dailyTvl) return [];
    return firstChain.timeSeries.dailyTvl.map(d => d.value);
  }, [filteredChains]);

  const usersChartData = useMemo(() => {
    const firstChain = filteredChains[0];
    if (!firstChain?.timeSeries?.dailyUsers) return [];
    return firstChain.timeSeries.dailyUsers.map(d => d.value);
  }, [filteredChains]);

  const volumeChartData = useMemo(() => {
    const firstChain = filteredChains[0];
    if (!firstChain?.timeSeries?.dailyVolume) return [];
    return firstChain.timeSeries.dailyVolume;
  }, [filteredChains]);

  if (loading) {
    return (
      <DashboardLayout>
        <div className="space-y-6">
          <div className="flex items-center justify-between">
            <Skeleton className="w-64 h-10" />
            <div className="flex gap-3">
              <Skeleton className="w-32 h-10" />
              <Skeleton className="w-32 h-10" />
            </div>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            {[1, 2, 3, 4].map(i => (
              <Skeleton key={i} className="h-32" />
            ))}
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <Skeleton className="h-64" />
            <Skeleton className="h-64" />
          </div>
        </div>
      </DashboardLayout>
    );
  }

  return (
    <DashboardLayout>
      <div className="space-y-6">
        {/* Header */}
        <div className="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
          <div>
            <h1 className="text-2xl font-bold text-[var(--text-primary)]">Cross-Chain Analytics</h1>
            <p className="text-sm text-[var(--text-secondary)] mt-1">
              Compare and analyze metrics across multiple blockchain networks
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            {/* Time Range Selector */}
            <div className="flex items-center bg-[var(--bg-card)] rounded-lg border border-[var(--border-subtle)] p-1">
              {timeRanges.map(range => (
                <button
                  key={range}
                  onClick={() => setTimeRange(range)}
                  className={`px-3 py-1.5 text-sm font-medium rounded-md transition-all ${
                    timeRange === range
                      ? 'bg-[var(--accent-blue)] text-white'
                      : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)]'
                  }`}
                >
                  {range}
                </button>
              ))}
            </div>

            {/* Chain Selector */}
            <div className="relative">
              <button
                onClick={() => setShowChainDropdown(!showChainDropdown)}
                className="flex items-center gap-2 px-4 py-2 bg-[var(--bg-card)] border border-[var(--border-subtle)] rounded-lg text-sm font-medium text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors"
              >
                <Filter className="w-4 h-4" />
                Chains
                {selectedChains.length > 0 && (
                  <span className="px-2 py-0.5 bg-[var(--accent-blue)]/20 text-[var(--accent-blue)] rounded-full text-xs">
                    {selectedChains.length}
                  </span>
                )}
                <ChevronDown className="w-4 h-4" />
              </button>
              {showChainDropdown && (
                <div className="absolute right-0 mt-2 w-56 bg-[var(--bg-card)] border border-[var(--border-subtle)] rounded-lg shadow-lg z-50">
                  <div className="p-2">
                    {chains.map(chain => (
                      <label
                        key={chain.id}
                        className="flex items-center gap-3 p-2 hover:bg-[var(--bg-hover)] rounded-lg cursor-pointer"
                      >
                        <input
                          type="checkbox"
                          checked={selectedChains.includes(chain.id)}
                          onChange={() => toggleChain(chain.id)}
                          className="w-4 h-4 rounded border-[var(--border-subtle)]"
                        />
                        <div className="w-6 h-6 rounded-full bg-[var(--accent-blue)]/20 flex items-center justify-center text-xs font-bold">
                          {chain.symbol[0]}
                        </div>
                        <span className="text-sm text-[var(--text-primary)]">{chain.name}</span>
                      </label>
                    ))}
                  </div>
                  <div className="border-t border-[var(--border-subtle)] p-2">
                    <button
                      onClick={() => { setSelectedChains([]); setShowChainDropdown(false); }}
                      className="w-full text-sm text-[var(--text-secondary)] hover:text-[var(--text-primary)] py-1"
                    >
                      Clear all
                    </button>
                  </div>
                </div>
              )}
            </div>

            {/* Metric Type Selector */}
            <select
              value={metricType}
              onChange={(e) => setMetricType(e.target.value as MetricType)}
              className="px-4 py-2 bg-[var(--bg-card)] border border-[var(--border-subtle)] rounded-lg text-sm font-medium text-[var(--text-secondary)] focus:outline-none focus:border-[var(--accent-blue)]"
            >
              <option value="all">All Metrics</option>
              <option value="tvl">TVL</option>
              <option value="revenue">Revenue</option>
              <option value="volume">Volume</option>
              <option value="users">Users</option>
              <option value="transactions">Transactions</option>
            </select>

            {/* Export Buttons */}
            <button
              onClick={exportToCSV}
              className="flex items-center gap-2 px-4 py-2 bg-[var(--bg-card)] border border-[var(--border-subtle)] rounded-lg text-sm font-medium text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:border-[var(--accent-blue)] transition-all"
            >
              <Download className="w-4 h-4" />
              CSV
            </button>
            <button
              onClick={generateShareLink}
              className="flex items-center gap-2 px-4 py-2 bg-[var(--accent-blue)] text-white rounded-lg text-sm font-medium hover:bg-[var(--accent-blue)]/90 transition-colors"
            >
              <Share2 className="w-4 h-4" />
              Share
            </button>
          </div>
        </div>

        {/* Analytics Overview */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <StatCard
            title="Total Cross-Chain Volume"
            value={formatCurrency(aggregates?.totalVolume || 0)}
            change={5.2}
            icon={<BarChart3 className="w-6 h-6 text-[var(--accent-blue)]" />}
            subtitle={`${timeRange} period`}
          />
          <StatCard
            title="Active Chains"
            value={aggregates?.activeChainsCount.toString() || '0'}
            change={12.5}
            icon={<Layers className="w-6 h-6 text-[var(--accent-blue)]" />}
            subtitle="Currently tracked"
          />
          <StatCard
            title="Cross-Chain Transactions"
            value={formatNumber(aggregates?.totalTransactions || 0)}
            change={8.7}
            icon={<Activity className="w-6 h-6 text-[var(--accent-blue)]" />}
            subtitle={`${timeRange} total`}
          />
          <StatCard
            title="Avg Confirmation Time"
            value={`${(aggregates?.avgConfirmationTime || 0).toFixed(1)}s`}
            change={-15.3}
            icon={<Clock className="w-6 h-6 text-[var(--accent-blue)]" />}
            subtitle="Across all chains"
          />
        </div>

        {/* Chain Comparison - Heatmap */}
        <div className="card-xdc p-6">
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-[var(--accent-blue)]/10 flex items-center justify-center">
                <Target className="w-5 h-5 text-[var(--accent-blue)]" />
              </div>
              <div>
                <h2 className="text-lg font-semibold text-[var(--text-primary)]">Chain Comparison Matrix</h2>
                <p className="text-sm text-[var(--text-secondary)]">Activity heatmap across key metrics</p>
              </div>
            </div>
          </div>
          <Heatmap data={filteredChains} />
        </div>

        {/* Time Series Charts */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Daily Revenue */}
          <div className="card-xdc p-6">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h3 className="text-lg font-semibold text-[var(--text-primary)]">Daily Revenue</h3>
                <p className="text-sm text-[var(--text-secondary)]">Revenue trends by chain</p>
              </div>
              <DollarSign className="w-5 h-5 text-[var(--accent-blue)]" />
            </div>
            <div className="h-64">
              <LineChart data={revenueChartData} labels={revenueChartLabels} />
            </div>
          </div>

          {/* TVL Trends */}
          <div className="card-xdc p-6">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h3 className="text-lg font-semibold text-[var(--text-primary)]">TVL Trends</h3>
                <p className="text-sm text-[var(--text-secondary)]">Total Value Locked over time</p>
              </div>
              <TrendingUp className="w-5 h-5 text-[var(--accent-blue)]" />
            </div>
            <div className="h-64">
              <LineChart data={tvlChartData} color="#22c55e" />
            </div>
          </div>

          {/* User Growth */}
          <div className="card-xdc p-6">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h3 className="text-lg font-semibold text-[var(--text-primary)]">User Growth</h3>
                <p className="text-sm text-[var(--text-secondary)]">Active users by day</p>
              </div>
              <Users className="w-5 h-5 text-[var(--accent-blue)]" />
            </div>
            <div className="h-64">
              <BarChart data={usersChartData} color="#8b5cf6" />
            </div>
          </div>

          {/* Transaction Volume */}
          <div className="card-xdc p-6">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h3 className="text-lg font-semibold text-[var(--text-primary)]">Transaction Volume</h3>
                <p className="text-sm text-[var(--text-secondary)]">Volume candlestick chart</p>
              </div>
              <Globe className="w-5 h-5 text-[var(--accent-blue)]" />
            </div>
            <div className="h-64">
              <CandlestickChart data={volumeChartData} />
            </div>
          </div>
        </div>

        {/* Revenue Comparison & TVL Comparison */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div className="card-xdc p-6">
            <h3 className="text-lg font-semibold text-[var(--text-primary)] mb-4">Revenue Comparison</h3>
            <div className="space-y-3">
              {filteredChains.slice(0, 5).map((chain, index) => (
                <div key={chain.id} className="flex items-center gap-4">
                  <div className="w-8 h-8 rounded-full bg-[var(--accent-blue)]/20 flex items-center justify-center text-xs font-bold">
                    {chain.symbol[0]}
                  </div>
                  <div className="flex-1">
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-sm font-medium text-[var(--text-primary)]">{chain.name}</span>
                      <span className="text-sm text-[var(--text-secondary)]">{formatCurrency(chain.revenue24h)}</span>
                    </div>
                    <div className="h-2 bg-[var(--bg-body)] rounded-full overflow-hidden">
                      <div 
                        className="h-full bg-[var(--accent-blue)] rounded-full"
                        style={{ 
                          width: `${(chain.revenue24h / (filteredChains[0]?.revenue24h || 1)) * 100}%` 
                        }}
                      />
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="card-xdc p-6">
            <h3 className="text-lg font-semibold text-[var(--text-primary)] mb-4">TVL Comparison</h3>
            <div className="space-y-3">
              {filteredChains.slice(0, 5).map((chain, index) => (
                <div key={chain.id} className="flex items-center gap-4">
                  <div className="w-8 h-8 rounded-full bg-[var(--accent-blue)]/20 flex items-center justify-center text-xs font-bold">
                    {chain.symbol[0]}
                  </div>
                  <div className="flex-1">
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-sm font-medium text-[var(--text-primary)]">{chain.name}</span>
                      <span className="text-sm text-[var(--text-secondary)]">{formatCurrency(chain.tvl)}</span>
                    </div>
                    <div className="h-2 bg-[var(--bg-body)] rounded-full overflow-hidden">
                      <div 
                        className="h-full bg-green-500 rounded-full"
                        style={{ 
                          width: `${(chain.tvl / (filteredChains[0]?.tvl || 1)) * 100}%` 
                        }}
                      />
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Ranking Tables */}
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-6">
          <RankingTable data={filteredChains} type="byRevenue" />
          <RankingTable data={filteredChains} type="bySpeed" />
          <RankingTable data={filteredChains} type="byUsers" />
          <RankingTable data={filteredChains} type="byPsRatio" />
        </div>

        {/* Footer */}
        <div className="border-t border-[var(--border-subtle)] pt-6 mt-8">
          <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4 text-sm text-[var(--text-tertiary)]">
            <p>Data updated: {new Date().toLocaleString()}</p>
            <p>Cross-Chain Analytics Dashboard &copy; {new Date().getFullYear()}</p>
          </div>
        </div>
      </div>
    </DashboardLayout>
  );
}
