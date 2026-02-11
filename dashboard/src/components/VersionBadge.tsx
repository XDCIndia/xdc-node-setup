'use client';

interface VersionBadgeProps {
  current: string;
  latest: string;
}

export default function VersionBadge({ current, latest }: VersionBadgeProps) {
  const isOutdated = current !== latest;
  
  return (
    <div className="flex items-center gap-1">
      <span
        className={`px-2 py-0.5 rounded text-xs font-mono ${
          isOutdated
            ? 'bg-status-critical/20 text-status-critical border border-status-critical/30'
            : 'bg-status-healthy/20 text-status-healthy border border-status-healthy/30'
        }`}
      >
        {current}
      </span>
      {isOutdated && (
        <span className="text-xs text-gray-500">→ {latest}</span>
      )}
    </div>
  );
}
