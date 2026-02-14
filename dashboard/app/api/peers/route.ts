import { NextResponse } from 'next/server';
import { geolocateBatch } from '@/lib/geo';

function getRpcUrl() { return process.env.RPC_URL || 'http://xdc-node:8545'; }

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

    // Geo-locate IPs using the geo module
    const geoData = await geolocateBatch(uniqueIPs);

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
