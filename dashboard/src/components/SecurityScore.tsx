'use client';

interface SecurityScoreProps {
  score: number;
  max?: number;
  size?: 'sm' | 'md' | 'lg';
  showLabel?: boolean;
}

export default function SecurityScore({ score, max = 100, size = 'md', showLabel = true }: SecurityScoreProps) {
  const percentage = Math.min((score / max) * 100, 100);
  
  const getColor = (pct: number): string => {
    if (pct >= 80) return 'text-status-healthy';
    if (pct >= 60) return 'text-status-warning';
    return 'text-status-critical';
  };

  const getGradient = (pct: number): string => {
    if (pct >= 80) return 'stroke-status-healthy';
    if (pct >= 60) return 'stroke-status-warning';
    return 'stroke-status-critical';
  };

  const sizeConfig = {
    sm: { width: 60, stroke: 6, fontSize: 'text-sm' },
    md: { width: 100, stroke: 8, fontSize: 'text-xl' },
    lg: { width: 140, stroke: 10, fontSize: 'text-3xl' },
  };

  const config = sizeConfig[size];
  const radius = (config.width - config.stroke) / 2;
  const circumference = radius * 2 * Math.PI;
  const offset = circumference - (percentage / 100) * circumference;

  return (
    <div className="flex flex-col items-center">
      <div className="relative" style={{ width: config.width, height: config.width }}>
        <svg
          className="transform -rotate-90"
          width={config.width}
          height={config.width}
        >
          {/* Background circle */}
          <circle
            cx={config.width / 2}
            cy={config.width / 2}
            r={radius}
            strokeWidth={config.stroke}
            fill="transparent"
            className="stroke-xdc-border"
          />
          {/* Progress circle */}
          <circle
            cx={config.width / 2}
            cy={config.width / 2}
            r={radius}
            strokeWidth={config.stroke}
            fill="transparent"
            strokeLinecap="round"
            strokeDasharray={circumference}
            strokeDashoffset={offset}
            className={`${getGradient(percentage)} transition-all duration-500`}
          />
        </svg>
        <div className="absolute inset-0 flex items-center justify-center">
          <span className={`${config.fontSize} font-bold ${getColor(percentage)}`}>
            {Math.round(score)}
          </span>
        </div>
      </div>
      {showLabel && (
        <span className="text-sm text-gray-400 mt-2">Security Score</span>
      )}
    </div>
  );
}
