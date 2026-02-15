'use client'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import { ArrowLeft, ArrowRight, Server, Beaker, Rocket } from 'lucide-react'
import Link from 'next/link'
import { useState } from 'react'

const clients = [
  {
    id: 'stable',
    name: 'XDC Stable',
    version: 'v2.6.8',
    description: 'Official Docker image - battle tested and production ready',
    features: ['Fast setup', 'Production ready', 'Official support'],
    recommended: true,
    icon: Server,
  },
  {
    id: 'geth-pr5',
    name: 'XDC Geth PR5',
    version: 'Latest',
    description: 'Latest geth with XDPoS consensus - builds from source',
    features: ['Latest features', 'Source build', '~10 min setup'],
    recommended: false,
    icon: Beaker,
  },
  {
    id: 'erigon',
    name: 'Erigon-XDC',
    version: 'Experimental',
    description: 'High-performance client with dual-sentry architecture',
    features: ['Fast sync', 'Lower disk usage', '8GB+ RAM required'],
    recommended: false,
    icon: Rocket,
  },
]

export default function ClientPage() {
  const [selectedClient, setSelectedClient] = useState('stable')

  return (
    <div className="min-h-screen bg-slate-50 dark:bg-slate-950">
      <div className="container mx-auto px-4 py-8 max-w-3xl">
        {/* Progress Header */}
        <div className="mb-8">
          <div className="flex items-center justify-between text-sm text-slate-600 dark:text-slate-400 mb-2">
            <span>Step 2 of 6</span>
            <span>Select Client</span>
          </div>
          <div className="w-full h-2 bg-slate-200 dark:bg-slate-800 rounded-full">
            <div className="h-full w-2/6 bg-blue-600 rounded-full"></div>
          </div>
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="text-2xl">Select Client</CardTitle>
            <CardDescription>
              Choose the XDC client that best fits your needs
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            <RadioGroup
              value={selectedClient}
              onValueChange={setSelectedClient}
              className="space-y-4"
            >
              {clients.map((client) => (
                <div key={client.id}>
                  <RadioGroupItem
                    value={client.id}
                    id={client.id}
                    className="peer sr-only"
                  />
                  <Label
                    htmlFor={client.id}
                    className="flex items-start gap-4 p-4 rounded-lg border-2 border-slate-200 dark:border-slate-800 cursor-pointer transition-all peer-data-[state=checked]:border-blue-600 peer-data-[state=checked]:bg-blue-50 dark:peer-data-[state=checked]:bg-blue-950"
                  >
                    <div className="p-2 rounded-md bg-slate-100 dark:bg-slate-800">
                      <client.icon className="w-6 h-6 text-slate-600 dark:text-slate-400" />
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center gap-2">
                        <span className="font-semibold text-slate-900 dark:text-white">
                          {client.name}
                        </span>
                        <span className="text-xs text-slate-500">
                          {client.version}
                        </span>
                        {client.recommended && (
                          <Badge variant="default" className="text-xs">
                            Recommended
                          </Badge>
                        )}
                      </div>
                      <div className="text-sm text-slate-600 dark:text-slate-400 mt-1">
                        {client.description}
                      </div>
                      <div className="flex flex-wrap gap-2 mt-2">
                        {client.features.map((feature) => (
                          <Badge
                            key={feature}
                            variant="secondary"
                            className="text-xs"
                          >
                            {feature}
                          </Badge>
                        ))}
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
          <Link href="/network">
            <Button variant="outline" className="gap-2">
              <ArrowLeft className="w-4 h-4" />
              Previous
            </Button>
          </Link>
          <Link href="/config">
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
