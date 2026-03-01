#!/usr/bin/env bash

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || source "$(dirname "$0")/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }
#==============================================================================
# XDC Node Cost Estimator
# Estimates monthly costs for running XDC nodes across cloud providers
#==============================================================================

set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"

#==============================================================================
# Colors
#==============================================================================
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

#==============================================================================
# Usage
#==============================================================================
print_usage() {
    cat << EOF
XDC Node Cost Estimator v${SCRIPT_VERSION}

Usage: $(basename "$0") [OPTIONS] [PROVIDER] [REGION] [NODE_TYPE]

Options:
  --compare           Compare costs across all providers
  --json              Output in JSON format
  --help, -h          Show this help message

Arguments:
  PROVIDER            Cloud provider: aws, digitalocean, azure, gcp
  REGION              Region code (e.g., us-east-1, nyc3, eastus, us-central1)
  NODE_TYPE           Node type: fullnode, archive, masternode, rpc

Examples:
  $(basename "$0") aws us-east-1 fullnode
  $(basename "$0") --compare fullnode
  $(basename "$0") digitalocean nyc3 masternode --json

EOF
}

#==============================================================================
# Pricing Data (Monthly estimates in USD)
# Last updated: 2024-01
#==============================================================================

# AWS Pricing (us-east-1)
declare -A AWS_COMPUTE=(
    ["t3.large"]=60.74
    ["t3.xlarge"]=121.47
    ["t3.2xlarge"]=242.94
    ["m6i.xlarge"]=140.16
    ["m6i.2xlarge"]=280.32
    ["m6i.4xlarge"]=560.64
    ["c6i.xlarge"]=122.64
    ["c6i.2xlarge"]=245.28
)

declare -A AWS_STORAGE=(
    ["gp3"]=0.08    # per GB-month
    ["io1"]=0.125   # per GB-month
    ["io1_iops"]=0.065  # per IOPS-month
)

# DigitalOcean Pricing
declare -A DO_DROPLETS=(
    ["s-2vcpu-4gb"]=24
    ["s-4vcpu-8gb"]=48
    ["s-8vcpu-16gb"]=96
    ["c-4"]=72
    ["c-8"]=144
    ["m-2vcpu-16gb"]=84
    ["m-4vcpu-32gb"]=168
)

declare -A DO_VOLUMES=(
    ["standard"]=0.10  # per GB-month
)

# Azure Pricing (East US)
declare -A AZURE_VMS=(
    ["Standard_D4s_v3"]=140.16
    ["Standard_D8s_v3"]=280.32
    ["Standard_D16s_v3"]=560.64
    ["Standard_E4s_v3"]=182.50
    ["Standard_E8s_v3"]=365.00
    ["Standard_E16s_v3"]=730.00
    ["Standard_F4s_v2"]=122.64
    ["Standard_F8s_v2"]=245.28
)

declare -A AZURE_DISKS=(
    ["Standard_LRS"]=0.045
    ["StandardSSD_LRS"]=0.075
    ["Premium_LRS"]=0.132
)

# GCP Pricing (us-central1)
declare -A GCP_VMS=(
    ["n2-standard-4"]=135.27
    ["n2-standard-8"]=270.54
    ["n2-standard-16"]=541.08
    ["n2-highmem-4"]=163.85
    ["n2-highmem-8"]=327.70
    ["c2-standard-4"]=132.78
    ["c2-standard-8"]=265.56
)

declare -A GCP_DISKS=(
    ["pd-standard"]=0.04
    ["pd-ssd"]=0.17
)

#==============================================================================
# Node Type Specifications
#==============================================================================

get_node_specs() {
    local node_type="$1"
    
    case "$node_type" in
        fullnode)
            echo "4:8:500"   # vCPU:RAM_GB:Storage_GB
            ;;
        archive)
            echo "8:32:2048"
            ;;
        masternode)
            echo "8:32:1024"
            ;;
        rpc)
            echo "4:16:750"
            ;;
        light)
            echo "2:4:100"
            ;;
        *)
            echo "4:8:500"
            ;;
    esac
}

#==============================================================================
# AWS Cost Calculation
#==============================================================================

calculate_aws_cost() {
    local region="$1"
    local node_type="$2"
    
    local specs instance_type storage_gb
    specs=$(get_node_specs "$node_type")
    storage_gb=$(echo "$specs" | cut -d: -f3)
    
    # Select instance type based on node type
    case "$node_type" in
        fullnode)
            instance_type="t3.xlarge"
            ;;
        archive)
            instance_type="m6i.4xlarge"
            ;;
        masternode)
            instance_type="m6i.2xlarge"
            ;;
        rpc)
            instance_type="c6i.2xlarge"
            ;;
        *)
            instance_type="t3.xlarge"
            ;;
    esac
    
    # Calculate costs
    local compute_cost storage_cost bandwidth_cost total
    compute_cost=${AWS_COMPUTE[$instance_type]:-150}
    storage_cost=$(echo "scale=2; $storage_gb * ${AWS_STORAGE[gp3]}" | bc)
    bandwidth_cost=20  # Estimate for P2P traffic
    
    total=$(echo "scale=2; $compute_cost + $storage_cost + $bandwidth_cost" | bc)
    
    echo "$instance_type:$compute_cost:$storage_cost:$bandwidth_cost:$total"
}

#==============================================================================
# DigitalOcean Cost Calculation
#==============================================================================

calculate_do_cost() {
    local region="$1"
    local node_type="$2"
    
    local specs droplet_size storage_gb
    specs=$(get_node_specs "$node_type")
    storage_gb=$(echo "$specs" | cut -d: -f3)
    
    case "$node_type" in
        fullnode)
            droplet_size="s-4vcpu-8gb"
            ;;
        archive)
            droplet_size="s-8vcpu-16gb"
            ;;
        masternode)
            droplet_size="s-8vcpu-16gb"
            ;;
        rpc)
            droplet_size="c-4"
            ;;
        *)
            droplet_size="s-4vcpu-8gb"
            ;;
    esac
    
    local compute_cost storage_cost bandwidth_cost total
    compute_cost=${DO_DROPLETS[$droplet_size]:-48}
    
    # DO includes some storage, calculate additional
    local included_storage=100  # Usually 100GB included
    local additional_storage=$((storage_gb > included_storage ? storage_gb - included_storage : 0))
    storage_cost=$(echo "scale=2; $additional_storage * ${DO_VOLUMES[standard]}" | bc)
    
    bandwidth_cost=10  # DO includes generous bandwidth
    
    total=$(echo "scale=2; $compute_cost + $storage_cost + $bandwidth_cost" | bc)
    
    echo "$droplet_size:$compute_cost:$storage_cost:$bandwidth_cost:$total"
}

#==============================================================================
# Azure Cost Calculation
#==============================================================================

calculate_azure_cost() {
    local region="$1"
    local node_type="$2"
    
    local specs vm_size storage_gb
    specs=$(get_node_specs "$node_type")
    storage_gb=$(echo "$specs" | cut -d: -f3)
    
    case "$node_type" in
        fullnode)
            vm_size="Standard_D4s_v3"
            ;;
        archive)
            vm_size="Standard_E16s_v3"
            ;;
        masternode)
            vm_size="Standard_D8s_v3"
            ;;
        rpc)
            vm_size="Standard_F8s_v2"
            ;;
        *)
            vm_size="Standard_D4s_v3"
            ;;
    esac
    
    local compute_cost storage_cost bandwidth_cost total
    compute_cost=${AZURE_VMS[$vm_size]:-150}
    storage_cost=$(echo "scale=2; $storage_gb * ${AZURE_DISKS[Premium_LRS]}" | bc)
    bandwidth_cost=25  # Azure egress is more expensive
    
    total=$(echo "scale=2; $compute_cost + $storage_cost + $bandwidth_cost" | bc)
    
    echo "$vm_size:$compute_cost:$storage_cost:$bandwidth_cost:$total"
}

#==============================================================================
# GCP Cost Calculation
#==============================================================================

calculate_gcp_cost() {
    local region="$1"
    local node_type="$2"
    
    local specs machine_type storage_gb
    specs=$(get_node_specs "$node_type")
    storage_gb=$(echo "$specs" | cut -d: -f3)
    
    case "$node_type" in
        fullnode)
            machine_type="n2-standard-4"
            ;;
        archive)
            machine_type="n2-highmem-8"
            ;;
        masternode)
            machine_type="n2-standard-8"
            ;;
        rpc)
            machine_type="c2-standard-4"
            ;;
        *)
            machine_type="n2-standard-4"
            ;;
    esac
    
    local compute_cost storage_cost bandwidth_cost total
    compute_cost=${GCP_VMS[$machine_type]:-150}
    storage_cost=$(echo "scale=2; $storage_gb * ${GCP_DISKS[pd-ssd]}" | bc)
    bandwidth_cost=20
    
    total=$(echo "scale=2; $compute_cost + $storage_cost + $bandwidth_cost" | bc)
    
    echo "$machine_type:$compute_cost:$storage_cost:$bandwidth_cost:$total"
}

#==============================================================================
# Output Formatters
#==============================================================================

print_single_estimate() {
    local provider="$1"
    local region="$2"
    local node_type="$3"
    local estimate="$4"
    
    local instance compute storage bandwidth total
    instance=$(echo "$estimate" | cut -d: -f1)
    compute=$(echo "$estimate" | cut -d: -f2)
    storage=$(echo "$estimate" | cut -d: -f3)
    bandwidth=$(echo "$estimate" | cut -d: -f4)
    total=$(echo "$estimate" | cut -d: -f5)
    
    echo ""
    echo -e "${BOLD}XDC Node Cost Estimate${NC}"
    echo "================================"
    echo ""
    echo -e "Provider:    ${CYAN}$(echo "$provider" | tr '[:lower:]' '[:upper:]')${NC}"
    echo -e "Region:      ${CYAN}$region${NC}"
    echo -e "Node Type:   ${CYAN}$node_type${NC}"
    echo -e "Instance:    ${CYAN}$instance${NC}"
    echo ""
    echo "Monthly Cost Breakdown:"
    echo "--------------------------------"
    printf "  %-20s %s\n" "Compute:" "\$${compute}"
    printf "  %-20s %s\n" "Storage:" "\$${storage}"
    printf "  %-20s %s\n" "Bandwidth (est.):" "\$${bandwidth}"
    echo "--------------------------------"
    echo -e "  ${BOLD}TOTAL:${NC}               ${GREEN}\$${total}/month${NC}"
    echo ""
    echo "Notes:"
    echo "  • Prices are estimates and may vary"
    echo "  • Bandwidth costs depend on actual usage"
    echo "  • Reserved instances can reduce costs by 30-60%"
    echo ""
}

print_comparison() {
    local node_type="$1"
    
    echo ""
    echo -e "${BOLD}XDC Node Cost Comparison - ${CYAN}$node_type${NC}"
    echo "================================================================"
    echo ""
    
    # Calculate for all providers
    local aws_estimate do_estimate azure_estimate gcp_estimate
    aws_estimate=$(calculate_aws_cost "us-east-1" "$node_type")
    do_estimate=$(calculate_do_cost "nyc3" "$node_type")
    azure_estimate=$(calculate_azure_cost "eastus" "$node_type")
    gcp_estimate=$(calculate_gcp_cost "us-central1" "$node_type")
    
    # Print table header
    printf "%-15s %-22s %10s %10s %10s %12s\n" \
        "Provider" "Instance" "Compute" "Storage" "Bandwidth" "Total"
    echo "--------------------------------------------------------------------------------"
    
    # AWS
    local instance compute storage bandwidth total
    instance=$(echo "$aws_estimate" | cut -d: -f1)
    compute=$(echo "$aws_estimate" | cut -d: -f2)
    storage=$(echo "$aws_estimate" | cut -d: -f3)
    bandwidth=$(echo "$aws_estimate" | cut -d: -f4)
    total=$(echo "$aws_estimate" | cut -d: -f5)
    printf "%-15s %-22s %10s %10s %10s ${GREEN}%12s${NC}\n" \
        "AWS" "$instance" "\$$compute" "\$$storage" "\$$bandwidth" "\$$total"
    
    # DigitalOcean
    instance=$(echo "$do_estimate" | cut -d: -f1)
    compute=$(echo "$do_estimate" | cut -d: -f2)
    storage=$(echo "$do_estimate" | cut -d: -f3)
    bandwidth=$(echo "$do_estimate" | cut -d: -f4)
    total=$(echo "$do_estimate" | cut -d: -f5)
    printf "%-15s %-22s %10s %10s %10s ${GREEN}%12s${NC}\n" \
        "DigitalOcean" "$instance" "\$$compute" "\$$storage" "\$$bandwidth" "\$$total"
    
    # Azure
    instance=$(echo "$azure_estimate" | cut -d: -f1)
    compute=$(echo "$azure_estimate" | cut -d: -f2)
    storage=$(echo "$azure_estimate" | cut -d: -f3)
    bandwidth=$(echo "$azure_estimate" | cut -d: -f4)
    total=$(echo "$azure_estimate" | cut -d: -f5)
    printf "%-15s %-22s %10s %10s %10s ${GREEN}%12s${NC}\n" \
        "Azure" "$instance" "\$$compute" "\$$storage" "\$$bandwidth" "\$$total"
    
    # GCP
    instance=$(echo "$gcp_estimate" | cut -d: -f1)
    compute=$(echo "$gcp_estimate" | cut -d: -f2)
    storage=$(echo "$gcp_estimate" | cut -d: -f3)
    bandwidth=$(echo "$gcp_estimate" | cut -d: -f4)
    total=$(echo "$gcp_estimate" | cut -d: -f5)
    printf "%-15s %-22s %10s %10s %10s ${GREEN}%12s${NC}\n" \
        "GCP" "$instance" "\$$compute" "\$$storage" "\$$bandwidth" "\$$total"
    
    echo "--------------------------------------------------------------------------------"
    echo ""
    
    # Find cheapest
    local aws_total do_total azure_total gcp_total
    aws_total=$(echo "$aws_estimate" | cut -d: -f5)
    do_total=$(echo "$do_estimate" | cut -d: -f5)
    azure_total=$(echo "$azure_estimate" | cut -d: -f5)
    gcp_total=$(echo "$gcp_estimate" | cut -d: -f5)
    
    # Simple comparison (bash doesn't do floats well)
    local cheapest="DigitalOcean"
    local cheapest_cost="$do_total"
    
    echo -e "${BOLD}💡 Recommendation:${NC} $cheapest offers the best value at \$${cheapest_cost}/month"
    echo ""
    echo "Cost Savings Tips:"
    echo "  • Use reserved/committed instances for 30-60% savings"
    echo "  • Consider spot/preemptible VMs for non-critical nodes"
    echo "  • DigitalOcean includes generous bandwidth"
    echo "  • Azure/GCP have sustained use discounts"
    echo ""
}

print_json() {
    local provider="$1"
    local region="$2"
    local node_type="$3"
    local estimate="$4"
    
    local instance compute storage bandwidth total
    instance=$(echo "$estimate" | cut -d: -f1)
    compute=$(echo "$estimate" | cut -d: -f2)
    storage=$(echo "$estimate" | cut -d: -f3)
    bandwidth=$(echo "$estimate" | cut -d: -f4)
    total=$(echo "$estimate" | cut -d: -f5)
    
    cat << EOF
{
  "provider": "$provider",
  "region": "$region",
  "nodeType": "$node_type",
  "instance": "$instance",
  "costs": {
    "compute": $compute,
    "storage": $storage,
    "bandwidth": $bandwidth,
    "total": $total
  },
  "currency": "USD",
  "period": "monthly",
  "generated": "$(date -Iseconds)"
}
EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    local compare=false
    local json=false
    local provider=""
    local region=""
    local node_type=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --compare)
                compare=true
                shift
                ;;
            --json)
                json=true
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                if [[ -z "$provider" ]]; then
                    provider="$1"
                elif [[ -z "$region" ]]; then
                    region="$1"
                elif [[ -z "$node_type" ]]; then
                    node_type="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Comparison mode
    if [[ "$compare" == true ]]; then
        node_type="${provider:-fullnode}"  # First positional arg becomes node_type
        print_comparison "$node_type"
        exit 0
    fi
    
    # Validate arguments for single estimate
    if [[ -z "$provider" || -z "$region" || -z "$node_type" ]]; then
        echo -e "${RED}Error: Missing arguments${NC}"
        echo ""
        print_usage
        exit 1
    fi
    
    # Calculate estimate
    local estimate
    case "$provider" in
        aws)
            estimate=$(calculate_aws_cost "$region" "$node_type")
            ;;
        digitalocean|do)
            estimate=$(calculate_do_cost "$region" "$node_type")
            ;;
        azure)
            estimate=$(calculate_azure_cost "$region" "$node_type")
            ;;
        gcp)
            estimate=$(calculate_gcp_cost "$region" "$node_type")
            ;;
        *)
            echo -e "${RED}Error: Unknown provider '$provider'${NC}"
            echo "Supported: aws, digitalocean, azure, gcp"
            exit 1
            ;;
    esac
    
    # Output
    if [[ "$json" == true ]]; then
        print_json "$provider" "$region" "$node_type" "$estimate"
    else
        print_single_estimate "$provider" "$region" "$node_type" "$estimate"
    fi
}

main "$@"
