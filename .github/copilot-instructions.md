# GitHub Copilot Instructions — xdc-node-setup

## What This Repo Is

Operational scripts and tooling for running XDC Network nodes. Multi-client support:
- `geth` — go-ethereum fork with XDPoS consensus (chain 50/51)
- `erigon` — staged sync client with XDPoS port
- `nethermind` — .NET client with XDC plugin
- `reth` — Rust Ethereum client (experimental)

## Key Technical Context

Read `.agent/CONTEXT.md` for complete technical details. Key points:

**Ports (mainnet):** geth=8545, erigon=8547, nethermind=8548, reth=8588

**Consensus:** XDPoS v2 — HotStuff BFT, 108 validators, 900-block epochs.
Epoch transition blocks run special state transitions — clients must be in sync.

**Data paths:** `/data/{client}/` on host, mounted into Docker containers named `xdc-{client}`.

## Bash Script Conventions

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Config with env overrides
MY_VAR="${MY_VAR:-default_value}"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

my_function() {
  local arg1="$1"
  local arg2="${2:-default}"
  # ...
}
```

## Suggestions to Prioritize

- Use `--dry-run` patterns for destructive operations
- Structure output as JSON in `data/` subdirectories
- Reference port variables from `configs/ports.env` instead of hardcoding
- Check `scripts/lib/` for shared utilities before writing new helper functions
- Follow existing script patterns in `scripts/` for consistency

## Suggestions to Avoid

- Don't suggest `#!/bin/sh` — always use `#!/usr/bin/env bash`
- Don't hardcode IP addresses or ports
- Don't suggest `set -e` alone — always use `set -euo pipefail`
- Don't suggest `curl http://` for production — require HTTPS or localhost
- Don't suggest committing anything to `data/` directories (runtime output)

## Agent Personas

For AI-assisted work with this repo, see `agents/`:
- `agents/fleet-operator.md` — fleet/deployment tasks
- `agents/incident-commander.md` — incident response
- `agents/node-doctor.md` — deep diagnostics
- `agents/security-auditor.md` — security audits

## Troubleshooting Skills

- `.agent/skills/sync-debug.md` — client-specific sync debugging
- `.agent/skills/peer-management.md` — P2P peer issues
- `.agent/skills/state-root.md` — state root mismatch handling
- `.agent/skills/docker-troubleshoot.md` — Docker and container issues
