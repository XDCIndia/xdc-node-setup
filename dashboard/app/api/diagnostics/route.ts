import { NextResponse } from 'next/server';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

function getRpcUrl() { return process.env.RPC_URL || 'http://xdc-node:8545'; }
function getContainerName() { return process.env.CONTAINER_NAME || 'xdc-node'; }

export interface DiagnosticResult {
  name: string;
  category: string;
  status: 'pass' | 'warn' | 'fail';
  message: string;
  details?: string;
}

async function checkContainerStatus(): Promise<DiagnosticResult> {
  try {
    const { stdout } = await execAsync(`docker inspect --format='{{.State.Status}}' ${getContainerName()} 2>/dev/null || echo "not_found"`);
    const status = stdout.trim();
    
    if (status === 'running') {
      return {
        name: 'Container Status',
        category: 'infrastructure',
        status: 'pass',
        message: 'Container is running',
        details: `Status: ${status}`
      };
    } else if (status === 'not_found') {
      return {
        name: 'Container Status',
        category: 'infrastructure',
        status: 'fail',
        message: 'Container not found',
        details: `Container ${getContainerName()} does not exist`
      };
    } else {
      return {
        name: 'Container Status',
        category: 'infrastructure',
        status: 'fail',
        message: `Container is ${status}`,
        details: `Status: ${status}`
      };
    }
  } catch (error) {
    return {
      name: 'Container Status',
      category: 'infrastructure',
      status: 'fail',
      message: 'Failed to check container status',
      details: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

async function checkRpcHealth(): Promise<DiagnosticResult> {
  try {
    const start = Date.now();
    const res = await fetch(getRpcUrl(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', method: 'eth_blockNumber', params: [], id: 1 }),
      signal: AbortSignal.timeout(5000),
    });
    
    const responseTime = Date.now() - start;
    
    if (!res.ok) {
      return {
        name: 'RPC Health',
        category: 'node',
        status: 'fail',
        message: `RPC returned HTTP ${res.status}`,
        details: `Response time: ${responseTime}ms`
      };
    }
    
    const data = await res.json();
    
    if (data.error) {
      return {
        name: 'RPC Health',
        category: 'node',
        status: 'warn',
        message: 'RPC responded with error',
        details: data.error.message || 'Unknown RPC error'
      };
    }
    
    const blockNumber = parseInt(data.result, 16);
    
    return {
      name: 'RPC Health',
      category: 'node',
      status: 'pass',
      message: 'RPC is responsive',
      details: `Current block: ${blockNumber.toLocaleString()} | Response time: ${responseTime}ms`
    };
  } catch (error) {
    return {
      name: 'RPC Health',
      category: 'node',
      status: 'fail',
      message: 'RPC is not responding',
      details: error instanceof Error ? error.message : 'Connection failed'
    };
  }
}

async function checkPeerConnectivity(): Promise<DiagnosticResult> {
  try {
    const res = await fetch(getRpcUrl(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', method: 'admin_peers', params: [], id: 1 }),
      signal: AbortSignal.timeout(5000),
    });
    
    if (!res.ok) {
      return {
        name: 'Peer Connectivity',
        category: 'network',
        status: 'warn',
        message: 'Cannot fetch peer list',
        details: `HTTP ${res.status}`
      };
    }
    
    const data = await res.json();
    const peerCount = Array.isArray(data.result) ? data.result.length : 0;
    
    if (peerCount === 0) {
      return {
        name: 'Peer Connectivity',
        category: 'network',
        status: 'warn',
        message: 'No peers connected',
        details: 'Node has no active peer connections'
      };
    } else if (peerCount < 3) {
      return {
        name: 'Peer Connectivity',
        category: 'network',
        status: 'warn',
        message: `Low peer count (${peerCount})`,
        details: `Connected to ${peerCount} peers. Recommended: 5+ peers`
      };
    } else {
      return {
        name: 'Peer Connectivity',
        category: 'network',
        status: 'pass',
        message: `Connected to ${peerCount} peers`,
        details: `Healthy peer connectivity`
      };
    }
  } catch (error) {
    return {
      name: 'Peer Connectivity',
      category: 'network',
      status: 'warn',
      message: 'Failed to check peers',
      details: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

async function checkSyncStatus(): Promise<DiagnosticResult> {
  try {
    const res = await fetch(getRpcUrl(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', method: 'eth_syncing', params: [], id: 1 }),
      signal: AbortSignal.timeout(5000),
    });
    
    if (!res.ok) {
      return {
        name: 'Sync Status',
        category: 'node',
        status: 'warn',
        message: 'Cannot check sync status',
        details: `HTTP ${res.status}`
      };
    }
    
    const data = await res.json();
    
    if (data.result === false) {
      return {
        name: 'Sync Status',
        category: 'node',
        status: 'pass',
        message: 'Node is fully synced',
        details: 'Not currently syncing'
      };
    } else if (typeof data.result === 'object') {
      const current = parseInt(data.result.currentBlock, 16);
      const highest = parseInt(data.result.highestBlock, 16);
      const progress = highest > 0 ? ((current / highest) * 100).toFixed(2) : '0.00';
      
      return {
        name: 'Sync Status',
        category: 'node',
        status: 'warn',
        message: `Syncing: ${progress}%`,
        details: `Current: ${current.toLocaleString()} | Highest: ${highest.toLocaleString()}`
      };
    } else {
      return {
        name: 'Sync Status',
        category: 'node',
        status: 'pass',
        message: 'Sync status unknown',
        details: 'RPC returned unexpected response'
      };
    }
  } catch (error) {
    return {
      name: 'Sync Status',
      category: 'node',
      status: 'warn',
      message: 'Failed to check sync status',
      details: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

async function checkDiskUsage(): Promise<DiagnosticResult> {
  try {
    const { stdout } = await execAsync("df -h / | tail -1 | awk '{print $5,$4}'");
    const [usedPercent, available] = stdout.trim().split(' ');
    const usedNum = parseInt(usedPercent.replace('%', ''));
    
    if (usedNum >= 90) {
      return {
        name: 'Disk Usage',
        category: 'resources',
        status: 'fail',
        message: `Disk critically full (${usedPercent})`,
        details: `Available: ${available}`
      };
    } else if (usedNum >= 80) {
      return {
        name: 'Disk Usage',
        category: 'resources',
        status: 'warn',
        message: `Disk usage high (${usedPercent})`,
        details: `Available: ${available}`
      };
    } else {
      return {
        name: 'Disk Usage',
        category: 'resources',
        status: 'pass',
        message: `Disk usage: ${usedPercent}`,
        details: `Available: ${available}`
      };
    }
  } catch (error) {
    return {
      name: 'Disk Usage',
      category: 'resources',
      status: 'warn',
      message: 'Failed to check disk usage',
      details: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

async function checkMemoryUsage(): Promise<DiagnosticResult> {
  try {
    const { stdout } = await execAsync("free | grep Mem | awk '{printf \"%.1f\", $3/$2 * 100.0}'");
    const usedPercent = parseFloat(stdout.trim());
    
    const { stdout: memDetails } = await execAsync("free -h | grep Mem | awk '{print $2,$3,$7}'");
    const [total, used, available] = memDetails.trim().split(' ');
    
    if (usedPercent >= 90) {
      return {
        name: 'Memory Usage',
        category: 'resources',
        status: 'fail',
        message: `Memory critically high (${usedPercent.toFixed(1)}%)`,
        details: `Total: ${total} | Used: ${used} | Available: ${available}`
      };
    } else if (usedPercent >= 80) {
      return {
        name: 'Memory Usage',
        category: 'resources',
        status: 'warn',
        message: `Memory usage high (${usedPercent.toFixed(1)}%)`,
        details: `Total: ${total} | Used: ${used} | Available: ${available}`
      };
    } else {
      return {
        name: 'Memory Usage',
        category: 'resources',
        status: 'pass',
        message: `Memory usage: ${usedPercent.toFixed(1)}%`,
        details: `Total: ${total} | Used: ${used} | Available: ${available}`
      };
    }
  } catch (error) {
    return {
      name: 'Memory Usage',
      category: 'resources',
      status: 'warn',
      message: 'Failed to check memory usage',
      details: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

async function checkPortBindings(): Promise<DiagnosticResult> {
  const ports = [30303, 8545];
  const results: string[] = [];
  let allPass = true;
  
  for (const port of ports) {
    try {
      const { stdout } = await execAsync(`ss -tlnp | grep ':${port}' | head -1 || netstat -tlnp 2>/dev/null | grep ':${port}' | head -1 || echo "not_listening"`);
      
      if (stdout.includes('not_listening')) {
        results.push(`Port ${port}: Not listening`);
        allPass = false;
      } else {
        results.push(`Port ${port}: Listening`);
      }
    } catch {
      results.push(`Port ${port}: Check failed`);
      allPass = false;
    }
  }
  
  return {
    name: 'Port Bindings',
    category: 'network',
    status: allPass ? 'pass' : 'warn',
    message: allPass ? 'Required ports open' : 'Some ports not listening',
    details: results.join(' | ')
  };
}

async function checkConfig(): Promise<DiagnosticResult> {
  const configPaths = [
    '/work/xdcchain/config.toml',
    '/data/config.toml',
    './config.toml'
  ];
  
  for (const path of configPaths) {
    try {
      const { stdout } = await execAsync(`test -f ${path} && echo "exists" || echo "not_found"`);
      
      if (stdout.trim() === 'exists') {
        // Check if config is valid by looking for required sections
        const { stdout: configContent } = await execAsync(`cat ${path} | head -50 || echo ""`);
        
        const hasRequiredFields = configContent.includes('[Node]') || 
                                   configContent.includes('DataDir') ||
                                   configContent.includes('HTTPHost');
        
        return {
          name: 'Config Check',
          category: 'configuration',
          status: hasRequiredFields ? 'pass' : 'warn',
          message: hasRequiredFields ? 'Config file valid' : 'Config file may be incomplete',
          details: `Found at: ${path}`
        };
      }
    } catch {
      // Continue to next path
    }
  }
  
  return {
    name: 'Config Check',
    category: 'configuration',
    status: 'warn',
    message: 'Config file not found',
    details: 'Checked: ' + configPaths.join(', ')
  };
}

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export async function GET() {
  try {
    const results = await Promise.all([
      checkContainerStatus(),
      checkRpcHealth(),
      checkPeerConnectivity(),
      checkSyncStatus(),
      checkDiskUsage(),
      checkMemoryUsage(),
      checkPortBindings(),
      checkConfig(),
    ]);

    const summary = {
      pass: results.filter(r => r.status === 'pass').length,
      warn: results.filter(r => r.status === 'warn').length,
      fail: results.filter(r => r.status === 'fail').length,
    };

    return NextResponse.json({
      results,
      summary,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Diagnostics error:', error);
    return NextResponse.json(
      { error: 'Failed to run diagnostics', results: [] },
      { status: 500 }
    );
  }
}
