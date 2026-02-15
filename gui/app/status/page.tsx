'use client'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Progress } from '@/components/ui/progress'
import {
  ArrowLeft,
  ArrowRight,
  Activity,
  Users,
  Database,
  Play,
  Square,
  RotateCcw,
  ExternalLink,
} from 'lucide-react'
import Link from 'next/link'
import { useState, useEffect } from 'react'

export default function StatusPage() {
  const [status, setStatus] = useState('running')
  const [blockHeight, setBlockHeight] = useState(89234567)
  const [peers, setPeers] = useState(25)
  const [syncProgress, setSyncProgress] = useState(94)

  useEffect(() => {
    // Simulate block height increasing
    const interval = setInterval(() => {
      setBlockHeight((prev) => prev + Math.floor(Math.random() * 3))
    }, 3000)

    return () => clearInterval(interval)
  }, [])

  const handleStart = () => setStatus('running')
  const handleStop = () => setStatus('stopped')
  const handleRestart = () => {
    setStatus('restarting')
    setTimeout(() => setStatus('running'), 2000)
  }

  return (
    <div className="min-h-screen bg-slate-50 dark:bg-slate-950">
      <div className="container mx-auto px-4 py-8 max-w-5xl">
        {/* Progress Header */}
        <div className="mb-8">
          <div className="flex items-center justify-between text-sm text-slate-600 dark:text-slate-400 mb-2">
            <span>Step 5 of 6</span>
            <span>Status</span>
          </div>
          <div className="w-full h-2 bg-slate-200 dark:bg-slate-800 rounded-full">
            <div className="h-full w-5/6 bg-blue-600 rounded-full"></div>
          </div>
        </div>

        <Card className="mb-6">
          <CardHeader>
            <div className="flex items-center justify-between">
              <CardTitle className="text-2xl">Node Status</CardTitle>
              <Badge
                variant={status === 'running' ? 'default' : 'secondary'}
                className="gap-1"
              >
                <span
                  className={`w-2 h-2 rounded-full ${
                    status === 'running' ? 'bg-green-400' : 'bg-slate-400'
                  }`}
                />
                {status === 'running'
                  ? 'Running'
                  : status === 'stopped'
                  ? 'Stopped'
                  : 'Restarting...'}
              </Badge>
            </div>
            <CardDescription>Monitor your XDC node status and health</CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            {/* Stats Grid */}
            <div className="grid grid-cols-3 gap-4">
              <Card>
                <CardContent className="pt-6">
                  <div className="flex items-center gap-2">
                    <Database className="w-4 h-4 text-blue-500" />
                    <span className="text-sm text-slate-600">Block Height</span>
                  </div>
                  <div className="text-2xl font-bold mt-1">
                    {blockHeight.toLocaleString()}
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardContent className="pt-6">
                  <div className="flex items-center gap-2">
                    <Users className="w-4 h-4 text-green-500" />
                    <span className="text-sm text-slate-600">Peers</span>
                  </div>
                  <div className="text-2xl font-bold mt-1">{peers}</div>
                </CardContent>
              </Card>

              <Card>
                <CardContent className="pt-6">
                  <div className="flex items-center gap-2">
                    <Activity className="w-4 h-4 text-purple-500" />
                    <span className="text-sm text-slate-600">Network</span>
                  </div>
                  <div className="text-2xl font-bold mt-1">Mainnet</div>
                </CardContent>
              </Card>
            </div>

            {/* Sync Progress */}
            <div className="space-y-2">
              <div className="flex justify-between">
                <span className="text-sm font-medium">Sync Progress</span>
                <span className="text-sm text-slate-600">{syncProgress}%</span>
              </div>
              <Progress value={syncProgress} className="h-2" />
              <p className="text-xs text-slate-500">
                ~2 hours remaining until fully synced
              </p>
            </div>

            {/* Action Buttons */}
            <div className="flex flex-wrap gap-3 pt-4 border-t">
              {status === 'stopped' ? (
                <Button onClick={handleStart} className="gap-2">
                  <Play className="w-4 h-4" />
                  Start Node
                </Button>
              ) : (
                <Button onClick={handleStop} variant="outline" className="gap-2">
                  <Square className="w-4 h-4" />
                  Stop Node
                </Button>
              )}

              <Button onClick={handleRestart} variant="outline" className="gap-2">
                <RotateCcw className="w-4 h-4" />
                Restart
              </Button>

              <Button variant="outline" className="gap-2">
                <ExternalLink className="w-4 h-4" />
                Open Dashboard
              </Button>
            </div>
          </CardContent>
        </Card>

        {/* Quick Links */}
        <Card className="bg-slate-50 dark:bg-slate-900">
          <CardHeader>
            <CardTitle className="text-lg">Quick Links</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <a
                href="http://localhost:7070"
                target="_blank"
                rel="noopener noreferrer"
                className="p-4 rounded-lg bg-white dark:bg-slate-800 hover:shadow-md transition-shadow"
              >
                <div className="font-medium">SkyOne Dashboard</div>
                <div className="text-xs text-slate-500">Port 7070</div>
              </a>

              <a
                href="#"
                className="p-4 rounded-lg bg-white dark:bg-slate-800 hover:shadow-md transition-shadow"
              >
                <div className="font-medium">RPC Endpoint</div>
                <div className="text-xs text-slate-500">Port 8545</div>
              </a>

              <a
                href="#"
                className="p-4 rounded-lg bg-white dark:bg-slate-800 hover:shadow-md transition-shadow"
              >
                <div className="font-medium">Documentation</div>
                <div className="text-xs text-slate-500">View docs</div>
              </a>

              <a
                href="#"
                className="p-4 rounded-lg bg-white dark:bg-slate-800 hover:shadow-md transition-shadow"
              >
                <div className="font-medium">Get Help</div>
                <div className="text-xs text-slate-500">GitHub Issues</div>
              </a>
            </div>
          </CardContent>
        </Card>

        {/* Navigation */}
        <div className="flex justify-between mt-6">
          <Link href="/install">
            <Button variant="outline" className="gap-2">
              <ArrowLeft className="w-4 h-4" />
              Previous
            </Button>
          </Link>
          <Link href="/">
            <Button className="gap-2">
              Finish
              <ArrowRight className="w-4 h-4" />
            </Button>
          </Link>
        </div>
      </div>
    </div>
  )
}
