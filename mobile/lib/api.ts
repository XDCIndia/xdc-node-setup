/**
 * XDC Node Monitor - API Client
 * Connects to SkyNet API for node management
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import type { Node, NodeDetail } from '@/types/node';
import type { Alert } from '@/types/alert';
import type { DashboardOverview } from '@/types/dashboard';

const DEFAULT_API_ENDPOINT = 'https://api.skyskynet.xdcindia.com';
const API_TIMEOUT = 30000;

class ApiClient {
  private baseUrl: string = DEFAULT_API_ENDPOINT;
  private apiKey: string | null = null;

  constructor() {
    this.loadConfig();
  }

  private async loadConfig() {
    try {
      const endpoint = await AsyncStorage.getItem('api_endpoint');
      const key = await AsyncStorage.getItem('api_key');
      if (endpoint) this.baseUrl = endpoint;
      if (key) this.apiKey = key;
    } catch (error) {
      console.error('Failed to load API config:', error);
    }
  }

  async setEndpoint(endpoint: string) {
    this.baseUrl = endpoint;
    await AsyncStorage.setItem('api_endpoint', endpoint);
  }

  async setApiKey(key: string) {
    this.apiKey = key;
    await AsyncStorage.setItem('api_key', key);
  }

  private async request<T>(
    path: string,
    options: RequestInit = {}
  ): Promise<T> {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), API_TIMEOUT);

    try {
      const headers: HeadersInit = {
        'Content-Type': 'application/json',
        ...(this.apiKey && { Authorization: `Bearer ${this.apiKey}` }),
        ...options.headers,
      };

      const response = await fetch(`${this.baseUrl}${path}`, {
        ...options,
        headers,
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        const error = await response.json().catch(() => ({}));
        throw new ApiError(
          error.message || `HTTP ${response.status}`,
          response.status
        );
      }

      return response.json();
    } catch (error) {
      clearTimeout(timeoutId);
      if (error instanceof ApiError) throw error;
      if (error instanceof Error && error.name === 'AbortError') {
        throw new ApiError('Request timeout', 408);
      }
      throw new ApiError('Network error', 0);
    }
  }

  // ============ Dashboard ============

  async getDashboard(): Promise<DashboardOverview> {
    return this.request<DashboardOverview>('/api/v1/dashboard');
  }

  // ============ Nodes ============

  async getNodes(): Promise<Node[]> {
    return this.request<Node[]>('/api/v1/nodes');
  }

  async getNode(id: string): Promise<NodeDetail> {
    return this.request<NodeDetail>(`/api/v1/nodes/${id}`);
  }

  async restartNode(id: string): Promise<{ success: boolean; message: string }> {
    return this.request(`/api/v1/nodes/${id}/restart`, {
      method: 'POST',
    });
  }

  async stopNode(id: string): Promise<{ success: boolean; message: string }> {
    return this.request(`/api/v1/nodes/${id}/stop`, {
      method: 'POST',
    });
  }

  async startNode(id: string): Promise<{ success: boolean; message: string }> {
    return this.request(`/api/v1/nodes/${id}/start`, {
      method: 'POST',
    });
  }

  async addPeer(
    nodeId: string,
    enode: string
  ): Promise<{ success: boolean; message: string }> {
    return this.request(`/api/v1/nodes/${nodeId}/peers`, {
      method: 'POST',
      body: JSON.stringify({ enode }),
    });
  }

  async removePeer(
    nodeId: string,
    enode: string
  ): Promise<{ success: boolean; message: string }> {
    return this.request(`/api/v1/nodes/${nodeId}/peers`, {
      method: 'DELETE',
      body: JSON.stringify({ enode }),
    });
  }

  async getNodeLogs(
    nodeId: string,
    options?: { lines?: number; since?: string }
  ): Promise<{ logs: string[] }> {
    const params = new URLSearchParams();
    if (options?.lines) params.set('lines', options.lines.toString());
    if (options?.since) params.set('since', options.since);
    const query = params.toString();
    return this.request(`/api/v1/nodes/${nodeId}/logs${query ? `?${query}` : ''}`);
  }

  // ============ Alerts ============

  async getAlerts(): Promise<Alert[]> {
    return this.request<Alert[]>('/api/v1/alerts');
  }

  async dismissAlert(id: string): Promise<{ success: boolean }> {
    return this.request(`/api/v1/alerts/${id}/dismiss`, {
      method: 'POST',
    });
  }

  async clearAllAlerts(): Promise<{ success: boolean }> {
    return this.request('/api/v1/alerts/clear', {
      method: 'POST',
    });
  }

  // ============ Push Notifications ============

  async registerPushToken(token: string, platform: 'ios' | 'android'): Promise<void> {
    await this.request('/api/v1/push/register', {
      method: 'POST',
      body: JSON.stringify({ token, platform }),
    });
  }

  async unregisterPushToken(token: string): Promise<void> {
    await this.request('/api/v1/push/unregister', {
      method: 'POST',
      body: JSON.stringify({ token }),
    });
  }

  // ============ Network Stats ============

  async getNetworkStats(): Promise<{
    totalNodes: number;
    activeValidators: number;
    totalTransactions: number;
    currentEpoch: number;
    blockTime: number;
  }> {
    return this.request('/api/v1/network/stats');
  }

  // ============ Health Check ============

  async healthCheck(): Promise<{ status: 'ok' | 'degraded' | 'down'; version: string }> {
    return this.request('/api/v1/health');
  }
}

export class ApiError extends Error {
  constructor(
    message: string,
    public statusCode: number
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

// Export singleton instance
export const api = new ApiClient();

// Export class for testing
export { ApiClient };
