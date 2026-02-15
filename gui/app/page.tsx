import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { ArrowRight, Server, Shield, Zap } from 'lucide-react'
import Link from 'next/link'

export default function WelcomePage() {
  return (
    <div className="min-h-screen bg-gradient-to-b from-slate-50 to-slate-100 dark:from-slate-950 dark:to-slate-900">
      <div className="container mx-auto px-4 py-16 max-w-5xl">
        {/* Header */}
        <div className="text-center mb-12">
          <div className="inline-flex items-center justify-center w-20 h-20 rounded-2xl bg-blue-600 mb-6">
            <Server className="w-10 h-10 text-white" />
          </div>
          <h1 className="text-4xl font-bold text-slate-900 dark:text-white mb-4">
            XDC Node Setup
          </h1>
          <p className="text-xl text-slate-600 dark:text-slate-400 max-w-2xl mx-auto">
            Deploy an XDC Network node in minutes with our guided setup wizard
          </p>
        </div>

        {/* Get Started Card */}
        <Card className="mb-8">
          <CardHeader className="text-center">
            <CardTitle className="text-2xl">Ready to get started?</CardTitle>
            <CardDescription>
              Follow our step-by-step wizard to configure and deploy your node
            </CardDescription>
          </CardHeader>
          <CardContent className="flex justify-center pb-8">
            <Link href="/network">
              <Button size="lg" className="gap-2">
                Get Started
                <ArrowRight className="w-4 h-4" />
              </Button>
            </Link>
          </CardContent>
        </Card>

        {/* Features Grid */}
        <div className="grid md:grid-cols-3 gap-6 mb-12">
          <Card>
            <CardHeader>
              <Zap className="w-8 h-8 text-yellow-500 mb-2" />
              <CardTitle>Fast Setup</CardTitle>
              <CardDescription>
                Get your node running in under 5 minutes with automated configuration
              </CardDescription>
            </CardHeader>
          </Card>

          <Card>
            <CardHeader>
              <Shield className="w-8 h-8 text-green-500 mb-2" />
              <CardTitle>Secure by Default</CardTitle>
              <CardDescription>
                Security hardening, firewall rules, and best practices built-in
              </CardDescription>
            </CardHeader>
          </Card>

          <Card>
            <CardHeader>
              <Server className="w-8 h-8 text-blue-500 mb-2" />
              <CardTitle>Multi-Client</CardTitle>
              <CardDescription>
                Choose from XDC Stable, Geth PR5, or Erigon clients
              </CardDescription>
            </CardHeader>
          </Card>
        </div>

        {/* System Requirements */}
        <Card className="bg-slate-50 dark:bg-slate-800">
          <CardHeader>
            <CardTitle className="text-lg">System Requirements</CardTitle>
          </CardHeader>
          <CardContent>
            <ul className="space-y-2 text-sm">
              <li className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-green-500"></span>
                Docker 20.10+ installed and running
              </li>
              <li className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-green-500"></span>
                4GB+ RAM (16GB recommended)
              </li>
              <li className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-green-500"></span>
                100GB+ disk space (500GB+ recommended for mainnet)
              </li>
              <li className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-green-500"></span>
                Linux x86_64 (Ubuntu 20.04+ recommended)
              </li>
            </ul>
          </CardContent>
        </Card>

        {/* Footer */}
        <div className="mt-12 text-center text-sm text-slate-500">
          <p>
            Need help? Check out the{' '}
            <a href="#" className="text-blue-600 hover:underline">
              documentation
            </a>{' '}
            or{' '}
            <a href="#" className="text-blue-600 hover:underline">
              GitHub repository
            </a>
          </p>
        </div>
      </div>
    </div>
  )
}
