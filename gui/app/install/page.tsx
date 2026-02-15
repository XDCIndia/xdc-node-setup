'use client'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Progress } from '@/components/ui/progress'
import { ArrowLeft, ArrowRight, Loader2, CheckCircle, XCircle } from 'lucide-react'
import Link from 'next/link'
import { useState, useEffect } from 'react'

const installSteps = [
  { id: 'docker', name: 'Pulling Docker images', status: 'pending' },
  { id: 'firewall', name: 'Configuring firewall', status: 'pending' },
  { id: 'snapshot', name: 'Downloading snapshot', status: 'pending' },
  { id: 'config', name: 'Generating configuration', status: 'pending' },
  { id: 'start', name: 'Starting node', status: 'pending' },
]

export default function InstallPage() {
  const [progress, setProgress] = useState(0)
  const [steps, setSteps] = useState(installSteps)
  const [isInstalling, setIsInstalling] = useState(true)
  const [logs, setLogs] = useState<string[]>([])

  useEffect(() => {
    // Simulate installation progress
    const interval = setInterval(() => {
      setProgress((prev) => {
        if (prev >= 100) {
          setIsInstalling(false)
          clearInterval(interval)
          return 100
        }
        return prev + 2
      })
    }, 100)

    return () => clearInterval(interval)
  }, [])

  useEffect(() => {
    // Simulate logs
    const logInterval = setInterval(() => {
      if (!isInstalling) {
        clearInterval(logInterval)
        return
      }
      setLogs((prev) => [
        ...prev.slice(-20),
        `[${new Date().toLocaleTimeString()}] ${getRandomLog()}`,
      ])
    }, 500)

    return () => clearInterval(logInterval)
  }, [isInstalling])

  const getRandomLog = () => {
    const logs = [
      'Pulling xdc-node:latest...',
      'Extracting files...',
      'Setting up directories...',
      'Configuring network...',
      'Downloading snapshot data...',
      'Verifying checksum...',
      'Applying configuration...',
      'Starting services...',
    ]
    return logs[Math.floor(Math.random() * logs.length)]
  }

  return (
    <div className="min-h-screen bg-slate-50 dark:bg-slate-950">
      <div className="container mx-auto px-4 py-8 max-w-3xl">
        {/* Progress Header */}
        <div className="mb-8">
          <div className="flex items-center justify-between text-sm text-slate-600 dark:text-slate-400 mb-2">
            <span>Step 4 of 6</span>
            <span>Installation</span>
          </div>
          <div className="w-full h-2 bg-slate-200 dark:bg-slate-800 rounded-full">
            <div className="h-full w-4/6 bg-blue-600 rounded-full"></div>
          </div>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="text-2xl">Installing Node</CardTitle>
            <CardDescription>
              {isInstalling
                ? 'Please wait while we set up your XDC node...'
                : 'Installation complete!'}
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            {/* Progress Bar */}
            <div className="space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-slate-600 dark:text-slate-400">Progress</span>
                <span className="font-medium">{progress}%</span>
              </div>
              <Progress value={progress} className="h-2" />
            </div>

            {/* Steps */}
            <div className="space-y-3">
              {steps.map((step, index) => {
                const stepProgress = (index / steps.length) * 100
                const isActive = progress >= stepProgress
                const isComplete = progress >= stepProgress + 100 / steps.length

                return (
                  <div
                    key={step.id}
                    className="flex items-center gap-3 p-3 rounded-lg bg-slate-50 dark:bg-slate-900"
                  >
                    {isComplete ? (
                      <CheckCircle className="w-5 h-5 text-green-500" />
                    ) : isActive ? (
                      <Loader2 className="w-5 h-5 text-blue-500 animate-spin" />
                    ) : (
                      <div className="w-5 h-5 rounded-full border-2 border-slate-300" />
                    )}
                    <span
                      className={`text-sm ${
                        isActive
                          ? 'text-slate-900 dark:text-white'
                          : 'text-slate-400'
                      }`}
                    >
                      {step.name}
                    </span>
                  </div>
                )
              })}
            </div>

            {/* Logs */}
            <div className="mt-6">
              <Label className="text-sm font-medium mb-2 block">Installation Logs</Label>
              <div className="bg-slate-950 rounded-lg p-4 font-mono text-xs text-green-400 h-48 overflow-y-auto">
                {logs.length === 0 && (
                  <span className="text-slate-500">Waiting to start...</span>
                )}
                {logs.map((log, index) => (
                  <div key={index}>{log}</div>
                ))}
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Navigation */}
        <div className="flex justify-between mt-6">
          <Link href="/config">
            <Button variant="outline" className="gap-2" disabled={isInstalling}>
              <ArrowLeft className="w-4 h-4" />
              Previous
            </Button>
          </Link>
          <Link href={isInstalling ? '#' : '/status'}>
            <Button className="gap-2" disabled={isInstalling}>
              Next
              <ArrowRight className="w-4 h-4" />
            </Button>
          </Link>
        </div>
      </div>
    </div>
  )
}

import { Label } from '@/components/ui/label'
