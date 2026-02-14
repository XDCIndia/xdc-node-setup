'use client';

import { useState, useEffect } from 'react';
import { DetectedIssue } from '@/lib/issue-detector';

interface IssuesResponse {
  issues: DetectedIssue[];
  count: number;
  lastCheck: string;
}

export default function IssueBanner() {
  const [issues, setIssues] = useState<DetectedIssue[]>([]);
  const [expanded, setExpanded] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Initial fetch
    fetchIssues();

    // Poll every 30 seconds
    const interval = setInterval(fetchIssues, 30000);
    return () => clearInterval(interval);
  }, []);

  const fetchIssues = async () => {
    try {
      const res = await fetch('/api/issues');
      const data: IssuesResponse = await res.json();
      setIssues(data.issues || []);
      setLoading(false);
    } catch (e) {
      console.error('Failed to fetch issues:', e);
      setLoading(false);
    }
  };

  if (loading) return null;
  if (issues.length === 0) return null;

  // Determine banner color based on highest severity
  const highestSeverity = issues[0]?.severity || 'low';
  const bannerColor = {
    critical: 'bg-red-600 border-red-700',
    high: 'bg-orange-600 border-orange-700',
    medium: 'bg-yellow-600 border-yellow-700',
    low: 'bg-blue-600 border-blue-700',
  }[highestSeverity];

  const textColor = 'text-white';

  return (
    <div className={`${bannerColor} ${textColor} border-b-2 shadow-lg`}>
      <div className="container mx-auto px-4 py-3">
        {/* Header */}
        <button
          onClick={() => setExpanded(!expanded)}
          className="w-full flex items-center justify-between hover:opacity-90 transition-opacity"
        >
          <div className="flex items-center gap-3">
            {/* Icon */}
            <svg
              className="w-6 h-6 flex-shrink-0"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
              />
            </svg>

            {/* Title */}
            <div className="text-left">
              <div className="font-bold text-lg">
                {issues.length} Active Issue{issues.length !== 1 ? 's' : ''} Detected
              </div>
              <div className="text-sm opacity-90">
                {highestSeverity.toUpperCase()} severity — Click to expand
              </div>
            </div>
          </div>

          {/* Expand/Collapse Icon */}
          <svg
            className={`w-5 h-5 transition-transform ${expanded ? 'rotate-180' : ''}`}
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M19 9l-7 7-7-7"
            />
          </svg>
        </button>

        {/* Expanded Issue List */}
        {expanded && (
          <div className="mt-4 space-y-3">
            {issues.map((issue, idx) => (
              <div
                key={`${issue.type}-${idx}`}
                className="bg-white bg-opacity-10 backdrop-blur-sm rounded-lg p-4 border border-white border-opacity-20"
              >
                <div className="flex items-start gap-3">
                  {/* Severity Badge */}
                  <div
                    className={`px-2 py-1 rounded text-xs font-bold uppercase flex-shrink-0 ${
                      issue.severity === 'critical'
                        ? 'bg-red-800 text-white'
                        : issue.severity === 'high'
                        ? 'bg-orange-800 text-white'
                        : issue.severity === 'medium'
                        ? 'bg-yellow-800 text-white'
                        : 'bg-blue-800 text-white'
                    }`}
                  >
                    {issue.severity}
                  </div>

                  {/* Issue Details */}
                  <div className="flex-1">
                    <div className="font-bold text-lg mb-1">{issue.title}</div>
                    <div className="text-sm opacity-90 mb-2">{issue.description}</div>
                    <div className="text-xs opacity-75">
                      Detected: {new Date(issue.detectedAt).toLocaleString()}
                    </div>

                    {/* Quick Diagnostics */}
                    <div className="mt-2 grid grid-cols-2 md:grid-cols-4 gap-2 text-xs">
                      <div>
                        <span className="opacity-75">Block:</span>{' '}
                        <span className="font-mono">{issue.diagnostics.blockHeight.toLocaleString()}</span>
                      </div>
                      <div>
                        <span className="opacity-75">Peers:</span>{' '}
                        <span className="font-mono">{issue.diagnostics.peers}</span>
                      </div>
                      <div>
                        <span className="opacity-75">CPU:</span>{' '}
                        <span className="font-mono">{issue.diagnostics.cpu}%</span>
                      </div>
                      <div>
                        <span className="opacity-75">Disk:</span>{' '}
                        <span className="font-mono">{issue.diagnostics.disk.toFixed(1)}%</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
