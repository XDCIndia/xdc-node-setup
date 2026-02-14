import { NextResponse } from 'next/server';
import fs from 'fs';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

const HEARTBEAT_FILE = '/tmp/skynet-heartbeat.json';
const SKYNET_CONF = '/etc/xdc-node/skynet.conf';

interface HeartbeatData {
  lastHeartbeat?: string;
  status?: string;
  skynetUrl?: string;
  nodeId?: string;
  nodeName?: string;
  error?: string;
}

interface HeartbeatResponse {
  enabled: boolean;
  connected: boolean;
  lastHeartbeat: string | null;
  skynetUrl: string | null;
  nodeId: string | null;
  nodeName: string | null;
  error: string | null;
  statusText: string;
  lastHeartbeatSeconds: number | null;
}

export async function GET() {
  try {
    // Check if SkyNet is enabled by reading config
    let skynetEnabled = false;
    let configUrl = null;
    
    try {
      if (fs.existsSync(SKYNET_CONF)) {
        const config = fs.readFileSync(SKYNET_CONF, 'utf-8');
        skynetEnabled = config.includes('SKYNET_API_URL') && !config.includes('#SKYNET_API_URL');
        const urlMatch = config.match(/SKYNET_API_URL=["']?([^"'\n]+)["']?/);
        if (urlMatch) configUrl = urlMatch[1];
      }
    } catch (err) {
      console.error('Error reading SkyNet config:', err);
    }

    if (!skynetEnabled) {
      return NextResponse.json({
        enabled: false,
        connected: false,
        lastHeartbeat: null,
        skynetUrl: null,
        nodeId: null,
        nodeName: null,
        error: null,
        statusText: 'disabled',
        lastHeartbeatSeconds: null,
      } as HeartbeatResponse);
    }

    // Read heartbeat status file
    let heartbeatData: HeartbeatData = {};
    
    try {
      if (fs.existsSync(HEARTBEAT_FILE)) {
        const content = fs.readFileSync(HEARTBEAT_FILE, 'utf-8');
        heartbeatData = JSON.parse(content);
      }
    } catch (err) {
      console.error('Error reading heartbeat file:', err);
    }

    const lastHeartbeat = heartbeatData.lastHeartbeat || null;
    const status = heartbeatData.status || 'unknown';
    const error = heartbeatData.error || null;
    
    // Calculate time since last heartbeat
    let lastHeartbeatSeconds: number | null = null;
    let statusText = 'disconnected';
    let connected = false;
    
    if (lastHeartbeat) {
      const lastTime = new Date(lastHeartbeat).getTime();
      const now = Date.now();
      lastHeartbeatSeconds = Math.floor((now - lastTime) / 1000);
      
      // Determine connection status
      if (status === 'success') {
        if (lastHeartbeatSeconds < 120) {
          statusText = 'connected';
          connected = true;
        } else if (lastHeartbeatSeconds < 300) {
          statusText = 'pending';
        } else {
          statusText = 'offline';
        }
      } else if (status === 'failed') {
        statusText = 'error';
      }
    }

    return NextResponse.json({
      enabled: true,
      connected,
      lastHeartbeat,
      skynetUrl: heartbeatData.skynetUrl || configUrl,
      nodeId: heartbeatData.nodeId || null,
      nodeName: heartbeatData.nodeName || null,
      error,
      statusText,
      lastHeartbeatSeconds,
    } as HeartbeatResponse);
  } catch (error) {
    console.error('Error fetching heartbeat status:', error);
    return NextResponse.json(
      { 
        error: 'Failed to fetch heartbeat status',
        enabled: false,
        connected: false,
        lastHeartbeat: null,
        skynetUrl: null,
        nodeId: null,
        nodeName: null,
        statusText: 'error',
        lastHeartbeatSeconds: null,
      } as HeartbeatResponse,
      { status: 500 }
    );
  }
}
