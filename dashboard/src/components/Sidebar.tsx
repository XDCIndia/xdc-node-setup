'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const navItems = [
  { href: '/', label: 'Overview', icon: '📊' },
  { href: '/nodes', label: 'Nodes', icon: '🖥️' },
  { href: '/security', label: 'Security', icon: '🔒' },
  { href: '/versions', label: 'Versions', icon: '📦' },
  { href: '/alerts', label: 'Alerts', icon: '🔔' },
  { href: '/settings', label: 'Settings', icon: '⚙️' },
];

export default function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="fixed left-0 top-0 h-full w-64 bg-xdc-card border-r border-xdc-border flex flex-col">
      <div className="p-6 border-b border-xdc-border">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-lg bg-xdc-primary flex items-center justify-center">
            <span className="text-white font-bold text-lg">X</span>
          </div>
          <div>
            <h1 className="font-bold text-white">XDC Node</h1>
            <p className="text-xs text-gray-400">Dashboard</p>
          </div>
        </div>
      </div>
      
      <nav className="flex-1 p-4">
        <ul className="space-y-1">
          {navItems.map((item) => {
            const isActive = pathname === item.href || 
              (item.href !== '/' && pathname.startsWith(item.href));
            
            return (
              <li key={item.href}>
                <Link
                  href={item.href}
                  className={`flex items-center gap-3 px-4 py-3 rounded-lg transition-colors ${
                    isActive
                      ? 'bg-xdc-primary text-white'
                      : 'text-gray-400 hover:text-white hover:bg-xdc-border'
                  }`}
                >
                  <span className="text-lg">{item.icon}</span>
                  <span className="font-medium">{item.label}</span>
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>
      
      <div className="p-4 border-t border-xdc-border">
        <div className="text-xs text-gray-500">
          <p>XDC Node Setup v2.0.0</p>
          <p className="mt-1">© 2026 XDC Network</p>
        </div>
      </div>
    </aside>
  );
}
