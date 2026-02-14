import { NextResponse } from 'next/server';

function getRpcUrl() { return process.env.RPC_URL || 'http://xdc-node:8545'; }

export const dynamic = 'force-dynamic';

export async function GET() {
  const checks: Record<string, { status: string; responseTime?: number; message?: string }> = {
    rpc: { status: 'pass' },
  };

  try {
    const start = Date.now();
    const res = await fetch(getRpcUrl(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', method: 'eth_blockNumber', params: [], id: 1 }),
      signal: AbortSignal.timeout(5000),
    });
    checks.rpc.responseTime = Date.now() - start;
    if (!res.ok) {
      checks.rpc.status = 'fail';
      checks.rpc.message = `HTTP ${res.status}`;
    }
  } catch (error) {
    checks.rpc.status = 'fail';
    checks.rpc.message = error instanceof Error ? error.message : 'Unknown error';
  }

  const healthy = checks.rpc.status === 'pass';
  return NextResponse.json(
    { status: healthy ? 'healthy' : 'degraded', checks, timestamp: new Date().toISOString() },
    { status: healthy ? 200 : 503 }
  );
}
