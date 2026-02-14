import { NextResponse } from 'next/server';
import { getLFGConfig } from '@/lib/lfg';

/**
 * GET /api/lfg/config
 * Returns LFG configuration (safe to expose - no secrets)
 */
export async function GET() {
  const config = getLFGConfig();
  return NextResponse.json(config);
}
