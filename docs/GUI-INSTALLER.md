# GUI Installer Design Specification

## Design Principles

1. **Simplicity**: Clear, step-by-step guidance
2. **Transparency**: Real-time feedback and logs
3. **Flexibility**: Support for all client types and networks
4. **Reliability**: Validation at every step

## User Interface Design

### Color Palette

- **Primary**: #1B4D89 (XDC Blue)
- **Secondary**: #2ECC71 (Success Green)
- **Accent**: #F39C12 (Warning Orange)
- **Error**: #E74C3C (Error Red)
- **Background**: #F8F9FA (Light Gray)
- **Text**: #2C3E50 (Dark Gray)

### Typography

- **Headings**: Inter, 600 weight
- **Body**: Inter, 400 weight
- **Monospace**: JetBrains Mono (for logs/code)

### Layout

- Max width: 1200px
- Card-based design
- Progress indicator at top
- Navigation sidebar (collapsible)

## Component Library

Based on shadcn/ui components:

- Button
- Card
- Input
- Select
- Switch
- Progress
- Tabs
- Dialog
- Alert
- Badge
- Separator
- Skeleton

## Page Specifications

### Welcome Page

```
┌─────────────────────────────────────────────┐
│  XDC Node Setup                             │
│  ─────────────────────────────────────────  │
│                                             │
│  [Logo]                                     │
│                                             │
│  Welcome to XDC Node Setup                  │
│  Deploy an XDC Network node in minutes      │
│                                             │
│  [Get Started]  [Documentation]             │
│                                             │
│  System Requirements:                       │
│  ✓ Docker installed                         │
│  ✓ 4GB+ RAM available                       │
│  ✓ 100GB+ disk space                        │
└─────────────────────────────────────────────┘
```

### Network Selection

```
┌─────────────────────────────────────────────┐
│  Step 1 of 6: Select Network                │
│  ═══════════════════════════════            │
│                                             │
│  [●] Mainnet                                │
│      Production XDC Network                 │
│      Requires 500GB+ storage                │
│                                             │
│  [ ] Testnet (Apothem)                      │
│      Testing and development                │
│      Requires 100GB+ storage                │
│                                             │
│  [ ] Devnet                                 │
│      Local development network              │
│                                             │
│  [Previous]  [Next]                         │
└─────────────────────────────────────────────┘
```

### Client Selection

```
┌─────────────────────────────────────────────┐
│  Step 2 of 6: Select Client                 │
│  ═══════════════════════════════            │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ [●] XDC Stable (v2.6.8)  ★ RECOMMENDED │ │
│  │ Official Docker image                 │   │
│  │ Fast setup • Production ready         │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ [ ] XDC Geth PR5                    │   │
│  │ Latest geth with XDPoS              │   │
│  │ ~10 min build time                  │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ [ ] Erigon-XDC                      │   │
│  │ High-performance client             │   │
│  │ Experimental • 8GB+ RAM required    │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  [Previous]  [Next]                         │
└─────────────────────────────────────────────┘
```

### Configuration

```
┌─────────────────────────────────────────────┐
│  Step 3 of 6: Configure Node                │
│  ═══════════════════════════════            │
│                                             │
│  Node Name                                  │
│  ┌─────────────────────────────────────┐   │
│  │ my-xdc-node                         │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  [✓] Enable RPC (Port 8545)                │
│  [✓] Enable WebSocket (Port 8546)          │
│  [ ] Enable Mining                         │
│                                             │
│  ─── Advanced Options ───                  │
│                                             │
│  Max Peers:  [50        ]                  │
│  Cache Size: [4096 MB   ]                  │
│                                             │
│  [Previous]  [Next]                         │
└─────────────────────────────────────────────┘
```

### Installation

```
┌─────────────────────────────────────────────┐
│  Step 4 of 6: Installing...                 │
│  ═══════════════════════════════            │
│                                             │
│  [████████████░░░░░░░░] 60%                 │
│                                             │
│  Status: Downloading snapshot...            │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ > Pulling Docker images...          │   │
│  │ > Downloading snapshot...           │   │
│  │ ✓ Configuring firewall              │   │
│  │ ✓ Setting up directories            │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  [View Full Logs]  [Cancel]                 │
└─────────────────────────────────────────────┘
```

### Status Dashboard

```
┌─────────────────────────────────────────────┐
│  Step 5 of 6: Node Status                   │
│  ═══════════════════════════════            │
│                                             │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ │
│  │ Status    │ │ Block     │ │ Peers     │ │
│  │ ● Running │ │ 89,234,567│ │ 25        │ │
│  └───────────┘ └───────────┘ └───────────┘ │
│                                             │
│  Sync Progress:                             │
│  [████████████████████░░] 94%               │
│  ~2 hours remaining                         │
│                                             │
│  [Stop] [Restart] [View Logs] [Dashboard]   │
│                                             │
│  [← Back to Welcome]                        │
└─────────────────────────────────────────────┘
```

## Responsive Design

### Desktop (1200px+)
- Full sidebar navigation
- Multi-column layouts
- Expanded detail views

### Tablet (768px - 1199px)
- Collapsible sidebar
- Two-column layouts
- Touch-friendly controls

### Mobile (< 768px)
- Bottom navigation
- Single column layout
- Simplified views

## Accessibility

- WCAG 2.1 AA compliant
- Keyboard navigation support
- Screen reader compatible
- High contrast mode
- Reduced motion support

## Animation Guidelines

- Progress transitions: 300ms ease
- Page transitions: 200ms fade
- Loading states: Pulse animation
- Success states: Checkmark animation
- Error states: Shake animation

## Error Handling

- Inline validation
- Clear error messages
- Recovery suggestions
- Retry mechanisms
- Rollback capabilities
