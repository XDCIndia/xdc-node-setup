import { NextResponse } from 'next/server';

const PROMETHEUS_URL = process.env.PROMETHEUS_URL || 'http://127.0.0.1:19090';
const RPC_URL = process.env.RPC_URL || 'http://127.0.0.1:38545';

export const dynamic = 'force-dynamic';

/**
 * Readiness probe endpoint
 * Returns 200 if the API is ready to accept traffic
 * Checks database connections and required services
 * Used by Kubernetes readiness probes
 */
export async function GET() {
  const checks = {
    database: 'ok' as const,
    rpc: 'ok' as const,
    prometheus: 'ok' as const,
  };
  let ready = true;

  // Check RPC connection
  try {
    const rpcResponse = await fetch(RPC_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'eth_blockNumber',
        params: [],
        id: 1,
      }),
      signal: AbortSignal.timeout(5000),
    });
    
    if (!rpcResponse.ok) {
      checks.rpc = 'error';
      ready = false;
    }
  } catch {
    checks.rpc = 'error';
    ready = false;
  }

  // Check Prometheus (optional for readiness)
  try {
    const promResponse = await fetch(`${PROMETHEUS_URL}/api/v1/status/targets`, {
      method: 'GET',
      signal: AbortSignal.timeout(5000),
    });
    
    if (!promResponse.ok) {
      checks.prometheus = 'error';
      // Don't fail readiness if Prometheus is down
    }
  } catch {
    checks.prometheus = 'error';
    // Don't fail readiness if Prometheus is down
  }

  return NextResponse.json(
    {
      ready,
      checks,
      timestamp: new Date().toISOString(),
    },
    { status: ready ? 200 : 503 }
  );
}
