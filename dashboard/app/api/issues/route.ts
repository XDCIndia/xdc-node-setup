/**
 * Issues API - Returns currently active issues
 * Module-level storage for tracking issues (no external DB needed)
 */

import { NextResponse } from 'next/server';
import { DetectedIssue } from '@/lib/issue-detector';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

// Module-level issue storage (keyed by issue type)
const activeIssues = new Map<string, DetectedIssue>();
let lastCheckTime = new Date().toISOString();

// Issue expiration time (30 minutes)
const ISSUE_EXPIRY_MS = 30 * 60 * 1000;

/**
 * Store or update detected issues
 * Called by the metrics endpoint after detection
 * Note: This is accessed via the global object to avoid Next.js route export restrictions
 */
declare global {
  var updateActiveIssues: ((issues: DetectedIssue[]) => void) | undefined;
}

function updateActiveIssues(issues: DetectedIssue[]): void {
  const now = Date.now();
  
  // Clear expired issues
  Array.from(activeIssues.entries()).forEach(([type, issue]) => {
    const issueTime = new Date(issue.detectedAt).getTime();
    if (now - issueTime > ISSUE_EXPIRY_MS) {
      activeIssues.delete(type);
    }
  });
  
  // Update with new detections
  for (const issue of issues) {
    activeIssues.set(issue.type, issue);
  }
  
  lastCheckTime = new Date().toISOString();
}

// Expose via global for other API routes to use
if (typeof global !== 'undefined') {
  global.updateActiveIssues = updateActiveIssues;
}

/**
 * GET /api/issues
 * Returns currently active issues
 */
export async function GET() {
  // Clean up expired issues before returning
  const now = Date.now();
  Array.from(activeIssues.entries()).forEach(([type, issue]) => {
    const issueTime = new Date(issue.detectedAt).getTime();
    if (now - issueTime > ISSUE_EXPIRY_MS) {
      activeIssues.delete(type);
    }
  });
  
  const issues = Array.from(activeIssues.values());
  
  // Sort by severity: critical > high > medium > low
  const severityOrder = { critical: 0, high: 1, medium: 2, low: 3 };
  issues.sort((a, b) => severityOrder[a.severity] - severityOrder[b.severity]);
  
  return NextResponse.json({
    issues,
    count: issues.length,
    lastCheck: lastCheckTime,
  });
}
