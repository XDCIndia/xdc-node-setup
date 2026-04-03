#!/usr/bin/env bash
# =============================================================================
# config-manager.sh — XDC Node Configuration Management
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/98
#
# Usage:
#   config-manager.sh template <client> <network>   Generate compose from templates
#   config-manager.sh diff     <client> [network]   Diff running config vs template
#   config-manager.sh apply    <client> [network]   Regenerate and restart if changed
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIGS_DIR="$PROJECT_DIR/configs"
DOCKER_DIR="$PROJECT_DIR/docker"
GENERATED_DIR="$PROJECT_DIR/.generated"

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
die()   { error "$*"; exit 1; }

# ── helpers ───────────────────────────────────────────────────────────────────
normalise_client() {
  local c="${1,,}"
  case "$c" in
    gp5|go-xdc|geth)     echo "gp5"         ;;
    erigon|erigon-xdc)   echo "erigon"      ;;
    reth|rust-xdc)       echo "reth"        ;;
    nethermind|nm)       echo "nethermind"  ;;
    *)                   echo "$c"          ;;
  esac
}

normalise_network() {
  local n="${1,,}"
  case "$n" in
    mainnet|main)          echo "mainnet" ;;
    testnet|apothem)       echo "apothem" ;;
    devnet|dev)            echo "devnet"  ;;
    *)                     echo "$n"      ;;
  esac
}

# Resolve the canonical compose file for a client+network
compose_file_for() {
  local client="$1" network="$2"
  local candidates=(
    "$DOCKER_DIR/docker-compose.${client}-${network}.yml"
    "$DOCKER_DIR/docker-compose.${client}.yml"
    "$PROJECT_DIR/docker-compose.${client}-${network}.yml"
    "$PROJECT_DIR/docker-compose.${client}.yml"
  )

  # Map client aliases to compose filename patterns
  case "$client" in
    gp5)   candidates+=(
             "$DOCKER_DIR/docker-compose.gp5-${network}.yml"
             "$DOCKER_DIR/docker-compose.geth-pr5.yml"
             "$DOCKER_DIR/docker-compose.geth-pr5-standalone.yml"
           ) ;;
    reth)  candidates+=(
             "$DOCKER_DIR/docker-compose.reth-${network}.yml"
             "$DOCKER_DIR/docker-compose.reth.yml"
           ) ;;
  esac

  for f in "${candidates[@]}"; do
    [[ -f "$f" ]] && echo "$f" && return
  done
  echo ""
}

# Load ports.env and client.conf, export all vars
load_config() {
  local client="$1" network="$2"

  # Load port definitions
  if [[ -f "$CONFIGS_DIR/ports.env" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$CONFIGS_DIR/ports.env"
    set +a
  fi

  # Load network-level env
  local net_env="$CONFIGS_DIR/${network}.env"
  if [[ -f "$net_env" ]]; then
    set -a
    source "$net_env"
    set +a
  fi

  # Load client-specific conf
  local client_conf="$CONFIGS_DIR/clients/${client}.conf"
  if [[ -f "$client_conf" ]]; then
    set -a
    # Strip comment lines and blank lines, then source
    eval "$(grep -v '^\s*#' "$client_conf" | grep -v '^\s*$' | grep '=' || true)"
    set +a
  fi

  # Derive convenience vars based on client+network
  local NET_UPPER="${network^^}"   # MAINNET
  local CLI_UPPER

  case "$client" in
    gp5)         CLI_UPPER="GP5"         ;;
    erigon)      CLI_UPPER="ERIGON"      ;;
    reth)        CLI_UPPER="RETH"        ;;
    nethermind)  CLI_UPPER="NM"          ;;
    *)           CLI_UPPER="${client^^}" ;;
  esac

  # Resolve port variables → generic names used in templates
  export CLIENT="$client"
  export NETWORK="$network"
  export CLIENT_UPPER="$CLI_UPPER"
  export NETWORK_UPPER="$NET_UPPER"

  # Export resolved ports as generic names
  local rpc_var="${CLI_UPPER}_${NET_UPPER}_RPC"
  local ws_var="${CLI_UPPER}_${NET_UPPER}_WS"
  local p2p_var="${CLI_UPPER}_${NET_UPPER}_P2P"
  local auth_var="${CLI_UPPER}_${NET_UPPER}_AUTHRPC"
  local metrics_var="${CLI_UPPER}_${NET_UPPER}_METRICS"
  local skyone_var="${CLI_UPPER}_${NET_UPPER}_SKYONE"

  export RPC_PORT="${!rpc_var:-8545}"
  export WS_PORT="${!ws_var:-8546}"
  export P2P_PORT="${!p2p_var:-30303}"
  export AUTHRPC_PORT="${!auth_var:-8560}"
  export METRICS_PORT="${!metrics_var:-6060}"
  export SKYONE_PORT="${!skyone_var:-7060}"
}

# Simple envsubst-based template renderer
# Falls back to manual substitution if envsubst not available
render_template() {
  local template="$1"
  if command -v envsubst &>/dev/null; then
    envsubst < "$template"
  else
    # Manual substitution using sed
    local content
    content="$(cat "$template")"
    while IFS='=' read -r key val; do
      [[ -z "$key" || "$key" == \#* ]] && continue
      val="${val//\//\\/}"  # escape slashes
      content="$(echo "$content" | sed "s|\${${key}}|${val}|g; s|\$${key}|${val}|g")"
    done < <(env)
    echo "$content"
  fi
}

# =============================================================================
# CMD: template — generate compose from template + ports.env + client.conf
# =============================================================================
cmd_template() {
  local client="${1:-}" network="${2:-mainnet}"
  [[ -z "$client" ]] && die "Usage: config-manager.sh template <client> <network>"
  client="$(normalise_client "$client")"
  network="$(normalise_network "$network")"

  load_config "$client" "$network"

  local out_dir="$GENERATED_DIR/${client}/${network}"
  mkdir -p "$out_dir"
  local out_file="${out_dir}/docker-compose.yml"

  info "Generating compose for ${BOLD}$client${NC} on ${BOLD}$network${NC}"
  echo ""

  # ── Strategy: prefer explicit template file, else use existing compose ─────
  local template=""
  local template_candidates=(
    "$DOCKER_DIR/${client}/${network}/docker-compose.template.yml"
    "$DOCKER_DIR/${client}/docker-compose.template.yml"
    "$CONFIGS_DIR/examples/${client}-${network}.yml"
    "$CONFIGS_DIR/examples/${client}.yml"
  )

  for t in "${template_candidates[@]}"; do
    if [[ -f "$t" ]]; then
      template="$t"
      break
    fi
  done

  if [[ -n "$template" ]]; then
    info "Using template: $template"
    render_template "$template" > "$out_file"
  else
    # No dedicated template — find the closest matching compose file
    local src
    src="$(compose_file_for "$client" "$network")"

    if [[ -z "$src" ]]; then
      # Generate a minimal compose from scratch
      info "No existing compose found — generating minimal template"
      _generate_minimal_compose "$client" "$network" > "$out_file"
    else
      info "Using existing compose as base: $src"
      # Substitute port variables in the existing file
      cp "$src" "${out_file}.src"
      render_template "${out_file}.src" > "$out_file"
      rm -f "${out_file}.src"
    fi
  fi

  ok "Generated: $out_file"
  echo ""
  echo "Resolved ports:"
  echo "  RPC:     $RPC_PORT"
  echo "  WS:      $WS_PORT"
  echo "  P2P:     $P2P_PORT"
  echo "  AuthRPC: $AUTHRPC_PORT"
  echo "  Metrics: $METRICS_PORT"
  echo "  SkyOne:  $SKYONE_PORT"
  echo ""
  info "Review and apply: config-manager.sh apply $client $network"
}

# Generate a minimal docker-compose.yml from known defaults
_generate_minimal_compose() {
  local client="$1" network="$2"

  local image data_dir network_mode user_line restart extra_flags

  case "$client" in
    gp5)
      image="anilchinchawale/gx:latest"
      data_dir="./$network/xdcchain"
      network_mode="bridge"
      user_line=""
      restart="unless-stopped"
      extra_flags="--syncmode full --gcmode archive --http --http.addr 127.0.0.1 --http.port ${RPC_PORT}"
      ;;
    erigon)
      image="anilchinchawale/erix:latest"
      data_dir="./$network/xdcchain-erigon"
      network_mode="host"
      user_line="    user: \"1000:1000\""
      restart="unless-stopped"
      extra_flags="--chain xdc-$network --http.addr 127.0.0.1 --http.port ${RPC_PORT} --private.api.addr 127.0.0.1:${ERIGON_MAINNET_PRIVATE_API:-9091}"
      ;;
    reth)
      image="ghcr.io/paradigmxyz/reth:latest"
      data_dir="./$network/xdcchain-reth"
      network_mode="bridge"
      user_line=""
      restart="unless-stopped"
      extra_flags="--chain xdc --http --http.addr 127.0.0.1 --http.port ${RPC_PORT}"
      ;;
    nethermind)
      image="nethermind/nethermind:latest"
      data_dir="./$network/xdcchain-nm"
      network_mode="bridge"
      user_line=""
      restart="unless-stopped"
      extra_flags="--config xdc_${network} --JsonRpc.Enabled true --JsonRpc.Host 127.0.0.1 --JsonRpc.Port ${RPC_PORT}"
      ;;
    *)
      image="xdc/${client}:latest"
      data_dir="./$network/xdcchain-${client}"
      network_mode="bridge"
      user_line=""
      restart="unless-stopped"
      extra_flags=""
      ;;
  esac

  cat <<EOF
# Auto-generated by config-manager.sh
# Client: ${client}  Network: ${network}
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# DO NOT EDIT MANUALLY — regenerate with: config-manager.sh template ${client} ${network}

services:
  xdc-${client}-${network}:
    image: ${image}
    container_name: xdc-${client}-${network}
    restart: ${restart}
    network_mode: ${network_mode}
${user_line:+"$user_line"}
    volumes:
      - ${data_dir}:/data
    command: >
      ${extra_flags}
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://127.0.0.1:${RPC_PORT}"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

volumes:
  xdcchain-${client}-${network}:
    driver: local
EOF
}

# =============================================================================
# CMD: diff — show diff between running config and generated template
# =============================================================================
cmd_diff() {
  local client="${1:-}" network="${2:-mainnet}"
  [[ -z "$client" ]] && die "Usage: config-manager.sh diff <client> [network]"
  client="$(normalise_client "$client")"
  network="$(normalise_network "$network")"

  info "Diffing config for ${BOLD}$client${NC} ($network)"
  echo ""

  # Get the running (deployed) compose file
  local running
  running="$(compose_file_for "$client" "$network")"

  if [[ -z "$running" ]]; then
    die "No running compose file found for $client/$network"
  fi

  # Get the generated file
  local generated="$GENERATED_DIR/${client}/${network}/docker-compose.yml"

  if [[ ! -f "$generated" ]]; then
    info "No generated config yet. Run: config-manager.sh template $client $network"
    return 0
  fi

  echo -e "${BOLD}Running:   $running${NC}"
  echo -e "${BOLD}Generated: $generated${NC}"
  echo ""

  if diff -u "$running" "$generated" 2>/dev/null; then
    ok "No differences — configs are in sync."
  else
    echo ""
    warn "Differences found. Apply with: config-manager.sh apply $client $network"
  fi
}

# =============================================================================
# CMD: apply — regenerate template and restart container if config changed
# =============================================================================
cmd_apply() {
  local client="${1:-}" network="${2:-mainnet}"
  [[ -z "$client" ]] && die "Usage: config-manager.sh apply <client> [network]"
  client="$(normalise_client "$client")"
  network="$(normalise_network "$network")"

  info "Applying config for ${BOLD}$client${NC} ($network)"
  echo ""

  # Generate fresh template
  cmd_template "$client" "$network"

  local generated="$GENERATED_DIR/${client}/${network}/docker-compose.yml"
  local running
  running="$(compose_file_for "$client" "$network")"

  if [[ -z "$running" ]]; then
    warn "No running compose file found — using generated config."
    running="$PROJECT_DIR/docker-compose.${client}-${network}.yml"
    cp "$generated" "$running"
    ok "Wrote new compose file: $running"
  fi

  # Compare
  if diff -q "$running" "$generated" &>/dev/null; then
    ok "Config unchanged — no restart needed."
    return 0
  fi

  warn "Config has changed:"
  diff -u "$running" "$generated" || true
  echo ""

  # Backup and apply
  local backup="${running}.$(date +%Y%m%d%H%M%S).bak"
  info "Backing up current config: $backup"
  cp "$running" "$backup"

  info "Applying new config: $running"
  cp "$generated" "$running"

  # Restart containers
  local compose_dir
  compose_dir="$(dirname "$running")"
  local compose_file
  compose_file="$(basename "$running")"

  info "Restarting via docker compose…"
  if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
    (cd "$compose_dir" && docker compose -f "$compose_file" up -d --remove-orphans) && \
      ok "Containers restarted successfully." || \
      warn "docker compose failed — check compose file manually."
  else
    warn "docker compose not available — restart manually:"
    echo "  cd $compose_dir && docker-compose -f $compose_file up -d"
  fi

  ok "Config applied: $running"
}

# =============================================================================
# Entry point
# =============================================================================
usage() {
  cat <<EOF
${BOLD}config-manager.sh${NC} — XDC Node Configuration Management

Usage:
  config-manager.sh template <client> <network>   Generate compose from template + ports.env
  config-manager.sh diff     <client> [network]   Show diff between running and generated config
  config-manager.sh apply    <client> [network]   Apply new config and restart if changed

Clients:  gp5 | erigon | reth | nethermind
Networks: mainnet (default) | apothem | devnet

Generated configs are stored in: .generated/<client>/<network>/docker-compose.yml
Sources: configs/ports.env + configs/clients/<client>.conf + configs/<network>.env
EOF
}

case "${1:-help}" in
  template) shift; cmd_template "$@" ;;
  diff)     shift; cmd_diff     "$@" ;;
  apply)    shift; cmd_apply    "$@" ;;
  help|--help|-h) usage ;;
  *) error "Unknown command: $1"; usage; exit 1 ;;
esac
