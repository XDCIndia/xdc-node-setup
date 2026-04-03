#!/usr/bin/env bash
# =============================================================================
# security.sh — XDC Node Security Hardening
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/87
#
# Usage:
#   security.sh audit             Check RPC binding and exposure
#   security.sh nodekey [client]  Generate/rotate node key
#   security.sh jwt               Generate JWT secret for authrpc
#   security.sh firewall          Suggest iptables rules for P2P ports
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIGS_DIR="$PROJECT_DIR/configs"
KEYS_DIR="$PROJECT_DIR/.keys"

# Load port definitions
[[ -f "$CONFIGS_DIR/ports.env" ]] && source "$CONFIGS_DIR/ports.env"

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
die()   { error "$*"; exit 1; }
pass()  { echo -e "  ${GREEN}✓${NC} $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*"; }
note()  { echo -e "  ${YELLOW}!${NC} $*"; }

# =============================================================================
# CMD: audit — check RPC binding (127.0.0.1 in prod, warn if 0.0.0.0)
# =============================================================================
cmd_audit() {
  echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║   XDC Node Security Audit                ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
  echo ""

  local issues=0

  # ── 1. Check RPC listening interfaces ─────────────────────────────────────
  echo -e "${BOLD}[ RPC Exposure ]${NC}"

  # Ports to audit: all RPC and WS ports from ports.env
  local rpc_ports=(8545 8546 8547 8548 8549 8558 8559 8560 8561 8562 8563
                   8645 8646 8647 8648 8649 8658 8659 8660 8661 8662 8663)

  for port in "${rpc_ports[@]}"; do
    local bind
    bind="$(ss -tlnp 2>/dev/null | awk -v p=":$port " '$0 ~ p {print $4}' | head -1 || true)"
    [[ -z "$bind" ]] && continue  # port not in use

    if echo "$bind" | grep -q "0.0.0.0"; then
      fail "Port $port is bound to 0.0.0.0 (PUBLIC exposure!)"
      note "RPC/WS should only listen on 127.0.0.1 in production."
      note "Fix: add --http.addr 127.0.0.1 (geth/erigon) or --rpc-addr 127.0.0.1 (reth)"
      ((issues++))
    elif echo "$bind" | grep -qE "127\.0\.0\.1|::1"; then
      pass "Port $port bound to localhost only ($bind)"
    else
      warn "Port $port bound to $bind — verify this is intentional"
      ((issues++))
    fi
  done

  # ── 2. Check authRPC (engine API) ─────────────────────────────────────────
  echo ""
  echo -e "${BOLD}[ AuthRPC / Engine API ]${NC}"
  local auth_ports=(8560 8561 8562 8563 8660 8661 8662 8663)
  for port in "${auth_ports[@]}"; do
    local bind
    bind="$(ss -tlnp 2>/dev/null | awk -v p=":$port " '$0 ~ p {print $4}' | head -1 || true)"
    [[ -z "$bind" ]] && continue
    if echo "$bind" | grep -q "0.0.0.0"; then
      fail "AuthRPC port $port is public! JWT auth required."
      note "Ensure JWT secret is set: security.sh jwt"
      ((issues++))
    else
      pass "AuthRPC port $port: $bind"
    fi
  done

  # ── 3. Check P2P ports (should be public) ─────────────────────────────────
  echo ""
  echo -e "${BOLD}[ P2P Ports (should be reachable externally) ]${NC}"
  local p2p_ports=(30303 30304 30305 30306 30307 30313 30314 30315 30316)
  for port in "${p2p_ports[@]}"; do
    local bind
    bind="$(ss -tlnp 2>/dev/null | awk -v p=":$port " '$0 ~ p {print $4}' | head -1 || true)"
    local udp_bind
    udp_bind="$(ss -ulnp 2>/dev/null | awk -v p=":$port " '$0 ~ p {print $4}' | head -1 || true)"
    if [[ -n "$bind" || -n "$udp_bind" ]]; then
      pass "P2P port $port is listening (${bind:-UDP:$udp_bind})"
    fi
  done

  # ── 4. Check for open metrics/debug ports ─────────────────────────────────
  echo ""
  echo -e "${BOLD}[ Metrics / Debug Endpoints ]${NC}"
  local metrics_ports=(6060 6061 6062 6063 6064 6160 6161 6162 6163 6164)
  for port in "${metrics_ports[@]}"; do
    local bind
    bind="$(ss -tlnp 2>/dev/null | awk -v p=":$port " '$0 ~ p {print $4}' | head -1 || true)"
    [[ -z "$bind" ]] && continue
    if echo "$bind" | grep -q "0.0.0.0"; then
      warn "Metrics port $port is public. Consider restricting to 127.0.0.1."
      note "Scrape via SSH tunnel or move behind Nginx with auth."
      ((issues++))
    else
      pass "Metrics port $port: $bind (localhost)"
    fi
  done

  # ── 5. Docker compose file checks ─────────────────────────────────────────
  echo ""
  echo -e "${BOLD}[ Docker Compose Port Bindings ]${NC}"
  find "$PROJECT_DIR" -maxdepth 4 -name "docker-compose*.yml" -o -name "compose.yml" 2>/dev/null | \
  while read -r compose; do
    local exposed
    exposed="$(grep -oP '(?<=")\d+:\d+(?=")' "$compose" 2>/dev/null || \
               grep -oP '^\s+- "\d+:\d+"' "$compose" 2>/dev/null || true)"
    if [[ -n "$exposed" ]]; then
      note "$(basename "$(dirname "$compose")")/$(basename "$compose") exposes ports:"
      echo "$exposed" | while read -r p; do
        local hp="${p%%:*}"
        # RPC/WS range
        if [[ "$hp" =~ ^8[5-6] ]]; then
          warn "  Port $hp mapped to host — ensure firewall blocks external access to RPC"
          ((issues++)) || true
        else
          echo "    $p"
        fi
      done
    fi
  done

  # ── Summary ───────────────────────────────────────────────────────────────
  echo ""
  if [[ $issues -eq 0 ]]; then
    ok "Security audit passed — no issues found."
  else
    warn "Found ${issues} potential security issue(s). Review and fix."
    echo ""
    echo "Quick fixes:"
    echo "  • Restrict RPC: --http.addr 127.0.0.1"
    echo "  • Generate JWT: security.sh jwt"
    echo "  • Add firewall: security.sh firewall"
  fi
}

# =============================================================================
# CMD: nodekey — generate/rotate node key per client
# =============================================================================
cmd_nodekey() {
  local client="${1:-all}"
  mkdir -p "$KEYS_DIR"
  chmod 700 "$KEYS_DIR"

  local clients
  if [[ "$client" == "all" ]]; then
    clients=(gp5 erigon reth nethermind)
  else
    clients=("$client")
  fi

  for c in "${clients[@]}"; do
    local keyfile="$KEYS_DIR/${c}-nodekey"

    if [[ -f "$keyfile" ]]; then
      warn "Rotating existing nodekey for ${c}: $keyfile"
      cp "$keyfile" "${keyfile}.$(date +%Y%m%d%H%M%S).bak"
    fi

    # Generate 32-byte (256-bit) random private key as hex
    local key
    key="$(openssl rand -hex 32)"
    echo "$key" > "$keyfile"
    chmod 600 "$keyfile"

    ok "Generated nodekey for ${c}: $keyfile"
    echo "  Key (first 16 chars): ${key:0:16}…"
    echo ""
    echo "  Mount in compose:"
    case "$c" in
      gp5)
        echo "    --nodekey /data/.keys/${c}-nodekey"
        ;;
      erigon)
        echo "    --p2p.privatekey /data/.keys/${c}-nodekey"
        ;;
      reth)
        echo "    --p2p.secret-key /data/.keys/${c}-nodekey"
        ;;
      nethermind)
        echo "    --Network.DiscoveryPort (nodekey managed internally)"
        ;;
    esac
    echo ""
  done

  warn "Keep .keys/ out of version control! Add to .gitignore."
}

# =============================================================================
# CMD: jwt — generate JWT secret for authrpc
# =============================================================================
cmd_jwt() {
  local jwt_file="${1:-$PROJECT_DIR/.keys/jwt.hex}"
  mkdir -p "$(dirname "$jwt_file")"
  chmod 700 "$(dirname "$jwt_file")"

  if [[ -f "$jwt_file" ]]; then
    warn "JWT secret already exists: $jwt_file"
    echo "Rotating…"
    cp "$jwt_file" "${jwt_file}.$(date +%Y%m%d%H%M%S).bak"
  fi

  # Generate 256-bit JWT secret (EIP-3675 format: 0x-prefixed hex)
  local secret
  secret="0x$(openssl rand -hex 32)"
  echo "$secret" > "$jwt_file"
  chmod 600 "$jwt_file"

  ok "JWT secret generated: $jwt_file"
  echo "  Secret (first 20 chars): ${secret:0:20}…"
  echo ""
  echo "Mount in docker-compose:"
  echo "  volumes:"
  echo "    - .keys/jwt.hex:/data/jwt.hex:ro"
  echo ""
  echo "Client flags:"
  echo "  GP5:        --authrpc.jwtsecret /data/jwt.hex"
  echo "  Erigon:     --authrpc.jwtsecret /data/jwt.hex"
  echo "  Reth:       --authrpc.jwtsecret /data/jwt.hex"
  echo "  Nethermind: --JsonRpc.JwtSecretFile /data/jwt.hex"
}

# =============================================================================
# CMD: firewall — suggest iptables rules for P2P-only exposure
# =============================================================================
cmd_firewall() {
  echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║   Recommended iptables Rules — XDC Node  ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo "# Save to /etc/iptables/rules.v4 or apply with iptables-restore"
  echo ""
  cat <<'RULES'
# ── Allow established connections ──────────────────────────────────────────
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# ── SSH (adjust port if non-standard) ──────────────────────────────────────
-A INPUT -p tcp --dport 22 -j ACCEPT

# ── XDC P2P ports — Mainnet ────────────────────────────────────────────────
# GP5 / go-xdc
-A INPUT -p tcp --dport 30303 -j ACCEPT
-A INPUT -p udp --dport 30303 -j ACCEPT
# Erigon
-A INPUT -p tcp --dport 30304 -j ACCEPT
-A INPUT -p udp --dport 30304 -j ACCEPT
# Nethermind
-A INPUT -p tcp --dport 30305 -j ACCEPT
-A INPUT -p udp --dport 30305 -j ACCEPT
# Reth TCP
-A INPUT -p tcp --dport 30306 -j ACCEPT
# Reth Discovery UDP
-A INPUT -p udp --dport 30307 -j ACCEPT

# ── XDC P2P ports — Apothem (testnet) ─────────────────────────────────────
-A INPUT -p tcp --dport 30313 -j ACCEPT
-A INPUT -p udp --dport 30313 -j ACCEPT
-A INPUT -p tcp --dport 30314 -j ACCEPT
-A INPUT -p udp --dport 30314 -j ACCEPT
-A INPUT -p tcp --dport 30315 -j ACCEPT
-A INPUT -p udp --dport 30315 -j ACCEPT
-A INPUT -p tcp --dport 30316 -j ACCEPT
-A INPUT -p udp --dport 30317 -j ACCEPT

# ── Erigon BitTorrent (snapshot sync) ─────────────────────────────────────
-A INPUT -p tcp --dport 42069 -j ACCEPT
-A INPUT -p udp --dport 42069 -j ACCEPT

# ── BLOCK all RPC/WS/AuthRPC from external ─────────────────────────────────
# These should ONLY be accessible via localhost / SSH tunnel
-A INPUT -p tcp --dport 8545:8600 -j DROP
-A INPUT -p tcp --dport 8645:8700 -j DROP
# Metrics (scrape via Prometheus inside the same host/VPC)
-A INPUT -p tcp --dport 6060:6165 -j DROP

# ── Drop everything else ───────────────────────────────────────────────────
-A INPUT -j DROP
RULES

  echo ""
  echo -e "${BOLD}Apply these rules:${NC}"
  echo "  sudo iptables-restore < /path/to/rules"
  echo "  sudo netfilter-persistent save   # persist across reboots"
  echo ""
  echo -e "${BOLD}Or with ufw:${NC}"
  echo "  ufw allow 22/tcp"
  echo "  ufw allow 30303:30320/tcp"
  echo "  ufw allow 30303:30320/udp"
  echo "  ufw allow 42069/tcp"
  echo "  ufw allow 42069/udp"
  echo "  ufw deny 8545:8700/tcp"
  echo "  ufw deny 6060:6165/tcp"
  echo "  ufw enable"
  echo ""

  # Check existing firewall state
  echo -e "${BOLD}Current firewall status:${NC}"
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw status numbered 2>/dev/null
  elif command -v iptables &>/dev/null; then
    iptables -L INPUT -n --line-numbers 2>/dev/null | head -30 || warn "Run as root to see iptables rules"
  else
    warn "No firewall tool found. Install ufw: apt install ufw"
  fi
}

# =============================================================================
# Entry point
# =============================================================================
usage() {
  cat <<EOF
${BOLD}security.sh${NC} — XDC Node Security Hardening

Usage:
  security.sh audit              Audit RPC binding and exposure
  security.sh nodekey [client]   Generate/rotate node private key
  security.sh jwt [outfile]      Generate JWT secret for authrpc
  security.sh firewall           Show recommended iptables/ufw rules

Clients: gp5 | erigon | reth | nethermind | all (default)
EOF
}

case "${1:-help}" in
  audit)    cmd_audit    ;;
  nodekey)  shift; cmd_nodekey  "$@" ;;
  jwt)      shift; cmd_jwt      "$@" ;;
  firewall) cmd_firewall ;;
  help|--help|-h) usage ;;
  *) error "Unknown command: $1"; usage; exit 1 ;;
esac
