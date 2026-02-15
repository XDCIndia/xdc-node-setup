# XDC Node Setup - GUI Installer

A modern React-based web wizard for deploying XDC Network nodes with an intuitive, step-by-step interface.

## Overview

The GUI Installer provides a web-based deployment wizard that wraps the CLI commands, making it easy for users to configure and deploy XDC nodes without touching the command line.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GUI Installer Architecture               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │   Next.js   │◄──►│  Wizard UI   │◄──►│   CLI API    │   │
│  │   (App)     │    │  (Pages)     │    │  (Backend)   │   │
│  └─────────────┘    └──────────────┘    └──────────────┘   │
│                              │                               │
│                              ▼                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    Wizard Flow                          │ │
│  │  Welcome → Network → Client → Config → Install → Status │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Technology Stack

- **Framework**: Next.js 14+ with App Router
- **UI Library**: React 18+
- **Styling**: Tailwind CSS
- **Components**: shadcn/ui
- **State Management**: React Context + Hooks
- **API**: REST API endpoints that invoke CLI commands

## Project Structure

```
gui/
├── app/                    # Next.js App Router
│   ├── layout.tsx         # Root layout
│   ├── page.tsx           # Welcome page
│   ├── network/           # Network selection
│   ├── client/            # Client selection
│   ├── config/            # Configuration page
│   ├── install/           # Installation page
│   └── status/            # Status page
├── components/            # React components
│   ├── ui/               # shadcn/ui components
│   ├── wizard/           # Wizard-specific components
│   └── layout/           # Layout components
├── lib/                  # Utilities
│   ├── api.ts           # API client
│   └── utils.ts         # Helper functions
├── hooks/                # Custom React hooks
├── types/                # TypeScript types
├── public/               # Static assets
├── styles/               # Global styles
├── next.config.js
├── tailwind.config.ts
└── package.json
```

## Wizard Flow

### 1. Welcome Page
- Introduction to XDC Node Setup
- System requirements check
- Quick start option

### 2. Network Selection
- Mainnet (Production)
- Testnet (Apothem - Testing)
- Devnet (Development)

### 3. Client Selection
- XDC Stable (v2.6.8) - Recommended
- XDC Geth PR5 (Latest)
- Erigon-XDC (Experimental)

### 4. Configuration
- Node name
- RPC settings
- P2P port configuration
- Resource limits (CPU/Memory)
- Advanced options

### 5. Installation
- Progress indicator
- Real-time logs
- Download status
- Sync progress

### 6. Status Dashboard
- Node health
- Sync status
- Peer count
- Block height
- Quick actions (start/stop/restart)

## Development

### Prerequisites

- Node.js 18+
- npm or yarn

### Setup

```bash
cd gui
npm install
npm run dev
```

The GUI will be available at `http://localhost:3000`

### Build

```bash
npm run build
```

## API Integration

The GUI communicates with the backend through REST API endpoints:

```typescript
// Example API calls
GET  /api/status          → Get node status
POST /api/start           → Start node
POST /api/stop            → Stop node
POST /api/config          → Update configuration
GET  /api/logs            → Stream logs
```

## Future Enhancements

- [ ] Multi-node management
- [ ] SkyNet fleet integration
- [ ] Mobile app
- [ ] Dark mode
- [ ] Internationalization
- [ ] One-click cloud deployment

## License

MIT License - See [LICENSE](../LICENSE)
