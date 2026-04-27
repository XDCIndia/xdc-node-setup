# XNS 2.0 — Strategic Technology Roadmap

**Document owner:** Infrastructure Architecture
**Status:** Draft for review
**Date:** 2026-04-27
**Target GA:** XNS 2.0 — staged rollout, Q3 2026 → Q1 2027
**Predecessor audit:** `OPUS47-STRATEGIC-REVIEW.md`, `ARCHITECT-REVIEW-2026-02-13.md`

---

## 1. Executive Summary

XNS 1.x got XDCIndia from "manual SSH'd VPS nodes" to a 162-script,
41-compose, multi-client fleet runtime. It worked. It also calcified into
configuration sprawl that produced the recent class of incidents the OPUS47
audit caught — `1423020` JSON-escape bugs, `STATE_SCHEME` mismatches between
sibling compose files, RPC bind misconfigurations, copy-pasted healthchecks
that drift from container names.

XNS 2.0 is **not** a rewrite. It is a **consolidation around a generated,
typed, observable control plane** that replaces hand-edited YAML and `bash +
curl` agents with a single source of truth, a Go-based control plane, and a
small typed agent. The 162 scripts collapse into a CLI; the 41 compose files
collapse into ~5 templates × N profiles; the bash Skynet agent becomes a Go
binary with a documented protocol.

**The thesis:** the team's strength is Go (go-ethereum fork, Terraform
provider, K8s operator). Lean into it. Stop generating YAML by hand and stop
shipping bash where a typed binary belongs. Keep Next.js for the dashboard
and add the missing API tier behind it.

**Non-goals for 2.0:**
- Rewriting the dashboard frontend (Next.js stays).
- Forcing managed K8s on bare-metal/VPS operators (K8s remains optional).
- Breaking XNS 1.x naming or URL conventions (backward-compat is a hard requirement).

---

## 2. Current State — Honest Assessment

| Layer | Today | Problem |
|---|---|---|
| Node lifecycle | 162 bash scripts, ad-hoc `common.sh` sourcing | No types, no tests, drifting error handling |
| Container runtime | 41 hand-edited compose YAMLs, 18 Dockerfiles | Copy-paste rot, no schema, just-added CI lint |
| Naming/validation | None until last commit (`5ac1c30`) | Filenames and container names drift |
| Skynet agent | `skynet-agent.sh` — bash + curl + cron/systemd | No retry semantics, no offline buffering, no schema |
| Dashboard | Next.js 14 + TS, frontend only | No API tier — reads static JSON or RPC directly |
| API contract | Undocumented Skynet endpoints | Protocol drift between agent and platform |
| Fleet ops | Ansible + bash loops over `servers.env` | No declarative state, no rollback, no drift detection |
| K8s | Operator exists, basic CRUD | Not the deployment target for >90% of fleet |
| Terraform | Provider exists | Only models nodes/backups, not full topology |
| Secrets | Per-host `.env` files | No central rotation, no audit |
| Tests | Effectively none for bash; some Go in operator | No regression safety net |

**Root cause of the OPUS47 findings:** every compose file was written
independently with copy-paste as the only abstraction. There is no single
source of truth for "what an XDC node *is*." Every fix has to be
