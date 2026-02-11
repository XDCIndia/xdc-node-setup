'use client';

import { useEffect, useState } from 'react';

interface GaugeProps {
  value: number;
  max?: number;
  size?: number;
  strokeWidth?: number;
  color?: string;
  label?: string;
  sublabel?: string;
}

export default function Gauge({
  value,
  max = 100,
  size = 120,
  strokeWidth = 10,
  color = '#1E90FF',
  label,
  sublabel,
}: GaugeProps) {
  const [animatedValue, setAnimatedValue] = useState(0);
  
  const percentage = Math.min(100, Math.max(0, (value / max) * 100));
  const radius = (size - strokeWidth) / 2;
  const circumference = radius * 2 * Math.PI;
  const offset = circumference - (percentage / 100) * circumference;
  
  // Determine color based on percentage
  const getColor = () => {
    if (percentage >= 80) return '#ff4444'; // Error - red
    if (percentage >= 60) return '#ffaa00'; // Warning - orange
    return color;
  };

  useEffect(() => {
    const timer = setTimeout(() => setAnimatedValue(percentage), 100);
    return () => clearTimeout(timer);
  }, [percentage]);

  const displayValue = label || `${Math.round(value)}${max === 100 ? '%' : ''}`;

  return (
    <div className="flex flex-col items-center">
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
        {/* Background circle */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke="#2a2a50"
          strokeWidth={strokeWidth}
        />
        {/* Progress arc */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          stroke={getColor()}
          strokeWidth={strokeWidth}
          strokeLinecap="round"
          strokeDasharray={circumference}
          strokeDashoffset={circumference - (animatedValue / 100) * circumference}
          transform={`rotate(-90 ${size / 2} ${size / 2})`}
          style={{
            transition: 'stroke-dashoffset 1s ease-out, stroke 0.3s ease',
          }}
        />
        {/* Center text */}
        <text
          x={size / 2}
          y={size / 2}
          textAnchor="middle"
          dominantBaseline="middle"
          fill="white"
          fontSize={size / 5}
          fontWeight="bold"
        >
          {displayValue}
        </text>
      </svg>
      {sublabel && (
        <span className="text-sm text-gray-400 mt-1">{sublabel}</span>
      )}
    </div>
  );
}
