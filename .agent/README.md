# AI Agent Guide — xdc-node-setup

This repository is designed to be AI-native. This guide explains how AI agents (Claude, GPT-4, Copilot, Cursor, etc.) should work with this codebase effectively.

## Quick Start for AI Agents

1. **Read this file** — you're doing that
2. **Read `.agent/CONTEXT.md`** — key technical facts about XDC: ports, clients, quirks
3. **Read `.agent/CONVENTIONS.md`** — coding standards, commit format, PR rules
4. **Pick the right agent persona** from `agents/` for your task:
   - Fleet operations → `agents/fleet-operator.md`
   - Incident response → `agents/incident-commander.md`
   - Deep diagnostics → `agents/node-doctor.md`
   - Security audits → `agents/security-auditor.md`
5. **Use the skills** in `.agent/skills/` for common troubleshooting procedures

## Repository Purpose

`xdc-node-setup` is the operational toolkit for running XDC Network nodes across multiple clients:
- **geth/XDC** (go-ethereum fork with XDPoS)
- **Erigon** (with XDPoS port)
- **Nethermind** (with XDC plugin)
- **Reth** (experimental Rust client)

It provides: installation scripts, monitoring, benchmarking, incident response, fleet management, and security hardening.

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `scripts/` | Operational scripts (deploy, monitor, benchmark, incident) |
| `configs/` | Configuration templates and environment files |
| `agents/` | AI agent persona definitions |
| `.agent/` | AI-specific context, conventions, and skills |
| `monitoring/` | Prometheus/Grafana stack |
| `docker/` | Docker Compose files per client/network |
| `data/` | Runtime data: incidents, benchmarks, experiments |
| `docs/` | Technical documentation |

## How to Make Changes

1. Check if there's a relevant agent persona for context
2. Read `CONVENTIONS.md` for coding standards
3. Look at existing scripts in `scripts/` for patterns and style
4. Source `scripts/lib/common.sh` for shared utilities (if available)
5. Test changes with `--dry-run` flags where available
6. Follow the commit message format in `CONVENTIONS.md`

## Tools an Agent Should Know About

```bash
scripts/benchmark.sh         # Performance benchmarking
scripts/incident-response.sh # Automated incident handling
scripts/auto-optimize.sh     # Meta-agent optimization loop
scripts/deploy.sh            # Deploy/update a client
scripts/consensus-health.sh  # Check consensus state
scripts/cross-verify.sh      # Cross-client block verification
```

## Data Files (Runtime)

These directories are created at runtime and not committed:
```
data/incidents/      → Incident logs (YYYY-MM-DD.json)
data/benchmarks/     → Benchmark results
data/experiments/    → Auto-optimize experiment logs
```

## Getting Help

- Technical context: `.agent/CONTEXT.md`
- Sync debugging: `.agent/skills/sync-debug.md`
- Peer issues: `.agent/skills/peer-management.md`
- State root: `.agent/skills/state-root.md`
- Docker problems: `.agent/skills/docker-troubleshoot.md`
