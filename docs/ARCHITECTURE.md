# Architecture Overview

This document describes the architecture and deployment patterns for XDC Network nodes.

---

## Table of Contents

1. [Single Node Setup](#1-single-node-setup)
2. [Multi-Node HA Setup](#2-multi-node-ha-setup)
3. [RPC Infrastructure Setup](#3-rpc-infrastructure-setup)
4. [Network Diagrams](#4-network-diagrams)

---

## 1. Single Node Setup

The simplest deployment pattern, suitable for individual validators or small operations.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Single XDC Node                          │
│                     (Production Server)                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                  Docker Network                      │   │
│  │  ┌──────────────┐    ┌──────────────┐              │   │
│  │  │   XDC Node   │◄───│  Prometheus  │              │   │
│  │  │   (30303)    │    │   (9090)     │              │   │
│  │  │   (8545)     │    └──────────────┘              │   │
│  │  └──────┬───────┘         ▲                        │   │
│  │         │                 │                        │   │
│  │         ▼                 │                        │   │
│  │  ┌──────────────┐         │                        │   │
│  │  │ Chain Data   │         │                        │   │
│  │  │  (/xdcchain) │         │                        │   │
│  │  └──────────────┘         │                        │   │
│  │                            │                        │   │
│  │  ┌──────────────┐         │                        │   │
│  │  │  Grafana     │─────────┘                        │   │
│  │  │   (3000)     │                                  │   │
│  │  └──────────────┘                                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              System Services                         │   │
│  │  • systemd (xdc-node.service)                       │   │
│  │  • cron (health checks, backups)                    │   │
│  │  • UFW firewall                                     │   │
│  │  • fail2ban                                         │   │
│  │  • auditd                                           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Components

| Component | Purpose | Port |
|-----------|---------|------|
| XDC Node | Blockchain client | 30303 (P2P), 8545 (RPC) |
| Prometheus | Metrics collection | 9090 (local) |
| Grafana | Visualization | 3000 (local) |
| Node Exporter | System metrics | 9100 (internal) |

### Hardware Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 8 cores | 16 cores |
| RAM | 32 GB | 64 GB |
| Disk | 1 TB SSD | 2 TB NVMe |
| Network | 1 Gbps | 10 Gbps |

---

## 2. Multi-Node HA Setup

High-availability deployment with multiple nodes for redundancy.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Multi-Node HA Setup                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────────────┐         ┌──────────────────┐                     │
│   │   Node 1 (EU)    │◄───────►│   Node 2 (US)    │                     │
│   │  65.21.27.213    │  P2P    │  95.217.56.168   │                     │
│   │                  │         │                  │                     │
│   │ ┌──────────────┐ │         │ ┌──────────────┐ │                     │
│   │ │  XDC Node    │ │         │ │  XDC Node    │ │                     │
│   │ │  (Primary)   │ │         │ │  (Secondary) │ │                     │
│   │ └──────────────┘ │         │ └──────────────┘ │                     │
│   └────────┬─────────┘         └────────┬─────────┘                     │
│            │                            │                                │
│            │     ┌──────────────┐       │                                │
│            └────►│  HAProxy/    │◄──────┘                                │
│                  │  eRPC Load   │                                       │
│                  │  Balancer    │                                       │
│                  └──────┬───────┘                                       │
│                         │                                               │
│            ┌────────────┼────────────┐                                  │
│            ▼            ▼            ▼                                  │
│      ┌─────────┐  ┌─────────┐  ┌─────────┐                             │
│      │ Client 1│  │ Client 2│  │ Client 3│                             │
│      └─────────┘  └─────────┘  └─────────┘                             │
│                                                                          │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │                     Monitoring Stack                            │   │
│   │  • Centralized Prometheus (Node 1)                              │   │
│   │  • Grafana with multi-node dashboards                           │   │
│   │  • Shared alerts configuration                                  │   │
│   └────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### HA Configuration

**Node 1 (Primary)**
```yaml
# docker-compose.yml
services:
  xdc-node:
    environment:
      - SYNC_MODE=full
      - BOOTNODES=enode://...node2...
```

**Node 2 (Secondary)**
```yaml
# docker-compose.yml
services:
  xdc-node:
    environment:
      - SYNC_MODE=full
      - BOOTNODES=enode://...node1...
```

**Load Balancer (HAProxy)**
```haproxy
# /etc/haproxy/haproxy.cfg
global
    maxconn 4096

defaults
    mode http
    timeout connect 5s
    timeout client 30s
    timeout server 30s

backend xdc_rpc
    balance roundrobin
    option httpchk POST / HTTP/1.1\r\nContent-Type:\ application/json\r\n\r\n{"jsonrpc":"2.0","method":"net_version","id":1}
    server node1 65.21.27.213:8545 check
    server node2 95.217.56.168:8545 check backup

frontend xdc_frontend
    bind *:8989
    default_backend xdc_rpc
```

---

## 3. RPC Infrastructure Setup

Enterprise-grade RPC infrastructure for serving multiple clients.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      RPC Infrastructure Setup                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │                     Global Load Balancer                         │  │
│   │                   (CloudFlare / AWS ALB)                         │  │
│   └─────────────────────────────┬───────────────────────────────────┘  │
│                                 │                                       │
│           ┌─────────────────────┼─────────────────────┐                │
│           │                     │                     │                │
│           ▼                     ▼                     ▼                │
│   ┌───────────────┐     ┌───────────────┐     ┌───────────────┐       │
│   │  Region 1     │     │  Region 2     │     │  Region 3     │       │
│   │  (EU-West)    │     │  (US-East)    │     │  (Asia-Pacific)│      │
│   │               │     │               │     │               │       │
│   │ ┌───────────┐ │     │ ┌───────────┐ │     │ ┌───────────┐ │       │
│   │ │  Node 1A  │ │     │ │  Node 2A  │ │     │ │  Node 3A  │ │       │
│   │ │  (Full)   │ │     │ │  (Full)   │ │     │ │  (Full)   │ │       │
│   │ └─────┬─────┘ │     │ └─────┬─────┘ │     │ └─────┬─────┘ │       │
│   │       │       │     │       │       │     │       │       │       │
│   │ ┌─────▼─────┐ │     │ ┌─────▼─────┐ │     │ ┌─────▼─────┐ │       │
│   │ │  Node 1B  │ │     │ │  Node 2B  │ │     │ │  Node 3B  │ │       │
│   │ │ (Archive) │ │     │ │ (Archive) │ │     │ │ (Archive) │ │       │
│   │ └───────────┘ │     │ └───────────┘ │     │ └───────────┘ │       │
│   │               │     │               │     │               │       │
│   │ ┌───────────┐ │     │ ┌───────────┐ │     │ ┌───────────┐ │       │
│   │ │  eRPC     │ │     │ │  eRPC     │ │     │ │  eRPC     │ │       │
│   │ │ Gateway   │ │     │ │ Gateway   │ │     │ │ Gateway   │ │       │
│   │ └───────────┘ │     │ └───────────┘ │     │ └───────────┘ │       │
│   └───────────────┘     └───────────────┘     └───────────────┘       │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐  │
│   │                     Central Monitoring                           │  │
│   │  • Prometheus Federation                                          │  │
│   │  • Grafana with global dashboards                                 │  │
│   │  • PagerDuty/OpsGenie integration                                 │  │
│   └─────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### eRPC Configuration

```yaml
# erpc.yaml
server:
  listenV4: true
  httpHostV4: 0.0.0.0
  httpPort: 4000
  maxTimeout: 30s

projects:
  - id: xdc-mainnet
    networks:
      - architecture: evm
        evm:
          chainId: 50
        failsafe:
          timeout:
            duration: 30s
          retry:
            maxCount: 3
            delay: 1000ms
            backoffMaxDelay: 10s
            backoffFactor: 0.5
            jitter: 500ms
          hedge:
            delay: 500ms
            maxCount: 2
        upstreams:
          - endpoint: http://node1a:8545
          - endpoint: http://node1b:8545
          - endpoint: http://node2a:8545
          - endpoint: http://node2b:8545
          - endpoint: http://node3a:8545
          - endpoint: http://node3b:8545
```

---

## 4. Network Diagrams

### Network Flow - Transaction Processing

```
Client Request
     │
     ▼
┌─────────────┐
│   Load      │
│  Balancer   │
└──────┬──────┘
       │
       ▼
┌─────────────┐     ┌─────────────┐
│   eRPC      │────►│   XDC       │
│   Gateway   │◄────│   Node      │
└─────────────┘     └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
                    │  XDPoS      │
                    │ Consensus   │
                    └─────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   P2P       │
                    │  Network    │
                    └─────────────┘
```

### Network Flow - Block Propagation

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  Block      │─────►│   P2P       │─────►│   Peers     │
│  Producer   │      │  Broadcast  │      │  (Network)  │
└─────────────┘      └─────────────┘      └──────┬──────┘
                                                  │
        ┌─────────────────────────────────────────┼─────────┐
        │                                         │         │
        ▼                                         ▼         ▼
   ┌─────────┐                              ┌─────────┐ ┌─────────┐
   │ Node 1  │                              │ Node 2  │ │ Node 3  │
   │ (EU)    │                              │ (US)    │ │ (Asia)  │
   └─────────┘                              └─────────┘ └─────────┘
```

### Security Zones

```
┌───────────────────────────────────────────────────────────────────────┐
│                         PUBLIC ZONE                                   │
│  (Internet - Untrusted)                                               │
│                                                                       │
│  • Load Balancer (443/80)                                            │
│  • P2P Connections (30303)                                           │
└───────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌───────────────────────────────────────────────────────────────────────┐
│                        DMZ ZONE                                       │
│  (Limited Trust)                                                      │
│                                                                       │
│  • eRPC Gateway                                                       │
│  • DDoS Protection                                                    │
│  • Rate Limiting                                                      │
└───────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      INTERNAL ZONE                                    │
│  (Trusted - Never Exposed)                                            │
│                                                                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                │
│  │  XDC Node    │  │ Prometheus   │  │  Grafana     │                │
│  │  (8545/8546) │  │  (9090)      │  │  (3000)      │                │
│  └──────────────┘  └──────────────┘  └──────────────┘                │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Deployment Checklist

### Single Node
- [ ] Provision server (8+ cores, 32GB RAM, 1TB SSD)
- [ ] Run `setup.sh`
- [ ] Configure firewall
- [ ] Set up monitoring
- [ ] Configure backups
- [ ] Run security hardening

### Multi-Node HA
- [ ] Provision 2+ servers in different regions
- [ ] Deploy nodes on each server
- [ ] Configure P2P peering between nodes
- [ ] Set up load balancer
- [ ] Configure health checks
- [ ] Test failover

### RPC Infrastructure
- [ ] Provision 3+ regions
- [ ] Deploy full + archive nodes per region
- [ ] Configure eRPC gateway
- [ ] Set up global load balancer
- [ ] Configure rate limiting
- [ ] Set up monitoring aggregation
- [ ] Configure alerting (PagerDuty/OpsGenie)

---

## Scaling Considerations

| Metric | Single Node | Multi-Node | Enterprise |
|--------|-------------|------------|------------|
| RPS | 100-500 | 1,000-5,000 | 10,000+ |
| Regions | 1 | 2-3 | 3+ |
| Nodes | 1 | 2-6 | 10+ |
| Storage | 1 TB | 2-4 TB | 10+ TB |
| Network | 1 Gbps | 10 Gbps | 100 Gbps |
