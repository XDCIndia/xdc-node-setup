import { NextResponse } from 'next/server';

// Mock data for chain comparison and rankings
// In production, this would fetch from a database or external APIs

interface ChainComparisonData {
  id: string;
  name: string;
  symbol: string;
  logoUrl: string;
  metrics: {
    tvl: number;
    tvlChange24h: number;
    revenue24h: number;
    revenue7d: number;
    revenue30d: number;
    revenueChange24h: number;
    volume24h: number;
    volumeChange24h: number;
    transactions24h: number;
    avgConfirmationTime: number;
    activeUsers24h: number;
    activeUsersChange24h: number;
    marketCap: number;
    psRatio: number;
    fdv: number;
    price: number;
    priceChange24h: number;
    gasFeeAverage: number;
    throughput: number; // TPS
    decentralizationScore: number; // 0-100
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

// Generate time series data for the last 30 days
function generateTimeSeriesData(baseValue: number, volatility: number = 0.1, days: number = 30) {
  const data = [];
  let currentValue = baseValue;
  
  for (let i = days - 1; i >= 0; i--) {
    const date = new Date();
    date.setDate(date.getDate() - i);
    
    // Add random volatility
    const change = (Math.random() - 0.5) * 2 * volatility;
    currentValue = currentValue * (1 + change);
    
    data.push({
      date: date.toISOString().split('T')[0],
      value: Math.round(currentValue * 100) / 100,
    });
  }
  
  return data;
}

// Generate candlestick data for volume
function generateCandlestickData(baseValue: number, days: number = 30) {
  const data = [];
  
  for (let i = days - 1; i >= 0; i--) {
    const date = new Date();
    date.setDate(date.getDate() - i);
    
    const open = baseValue * (1 + (Math.random() - 0.5) * 0.2);
    const close = baseValue * (1 + (Math.random() - 0.5) * 0.2);
    const high = Math.max(open, close) * (1 + Math.random() * 0.1);
    const low = Math.min(open, close) * (1 - Math.random() * 0.1);
    
    data.push({
      date: date.toISOString().split('T')[0],
      open: Math.round(open * 100) / 100,
      high: Math.round(high * 100) / 100,
      low: Math.round(low * 100) / 100,
      close: Math.round(close * 100) / 100,
    });
  }
  
  return data;
}

const chainsComparisonData: ChainComparisonData[] = [
  {
    id: 'ethereum',
    name: 'Ethereum',
    symbol: 'ETH',
    logoUrl: '/chains/ethereum.svg',
    metrics: {
      tvl: 28500000000,
      tvlChange24h: 2.4,
      revenue24h: 4500000,
      revenue7d: 31000000,
      revenue30d: 135000000,
      revenueChange24h: 5.2,
      volume24h: 12500000000,
      volumeChange24h: -1.8,
      transactions24h: 1250000,
      avgConfirmationTime: 12,
      activeUsers24h: 450000,
      activeUsersChange24h: 2.1,
      marketCap: 285000000000,
      psRatio: 15.2,
      fdv: 285000000000,
      price: 2350.50,
      priceChange24h: 1.8,
      gasFeeAverage: 2.5,
      throughput: 15,
      decentralizationScore: 92,
    },
    rankings: {
      byRevenue: 1,
      byTvl: 1,
      byVolume: 1,
      byUsers: 2,
      bySpeed: 6,
      byPsRatio: 4,
      byActivity: 3,
    },
    timeSeries: {
      dailyRevenue: generateTimeSeriesData(4500000, 0.15),
      dailyTvl: generateTimeSeriesData(28500000000, 0.05),
      dailyUsers: generateTimeSeriesData(450000, 0.08),
      dailyVolume: generateCandlestickData(12500000000),
    },
  },
  {
    id: 'xdc',
    name: 'XDC Network',
    symbol: 'XDC',
    logoUrl: '/chains/xdc.svg',
    metrics: {
      tvl: 850000000,
      tvlChange24h: 8.5,
      revenue24h: 125000,
      revenue7d: 875000,
      revenue30d: 3800000,
      revenueChange24h: 12.3,
      volume24h: 45000000,
      volumeChange24h: 15.2,
      transactions24h: 85000,
      avgConfirmationTime: 2,
      activeUsers24h: 25000,
      activeUsersChange24h: 5.8,
      marketCap: 4200000000,
      psRatio: 8.5,
      fdv: 5200000000,
      price: 0.0285,
      priceChange24h: 3.2,
      gasFeeAverage: 0.001,
      throughput: 2000,
      decentralizationScore: 78,
    },
    rankings: {
      byRevenue: 5,
      byTvl: 4,
      byVolume: 6,
      byUsers: 8,
      bySpeed: 1,
      byPsRatio: 1,
      byActivity: 7,
    },
    timeSeries: {
      dailyRevenue: generateTimeSeriesData(125000, 0.12),
      dailyTvl: generateTimeSeriesData(850000000, 0.08),
      dailyUsers: generateTimeSeriesData(25000, 0.10),
      dailyVolume: generateCandlestickData(45000000),
    },
  },
  {
    id: 'bsc',
    name: 'BNB Chain',
    symbol: 'BNB',
    logoUrl: '/chains/bsc.svg',
    metrics: {
      tvl: 4200000000,
      tvlChange24h: -1.2,
      revenue24h: 850000,
      revenue7d: 5950000,
      revenue30d: 25500000,
      revenueChange24h: -3.5,
      volume24h: 1800000000,
      volumeChange24h: -5.2,
      transactions24h: 4500000,
      avgConfirmationTime: 3,
      activeUsers24h: 850000,
      activeUsersChange24h: -2.1,
      marketCap: 85000000000,
      psRatio: 22.5,
      fdv: 85000000000,
      price: 580.25,
      priceChange24h: -0.8,
      gasFeeAverage: 0.05,
      throughput: 160,
      decentralizationScore: 65,
    },
    rankings: {
      byRevenue: 2,
      byTvl: 2,
      byVolume: 2,
      byUsers: 1,
      bySpeed: 2,
      byPsRatio: 6,
      byActivity: 1,
    },
    timeSeries: {
      dailyRevenue: generateTimeSeriesData(850000, 0.10),
      dailyTvl: generateTimeSeriesData(4200000000, 0.06),
      dailyUsers: generateTimeSeriesData(850000, 0.05),
      dailyVolume: generateCandlestickData(1800000000),
    },
  },
  {
    id: 'polygon',
    name: 'Polygon',
    symbol: 'MATIC',
    logoUrl: '/chains/polygon.svg',
    metrics: {
      tvl: 1200000000,
      tvlChange24h: 1.5,
      revenue24h: 180000,
      revenue7d: 1260000,
      revenue30d: 5400000,
      revenueChange24h: 2.8,
      volume24h: 380000000,
      volumeChange24h: 4.2,
      transactions24h: 2800000,
      avgConfirmationTime: 2.5,
      activeUsers24h: 450000,
      activeUsersChange24h: 1.8,
      marketCap: 7500000000,
      psRatio: 12.8,
      fdv: 8500000000,
      price: 0.85,
      priceChange24h: 1.2,
      gasFeeAverage: 0.02,
      throughput: 7000,
      decentralizationScore: 72,
    },
    rankings: {
      byRevenue: 3,
      byTvl: 3,
      byVolume: 3,
      byUsers: 3,
      bySpeed: 4,
      byPsRatio: 3,
      byActivity: 2,
    },
    timeSeries: {
      dailyRevenue: generateTimeSeriesData(180000, 0.08),
      dailyTvl: generateTimeSeriesData(1200000000, 0.04),
      dailyUsers: generateTimeSeriesData(450000, 0.06),
      dailyVolume: generateCandlestickData(380000000),
    },
  },
  {
    id: 'arbitrum',
    name: 'Arbitrum',
    symbol: 'ARB',
    logoUrl: '/chains/arbitrum.svg',
    metrics: {
      tvl: 2800000000,
      tvlChange24h: 3.8,
      revenue24h: 320000,
      revenue7d: 2240000,
      revenue30d: 9600000,
      revenueChange24h: 8.5,
      volume24h: 950000000,
      volumeChange24h: 12.5,
      transactions24h: 1250000,
      avgConfirmationTime: 1,
      activeUsers24h: 320000,
      activeUsersChange24h: 4.2,
      marketCap: 2500000000,
      psRatio: 18.5,
      fdv: 9500000000,
      price: 0.95,
      priceChange24h: 5.2,
      gasFeeAverage: 0.15,
      throughput: 40000,
      decentralizationScore: 68,
    },
    rankings: {
      byRevenue: 4,
      byTvl: 5,
      byVolume: 4,
      byUsers: 4,
      bySpeed: 3,
      byPsRatio: 5,
      byActivity: 4,
    },
    timeSeries: {
      dailyRevenue: generateTimeSeriesData(320000, 0.20),
      dailyTvl: generateTimeSeriesData(2800000000, 0.10),
      dailyUsers: generateTimeSeriesData(320000, 0.12),
      dailyVolume: generateCandlestickData(950000000),
    },
  },
  {
    id: 'optimism',
    name: 'Optimism',
    symbol: 'OP',
    logoUrl: '/chains/optimism.svg',
    metrics: {
      tvl: 1800000000,
      tvlChange24h: 2.1,
      revenue24h: 210000,
      revenue7d: 1470000,
      revenue30d: 6300000,
      revenueChange24h: 4.2,
      volume24h: 580000000,
      volumeChange24h: 7.8,
      transactions24h: 850000,
      avgConfirmationTime: 1.2,
      activeUsers24h: 280000,
      activeUsersChange24h: 3.5,
      marketCap: 2200000000,
      psRatio: 24.2,
      fdv: 6200000000,
      price: 1.45,
      priceChange24h: 2.5,
      gasFeeAverage: 0.12,
      throughput: 4000,
      decentralizationScore: 70,
    },
    rankings: {
      byRevenue: 6,
      byTvl: 6,
      byVolume: 5,
      byUsers: 5,
      bySpeed: 5,
      byPsRatio: 7,
      byActivity: 5,
    },
    timeSeries: {
      dailyRevenue: generateTimeSeriesData(210000, 0.18),
      dailyTvl: generateTimeSeriesData(1800000000, 0.07),
      dailyUsers: generateTimeSeriesData(280000, 0.09),
      dailyVolume: generateCandlestickData(580000000),
    },
  },
  {
    id: 'avalanche',
    name: 'Avalanche',
    symbol: 'AVAX',
    logoUrl: '/chains/avalanche.svg',
    metrics: {
      tvl: 950000000,
      tvlChange24h: -2.5,
      revenue24h: 145000,
      revenue7d: 1015000,
      revenue30d: 4350000,
      revenueChange24h: -1.8,
      volume24h: 320000000,
      volumeChange24h: -3.2,
      transactions24h: 450000,
      avgConfirmationTime: 2.8,
      activeUsers24h: 180000,
      activeUsersChange24h: -1.2,
      marketCap: 12000000000,
      psRatio: 32.5,
      fdv: 18500000000,
      price: 28.50,
      priceChange24h: -1.5,
      gasFeeAverage: 0.08,
      throughput: 4500,
      decentralizationScore: 75,
    },
    rankings: {
      byRevenue: 7,
      byTvl: 7,
      byVolume: 7,
      byUsers: 6,
      bySpeed: 7,
      byPsRatio: 8,
      byActivity: 6,
    },
    timeSeries: {
      dailyRevenue: generateTimeSeriesData(145000, 0.14),
      dailyTvl: generateTimeSeriesData(950000000, 0.09),
      dailyUsers: generateTimeSeriesData(180000, 0.07),
      dailyVolume: generateCandlestickData(320000000),
    },
  },
  {
    id: 'fantom',
    name: 'Fantom',
    symbol: 'FTM',
    logoUrl: '/chains/fantom.svg',
    metrics: {
      tvl: 420000000,
      tvlChange24h: 4.5,
      revenue24h: 68000,
      revenue7d: 476000,
      revenue30d: 2040000,
      revenueChange24h: 6.2,
      volume24h: 180000000,
      volumeChange24h: 8.5,
      transactions24h: 650000,
      avgConfirmationTime: 1.5,
      activeUsers24h: 125000,
      activeUsersChange24h: 3.2,
      marketCap: 1800000000,
      psRatio: 8.2,
      fdv: 2000000000,
      price: 0.65,
      priceChange24h: 3.8,
      gasFeeAverage: 0.003,
      throughput: 2500,
      decentralizationScore: 71,
    },
    rankings: {
      byRevenue: 8,
      byTvl: 8,
      byVolume: 8,
      byUsers: 7,
      bySpeed: 8,
      byPsRatio: 2,
      byActivity: 8,
    },
    timeSeries: {
      dailyRevenue: generateTimeSeriesData(68000, 0.16),
      dailyTvl: generateTimeSeriesData(420000000, 0.11),
      dailyUsers: generateTimeSeriesData(125000, 0.13),
      dailyVolume: generateCandlestickData(180000000),
    },
  },
];

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const sortBy = searchParams.get('sortBy') || 'byRevenue';
  const limit = parseInt(searchParams.get('limit') || '10');
  const chainIds = searchParams.get('chains')?.split(',') || [];

  let filteredData = [...chainsComparisonData];

  // Filter by chain IDs if specified
  if (chainIds.length > 0 && chainIds[0] !== '') {
    filteredData = filteredData.filter(chain => chainIds.includes(chain.id));
  }

  // Sort by the specified ranking
  const sortedData = filteredData.sort((a, b) => {
    return a.rankings[sortBy as keyof typeof a.rankings] - b.rankings[sortBy as keyof typeof b.rankings];
  });

  // Limit results
  const limitedData = sortedData.slice(0, limit);

  // Generate rankings for each category
  const rankings = {
    byRevenue: chainsComparisonData
      .sort((a, b) => b.metrics.revenue24h - a.metrics.revenue24h)
      .map((c, i) => ({ ...c, rank: i + 1 })),
    bySpeed: chainsComparisonData
      .sort((a, b) => a.metrics.avgConfirmationTime - b.metrics.avgConfirmationTime)
      .map((c, i) => ({ ...c, rank: i + 1 })),
    byUsers: chainsComparisonData
      .sort((a, b) => b.metrics.activeUsers24h - a.metrics.activeUsers24h)
      .map((c, i) => ({ ...c, rank: i + 1 })),
    byPsRatio: chainsComparisonData
      .filter(c => c.metrics.psRatio > 0)
      .sort((a, b) => a.metrics.psRatio - b.metrics.psRatio)
      .map((c, i) => ({ ...c, rank: i + 1 })),
    byTvl: chainsComparisonData
      .sort((a, b) => b.metrics.tvl - a.metrics.tvl)
      .map((c, i) => ({ ...c, rank: i + 1 })),
  };

  return NextResponse.json({
    chains: limitedData,
    rankings,
    sortBy,
    timestamp: new Date().toISOString(),
  });
}
