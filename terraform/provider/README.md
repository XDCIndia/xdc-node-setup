# Terraform Provider for XDC Network

Custom Terraform provider for managing XDC node infrastructure.

## Resources

| Resource | Description |
|----------|-------------|
| `xdc_node` | Manage XDC node instances |
| `xdc_masternode` | Manage masternode configuration and staking |
| `xdc_backup` | Manage backup schedules |
| `xdc_monitor` | Configure monitoring and alerts |

## Data Sources

| Data Source | Description |
|-------------|-------------|
| `xdc_network` | Get network information (block height, epoch, gas price) |
| `xdc_validators` | Get current validator list |

## Quick Start

```hcl
terraform {
  required_providers {
    xdc = {
      source  = "AnilChinchawale/xdc"
      version = "~> 0.1"
    }
  }
}

provider "xdc" {
  endpoint    = "https://rpc.xinfin.network"
  private_key = var.xdc_private_key
}

# Deploy an XDC node
resource "xdc_node" "mainnet" {
  name    = "my-xdc-node"
  network = "mainnet"
  client  = "xdcchain"

  rpc_enabled = true
  rpc_port    = 8545
  ws_enabled  = true
  ws_port     = 8546
}

# Configure masternode
resource "xdc_masternode" "primary" {
  name           = "my-masternode"
  network        = "mainnet"
  coinbase       = "xdc..."
  staking_amount = "10000000"
  keystore_path  = var.keystore_path
}

# Set up backups
resource "xdc_backup" "daily" {
  node_id          = xdc_node.mainnet.id
  schedule         = "0 2 * * *"
  retention_days   = 30
  destination      = "s3"
  destination_path = "s3://my-bucket/xdc-backups"
}

# Configure monitoring
resource "xdc_monitor" "alerts" {
  node_id         = xdc_node.mainnet.id
  metrics_enabled = true
  metrics_port    = 9090
  alert_email     = "ops@example.com"

  alert_rules {
    name      = "high-peer-drop"
    condition = "peer_count < 5"
    threshold = 5
    severity  = "critical"
  }
}

# Read network info
data "xdc_network" "info" {}

data "xdc_validators" "current" {}
```

## Building

```bash
make build    # Build the provider binary
make install  # Install to local Terraform plugin directory
make test     # Run tests
```

## Status

🚧 **Scaffold** — resource CRUD operations are stubbed. Contributions welcome!
