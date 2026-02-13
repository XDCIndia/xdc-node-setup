import { NextResponse } from 'next/server';
import { promises as fs } from 'fs';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

const PROMETHEUS_URL = process.env.PROMETHEUS_URL || 'http://127.0.0.1:19090';
const RPC_URL = process.env.RPC_URL || 'http://127.0.0.1:38545';
const DATA_DIR = process.env.DATA_DIR || '/opt/xdc-node/mainnet/xdcchain';

export const dynamic = 'force-dynamic';

interface HealthCheck {
  status: 'pass' | 'fail' | 'warning';
  responseTime?: number;
  message?: string;
}

interface DeepHealthResponse {
  status: 'healthy' | 'unhealthy' | 'degraded';
  checks: {
    api: HealthCheck;
    rpc: HealthCheck & { blockHeight?: number };
    prometheus: HealthCheck;
    disk: HealthCheck & { usagePercent?: number; availableBytes?: number };
    memory?: HealthCheck & { usagePercent?: number };
  };
  timestamp: string;
}

/**
 * Deep health check endpoint
 * Comprehensive health check that validates all systems
 * - API service status
 * - XDC node RPC connectivity
 * - Prometheus connectivity
 * - Disk space availability
 */
export async function GET() {
  const startTime = Date.now();
  const checks: DeepHealthResponse['checks'] = {
    api: { status: 'pass' },
    rpc: { status: 'pass' },
    prometheus: { status: 'pass' },
    disk: { status: 'pass' },
  };

  // API Health Check
  checks.api.responseTime = Date.now() - startTime;

  // RPC Health Check
  try {
    const rpcStart = Date.now();
    const rpcResponse = await fetch(RPC_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'eth_blockNumber',
        params: [],
        id: 1,
      }),
      signal: AbortSignal.timeout(10000),
    });

    if (rpcResponse.ok) {
      const data = await rpcResponse.json();
      checks.rpc.responseTime = Date.now() - rpcStart;
      checks.rpc.blockHeight = parseInt(data.result || '0x0', 16);
    } else {
      checks.rpc.status = 'fail';
      checks.rpc.message = `HTTP ${rpcResponse.status}`;
    }
  } catch (error) {
    checks.rpc.status = 'fail';
    checks.rpc.message = error instanceof Error ? error.message : 'Unknown error';
  }

  // Prometheus Health Check
  try {
    const promStart = Date.now();
    const promResponse = await fetch(`${PROMETHEUS_URL}/api/v1/status/targets`, {
      method: 'GET',
      signal: AbortSignal.timeout(5000),
    });

    if (promResponse.ok) {
      checks.prometheus.responseTime = Date.now() - promStart;
    } else {
      checks.prometheus.status = 'fail';
      checks.prometheus.message = `HTTP ${promResponse.status}`;
    }
  } catch (error) {
    checks.prometheus.status = 'fail';
    checks.prometheus.message = error instanceof Error ? error.message : 'Unknown error';
  }

  // Disk Space Check
  try {
    const { stdout } = await execAsync(`df -B1 "${DATA_DIR}" | tail -1`);
    const parts = stdout.trim().split(/\s+/);
    if (parts.length >= 4) {
      const total = parseInt(parts[1], 10);
      const used = parseInt(parts[2], 10);
      const available = parseInt(parts[3], 10);
      const usagePercent = Math.round((used / total) * 100);

      checks.disk.usagePercent = usagePercent;
      checks.disk.availableBytes = available;

      if (usagePercent >= 95) {
        checks.disk.status = 'fail';
        checks.disk.message = `Critical disk usage: ${usagePercent}%`;
      } else if (usagePercent >= 80) {
        checks.disk.status = 'warning';
        checks.disk.message = `High disk usage: ${usagePercent}%`;
      }
    }
  } catch (error) {
    checks.disk.status = 'fail';
    checks.disk.message = error instanceof Error ? error.message : 'Failed to check disk space';
  }

  // Memory Check (Linux only)
  try {
    const memInfo = await fs.readFile('/proc/meminfo', 'utf8');
    const totalMatch = memInfo.match(/MemTotal:\s+(\d+)/);
    const availableMatch = memInfo.match(/MemAvailable:\s+(\d+)/);

    if (totalMatch && availableMatch) {
      const total = parseInt(totalMatch[1], 10) * 1024; // Convert from KB to bytes
      const available = parseInt(availableMatch[1], 10) * 1024;
      const used = total - available;
      const usagePercent = Math.round((used / total) * 100);

      checks.memory = {
        status: usagePercent >= 95 ? 'fail' : usagePercent >= 85 ? 'warning' : 'pass',
        usagePercent,
      };
    }
  } catch {
    // Memory check is optional, ignore errors
  }

  // Determine overall status
  const hasFail = Object.values(checks).some((check) => check?.status === 'fail');
  const hasWarning = Object.values(checks).some((check) => check?.status === 'warning');

  let status: DeepHealthResponse['status'] = 'healthy';
  if (hasFail) {
    status = 'unhealthy';
  } else if (hasWarning) {
    status = 'degraded';
  }

  const response: DeepHealthResponse = {
    status,
    checks,
    timestamp: new Date().toISOString(),
  };

  return NextResponse.json(response, { status: hasFail ? 503 : 200 });
}
