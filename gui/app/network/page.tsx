'use client'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group'
import { Label } from '@/components/ui/label'
import { ArrowLeft, ArrowRight, Globe, FlaskConical, Code } from 'lucide-react'
import Link from 'next/link'
import { useState } from 'react'

const networks = [
  {
    id: 'mainnet',
    name: 'Mainnet',
    description: 'Production XDC Network',
    details: 'Requires 500GB+ storage • Real XDC tokens',
    icon: Globe,
  },
  {
    id: 'testnet',
    name: 'Testnet (Apothem)',
    description: 'Testing and development',
    details: 'Requires 100GB+ storage • Test XDC tokens',
    icon: FlaskConical,
  },
  {
    id: 'devnet',
    name: 'Devnet',
    description: 'Local development network',
    details: 'Minimal storage • For developers',
    icon: Code,
  },
]

export default function NetworkPage() {
  const [selectedNetwork, setSelectedNetwork] = useState('mainnet')

  return (
    <div className="min-h-screen bg-slate-50 dark:bg-slate-950">
      <div className="container mx-auto px-4 py-8 max-w-3xl">
        {/* Progress Header */}
        <div className="mb-8">
          <div className="flex items-center justify-between text-sm text-slate-600 dark:text-slate-400 mb-2">
            <span>Step 1 of 6</span>
            <span>Select Network</span>
          </div>
          <div className="w-full h-2 bg-slate-200 dark:bg-slate-800 rounded-full">
            <div className="h-full w-1/6 bg-blue-600 rounded-full"></div>
          </div>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="text-2xl">Select Network</CardTitle>
            <CardDescription>
              Choose which XDC Network you want to connect to
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            <RadioGroup
              value={selectedNetwork}
              onValueChange={setSelectedNetwork}
              className="space-y-4"
            >
              {networks.map((network) => (
                <div key={network.id}>
                  <RadioGroupItem
                    value={network.id}
                    id={network.id}
                    className="peer sr-only"
                  />
                  <Label
                    htmlFor={network.id}
                    className="flex items-start gap-4 p-4 rounded-lg border-2 border-slate-200 dark:border-slate-800 cursor-pointer transition-all peer-data-[state=checked]:border-blue-600 peer-data-[state=checked]:bg-blue-50 dark:peer-data-[state=checked]:bg-blue-950"
                  >
                    <div className="p-2 rounded-md bg-slate-100 dark:bg-slate-800">
                      <network.icon className="w-6 h-6 text-slate-600 dark:text-slate-400" />
                    </div>
                    <div className="flex-1">
                      <div className="font-semibold text-slate-900 dark:text-white">
                        {network.name}
                      </div>
                      <div className="text-sm text-slate-600 dark:text-slate-400">
                        {network.description}
                      </div>
                      <div className="text-xs text-slate-500 mt-1">
                        {network.details}
                      </div>
                    </div>
                  </Label>
                </div>
              ))}
            </RadioGroup>
          </CardContent>
        </Card>

        {/* Navigation */}
        <div className="flex justify-between mt-6">
          <Link href="/">
            <Button variant="outline" className="gap-2">
              <ArrowLeft className="w-4 h-4" />
              Previous
            </Button>
          </Link>
          <Link href="/client">
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
