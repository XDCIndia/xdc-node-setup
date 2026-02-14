import { NextResponse } from 'next/server';

const RPC_URL = process.env.RPC_URL || 'http://xdc-node:8545';

export const dynamic = 'force-dynamic';

export async function GET() {
  const checks = {
    rpc: false,
    timestamp: new Date().toISOString(),
  };

  try {
    const rpcResponse = await fetch(RPC_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', method: 'eth_blockNumber', params: [], id: 1 }),
      signal: AbortSignal.timeout(5000),
    });
    checks.rpc = rpcResponse.ok;
  } catch {
    checks.rpc = false;
  }

  return NextResponse.json(checks, { status: checks.rpc ? 200 : 503 });
}
