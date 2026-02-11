import { NextResponse } from 'next/server';

const PROMETHEUS_URL = process.env.PROMETHEUS_URL || 'http://127.0.0.1:19090';
const RPC_URL = process.env.RPC_URL || 'http://127.0.0.1:38545';

export const dynamic = 'force-dynamic';

export async function GET() {
  const checks = {
    prometheus: false,
    rpc: false,
    timestamp: new Date().toISOString(),
  };

  try {
    // Check Prometheus
    const promResponse = await fetch(`${PROMETHEUS_URL}/api/v1/status/targets`, {
      method: 'GET',
      signal: AbortSignal.timeout(5000),
    });
    checks.prometheus = promResponse.ok;
  } catch {
    checks.prometheus = false;
  }

  try {
    // Check RPC
    const rpcResponse = await fetch(RPC_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'eth_syncing',
        params: [],
        id: 1,
      }),
      signal: AbortSignal.timeout(5000),
    });
    checks.rpc = rpcResponse.ok;
  } catch {
    checks.rpc = false;
  }

  const isHealthy = checks.prometheus || checks.rpc;
  
  return NextResponse.json(checks, { 
    status: isHealthy ? 200 : 503 
  });
}
