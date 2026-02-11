'use client';

import { useMemo } from 'react';

interface SparklineChartProps {
  data: number[];
  width?: number;
  height?: number;
  color?: string;
  fillOpacity?: number;
  showMinMax?: boolean;
}

export default function SparklineChart({
  data,
  width = 200,
  height = 60,
  color = '#1E90FF',
  fillOpacity = 0.3,
  showMinMax = true,
}: SparklineChartProps) {
  const { path, areaPath, min, max, last } = useMemo(() => {
    if (!data || data.length === 0) {
      return { path: '', areaPath: '', min: 0, max: 0, last: 0 };
    }

    const minVal = Math.min(...data);
    const maxVal = Math.max(...data);
    const range = maxVal - minVal || 1;
    const padding = 4;
    
    const chartWidth = width - padding * 2;
    const chartHeight = height - padding * 2;

    const points = data.map((value, index) => {
      const x = padding + (index / (data.length - 1 || 1)) * chartWidth;
      const y = padding + chartHeight - ((value - minVal) / range) * chartHeight;
      return { x, y, value };
    });

    // Create smooth bezier curve
    let path = `M ${points[0].x} ${points[0].y}`;
    
    for (let i = 1; i < points.length; i++) {
      const prev = points[i - 1];
      const curr = points[i];
      const cpx1 = prev.x + (curr.x - prev.x) / 3;
      const cpx2 = curr.x - (curr.x - prev.x) / 3;
      path += ` C ${cpx1} ${prev.y}, ${cpx2} ${curr.y}, ${curr.x} ${curr.y}`;
    }

    // Create area path
    const areaPath = `${path} L ${points[points.length - 1].x} ${height} L ${points[0].x} ${height} Z`;

    return {
      path,
      areaPath,
      min: minVal,
      max: maxVal,
      last: data[data.length - 1],
    };
  }, [data, width, height]);

  if (!data || data.length === 0) {
    return (
      <div 
        className="flex items-center justify-center text-gray-500 text-xs"
        style={{ width, height }}
      >
        No data
      </div>
    );
  }

  return (
    <div className="relative">
      <svg width={width} height={height} className="overflow-visible">
        <defs>
          <linearGradient id={`gradient-${color.replace('#', '')}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity={fillOpacity} />
            <stop offset="100%" stopColor={color} stopOpacity={0} />
          </linearGradient>
        </defs>
        
        {/* Area fill */}
        <path
          d={areaPath}
          fill={`url(#gradient-${color.replace('#', '')})`}
          stroke="none"
        />
        
        {/* Line */}
        <path
          d={path}
          fill="none"
          stroke={color}
          strokeWidth={2}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
        
        {/* Last value dot */}
        {data.length > 0 && (
          <circle
            cx={width - 4}
            cy={(() => {
              const minVal = Math.min(...data);
              const maxVal = Math.max(...data);
              const range = maxVal - minVal || 1;
              const chartHeight = height - 8;
              return 4 + chartHeight - ((last - minVal) / range) * chartHeight;
            })()}
            r={4}
            fill={color}
            stroke="#0a0a1a"
            strokeWidth={2}
          />
        )}
      </svg>
      
      {showMinMax && (
        <div className="flex justify-between text-[10px] text-gray-500 mt-1">
          <span>Min: {min.toFixed(2)}</span>
          <span>Max: {max.toFixed(2)}</span>
        </div>
      )}
    </div>
  );
}
