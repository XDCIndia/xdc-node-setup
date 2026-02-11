'use client';

import { useEffect, useState } from 'react';

interface ProgressBarProps {
  value: number;
  max?: number;
  height?: number;
  showPercentage?: boolean;
  color?: string;
  gradient?: boolean;
  className?: string;
}

export default function ProgressBar({
  value,
  max = 100,
  height = 8,
  showPercentage = true,
  color,
  gradient = false,
  className = '',
}: ProgressBarProps) {
  const [animatedWidth, setAnimatedWidth] = useState(0);
  
  const percentage = Math.min(100, Math.max(0, (value / max) * 100));
  
  useEffect(() => {
    const timer = setTimeout(() => setAnimatedWidth(percentage), 100);
    return () => clearTimeout(timer);
  }, [percentage]);

  const getBarColor = () => {
    if (color) return color;
    if (percentage >= 90) return '#ff4444';
    if (percentage >= 75) return '#ffaa00';
    if (percentage >= 50) return '#1E90FF';
    return '#00ff88';
  };

  return (
    <div className={`w-full ${className}`}>
      <div
        className="w-full rounded-full overflow-hidden"
        style={{ 
          height,
          backgroundColor: '#2a2a50',
        }}
      >
        <div
          className="h-full rounded-full transition-all duration-1000 ease-out"
          style={{
            width: `${animatedWidth}%`,
            background: gradient 
              ? `linear-gradient(90deg, ${getBarColor()}80, ${getBarColor()})`
              : getBarColor(),
            boxShadow: `0 0 10px ${getBarColor()}40`,
          }}
        />
      </div>
      {showPercentage && (
        <div className="flex justify-between text-xs text-gray-400 mt-1">
          <span>{percentage.toFixed(1)}%</span>
          <span>{value.toLocaleString()} / {max.toLocaleString()}</span>
        </div>
      )}
    </div>
  );
}
