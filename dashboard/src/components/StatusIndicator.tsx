'use client';

interface StatusIndicatorProps {
  status: 'healthy' | 'syncing' | 'degraded' | 'offline';
  size?: 'sm' | 'md' | 'lg';
}

const statusConfig = {
  healthy: {
    color: 'bg-status-healthy',
    textColor: 'text-status-healthy',
    label: 'Healthy',
    pulse: false,
  },
  syncing: {
    color: 'bg-status-warning',
    textColor: 'text-status-warning',
    label: 'Syncing',
    pulse: true,
  },
  degraded: {
    color: 'bg-status-warning',
    textColor: 'text-status-warning',
    label: 'Degraded',
    pulse: false,
  },
  offline: {
    color: 'bg-status-critical',
    textColor: 'text-status-critical',
    label: 'Offline',
    pulse: false,
  },
};

const sizeConfig = {
  sm: { dot: 'w-2 h-2', text: 'text-xs' },
  md: { dot: 'w-3 h-3', text: 'text-sm' },
  lg: { dot: 'w-4 h-4', text: 'text-base' },
};

export default function StatusIndicator({ status, size = 'md' }: StatusIndicatorProps) {
  const config = statusConfig[status];
  const sizes = sizeConfig[size];

  return (
    <div className="flex items-center gap-2">
      <span className="relative flex">
        <span
          className={`${sizes.dot} rounded-full ${config.color} ${
            config.pulse ? 'animate-pulse' : ''
          }`}
        />
        {config.pulse && (
          <span
            className={`absolute inline-flex h-full w-full rounded-full ${config.color} opacity-75 animate-ping`}
          />
        )}
      </span>
      <span className={`${sizes.text} font-medium ${config.textColor}`}>
        {config.label}
      </span>
    </div>
  );
}
