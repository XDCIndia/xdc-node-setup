'use client';

import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from 'recharts';
import type { HistoricalMetric } from '@/lib/types';

interface BlockHeightChartProps {
  data: HistoricalMetric[];
  metric?: 'blockHeight' | 'peerCount' | 'cpuUsage' | 'ramUsage' | 'diskUsage';
  title?: string;
  color?: string;
}

export default function BlockHeightChart({
  data,
  metric = 'blockHeight',
  title = 'Block Height',
  color = '#1F4CED',
}: BlockHeightChartProps) {
  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp);
    return date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
  };

  const formatValue = (value: number) => {
    if (metric === 'blockHeight') {
      return value.toLocaleString();
    }
    if (['cpuUsage', 'ramUsage', 'diskUsage'].includes(metric)) {
      return `${value.toFixed(1)}%`;
    }
    return value.toString();
  };

  const chartData = data.map((d) => ({
    timestamp: formatTimestamp(d.timestamp),
    value: d[metric],
  }));

  return (
    <div className="bg-xdc-card border border-xdc-border rounded-xl p-4">
      <h3 className="text-white font-medium mb-4">{title}</h3>
      <div className="h-64">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={chartData}>
            <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3e" />
            <XAxis
              dataKey="timestamp"
              tick={{ fill: '#9ca3af', fontSize: 12 }}
              tickLine={{ stroke: '#2a2a3e' }}
            />
            <YAxis
              tick={{ fill: '#9ca3af', fontSize: 12 }}
              tickLine={{ stroke: '#2a2a3e' }}
              tickFormatter={formatValue}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: '#1a1a2e',
                border: '1px solid #2a2a3e',
                borderRadius: '8px',
              }}
              labelStyle={{ color: '#9ca3af' }}
              itemStyle={{ color: color }}
              formatter={(value: number) => [formatValue(value), title]}
            />
            <Line
              type="monotone"
              dataKey="value"
              stroke={color}
              strokeWidth={2}
              dot={false}
              activeDot={{ r: 4, fill: color }}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
