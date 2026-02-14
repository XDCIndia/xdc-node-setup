import { NextResponse } from 'next/server';

const RPC_URL = process.env.RPC_URL || 'http://xdc-node:8545';

export const dynamic = 'force-dynamic';

export async function GET() {
  const checks = { rpc: 'ok' as 'ok' | 'error' };

  try {
    const res = await fetch(RPC_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', method: 'eth_blockNumber', params: [], id: 1 }),
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) checks.rpc = 'error';
  } catch {
    checks.rpc = 'error';
  }

  const ready = checks.rpc === 'ok';
  return NextResponse.json(
    { status: ready ? 'ready' : 'not_ready', checks, timestamp: new Date().toISOString() },
    { status: ready ? 200 : 503 }
  );
}
