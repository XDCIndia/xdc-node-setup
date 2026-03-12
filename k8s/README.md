# Kubernetes Deployment for XDC Node

This directory contains Kubernetes manifests for deploying XDC nodes in production environments.

## Prerequisites

- Kubernetes cluster (1.25+)
- kubectl configured
- Storage class with SSD support (recommended: `fast-ssd`)
- At least 1000GB of storage per node
- 8GB+ RAM per node

## Quick Start

```bash
# Deploy all resources
kubectl apply -k k8s/

# Or deploy individually
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/statefulset.yaml
kubectl apply -f k8s/network-policy.yaml
kubectl apply -f k8s/pod-disruption-budget.yaml
```

## Components

### Namespace
Isolates XDC resources in the `xdc-network` namespace.

### ConfigMap
Configuration for network, sync mode, and XDPoS 2.0 settings.

### StatefulSet
- Runs the XDC node container
- Persistent storage for chain data
- Liveness, readiness, and startup probes
- Resource limits and requests
- Security context with non-root user

### Service
Exposes RPC (8545), WebSocket (8546), P2P (30303), and metrics (6060) ports.

### Network Policy
Restricts network access:
- P2P: Open to all
- RPC: Internal networks only
- Metrics: Monitoring namespace only

### Pod Disruption Budget
Ensures at least 1 node is available during maintenance.

## Storage Configuration

The default configuration uses a StorageClass named `fast-ssd`. Update `statefulset.yaml` and `pvc.yaml` to match your cluster's storage class:

```yaml
volumeClaimTemplates:
- metadata:
    name: xdc-data
  spec:
    storageClassName: your-storage-class  # Change this
```

## Resource Requirements

| Resource | Request | Limit |
|----------|---------|-------|
| CPU | 4 cores | 8 cores |
| Memory | 8 GB | 32 GB |
| Storage | 1000 GB | - |

## Security Features

- Non-root user (UID 1000)
- Read-only root filesystem option
- Dropped capabilities (only NET_BIND_SERVICE added)
- Network policy restricting traffic
- No privilege escalation

## Monitoring

Prometheus metrics are exposed on port 6060 with annotations:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "6060"
  prometheus.io/path: "/debug/metrics/prometheus"
```

## Troubleshooting

```bash
# Check pod status
kubectl get pods -n xdc-network

# View logs
kubectl logs -n xdc-network -l app=xdc-node -f

# Check storage
kubectl get pvc -n xdc-network

# Port forward for local access
kubectl port-forward -n xdc-network pod/xdc-node-0 8545:8545

# Check node sync status
kubectl exec -n xdc-network xdc-node-0 -- \
  curl -s http://localhost:8545 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

## Multi-Client Support

To run multiple clients (Geth, Erigon, Nethermind, Reth):

```bash
# Create separate StatefulSets for each client
kubectl apply -f k8s/statefulset-geth.yaml
kubectl apply -f k8s/statefulset-erigon.yaml
```

## Production Checklist

- [ ] Configure appropriate storage class
- [ ] Set resource limits based on node size
- [ ] Configure network policies for your environment
- [ ] Set up monitoring (Prometheus/Grafana)
- [ ] Configure backup for persistent volumes
- [ ] Test pod disruption budget
- [ ] Verify liveness/readiness probes work correctly
- [ ] Set up log aggregation
