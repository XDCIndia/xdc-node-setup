# Coding Conventions — xdc-node-setup

## Shell Scripts

### Shebang and Options

```bash
#!/usr/bin/env bash
set -euo pipefail
```

Always use `bash`, not `sh`. Always set `errexit`, `nounset`, `pipefail`.

### Script Header

Every script must have a header block:

```bash
#!/usr/bin/env bash
#==============================================================================
# Short description of what this script does
#
# Usage:
#   ./script.sh [options]
#
# Options:
#   --flag    Description
#
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/NNN
#==============================================================================
```

### Variables

```bash
# Constants: UPPER_SNAKE_CASE, readonly
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Config with defaults: allow env override
LOG_DIR="${LOG_DIR:-/var/log/xdc-node}"
DRY_RUN="${DRY_RUN:-false}"

# Arrays
declare -A CLIENT_PORTS=(
  [geth]=8545
  [erigon]=8547
)
```

### Functions

```bash
# Functions: lower_snake_case
# Always declare local variables
check_client_health() {
  local client="$1"
  local port="${2:-8545}"
  # ...
}
```

### Logging

```bash
# Use consistent log format
log()  { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
warn() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] WARN: $*" >&2; }
err()  { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" >&2; }
```

### Dry-run Support

Scripts that modify state MUST support `--dry-run`:

```bash
if [[ "${DRY_RUN}" == false ]]; then
  docker restart "${container}"
else
  log "[DRY-RUN] Would restart ${container}"
fi
```

### Error Handling

```bash
# Use || with meaningful messages
docker pull "${image}" || { err "Failed to pull ${image}"; exit 1; }

# Trap for cleanup
trap 'err "Script failed at line $LINENO"' ERR
```

## JSON Output

Structured data files use JSON. Schema:

```json
{
  "timestamp": "2026-04-03T10:00:00Z",
  "client": "erigon",
  "action": "...",
  "result": "ok|failed|dry_run",
  "detail": "..."
}
```

Arrays of entries are wrapped: `[{...}, {...}]`

## File Organization

- `scripts/` — Executable scripts, `chmod +x`
- `scripts/lib/` — Sourced libraries, not executed directly
- `configs/` — Templates and static config
- `data/` — Runtime output, not committed (add to `.gitignore`)
- `docs/` — Human-readable documentation
- `agents/` — AI agent persona definitions
- `.agent/` — AI-native context and skills

## Commit Messages

Format: `<type>(<scope>): <description>`

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`

```
feat(scripts): add autonomous incident-response loop
fix(erigon): correct state root bypass for mainnet
docs(agents): add fleet-operator persona
chore(data): add benchmark result directories
```

Rules:
- Subject line ≤ 72 characters
- Use imperative mood ("add", not "added")
- Reference issue: `Closes #121` in body
- No period at end of subject

## PR Format

```markdown
## Summary
<!-- 2-3 sentences: what and why -->

## Changes
- [ ] Added `scripts/incident-response.sh`
- [ ] Created `data/incidents/` directory

## Testing
- Ran with `--dry-run` on mainnet
- Unit tested with mock RPC

## Related Issues
Closes #121
```

## Client Naming

Canonical names (lowercase, use in code):
- `geth` — go-ethereum XDC fork (also called gp5, go-xdc)
- `erigon` — Erigon XDC port
- `nethermind` — Nethermind with XDC plugin
- `reth` — Rust Ethereum (experimental)

## Network Naming

- `mainnet` — XDC Network mainnet (chain ID 50)
- `apothem` — XDC testnet (chain ID 51)
- `devnet` — Local development network

## Permissions

All executable scripts: `chmod 755`
Config files and docs: `chmod 644`
