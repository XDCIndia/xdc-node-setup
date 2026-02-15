# Kubernetes Operator for XDC Network

A Kubernetes operator with Custom Resource Definitions (CRDs) for managing XDC nodes, masternodes, and backups.

## CRD Types

### XDCNode

Defines an XDC node deployment with full lifecycle management.

```yaml
apiVersion: xdc.network/v1alpha1
kind: XDCNode
metadata:
  name: xdcnode-mainnet
spec:
  network: mainnet
  client: xdcchain
  rpc:
    enabled: true
    port: 8545
  ws:
    enabled: true
    port: 8546
```

See `k8s/operator/config/samples/xdcnode-mainnet.yaml` for a full example.

### XDCMasternode

Manages masternode registration and staking.

```yaml
apiVersion: xdc.network/v1alpha1
kind: XDCMasternode
metadata:
  name: masternode-mainnet
spec:
  network: mainnet
  coinbase: "xdc..."
  stakingAmount: "10000000"
  keystoreSecret: masternode-keystore
  nodeRef: xdcnode-mainnet
```

See `k8s/operator/config/samples/xdcmasternode-mainnet.yaml`.

### XDCBackup

Defines backup policies with scheduling and retention.

```yaml
apiVersion: xdc.network/v1alpha1
kind: XDCBackup
metadata:
  name: daily-backup
spec:
  nodeRef: xdcnode-mainnet
  schedule: "0 2 * * *"
  retentionDays: 30
  destination:
    type: s3
    bucket: xdc-backups
    secretRef: aws-credentials
```

See `k8s/operator/config/samples/xdcbackup-daily.yaml`.

## Features

- **Automatic node deployment** — declarative XDC node management
- **Self-healing** — operator restarts failed nodes automatically
- **Horizontal scaling** — deploy multiple nodes via separate CRs
- **Configuration management** — all config via CRD spec fields
- **Masternode lifecycle** — register, monitor, and resign masternodes
- **Scheduled backups** — cron-based backups with retention policies

## Installation

### Apply CRDs

```bash
kubectl apply -f k8s/operator/config/crd/
```

### Deploy Operator

```bash
kubectl apply -f k8s/operator/config/manager/deployment.yaml
kubectl apply -f k8s/operator/config/rbac/role.yaml
```

### Using Helm

```bash
helm install xdc-node k8s/helm/xdc-node/ -f values.yaml
```

## Architecture

```
┌──────────────────────────────────────────────┐
│              Kubernetes Cluster               │
│                                               │
│  ┌─────────────────────────────────────────┐  │
│  │         XDC Node Operator                │  │
│  │                                          │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ │  │
│  │  │ XDCNode  │ │XDCMaster │ │XDCBackup │ │  │
│  │  │Controller│ │Controller│ │Controller│ │  │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘ │  │
│  └───────┼─────────────┼────────────┼───────┘  │
│          ▼             ▼            ▼           │
│  ┌────────────┐ ┌───────────┐ ┌──────────┐    │
│  │StatefulSet │ │  Secrets  │ │ CronJobs │    │
│  │(XDC Nodes) │ │(Keystores)│ │(Backups) │    │
│  └────────────┘ └───────────┘ └──────────┘    │
└──────────────────────────────────────────────┘
```

## Development

```bash
cd k8s/operator

# Build operator image
docker build -t xdc-operator:latest .

# Run locally (requires kubeconfig)
go run ./main.go
```

## Status

🚧 **Scaffold** — controller reconciliation logic is stubbed. Contributions welcome!
