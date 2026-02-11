'use client';

import { useState } from 'react';
import { 
  Link2, 
  Crown, 
  RefreshCw, 
  FileText, 
  Monitor, 
  HardDrive, 
  Globe 
} from 'lucide-react';

interface DockItem {
  id: string;
  label: string;
  icon: React.ReactNode;
}

const dockItems: DockItem[] = [
  { id: 'blockchain', label: 'Blockchain', icon: <Link2 className="w-6 h-6" /> },
  { id: 'consensus', label: 'Consensus', icon: <Crown className="w-6 h-6" /> },
  { id: 'sync', label: 'Sync', icon: <RefreshCw className="w-6 h-6" /> },
  { id: 'transactions', label: 'TxPool', icon: <FileText className="w-6 h-6" /> },
  { id: 'server', label: 'Server', icon: <Monitor className="w-6 h-6" /> },
  { id: 'storage', label: 'Storage', icon: <HardDrive className="w-6 h-6" /> },
  { id: 'map', label: 'Map', icon: <Globe className="w-6 h-6" /> },
];

export default function Dock() {
  const [hoveredIndex, setHoveredIndex] = useState<number | null>(null);

  const handleClick = (id: string) => {
    const element = document.getElementById(id);
    if (element) {
      element.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  };

  const getScale = (index: number): number => {
    if (hoveredIndex === null) return 1;
    const distance = Math.abs(index - hoveredIndex);
    if (distance === 0) return 1.5;
    if (distance === 1) return 1.2;
    if (distance === 2) return 1.05;
    return 1;
  };

  const getTranslateY = (index: number): number => {
    if (hoveredIndex === null) return 0;
    const distance = Math.abs(index - hoveredIndex);
    if (distance === 0) return -12;
    if (distance === 1) return -6;
    return 0;
  };

  return (
    <div className="dock">
      {dockItems.map((item, index) => (
        <button
          key={item.id}
          className="dock-item"
          onClick={() => handleClick(item.id)}
          onMouseEnter={() => setHoveredIndex(index)}
          onMouseLeave={() => setHoveredIndex(null)}
          style={{
            transform: `scale(${getScale(index)}) translateY(${getTranslateY(index)}px)`,
          }}
          aria-label={item.label}
        >
          <span className="dock-icon text-[#1E90FF]">{item.icon}</span>
          <span className="dock-label">{item.label}</span>
        </button>
      ))}
    </div>
  );
}
