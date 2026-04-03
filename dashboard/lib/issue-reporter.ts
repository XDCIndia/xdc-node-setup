/**
 * Issue Reporter - Reports detected issues to SkyNet
 * Silent failures to ensure reporting never breaks the dashboard
 */

import { DetectedIssue } from './issue-detector';

const SKYNET_API_URL = process.env.SKYNET_API_URL || 'https://skynet.xdcindia.com/api/v1';
const SKYNET_API_KEY = process.env.SKYNET_API_KEY || '';
const SKYNET_NODE_ID = process.env.SKYNET_NODE_ID || '';

/**
 * Report detected issues to SkyNet
 * Fire and forget - never throws errors
 */
export async function reportIssues(issues: DetectedIssue[]): Promise<void> {
  // Skip if not configured or no issues
  if (!SKYNET_API_KEY || !SKYNET_NODE_ID || issues.length === 0) {
    return;
  }

  // Report each issue independently (one failure doesn't block others)
  for (const issue of issues) {
    try {
      await fetch(`${SKYNET_API_URL}/issues/report`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${SKYNET_API_KEY}`,
        },
        body: JSON.stringify({
          nodeId: SKYNET_NODE_ID,
          ...issue,
        }),
        signal: AbortSignal.timeout(10000),
      });
    } catch (e) {
      // Silent fail — don't break metrics if SkyNet is down
      // Could log to console in dev mode if needed
    }
  }
}
