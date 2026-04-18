# Implementation Plan: `xdc deploy` CLI Command

**Issue:** #140 — Add `xdc deploy` CLI command to xdc-node-setup  
**Repository:** XDCIndia/xdc-node-setup  
**Target File:** `cli/xdc` (~5736 lines bash)  
**Plan Version:** 1.0.0  
**Date:** 2026-04-18

---

## 1. Overview

Add a new `xdc deploy` command that allows one-line deployment of XDC nodes by:
- Resolving the correct Docker Compose file from `--client` + `--network`
- Auto-detecting binary names, CLI flags, network IDs, and ports
- Running pre-flight checks (Docker, ports, disk, permissions)
- Generating and exporting environment variables
- Executing `docker compose up -d`
- Performing post-deploy health checks
- Integrating with the existing `xdc status` command

---

## 2. Desired UX

```bash
# Deploy v2.6.8 mainnet
xdc deploy --client v268 --network mainnet --data-root /mnt/data

# Deploy v2.6.8 apothem
xdc deploy --client v268 --network apothem --data-root /mnt/data

# Deploy GP5 mainnet (uses --http flags)
xdc deploy --client gp5 --network mainnet --data-root /mnt/data

# Deploy with dry-run
xdc deploy --client v268 --network mainnet --data-root /mnt/data --dry-run

# Deploy with monitoring
xdc deploy --client v268 --network mainnet --data-root /mnt/data --monitoring

# Check status afterward
xdc status --all
```

---

## 3. Step-by-Step Implementation

### 3.1 Define the Client Registry (New Config Block)

**Location:** In `cli/xdc`, after the existing `readonly` config declarations (around line 64, after `readonly NOTIFY_CONF`).

Add a structured client registry using bash associative patterns. Because bash <4 lacks true associative arrays, use a prefix-key convention already used elsewhere in the script.

```bash
#==============================================================================
# Client Registry for deploy command (Issue #140)
#==============================================================================

# Client canonical names: v268, gp5, erigon, nethermind, reth
# Network names: mainnet, apothem

# Compose file paths (relative to PROJECT_DIR)
_client_compose_v268_mainnet="docker/mainnet/v268.yml"
_client_compose_v268_apothem="docker/apothem/v268.yml"
_client_compose_gp5_mainnet="docker/docker-compose.geth-pr5.yml"
_client_compose_gp5_apothem="docker/docker-compose.gp5-apothem.yml"
_client_compose_erigon_mainnet="docker/docker-compose.erigon.yml"
_client_compose_erigon_apothem="docker/docker-compose.erigon-testnet.yml"
_client_compose_nethermind_mainnet="docker/docker-compose.nethermind.yml"
_client_compose_nethermind_apothem="docker/docker-compose.nethermind-testnet.yml"
_client_compose_reth_mainnet="docker/docker-compose.reth.yml"
# reth apothem uses standalone or reth.yml with NETWORK override
_client_compose_reth_apothem="docker/docker-compose.reth-standalone.yml"

# Binary names per client
_client_binary_v268_mainnet="XDC-mainnet"
_client_binary_v268_apothem="XDC-testnet"
_client_binary_gp5="geth"
_client_binary_erigon="erigon"
_client_binary_nethermind="nethermind"
_client_binary_reth="reth"

# Network IDs
_network_id_mainnet="50"
_network_id_apothem="51"

# Flag style: legacy (v268) vs modern (gp5, erigon, nethermind, reth)
_client_flagstyle_v268="legacy"   # uses --rpc / --rpcaddr / --rpcport / --ws / --wsaddr
_client_flagstyle_gp5="modern"    # uses --http / --http.addr / --http.port / --ws / --ws.addr
_client_flagstyle_erigon="modern"
_client_flagstyle_nethermind="modern"
_client_flagstyle_reth="modern"
```

> **Note:** Do NOT use bash 4 associative arrays to preserve compatibility with macOS bash 3.2. Use the prefix-key pattern shown above.

---

### 3.2 Implement `cmd_deploy()` Function

**Location:** In `cli/xdc`, after `cmd_client()` (which ends around line 3676). Place `cmd_deploy()` immediately before `cmd_peers()` (line 3710).

#### 3.2.1 Full Function Skeleton

```bash
#==============================================================================
# Command: deploy
# Issue: #140
#==============================================================================
cmd_deploy() {
    local client=""
    local network=""
    local data_root=""
    local dry_run=false
    local monitoring=false
    local logging=false
    local force=false
    local skip_healthcheck=false
    local env_file=""
    local compose_override=""
    
    # --- Argument Parsing ---
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                cat << 'EOF'
$(c BOLD)xdc deploy$(c NC) — Deploy an XDC node via Docker Compose

$(c BOLD)USAGE:$(c NC)
    xdc deploy --client CLIENT --network NETWORK [OPTIONS]

$(c BOLD)REQUIRED OPTIONS:$(c NC)
    --client CLIENT      Client to deploy: v268, gp5, erigon, nethermind, reth
    --network NETWORK    Network to deploy on: mainnet, apothem
    --data-root PATH     Host path for blockchain data (e.g. /mnt/data)

$(c BOLD)OPTIONAL OPTIONS:$(c NC)
    --env-file PATH      Path to additional .env file to source
    --compose PATH       Override the auto-resolved compose file
    --monitoring         Also start the monitoring stack (Prometheus + Grafana)
    --logging            Also start the log aggregation stack (Loki + Promtail)
    --dry-run            Show what would be done without executing
    --force              Skip "already running" warnings and redeploy
    --skip-healthcheck   Skip post-deploy RPC health check
    --help               Show this help

$(c BOLD)EXAMPLES:$(c NC)
    xdc deploy --client v268 --network mainnet --data-root /mnt/data
    xdc deploy --client gp5 --network apothem --data-root /mnt/data
    xdc deploy --client v268 --network mainnet --data-root /mnt/data --monitoring
    xdc deploy --client erigon --network mainnet --data-root /mnt/data --dry-run

$(c BOLD)NOTES:$(c NC)
    - v2.6.8 (v268) uses legacy --rpc flags; all others use modern --http flags.
    - Mainnet network ID is 50; Apothem is 51.
    - Correct binary is auto-selected (XDC-mainnet vs XDC-testnet for v268).
    - Ports are auto-configured from configs/ports.env.

EOF
                return 0
                ;;
            --client)
                client="$2"
                shift 2
                ;;
            --network)
                network="$2"
                shift 2
                ;;
            --data-root)
                data_root="$2"
                shift 2
                ;;
            --env-file)
                env_file="$2"
                shift 2
                ;;
            --compose)
                compose_override="$2"
                shift 2
                ;;
            --monitoring)
                monitoring=true
                shift
                ;;
            --logging)
                logging=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --skip-healthcheck)
                skip_healthcheck=true
                shift
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # --- Validation ---
    if [[ -z "$client" ]]; then
        die "Missing required option: --client. Run 'xdc deploy --help' for usage."
    fi
    if [[ -z "$network" ]]; then
        die "Missing required option: --network. Run 'xdc deploy --help' for usage."
    fi
    if [[ -z "$data_root" ]]; then
        die "Missing required option: --data-root. Run 'xdc deploy --help' for usage."
    fi
    
    # Normalize client aliases
    case "$client" in
        v268|v2.6.8|stable|xdc-stable) client="v268" ;;
        gp5|geth-pr5|gx|pr5) client="gp5" ;;
        erigon|erigon-xdc) client="erigon" ;;
        nethermind|nm) client="nethermind" ;;
        reth|reth-xdc) client="reth" ;;
        *)
            die "Unknown client: $client. Supported: v268, gp5, erigon, nethermind, reth"
            ;;
    esac
    
    # Normalize network
    case "$network" in
        mainnet|xinfin|xdc) network="mainnet" ;;
        apothem|testnet) network="apothem" ;;
        *)
            die "Unknown network: $network. Supported: mainnet, apothem"
            ;;
    esac
    
    # --- Resolve Compose File ---
    local compose_file=""
    if [[ -n "$compose_override" ]]; then
        compose_file="$compose_override"
        if [[ ! -f "$compose_file" ]]; then
            die "Compose override file not found: $compose_file"
        fi
    else
        local key="_client_compose_${client}_${network}"
        compose_file="${!key:-}"
        if [[ -z "$compose_file" ]]; then
            die "No compose file registered for client=$client network=$network"
        fi
        # Make absolute relative to PROJECT_DIR
        compose_file="${PROJECT_DIR}/${compose_file}"
    fi
    
    if [[ ! -f "$compose_file" ]]; then
        die "Compose file not found: $compose_file"
    fi
    
    # --- Resolve Metadata ---
    local network_id=""
    case "$network" in
        mainnet) network_id="$_network_id_mainnet" ;;
        apothem) network_id="$_network_id_apothem" ;;
    esac
    
    local binary_name=""
    if [[ "$client" == "v268" ]]; then
        local bin_key="_client_binary_${client}_${network}"
        binary_name="${!bin_key}"
    else
        local bin_key="_client_binary_${client}"
        binary_name="${!bin_key}"
    fi
    
    local flag_style=""
    local flag_key="_client_flagstyle_${client}"
    flag_style="${!flag_key:-modern}"
    
    # --- Determine RPC URL for Health Check ---
    local rpc_port=""
    local env_port_var=""
    case "$client" in
        v268)
            env_port_var="V268_${network^^}_RPC"
            ;;
        gp5)
            env_port_var="GP5_${network^^}_RPC"
            ;;
        erigon)
            env_port_var="ERIGON_${network^^}_RPC"
            ;;
        nethermind)
            env_port_var="NM_${network^^}_RPC"
            ;;
        reth)
            env_port_var="RETH_${network^^}_RPC"
            ;;
    esac
    
    # Source ports.env if available
    if [[ -f "${CONFIGS_DIR}/ports.env" ]]; then
        source "${CONFIGS_DIR}/ports.env"
    fi
    rpc_port="${!env_port_var:-}"
    # Fallback defaults if ports.env missing or var empty
    if [[ -z "$rpc_port" ]]; then
        case "$client" in
            v268) rpc_port="8550" ;;
            gp5)  rpc_port="8545" ;;
            erigon) rpc_port="8547" ;;
            nethermind) rpc_port="8558" ;;
            reth) rpc_port="8548" ;;
        esac
        # Apothem offset (+100)
        if [[ "$network" == "apothem" ]]; then
            rpc_port=$((rpc_port + 100))
        fi
    fi
    local rpc_url="http://localhost:${rpc_port}"
    
    # --- Pre-flight Checks ---
    log "Running pre-flight checks..."
    
    # 1. Docker available
    if ! command -v docker &>/dev/null; then
        die "Docker is not installed or not in PATH."
    fi
    if ! docker info &>/dev/null; then
        die "Docker daemon is not running or user lacks permissions."
    fi
    
    # 2. docker compose plugin available
    if ! docker compose version &>/dev/null; then
        die "Docker Compose plugin not found. Install docker-compose-plugin."
    fi
    
    # 3. Data root exists and is writable
    if [[ ! -d "$data_root" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            info "[dry-run] Would create directory: $data_root"
        else
            info "Creating data root: $data_root"
            mkdir -p "$data_root" || die "Failed to create data root: $data_root"
        fi
    fi
    if [[ ! -w "$data_root" ]]; then
        die "Data root is not writable: $data_root"
    fi
    
    # 4. Port availability (only for host-network or published ports)
    # v268 uses network_mode: host; others use port mapping
    local ports_to_check=()
    if [[ "$client" == "v268" ]]; then
        local p2p_port_var="V268_${network^^}_P2P"
        local ws_port_var="V268_${network^^}_WS"
        local p2p_port="${!p2p_port_var:-30310}"
        local ws_port="${!ws_port_var:-8551}"
        [[ "$network" == "apothem" ]] && p2p_port=$((p2p_port + 10)) && ws_port=$((ws_port + 100))
        ports_to_check=("$rpc_port" "$ws_port" "$p2p_port")
    else
        # For port-mapped clients, check the host-side bind port
        ports_to_check=("$rpc_port")
    fi
    
    for port in "${ports_to_check[@]}"; do
        if command -v ss &>/dev/null; then
            if ss -tln | awk '{print $4}' | grep -qE ":${port}$"; then
                if [[ "$force" != "true" ]]; then
                    die "Port $port is already in use. Use --force to override."
                else
                    warn "Port $port is already in use (--force set, continuing)"
                fi
            fi
        elif command -v netstat &>/dev/null; then
            if netstat -tln 2>/dev/null | awk '{print $4}' | grep -qE ":${port}$"; then
                if [[ "$force" != "true" ]]; then
                    die "Port $port is already in use. Use --force to override."
                else
                    warn "Port $port is already in use (--force set, continuing)"
                fi
            fi
        fi
    done
    
    # 5. Disk space (require at least 50 GB free)
    local required_gb=50
    local available_kb
    available_kb=$(df -k "$data_root" | awk 'NR==2 {print $4}')
    local available_gb=$((available_kb / 1024 / 1024))
    if [[ $available_gb -lt $required_gb ]]; then
        die "Insufficient disk space on $data_root: ${available_gb}G available, ${required_gb}G required."
    fi
    
    # 6. Check for existing container
    local existing_container=""
    existing_container=$(docker ps -a --format '{{.Names}}' | grep -E "^${client}-${network}-|^xdc-node-${client}-|^xdc-node-" | head -1 || true)
    if [[ -n "$existing_container" && "$force" != "true" ]]; then
        die "Existing container detected: $existing_container. Use --force to redeploy."
    fi
    
    # --- Environment Variable Generation ---
    local env_exports=()
    env_exports+=("DATA_ROOT=${data_root}")
    env_exports+=("NETWORK=${network}")
    env_exports+=("NETWORK_ID=${network_id}")
    
    # Client-specific env vars
    case "$client" in
        v268)
            env_exports+=("V268_IMAGE=xinfinorg/xdposchain:v2.6.8")
            ;;
        gp5)
            env_exports+=("GP5_IMAGE=anilchinchawale/gp5-xdc:v34")
            ;;
        erigon)
            env_exports+=("ERIGON_IMAGE=anilchinchawale/erigon-xdc:latest")
            ;;
        nethermind)
            env_exports+=("NM_IMAGE=anilchinchawale/nmx:latest")
            ;;
        reth)
            env_exports+=("RETH_IMAGE=anilchinchawale/xdc-reth:latest")
            ;;
    esac
    
    # Source additional env file if provided
    if [[ -n "$env_file" && -f "$env_file" ]]; then
        info "Loading environment from $env_file"
        # In dry-run, just report; otherwise export each line
        while IFS='=' read -r key val; do
            [[ -z "$key" || "$key" =~ ^# ]] && continue
            env_exports+=("${key}=${val}")
        done < <(grep -v '^\s*#' "$env_file" | grep '=')
    fi
    
    # --- Dry Run Output ---
    if [[ "$dry_run" == "true" ]]; then
        info "[dry-run] Deployment plan:"
        echo "  Client:       $client"
        echo "  Network:      $network (id=$network_id)"
        echo "  Data root:    $data_root"
        echo "  Binary:       $binary_name"
        echo "  Flag style:   $flag_style"
        echo "  Compose file: $compose_file"
        echo "  RPC URL:      $rpc_url"
        echo "  Environment:"
        for e in "${env_exports[@]}"; do
            echo "    export $e"
        done
        if [[ "$monitoring" == "true" ]]; then
            echo "  + monitoring stack (docker-compose.monitoring.yml)"
        fi
        if [[ "$logging" == "true" ]]; then
            echo "  + logging stack (docker-compose.logging.yml)"
        fi
        return 0
    fi
    
    # --- Execute Deployment ---
    log "Deploying $client on $network..."
    start_spinner "Deploying $client $network node"
    
    # Build the compose command
    local compose_cmd=("docker" "compose" "-f" "$compose_file")
    
    if [[ "$monitoring" == "true" ]]; then
        local monitoring_file="${PROJECT_DIR}/docker/docker-compose.monitoring.yml"
        if [[ -f "$monitoring_file" ]]; then
            compose_cmd+=("-f" "$monitoring_file")
        else
            warn "Monitoring compose file not found, skipping"
        fi
    fi
    
    if [[ "$logging" == "true" ]]; then
        local logging_file="${PROJECT_DIR}/docker/docker-compose.logging.yml"
        if [[ -f "$logging_file" ]]; then
            compose_cmd+=("-f" "$logging_file")
        else
            warn "Logging compose file not found, skipping"
        fi
    fi
    
    compose_cmd+=("up" "-d")
    
    # Export environment variables for docker compose
    for e in "${env_exports[@]}"; do
        export "$e"
    done
    
    # Run compose
    if "${compose_cmd[@]}" >/dev/null 2>&1; then
        stop_spinner true "Deployed $client $network node"
    else
        stop_spinner false "Deployment failed"
        # Attempt to capture logs for debugging
        error "Docker compose failed. Run with --verbose for details."
        error "Command: ${compose_cmd[*]}"
        return 1
    fi
    
    # --- Post-Deploy Health Check ---
    if [[ "$skip_healthcheck" != "true" ]]; then
        log "Waiting for RPC to become available at $rpc_url..."
        local attempts=0
        local max_attempts=30
        local healthy=false
        
        while [[ $attempts -lt $max_attempts ]]; do
            local resp
            resp=$(rpc_call "$rpc_url" "eth_blockNumber" 2>/dev/null || echo '{}')
            local result
            result=$(echo "$resp" | jq -r '.result // empty')
            if [[ -n "$result" && "$result" != "null" ]]; then
                healthy=true
                break
            fi
            sleep 2
            attempts=$((attempts + 1))
        done
        
        if [[ "$healthy" == "true" ]]; then
            log "Health check passed: RPC responding at $rpc_url"
        else
            warn "Health check timed out after $((max_attempts * 2)) seconds."
            warn "Container may still be starting. Run 'xdc status' to check."
        fi
    fi
    
    # --- Save Deployment State ---
    local state_dir="${XDC_STATE_DIR}"
    mkdir -p "$state_dir"
    cat > "${state_dir}/deploy.state.json" << STATE
{
  "client": "$client",
  "network": "$network",
  "networkId": $network_id,
  "dataRoot": "$data_root",
  "composeFile": "$compose_file",
  "rpcUrl": "$rpc_url",
  "deployedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "binary": "$binary_name",
  "flagStyle": "$flag_style"
}
STATE
    
    # --- Summary ---
    echo ""
    echo -e "$(c GREEN)✓$(c NC) Deployment complete"
    echo ""
    echo -e "$(c BOLD)Container:$(c NC)    $(docker compose -f "$compose_file" ps --format '{{.Name}}' 2>/dev/null | head -1 || echo 'N/A')"
    echo -e "$(c BOLD)Client:$(c NC)       $client"
    echo -e "$(c BOLD)Network:$(c NC)      $network (chain ID: $network_id)"
    echo -e "$(c BOLD)Data root:$(c NC)    $data_root"
    echo -e "$(c BOLD)RPC endpoint:$(c NC) $rpc_url"
    echo ""
    echo -e "$(c DIM)Run 'xdc status' to monitor sync progress.$(c NC)"
}
```

> **Important:** The `$(c BOLD)` / `$(c NC)` inside the heredoc for `--help` will NOT work inside a single-quoted heredoc. Change the `--help` block to use `cat << EOF` (unquoted) so that the `$(c ...)` calls are evaluated. The example above already uses `cat << 'EOF'` which is incorrect — it should be `cat << EOF` to match the pattern used by `cmd_start()` and others.

---

### 3.3 Register Command in `main()` Dispatch

**Location:** `cli/xdc`, inside `main()` at the case statement (around line 5636–5680).

Add `deploy)` alongside `start)`:

```bash
        init)       cmd_init "$@" ;;
        status)     cmd_status "$@" ;;
        info)       cmd_status "$@" ;;
        deploy)     cmd_deploy "$@" ;;   # <-- ADD THIS LINE
        health)     cmd_health "$@" ;;
```

**Also add to the help dispatch** (around line 5683–5721) so that `xdc help deploy` works:

```bash
                    start)      cmd_start --help ;;
                    deploy)     cmd_deploy --help ;;   # <-- ADD THIS LINE
                    config)     cmd_config --help ;;
```

---

### 3.4 Add `deploy` to `print_help()` Summary

**Location:** `cli/xdc`, inside `print_help()` (around line 121–210).

Add `deploy` to the general commands list:

```
$(c BOLD)GENERAL COMMANDS:$(c NC)
    init             Interactive setup wizard
    start            Start the node
    deploy           Deploy a new node via Docker Compose   # <-- ADD THIS
    stop             Stop the node
```

---

### 3.5 Update `xdc status --all` to Include Deployed Nodes

**Location:** `cli/xdc`, `cmd_status()` (starting line 640).

The existing `cmd_status()` already checks for `xdc-node` and `xdc-node-erigon` containers. We should augment it to also discover containers launched by `xdc deploy`.

In the `show_status()` helper, add a container discovery loop at the top:

```bash
    show_status() {
        local rpc_url="${XDC_RPC_URL:-http://localhost:8545}"
        local mainnet_rpc="${MAINNET_RPC_URL:-https://erpc.xinfin.network}"
        
        # Discover all XDC containers (legacy + deploy command)
        local containers=()
        while IFS= read -r name; do
            [[ -n "$name" ]] && containers+=("$name")
        done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -E '^xdc-node|^v268-|^gp5-|^erigon-|^nethermind-|^reth-' || true)
        
        # If no containers found via naming, fallback to legacy check
        ... (rest of existing logic)
```

This ensures `xdc status --all` (or just `xdc status`) will detect nodes deployed via `xdc deploy` even if they use non-standard container names like `test-v268-mainnet-168`.

---

### 3.6 Pre-flight Check Helpers (Optional Refactor)

If the pre-flight checks inside `cmd_deploy()` grow too large, extract these helpers and place them near the other utility functions (around line 330):

```bash
# Check if a TCP port is listening on localhost
check_port_free() {
    local port="$1"
    if command -v ss &>/dev/null; then
        ss -tln | awk '{print $4}' | grep -qE ":${port}$" && return 1
    elif command -v netstat &>/dev/null; then
        netstat -tln 2>/dev/null | awk '{print $4}' | grep -qE ":${port}$" && return 1
    fi
    return 0
}

# Check available disk space in GB
check_disk_space() {
    local path="$1"
    local required_gb="$2"
    local available_kb
    available_kb=$(df -k "$path" | awk 'NR==2 {print $4}')
    local available_gb=$((available_kb / 1024 / 1024))
    [[ $available_gb -ge $required_gb ]]
}
```

For the initial implementation, it is acceptable to inline these checks inside `cmd_deploy()` and extract them in a follow-up refactor.

---

## 4. Error Handling and Rollback

### 4.1 Rollback on Failure

Inside `cmd_deploy()`, if `docker compose up -d` fails, optionally run a cleanup:

```bash
    # Run compose
    if "${compose_cmd[@]}" >/dev/null 2>&1; then
        stop_spinner true "Deployed $client $network node"
    else
        stop_spinner false "Deployment failed"
        error "Docker compose failed. Attempting rollback..."
        
        # Rollback: remove partially created containers for this project
        docker compose -f "$compose_file" down --remove-orphans 2>/dev/null || true
        
        error "Command: ${compose_cmd[*]}"
        return 1
    fi
```

> **Note:** Do NOT delete the data directory on rollback — only remove containers/volumes created by compose. User data must be preserved.

### 4.2 Partial Success Handling

If the deployment succeeds but the health check fails, the function should:
1. Print a warning (not die)
2. Still write `deploy.state.json`
3. Advise the user to run `xdc logs` or `xdc status`

This matches the existing pattern in `cmd_start()` where inject_peers is called with `|| true`.

---

## 5. Integration with Existing Commands

| Existing Command | Integration Point |
|------------------|-------------------|
| `xdc status` | Discover deploy-launched containers by name pattern (see 3.5) |
| `xdc start` | If `deploy.state.json` exists, `xdc start` could read it to know which compose file to use. **For this issue, only document the relationship; do not modify `cmd_start()` unless explicitly requested.** |
| `xdc stop` | Already works via `find_container()` for common names. For deploy-specific names, users can run `docker compose -f <file> down`. **Future enhancement:** teach `cmd_stop()` to read `deploy.state.json`. |
| `xdc logs` | Same as above — works for common container names. |
| `xdc client` | Could read `deploy.state.json` to show the deployed client. **Future enhancement.** |

---

## 6. Testing Checklist

Before marking the issue complete, verify:

- [ ] `xdc deploy --help` prints formatted help with examples
- [ ] `xdc deploy --client v268 --network mainnet --data-root /tmp/xdc-test` deploys successfully
- [ ] `xdc deploy --client v268 --network apothem --data-root /tmp/xdc-test` uses `XDC-testnet` binary and networkid 51
- [ ] `xdc deploy --client gp5 --network mainnet --data-root /tmp/xdc-test` uses modern `--http` flags
- [ ] `xdc deploy ... --dry-run` prints plan without executing
- [ ] `xdc deploy ... --force` redeploys even when port/container exists
- [ ] Missing `--client`, `--network`, or `--data-root` exits with clear error
- [ ] Unknown client/network exits with clear error
- [ ] Post-deploy health check detects RPC availability
- [ ] `xdc status` shows the newly deployed container
- [ ] `deploy.state.json` is written to `XDC_STATE_DIR`
- [ ] Rollback removes containers but preserves data directory on failure

---

## 7. Files to Modify

| File | Change |
|------|--------|
| `cli/xdc` | Add client registry vars, `cmd_deploy()` function, dispatch in `main()`, help text in `print_help()` |
| `configs/ports.env` | No changes required (existing vars are sufficient) |
| `docker/mainnet/v268.yml` | No changes required |
| `docker/apothem/v268.yml` | No changes required |

---

## 8. Future Enhancements (Out of Scope for #140)

1. Teach `cmd_start()`, `cmd_stop()`, `cmd_restart()` to read `deploy.state.json` and operate on deploy-managed containers.
2. Add `--snapshot URL` support to `xdc deploy` to auto-download a snapshot before first start.
3. Add Kubernetes manifest resolution (`k8s/` directory) for `--runtime k8s`.
4. Auto-generate systemd service files for non-Docker deployments.
5. Support `xdc deploy --client nethermind --network apothem` once a dedicated apothem compose file exists.

---

## 9. Commit Message

```
feat(cli): add xdc deploy command for one-line node deployment

Issue: #140

- Add cmd_deploy() with client/network resolution and pre-flight checks
- Auto-detect binary, flags, network ID, and compose file
- Support --dry-run, --force, --monitoring, --logging
- Integrate with xdc status for container discovery
- Write deployment state to deploy.state.json
```
