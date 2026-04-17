# XDC Node Module - Variable Definitions

# ============================================
# Required Variables
# ============================================

variable "node_name" {
  description = "Name of the XDC node (used for resource naming)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,62}$", var.node_name))
    error_message = "Node name must be lowercase alphanumeric with hyphens, 3-63 characters, starting with a letter"
  }
}

variable "network" {
  description = "XDC network to connect to (mainnet, testnet, devnet)"
  type        = string
  default     = "mainnet"

  validation {
    condition     = contains(["mainnet", "testnet", "devnet"], var.network)
    error_message = "Network must be one of: mainnet, testnet, devnet"
  }
}

variable "client" {
  description = "XDC client implementation (XDPoSChain, erigon-xdc)"
  type        = string
  default     = "XDPoSChain"

  validation {
    condition     = contains(["XDPoSChain", "erigon-xdc"], var.client)
    error_message = "Client must be one of: XDPoSChain, erigon-xdc"
  }
}

variable "node_type" {
  description = "Type of node to deploy (full, archive, validator, rpc)"
  type        = string
  default     = "full"

  validation {
    condition     = contains(["full", "archive", "validator", "rpc"], var.node_type)
    error_message = "Node type must be one of: full, archive, validator, rpc"
  }
}

# ============================================
# Cloud Provider Settings
# ============================================

variable "cloud_provider" {
  description = "Cloud provider (aws, digitalocean, hetzner)"
  type        = string
  default     = "aws"

  validation {
    condition     = contains(["aws", "digitalocean", "hetzner"], var.cloud_provider)
    error_message = "Cloud provider must be one of: aws, digitalocean, hetzner"
  }
}

variable "region" {
  description = "Region/location for deployment"
  type        = string
  default     = "us-east-1"
}

variable "instance_size" {
  description = "Instance size (small, medium, large, xlarge)"
  type        = string
  default     = "medium"

  validation {
    condition     = contains(["small", "medium", "large", "xlarge"], var.instance_size)
    error_message = "Instance size must be one of: small, medium, large, xlarge"
  }
}

# ============================================
# Network Configuration
# ============================================

variable "enable_rpc" {
  description = "Enable HTTP RPC endpoint"
  type        = bool
  default     = true
}

variable "enable_ws" {
  description = "Enable WebSocket endpoint"
  type        = bool
  default     = false
}

variable "enable_metrics" {
  description = "Enable metrics endpoint"
  type        = bool
  default     = true
}

variable "rpc_port" {
  description = "HTTP RPC port"
  type        = number
  default     = 8545
}

variable "ws_port" {
  description = "WebSocket port"
  type        = number
  default     = 8546
}

variable "p2p_port" {
  description = "P2P networking port"
  type        = number
  default     = 30303
}

variable "metrics_port" {
  description = "Metrics port"
  type        = number
  default     = 6060
}

variable "allowed_rpc_cidrs" {
  description = "CIDR blocks allowed to access RPC"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to access SSH"
  type        = list(string)
  default     = []
}

variable "enable_public_rpc" {
  description = "Allow public access to RPC (use with caution)"
  type        = bool
  default     = false
}

# ============================================
# Storage Configuration
# ============================================

variable "data_volume_size" {
  description = "Size of data volume in GB"
  type        = number
  default     = 500

  validation {
    condition     = var.data_volume_size >= 100
    error_message = "Data volume must be at least 100 GB"
  }
}

variable "data_volume_type" {
  description = "Type of data volume (ssd, nvme)"
  type        = string
  default     = "ssd"

  validation {
    condition     = contains(["ssd", "nvme"], var.data_volume_type)
    error_message = "Volume type must be one of: ssd, nvme"
  }
}

variable "enable_volume_encryption" {
  description = "Enable encryption for data volumes"
  type        = bool
  default     = true
}

# ============================================
# Node Configuration
# ============================================

variable "xdc_version" {
  description = "Version of XDC client to deploy"
  type        = string
  default     = "latest"
}

variable "node_private_key" {
  description = "Node private key (hex). If empty, a new key will be generated"
  type        = string
  default     = ""
  sensitive   = true
}

variable "extra_flags" {
  description = "Additional flags to pass to the XDC client"
  type        = list(string)
  default     = []
}

variable "state_scheme" {
  description = "State database scheme (hash or path). Leave empty for auto-detection"
  type        = string
  default     = ""
}

variable "bootnodes" {
  description = "Custom bootnode URLs (overrides defaults)"
  type        = list(string)
  default     = []
}

variable "max_peers" {
  description = "Maximum number of peers"
  type        = number
  default     = 50
}

variable "cache_size" {
  description = "Database cache size in MB"
  type        = number
  default     = 4096
}

# ============================================
# Validator Configuration (if node_type = validator)
# ============================================

variable "validator_address" {
  description = "Validator wallet address"
  type        = string
  default     = ""
}

variable "validator_keystore" {
  description = "Path to validator keystore file"
  type        = string
  default     = ""
  sensitive   = true
}

# ============================================
# SSH & Access
# ============================================

variable "ssh_public_keys" {
  description = "SSH public keys for access"
  type        = list(string)
  default     = []
}

variable "ssh_key_name" {
  description = "Name of existing SSH key (cloud provider)"
  type        = string
  default     = ""
}

# ============================================
# DNS Configuration
# ============================================

variable "enable_dns" {
  description = "Enable DNS record creation"
  type        = bool
  default     = false
}

variable "dns_zone" {
  description = "DNS zone for node records"
  type        = string
  default     = ""
}

variable "dns_record_name" {
  description = "DNS record name (subdomain)"
  type        = string
  default     = ""
}

# ============================================
# Backup Configuration
# ============================================

variable "enable_backup" {
  description = "Enable automated backups"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "backup_bucket" {
  description = "S3/Object storage bucket for backups"
  type        = string
  default     = ""
}

# ============================================
# Monitoring & Alerting
# ============================================

variable "enable_monitoring" {
  description = "Enable Prometheus/Grafana monitoring stack"
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
  default     = ""
}

variable "slack_webhook" {
  description = "Slack webhook URL for alerts"
  type        = string
  default     = ""
  sensitive   = true
}

# ============================================
# Health Check
# ============================================

variable "enable_health_check" {
  description = "Enable post-deployment health checks"
  type        = bool
  default     = true
}

variable "node_ip" {
  description = "Node IP address (set after deployment)"
  type        = string
  default     = ""
}

# ============================================
# Tags
# ============================================

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"
}
