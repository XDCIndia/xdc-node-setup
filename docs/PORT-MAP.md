# XDC Node Port Map

This document defines the standard port assignments for XDC Network nodes across all supported clients.

## Overview

The standardized port allocation enables running multiple XDC clients simultaneously without conflicts.

**Standard Ports:**
- GP5 (Geth): 8545, 8546, 30303
- Erigon: 8547, 8548, 30305, 30311
- Nethermind: 8558, 8559, 30306
- Reth: 8588, 8589, 40303, 40304

For complete details, see `configs/ports.env` and the full documentation below.

## Port Assignments

### GP5 (Geth XDC Stable)

| Service | Port | Protocol |
|---------|------|----------|
| RPC | 8545 | HTTP |
| WebSocket | 8546 | WS |
| P2P | 30303 | TCP/UDP |
| Metrics | 6060 | HTTP |

### Erigon-XDC

| Service | Port | Protocol | XDC Compatible |
|---------|------|----------|----------------|
| RPC | 8547 | HTTP | N/A |
| WebSocket | 8548 | WS | N/A |
| P2P (eth/63) | 30305 | TCP/UDP | ✅ Yes |
| P2P (eth/68) | 30311 | TCP/UDP | ❌ No |
| Auth RPC | 8561 | HTTP | N/A |
| Private API | 9091 | TCP | N/A |
| Metrics | 6071 | HTTP | N/A |

**Important:** Port 30305 is XDC-compatible; port 30311 is NOT.

### Nethermind-XDC

| Service | Port | Protocol |
|---------|------|----------|
| RPC | 8558 | HTTP |
| WebSocket | 8559 | WS |
| P2P | 30306 | TCP/UDP |
| Metrics | 6072 | HTTP |

### Reth-XDC (Alpha)

| Service | Port | Protocol |
|---------|------|----------|
| RPC | 8588 | HTTP |
| WebSocket | 8589 | WS |
| P2P | 40303 | TCP/UDP |
| Discovery | 40304 | UDP |
| Auth RPC | 8551 | HTTP |
| Metrics | 6073 | HTTP |

## Usage

See `configs/ports.env` for environment variables.

For firewall configuration and troubleshooting, see `TROUBLESHOOTING.md`.
