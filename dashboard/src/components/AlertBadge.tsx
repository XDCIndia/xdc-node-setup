'use client';

import type { AlertLevel } from '@/lib/types';

interface AlertBadgeProps {
  level: AlertLevel;
  size?: 'sm' | 'md' | 'lg';
}

const levelConfig = {
  critical: {
    bg: 'bg-status-critical/20',
    text: 'text-status-critical',
    border: 'border-status-critical/50',
    icon: '🚨',
  },
  warning: {
    bg: 'bg-status-warning/20',
    text: 'text-status-warning',
    border: 'border-status-warning/50',
    icon: '⚠️',
  },
  info: {
    bg: 'bg-status-info/20',
    text: 'text-status-info',
    border: 'border-status-info/50',
    icon: 'ℹ️',
  },
};

const sizeConfig = {
  sm: 'px-2 py-0.5 text-xs',
  md: 'px-2.5 py-1 text-sm',
  lg: 'px-3 py-1.5 text-base',
};

export default function AlertBadge({ level, size = 'md' }: AlertBadgeProps) {
  const config = levelConfig[level];
  const sizeClass = sizeConfig[size];

  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full border ${config.bg} ${config.text} ${config.border} ${sizeClass} font-medium capitalize`}
    >
      <span>{config.icon}</span>
      {level}
    </span>
  );
}
