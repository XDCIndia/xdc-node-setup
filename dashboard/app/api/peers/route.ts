import { NextResponse } from 'next/server';

function getRpcUrl() { return process.env.RPC_URL || 'http://xdc-node:8545'; }
const GEO_CACHE_TTL = parseInt(process.env.GEO_CACHE_TTL || '300000'); // 5 minutes

interface PeerNetwork {
  localAddress: string;
  remoteAddress: string;
  inbound: boolean;
  trusted: boolean;
  static: boolean;
}

interface PeerInfo {
  enode: string;
  id: string;
  name: string;
  network: PeerNetwork;
  protocols: Record<string, unknown>;
}

interface GeoLocation {
  status: string;
  country: string;
  countryCode: string;
  region: string;
  regionName: string;
  city: string;
  lat: number;
  lon: number;
  isp: string;
  query: string;
}

// In-memory cache for geo-location data
const geoCache = new Map<string, GeoLocation>();
const cacheTimestamps = new Map<string, number>();

function extractIP(remoteAddress: string): string | null {
  // Handle formats like "54.219.236.246:30303" or "[::]:30303"
  if (remoteAddress.startsWith('[')) {
    // IPv6 - skip for now
    return null;
  }
  const parts = remoteAddress.split(':');
  if (parts.length >= 2) {
    return parts[0];
  }
  return remoteAddress;
}

function isPrivateIP(ip: string): boolean {
  const privateRanges = [
    /^10\./,
    /^172\.(1[6-9]|2[0-9]|3[01])\./,
    /^192\.168\./,
    /^127\./,
    /^::1$/,
    /^fc00:/i,
    /^fe80:/i,
  ];
  return privateRanges.some(range => range.test(ip));
}

async function getGeoLocation(ip: string): Promise<GeoLocation | null> {
  // Check cache first
  const now = Date.now();
  const cachedTime = cacheTimestamps.get(ip);
  if (cachedTime && (now - cachedTime) < GEO_CACHE_TTL) {
    const cached = geoCache.get(ip);
    if (cached) return cached;
  }

  try {
    const response = await fetch(`http://ip-api.com/json/${ip}?fields=status,country,countryCode,region,regionName,city,lat,lon,isp,query`, {
      method: 'GET',
      headers: { 'Accept': 'application/json' },
    });

    if (!response.ok) {
      return null;
    }

    const data: GeoLocation = await response.json();
    
    if (data.status === 'success') {
      geoCache.set(ip, data);
      cacheTimestamps.set(ip, now);
      return data;
    }
    return null;
  } catch (error) {
    console.error(`Geo-location error for ${ip}:`, error);
    return null;
  }
}

async function batchGeoLocate(ips: string[]): Promise<Map<string, GeoLocation>> {
  const results = new Map<string, GeoLocation>();
  const now = Date.now();
  
  // Filter out cached and private IPs
  const ipsToQuery = ips.filter(ip => {
    if (isPrivateIP(ip)) return false;
    const cachedTime = cacheTimestamps.get(ip);
    if (cachedTime && (now - cachedTime) < GEO_CACHE_TTL) {
      const cached = geoCache.get(ip);
      if (cached) results.set(ip, cached);
      return false;
    }
    return true;
  });

  if (ipsToQuery.length === 0) return results;

  try {
    // Batch request to ip-api (max 100 IPs per request)
    const batch = ipsToQuery.slice(0, 100).map(ip => ({ query: ip }));
    
    const response = await fetch('http://ip-api.com/batch?fields=status,country,countryCode,region,regionName,city,lat,lon,isp,query', {
      method: 'POST',
      headers: { 
        'Accept': 'application/json',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(batch),
    });

    if (!response.ok) {
      console.error('Batch geo-location failed:', response.statusText);
      return results;
    }

    const data: GeoLocation[] = await response.json();
    
    for (const loc of data) {
      if (loc.status === 'success') {
        geoCache.set(loc.query, loc);
        cacheTimestamps.set(loc.query, now);
        results.set(loc.query, loc);
      }
    }
  } catch (error) {
    console.error('Batch geo-location error:', error);
  }

  return results;
}

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export async function GET() {
  try {
    // Fetch peers from XDC RPC
    const response = await fetch(getRpcUrl(), {
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'admin_peers',
        params: [],
        id: 1,
      }),
    });

    if (!response.ok) {
      return NextResponse.json(
        { error: 'Failed to fetch peers from RPC', totalPeers: 0, peers: [], countries: {} },
        { status: 503 }
      );
    }

    const rpcData = await response.json();
    
    if (rpcData.error) {
      console.error('RPC error:', rpcData.error);
      return NextResponse.json(
        { error: rpcData.error.message || 'RPC error', totalPeers: 0, peers: [], countries: {} },
        { status: 503 }
      );
    }

    const peers: PeerInfo[] = rpcData.result || [];
    
    // Extract unique IPs
    const ipMap = new Map<string, { peer: PeerInfo; ip: string; port: number }>();
    const uniqueIPs: string[] = [];

    for (const peer of peers) {
      const remoteAddr = peer.network?.remoteAddress;
      if (!remoteAddr) continue;
      
      const ip = extractIP(remoteAddr);
      if (!ip) continue;
      
      const port = parseInt(remoteAddr.split(':').pop() || '30303');
      
      if (!ipMap.has(ip)) {
        ipMap.set(ip, { peer, ip, port });
        if (!isPrivateIP(ip)) {
          uniqueIPs.push(ip);
        }
      }
    }

    // Geo-locate IPs
    const geoData = await batchGeoLocate(uniqueIPs);

    // Build peer list with geo data
    const enrichedPeers = [];
    const countries: Record<string, { name: string; count: number }> = {};

    for (const [ip, { peer, port }] of Array.from(ipMap.entries())) {
      const geo = geoData.get(ip);
      
      if (geo) {
        const countryCode = geo.countryCode.toLowerCase();
        if (!countries[countryCode]) {
          countries[countryCode] = { name: geo.country, count: 0 };
        }
        countries[countryCode].count++;
      }

      enrichedPeers.push({
        id: peer.id,
        name: peer.name,
        ip,
        port,
        country: geo?.country || 'Unknown',
        countryCode: geo?.countryCode?.toLowerCase() || 'unknown',
        city: geo?.city || 'Unknown',
        lat: geo?.lat || 0,
        lon: geo?.lon || 0,
        isp: geo?.isp || 'Unknown',
        inbound: peer.network?.inbound || false,
      });
    }

    return NextResponse.json({
      peers: enrichedPeers,
      countries,
      totalPeers: enrichedPeers.length,
    });
  } catch (error) {
    console.error('Error fetching peers:', error);
    return NextResponse.json(
      { error: 'Failed to fetch peers', totalPeers: 0, peers: [], countries: {} },
      { status: 500 }
    );
  }
}
