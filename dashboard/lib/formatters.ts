export function formatNumber(num: number): string {
  if (num === 0) return '0';
  if (!isFinite(num) || isNaN(num)) return '—';
  return num.toLocaleString('en-US', { maximumFractionDigits: 0 });
}

export function formatCompactNumber(num: number): string {
  if (num === 0) return '0';
  if (!isFinite(num) || isNaN(num)) return '—';
  if (num >= 1e9) return (num / 1e9).toFixed(2) + 'B';
  if (num >= 1e6) return (num / 1e6).toFixed(2) + 'M';
  if (num >= 1e3) return (num / 1e3).toFixed(2) + 'K';
  return num.toLocaleString();
}

export function formatBytes(bytes: number, decimals = 2): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const dm = decimals < 0 ? 0 : decimals;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

export function formatBytesPerSecond(bytes: number): string {
  return formatBytes(bytes) + '/s';
}

export function formatDuration(seconds: number): string {
  if (seconds < 60) return Math.floor(seconds) + 's';
  if (seconds < 3600) {
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return `${m}m ${s}s`;
  }
  if (seconds < 86400) {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    return `${h}h ${m}m`;
  }
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  return `${d}d ${h}h`;
}

export function formatDurationLong(seconds: number): string {
  if (!seconds || seconds <= 0) return '—';
  
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  
  const parts: string[] = [];
  if (days > 0) parts.push(`${days}d`);
  if (hours > 0) parts.push(`${hours}h`);
  if (minutes > 0) parts.push(`${minutes}m`);
  
  return parts.join(' ') || '< 1m';
}

export function formatPercentage(value: number, decimals = 1): string {
  return value.toFixed(decimals) + '%';
}

export function formatXDC(value: number): string {
  if (value >= 1e6) return (value / 1e6).toFixed(2) + 'M XDC';
  if (value >= 1e3) return (value / 1e3).toFixed(2) + 'K XDC';
  return value.toFixed(2) + ' XDC';
}

export function formatTimeAgo(date: string | Date): string {
  const now = new Date();
  const then = new Date(date);
  const diffMs = now.getTime() - then.getTime();
  const diffSec = Math.floor(diffMs / 1000);
  
  if (diffSec < 60) return 'just now';
  if (diffSec < 3600) return Math.floor(diffSec / 60) + 'm ago';
  if (diffSec < 86400) return Math.floor(diffSec / 3600) + 'h ago';
  return Math.floor(diffSec / 86400) + 'd ago';
}

// Color helpers for status
export function getSyncColor(percent: number): string {
  if (percent >= 99) return '#10B981';
  if (percent >= 90) return '#F59E0B';
  return '#1E90FF';
}

export function getUsageColor(percent: number): string {
  if (percent >= 80) return '#EF4444';
  if (percent >= 60) return '#F59E0B';
  return '#10B981';
}
