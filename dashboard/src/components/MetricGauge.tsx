'use client';

interface MetricGaugeProps {
  label: string;
  value: number;
  max?: number;
  showValue?: boolean;
}

export default function MetricGauge({ label, value, max = 100, showValue = true }: MetricGaugeProps) {
  const percentage = Math.min((value / max) * 100, 100);
  
  const getColor = (pct: number): string => {
    if (pct < 60) return 'bg-status-healthy';
    if (pct < 80) return 'bg-status-warning';
    return 'bg-status-critical';
  };

  return (
    <div className="flex flex-col items-center">
      <div className="relative w-12 h-12">
        <svg className="w-12 h-12 transform -rotate-90">
          <circle
            cx="24"
            cy="24"
            r="20"
            stroke="currentColor"
            strokeWidth="4"
            fill="transparent"
            className="text-xdc-border"
          />
          <circle
            cx="24"
            cy="24"
            r="20"
            stroke="currentColor"
            strokeWidth="4"
            fill="transparent"
            strokeDasharray={`${(percentage / 100) * 125.6} 125.6`}
            strokeLinecap="round"
            className={getColor(percentage).replace('bg-', 'text-')}
          />
        </svg>
        {showValue && (
          <div className="absolute inset-0 flex items-center justify-center">
            <span className="text-xs text-white font-medium">{Math.round(value)}%</span>
          </div>
        )}
      </div>
      <span className="text-xs text-gray-400 mt-1">{label}</span>
    </div>
  );
}
