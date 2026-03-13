import { NextResponse } from 'next/server';

// Mock data for cross-chain financial metrics
// In production, this would fetch from a database or external APIs

interface ChainFinancialData {
  id: string;
  name: string;
  symbol: string;
  logoUrl: string;
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
  avgConfirmationTime: number; // in seconds
  activeUsers24h: number;
  activeUsers7d: number;
  activeUsers30d: number;
  marketCap: number;
  price: number;
  priceChange24h: number;
  fdv: number;
  psRatio: number; // Price to Sales ratio
  timestamp: string;
}

const chainsData: ChainFinancialData[] = [
  {
    id: 'ethereum',
    name: 'Ethereum',
    symbol: 'ETH',
    logoUrl: '/chains/ethereum.svg',
    tvl: 28500000000,
    tvlChange24h: 2.4,
    revenue24h: 4500000,
    revenue7d: 31000000,
    revenue30d: 135000000,
    revenueChange24h: 5.2,
    volume24h: 12500000000,
    volume7d: 87500000000,
    volume30d: 385000000000,
    volumeChange24h: -1.8,
    transactions24h: 1250000,
    transactions7d: 8750000,
    transactions30d: 38500000,
    avgConfirmationTime: 12,
    activeUsers24h: 450000,
    activeUsers7d: 2100000,
    activeUsers30d: 8500000,
    marketCap: 285000000000,
    price: 2350.50,
    priceChange24h: 1.8,
    fdv: 285000000000,
    psRatio: 15.2,
    timestamp: new Date().toISOString(),
  },
  {
    id: 'xdc',
    name: 'XDC Network',
    symbol: 'XDC',
    logoUrl: '/chains/xdc.svg',
    tvl: 850000000,
    tvlChange24h: 8.5,
    revenue24h: 125000,
    revenue7d: 875000,
    revenue30d: 3800000,
    revenueChange24h: 12.3,
    volume24h: 45000000,
    volume7d: 315000000,
    volume30d: 1380000000,
    volumeChange24h: 15.2,
    transactions24h: 85000,
    transactions7d: 595000,
    transactions30d: 2600000,
    avgConfirmationTime: 2,
    activeUsers24h: 25000,
    activeUsers7d: 125000,
    activeUsers30d: 450000,
    marketCap: 4200000000,
    price: 0.0285,
    priceChange24h: 3.2,
    fdv: 5200000000,
    psRatio: 8.5,
    timestamp: new Date().toISOString(),
  },
  {
    id: 'bsc',
    name: 'BNB Chain',
    symbol: 'BNB',
    logoUrl: '/chains/bsc.svg',
    tvl: 4200000000,
    tvlChange24h: -1.2,
    revenue24h: 850000,
    revenue7d: 5950000,
    revenue30d: 25500000,
    revenueChange24h: -3.5,
    volume24h: 1800000000,
    volume7d: 12600000000,
    volume30d: 55200000000,
    volumeChange24h: -5.2,
    transactions24h: 4500000,
    transactions7d: 31500000,
    transactions30d: 138000000,
    avgConfirmationTime: 3,
    activeUsers24h: 850000,
    activeUsers7d: 4500000,
    activeUsers30d: 18500000,
    marketCap: 85000000000,
    price: 580.25,
    priceChange24h: -0.8,
    fdv: 85000000000,
    psRatio: 22.5,
    timestamp: new Date().toISOString(),
  },
  {
    id: 'polygon',
    name: 'Polygon',
    symbol: 'MATIC',
    logoUrl: '/chains/polygon.svg',
    tvl: 1200000000,
    tvlChange24h: 1.5,
    revenue24h: 180000,
    revenue7d: 1260000,
    revenue30d: 5400000,
    revenueChange24h: 2.8,
    volume24h: 380000000,
    volume7d: 2660000000,
    volume30d: 11660000000,
    volumeChange24h: 4.2,
    transactions24h: 2800000,
    transactions7d: 19600000,
    transactions30d: 85800000,
    avgConfirmationTime: 2.5,
    activeUsers24h: 450000,
    activeUsers7d: 2200000,
    activeUsers30d: 9200000,
    marketCap: 7500000000,
    price: 0.85,
    priceChange24h: 1.2,
    fdv: 8500000000,
    psRatio: 12.8,
    timestamp: new Date().toISOString(),
  },
  {
    id: 'arbitrum',
    name: 'Arbitrum',
    symbol: 'ARB',
    logoUrl: '/chains/arbitrum.svg',
    tvl: 2800000000,
    tvlChange24h: 3.8,
    revenue24h: 320000,
    revenue7d: 2240000,
    revenue30d: 9600000,
    revenueChange24h: 8.5,
    volume24h: 950000000,
    volume7d: 6650000000,
    volume30d: 29150000000,
    volumeChange24h: 12.5,
    transactions24h: 1250000,
    transactions7d: 8750000,
    transactions30d: 38250000,
    avgConfirmationTime: 1,
    activeUsers24h: 320000,
    activeUsers7d: 1680000,
    activeUsers30d: 7000000,
    marketCap: 2500000000,
    price: 0.95,
    priceChange24h: 5.2,
    fdv: 9500000000,
    psRatio: 18.5,
    timestamp: new Date().toISOString(),
  },
  {
    id: 'optimism',
    name: 'Optimism',
    symbol: 'OP',
    logoUrl: '/chains/optimism.svg',
    tvl: 1800000000,
    tvlChange24h: 2.1,
    revenue24h: 210000,
    revenue7d: 1470000,
    revenue30d: 6300000,
    revenueChange24h: 4.2,
    volume24h: 580000000,
    volume7d: 4060000000,
    volume30d: 17780000000,
    volumeChange24h: 7.8,
    transactions24h: 850000,
    transactions7d: 5950000,
    transactions30d: 26050000,
    avgConfirmationTime: 1.2,
    activeUsers24h: 280000,
    activeUsers7d: 1450000,
    activeUsers30d: 6000000,
    marketCap: 2200000000,
    price: 1.45,
    priceChange24h: 2.5,
    fdv: 6200000000,
    psRatio: 24.2,
    timestamp: new Date().toISOString(),
  },
  {
    id: 'avalanche',
    name: 'Avalanche',
    symbol: 'AVAX',
    logoUrl: '/chains/avalanche.svg',
    tvl: 950000000,
    tvlChange24h: -2.5,
    revenue24h: 145000,
    revenue7d: 1015000,
    revenue30d: 4350000,
    revenueChange24h: -1.8,
    volume24h: 320000000,
    volume7d: 2240000000,
    volume30d: 9800000000,
    volumeChange24h: -3.2,
    transactions24h: 450000,
    transactions7d: 3150000,
    transactions30d: 13800000,
    avgConfirmationTime: 2.8,
    activeUsers24h: 180000,
    activeUsers7d: 950000,
    activeUsers30d: 4000000,
    marketCap: 12000000000,
    price: 28.50,
    priceChange24h: -1.5,
    fdv: 18500000000,
    psRatio: 32.5,
    timestamp: new Date().toISOString(),
  },
  {
    id: 'fantom',
    name: 'Fantom',
    symbol: 'FTM',
    logoUrl: '/chains/fantom.svg',
    tvl: 420000000,
    tvlChange24h: 4.5,
    revenue24h: 68000,
    revenue7d: 476000,
    revenue30d: 2040000,
    revenueChange24h: 6.2,
    volume24h: 180000000,
    volume7d: 1260000000,
    volume30d: 5460000000,
    volumeChange24h: 8.5,
    transactions24h: 650000,
    transactions7d: 4550000,
    transactions30d: 19950000,
    avgConfirmationTime: 1.5,
    activeUsers24h: 125000,
    activeUsers7d: 650000,
    activeUsers30d: 2800000,
    marketCap: 1800000000,
    price: 0.65,
    priceChange24h: 3.8,
    fdv: 2000000000,
    psRatio: 8.2,
    timestamp: new Date().toISOString(),
  },
];

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const timeRange = searchParams.get('timeRange') || '24h';
  const chainIds = searchParams.get('chains')?.split(',') || [];

  let filteredData = [...chainsData];

  // Filter by chain IDs if specified
  if (chainIds.length > 0 && chainIds[0] !== '') {
    filteredData = filteredData.filter(chain => chainIds.includes(chain.id));
  }

  // Apply time range adjustments (simulate historical data)
  const adjustedData = filteredData.map(chain => {
    const multiplier = getTimeRangeMultiplier(timeRange);
    return {
      ...chain,
      volume: chain.volume24h * multiplier,
      transactions: chain.transactions24h * multiplier,
      activeUsers: Math.round(chain.activeUsers24h * multiplier),
    };
  });

  // Calculate aggregate metrics
  const totalVolume = adjustedData.reduce((sum, chain) => sum + chain.volume24h, 0);
  const totalTransactions = adjustedData.reduce((sum, chain) => sum + chain.transactions24h, 0);
  const totalRevenue = adjustedData.reduce((sum, chain) => sum + chain.revenue24h, 0);
  const avgConfirmationTime = adjustedData.reduce((sum, chain) => sum + chain.avgConfirmationTime, 0) / adjustedData.length;

  return NextResponse.json({
    chains: adjustedData,
    aggregates: {
      totalVolume,
      totalTransactions,
      totalRevenue,
      activeChainsCount: adjustedData.length,
      avgConfirmationTime: Math.round(avgConfirmationTime * 100) / 100,
    },
    timeRange,
    timestamp: new Date().toISOString(),
  });
}

function getTimeRangeMultiplier(timeRange: string): number {
  switch (timeRange) {
    case '24h': return 1;
    case '7d': return 7;
    case '30d': return 30;
    case '90d': return 90;
    case '1y': return 365;
    default: return 1;
  }
}
