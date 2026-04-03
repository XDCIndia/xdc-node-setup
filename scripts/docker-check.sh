#!/usr/bin/env bash
# =============================================================================
# docker-check.sh — Docker / Compose Best Practices Validator
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/88
#
# Usage:
#   docker-check.sh [path/to/docker-compose.yml ...]
#   docker-check.sh --all       (scan project for all compose files)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
pass()  { echo -e "  ${GREEN}✓${NC} $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*"; ((ISSUES++)); }
warn()  { echo -e "  ${YELLOW}!${NC} $*"; ((WARNINGS++)); }
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }

ISSUES=0
WARNINGS=0

# =============================================================================
# Check a single compose file
# =============================================================================
check_compose() {
  local file="$1"
  echo ""
  echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
  echo -e "${BOLD} Checking: $file${NC}"
  echo -e "${BOLD}══════════════════════════════════════════════════${NC}"

  # ── 1. File validity ───────────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}[ Syntax Validation ]${NC}"

  if command -v docker &>/dev/null; then
    local compose_cmd
    if docker compose version &>/dev/null 2>&1; then
      compose_cmd="docker compose"
    else
      compose_cmd="docker-compose"
    fi

    local compose_dir
    compose_dir="$(dirname "$file")"
    local compose_file
    compose_file="$(basename "$file")"

    if (cd "$compose_dir" && $compose_cmd -f "$compose_file" config --quiet 2>/dev/null); then
      pass "Compose file is valid YAML and passes docker compose config"
    else
      fail "Compose file failed docker compose config validation"
      # Show error
      (cd "$compose_dir" && $compose_cmd -f "$compose_file" config 2>&1 | head -20) || true
    fi
  else
    # Fallback: basic YAML check via python or yq
    if command -v python3 &>/dev/null; then
      if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        pass "YAML syntax is valid (python3)"
      else
        fail "Invalid YAML syntax"
      fi
    elif command -v yq &>/dev/null; then
      if yq e '.' "$file" &>/dev/null; then
        pass "YAML syntax is valid (yq)"
      else
        fail "Invalid YAML syntax"
      fi
    else
      warn "docker and python3/yq not found — skipping syntax validation"
    fi
  fi

  # ── 2. Volume mount source validation ─────────────────────────────────────
  echo ""
  echo -e "${BOLD}[ Volume Mounts ]${NC}"

  local compose_dir
  compose_dir="$(dirname "$file")"

  # Extract bind mounts (source:target or src:dst)
  grep -oP '(?<=- )[./~][^:]+(?=:)' "$file" 2>/dev/null | \
  while read -r src; do
    # Expand relative paths
    if [[ "$src" == ./* || "$src" == ../* ]]; then
      src="$compose_dir/$src"
    fi

    # Expand ~ (unlikely in compose but handle it)
    src="${src/#\~/$HOME}"

    # Check if source is a file being mounted as a file (not a dir)
    # Common file mounts: jwt.hex, genesis.json, config files
    if [[ "$src" =~ \.(json|toml|yaml|yml|env|hex|conf|key|pem|crt)$ ]]; then
      if [[ ! -f "$src" ]]; then
        fail "Volume source should be a FILE but doesn't exist: $src"
        warn "  Docker will create it as a directory, causing errors."
        warn "  Fix: touch $src (or provide the actual file)"
      else
        pass "File mount exists: $src"
      fi
    elif [[ ! -e "$src" ]]; then
      warn "Volume source doesn't exist yet: $src (will be created as dir)"
    fi
  done

  # ── 3. Erigon uid/gid check ───────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}[ Erigon User/Group (uid 1000) ]${NC}"

  if grep -qi "erigon" "$file"; then
    # Check if user is set to 1000
    if grep -qP 'user:\s*(1000|"1000"|1000:1000)' "$file"; then
      pass "Erigon service has user: 1000 set"
    else
      warn "Erigon service found but 'user: 1000' not set."
      warn "  Erigon MDBX requires uid 1000. Add: user: \"1000:1000\""
    fi

    # Check volume directory ownership on host
    grep -oP '(?<=- )[./~][^:]+(?=:)' "$file" | \
    grep -i "erigon\|mdbx\|xdcchain-erigon" | \
    while read -r vol; do
      [[ "$vol" == ./* ]] && vol="$compose_dir/$vol"
      if [[ -d "$vol" ]]; then
        local owner
        owner="$(stat -c '%u' "$vol" 2>/dev/null || echo "?")"
        if [[ "$owner" == "1000" ]]; then
          pass "Erigon volume $vol owned by uid 1000"
        else
          fail "Erigon volume $vol owned by uid $owner (should be 1000)"
          warn "  Fix: chown -R 1000:1000 $vol"
        fi
      fi
    done
  else
    info "No Erigon services detected in this file."
  fi

  # ── 4. network_mode consistency ───────────────────────────────────────────
  echo ""
  echo -e "${BOLD}[ network_mode Consistency ]${NC}"

  local host_count bridge_count
  host_count="$(grep -c 'network_mode:.*host' "$file" 2>/dev/null || echo 0)"
  bridge_count="$(grep -c 'network_mode:.*bridge' "$file" 2>/dev/null || echo 0)"
  # Services without explicit network_mode default to bridge in Compose
  local default_count
  default_count="$(grep -c '^\s\{2,4\}[a-z]' "$file" 2>/dev/null || echo 0)"

  if [[ "$host_count" -gt 0 && "$bridge_count" -gt 0 ]]; then
    warn "Mix of host and bridge network modes. Ensure ports aren't conflicting."
    warn "  host_mode services: $host_count, bridge services: $bridge_count"
  elif [[ "$host_count" -gt 0 ]]; then
    pass "All services use host networking (no port mapping needed)"
    # Check that host-mode services don't also declare ports:
    if grep -A5 'network_mode:.*host' "$file" | grep -q 'ports:'; then
      fail "Services with network_mode: host should NOT have 'ports:' declarations"
    fi
  else
    pass "Services use bridge/default networking"
  fi

  # ── 5. restart policy ─────────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}[ Restart Policies ]${NC}"

  # Count services vs services with restart:
  local service_names
  service_names="$(grep -oP '^\s{2}[a-z][a-z0-9_-]+(?=:)' "$file" 2>/dev/null | grep -v 'volumes\|networks\|configs\|secrets\|version' || true)"

  if [[ -z "$service_names" ]]; then
    info "Could not parse service names."
  else
    echo "$service_names" | while read -r svc; do
      svc="${svc#"${svc%%[! ]*}"}"  # trim leading spaces
      # Look for restart: under this service block
      # Simple check: does the file contain restart: after this service?
      if grep -A 20 "^  ${svc}:" "$file" 2>/dev/null | grep -q 'restart:'; then
        local policy
        policy="$(grep -A 20 "^  ${svc}:" "$file" | grep 'restart:' | head -1 | grep -oP '(?<=restart: )\S+')"
        pass "Service '$svc': restart: $policy"
      else
        fail "Service '$svc': no restart policy defined"
        warn "  Add: restart: unless-stopped"
      fi
    done
  fi

  # ── 6. Image tag pinning ───────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}[ Image Tags ]${NC}"

  grep -oP 'image:\s*\K\S+' "$file" 2>/dev/null | \
  while read -r img; do
    if [[ "$img" == *":latest" || ! "$img" == *":"* ]]; then
      warn "Image not pinned to specific version: $img"
      warn "  Use: image: ghcr.io/xdcfoundation/erigon-xdc:v2.60.0 etc."
    else
      pass "Image pinned: $img"
    fi
  done

  # ── 7. Healthcheck presence ────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}[ Healthchecks ]${NC}"

  if grep -q 'healthcheck:' "$file"; then
    pass "Healthcheck(s) defined"
  else
    warn "No healthchecks defined. Consider adding healthcheck: blocks."
  fi
}

# =============================================================================
# Entry point
# =============================================================================
usage() {
  cat <<EOF
${BOLD}docker-check.sh${NC} — Docker Compose Best Practices Validator

Usage:
  docker-check.sh [file1.yml] [file2.yml ...]
  docker-check.sh --all    Scan entire project for compose files

Checks:
  ✓ Compose file YAML validity (docker compose config)
  ✓ Volume mount sources exist as files (not dirs)
  ✓ Erigon uid/gid = 1000
  ✓ network_mode consistency (no host+bridge mix)
  ✓ restart policies on all services
  ✓ Image tag pinning (no :latest)
  ✓ Healthcheck presence
EOF
}

# Collect files to check
FILES=()

if [[ "${1:-}" == "--all" || "${1:-}" == "-a" ]]; then
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find "$PROJECT_DIR" -maxdepth 5 \
    \( -name "docker-compose*.yml" -o -name "compose.yml" -o -name "docker-compose*.yaml" \) \
    ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null | sort)
elif [[ $# -eq 0 ]]; then
  # Default: check current dir or project root
  for default in "docker-compose.yml" "compose.yml" "$PROJECT_DIR/docker-compose.yml"; do
    [[ -f "$default" ]] && FILES+=("$default") && break
  done
  if [[ ${#FILES[@]} -eq 0 ]]; then
    warn "No compose file found. Use --all to scan the project."
    usage
    exit 0
  fi
else
  for f in "$@"; do
    [[ -f "$f" ]] || { echo "Not found: $f"; continue; }
    FILES+=("$f")
  done
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No compose files found."
  exit 0
fi

for f in "${FILES[@]}"; do
  check_compose "$f"
done

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${BOLD} Summary${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "  Files checked: ${#FILES[@]}"
echo -e "  ${RED}Errors:${NC}   $ISSUES"
echo -e "  ${YELLOW}Warnings:${NC} $WARNINGS"

if [[ $ISSUES -gt 0 ]]; then
  echo ""
  echo -e "${RED}Fix errors before running docker compose up.${NC}"
  exit 1
else
  echo ""
  ok "All checks passed (${WARNINGS} warnings)."
fi
