'use client'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Slider } from '@/components/ui/slider'
import { ArrowLeft, ArrowRight, Settings } from 'lucide-react'
import Link from 'next/link'
import { useState } from 'react'

export default function ConfigPage() {
  const [nodeName, setNodeName] = useState('my-xdc-node')
  const [enableRPC, setEnableRPC] = useState(true)
  const [enableWS, setEnableWS] = useState(true)
  const [enableMining, setEnableMining] = useState(false)
  const [maxPeers, setMaxPeers] = useState([50])
  const [cacheSize, setCacheSize] = useState([4096])

  return (
    <div className="min-h-screen bg-slate-50 dark:bg-slate-950">
      <div className="container mx-auto px-4 py-8 max-w-3xl">
        {/* Progress Header */}
        <div className="mb-8">
          <div className="flex items-center justify-between text-sm text-slate-600 dark:text-slate-400 mb-2">
            <span>Step 3 of 6</span>
            <span>Configure</span>
          </div>
          <div className="w-full h-2 bg-slate-200 dark:bg-slate-800 rounded-full">
            <div className="h-full w-3/6 bg-blue-600 rounded-full"></div>
          </div>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="text-2xl flex items-center gap-2">
              <Settings className="w-6 h-6" />
              Configure Node
            </CardTitle>
            <CardDescription>
              Customize your node settings
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            {/* Node Name */}
            <div className="space-y-2">
              <Label htmlFor="nodeName">Node Name</Label>
              <Input
                id="nodeName"
                value={nodeName}
                onChange={(e) => setNodeName(e.target.value)}
                placeholder="Enter node name"
              />
              <p className="text-xs text-slate-500">
                This name will be used to identify your node in the dashboard
              </p>
            </div>

            {/* Toggles */}
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div className="space-y-0.5">
                  <Label htmlFor="rpc">Enable RPC (Port 8545)</Label>
                  <p className="text-xs text-slate-500">
                    Allow JSON-RPC API access
                  </p>
                </div>
                <Switch
                  id="rpc"
                  checked={enableRPC}
                  onCheckedChange={setEnableRPC}
                />
              </div>

              <div className="flex items-center justify-between">
                <div className="space-y-0.5">
                  <Label htmlFor="ws">Enable WebSocket (Port 8546)</Label>
                  <p className="text-xs text-slate-500">
                    Allow WebSocket API access
                  </p>
                </div>
                <Switch
                  id="ws"
                  checked={enableWS}
                  onCheckedChange={setEnableWS}
                />
              </div>

              <div className="flex items-center justify-between">
                <div className="space-y-0.5">
                  <Label htmlFor="mining">Enable Mining</Label>
                  <p className="text-xs text-slate-500">
                    Enable block production (masternode only)
                  </p>
                </div>
                <Switch
                  id="mining"
                  checked={enableMining}
                  onCheckedChange={setEnableMining}
                />
              </div>
            </div>

            {/* Sliders */}
            <div className="space-y-6 pt-4 border-t">
              <div className="space-y-3">
                <div className="flex justify-between">
                  <Label>Max Peers</Label>
                  <span className="text-sm text-slate-600">{maxPeers[0]}</span>
                </div>
                <Slider
                  value={maxPeers}
                  onValueChange={setMaxPeers}
                  min={10}
                  max={200}
                  step={10}
                />
                <p className="text-xs text-slate-500">
                  Maximum number of peer connections
                </p>
              </div>

              <div className="space-y-3">
                <div className="flex justify-between">
                  <Label>Cache Size</Label>
                  <span className="text-sm text-slate-600">
                    {cacheSize[0]} MB
                  </span>
                </div>
                <Slider
                  value={cacheSize}
                  onValueChange={setCacheSize}
                  min={1024}
                  max={16384}
                  step={1024}
                />
                <p className="text-xs text-slate-500">
                  Memory allocation for state caching
                </p>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Navigation */}
        <div className="flex justify-between mt-6">
          <Link href="/client">
            <Button variant="outline" className="gap-2">
              <ArrowLeft className="w-4 h-4" />
              Previous
            </Button>
          </Link>
          <Link href="/install">
            <Button className="gap-2">
              Next
              <ArrowRight className="w-4 h-4" />
            </Button>
          </Link>
        </div>
      </div>
    </div>
  )
}
