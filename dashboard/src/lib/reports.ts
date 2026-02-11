import { promises as fs } from 'fs';
import path from 'path';
import { glob } from 'glob';
import type { HealthReport, NodeReport } from './types';

const REPORTS_DIR = path.join(process.cwd(), '..', 'reports');

export async function getLatestReport(): Promise<HealthReport | null> {
  try {
    const pattern = path.join(REPORTS_DIR, 'node-health-*.json');
    const files = await glob(pattern);
    
    if (files.length === 0) {
      return null;
    }
    
    // Sort by filename (date) descending
    files.sort().reverse();
    
    const latestFile = files[0];
    const content = await fs.readFile(latestFile, 'utf-8');
    return JSON.parse(content) as HealthReport;
  } catch (error) {
    console.error('Error reading latest report:', error);
    return null;
  }
}

export async function getReportByDate(date: string): Promise<HealthReport | null> {
  try {
    const filePath = path.join(REPORTS_DIR, `node-health-${date}.json`);
    const content = await fs.readFile(filePath, 'utf-8');
    return JSON.parse(content) as HealthReport;
  } catch (error) {
    console.error(`Error reading report for date ${date}:`, error);
    return null;
  }
}

export async function getNodeById(nodeId: string): Promise<NodeReport | null> {
  const report = await getLatestReport();
  if (!report) return null;
  
  return report.nodes.find(n => n.id === nodeId) || null;
}

export async function getAllReportDates(): Promise<string[]> {
  try {
    const pattern = path.join(REPORTS_DIR, 'node-health-*.json');
    const files = await glob(pattern);
    
    return files.map(f => {
      const match = path.basename(f).match(/node-health-(.+)\.json/);
      return match ? match[1] : '';
    }).filter(Boolean).sort().reverse();
  } catch (error) {
    console.error('Error getting report dates:', error);
    return [];
  }
}

export function calculateSummary(nodes: NodeReport[]) {
  const total = nodes.length;
  const healthy = nodes.filter(n => n.status === 'healthy').length;
  const warning = nodes.filter(n => n.status === 'syncing' || n.status === 'degraded').length;
  const critical = nodes.filter(n => n.status === 'offline').length;
  
  const avgSyncProgress = nodes.length > 0
    ? nodes.reduce((sum, n) => sum + n.metrics.syncProgress, 0) / nodes.length
    : 0;
  
  return { total, healthy, warning, critical, avgSyncProgress };
}
