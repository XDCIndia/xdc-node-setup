'use client';

import { ReactNode } from 'react';

interface MetricCardProps {
  title: string;
  children: ReactNode;
  icon?: ReactNode;
  className?: string;
  loading?: boolean;
}

export default function MetricCard({
  title,
  children,
  icon,
  className = '',
  loading = false,
}: MetricCardProps) {
  return (
    <div className={`card-premium p-4 ${className}`}>
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          {icon && (
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[#1E90FF]/20 to-[#00D4FF]/20 flex items-center justify-center">
              <span className="text-[#1E90FF]">{icon}</span>
            </div>
          )}
          <h3 className="text-sm font-medium text-[#8B8CA7]">{title}</h3>
        </div>
        {loading && (
          <div className="w-4 h-4 border-2 border-[#1E90FF] border-t-transparent rounded-full animate-spin" />
        )}
      </div>
      <div>{children}</div>
    </div>
  );
}
