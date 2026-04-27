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
source of truth for "what an XDC node *is*." Every fix has to be applied 41
times, and inevitably isn't.

---

## 3. North-Star Architecture (XNS 2.0)

```
                     ┌────────────────────────────────────┐
                     │  Operator (CLI / Web / Terraform)  │
                     └────────────────┬───────────────────┘
                                      │ typed config (HCL/YAML, schema-validated)
                                      ▼
                     ┌────────────────────────────────────┐
                     │   xnsctl (Go) — control plane CLI  │
                     │   • render compose from templates  │
                     │   • plan / apply / rollback        │
                     │   • drift detection                │
                     └────┬──────────────────┬────────────┘
                          │                  │
                  renders │                  │ talks to
                          ▼                  ▼
         ┌────────────────────────┐   ┌─────────────────────────┐
         │ Generated artifacts:   │   │  XNS API (Go, gRPC+REST) │
         │ • docker-compose.yml   │   │  • node registry         │
         │ • systemd units        │   │  • heartbeat ingestion   │
         │ • k8s manifests        │   │  • config versioning     │
         │ • nginx vhosts         │   │  • event log             │
         └────────────────────────┘   └────────────┬────────────┘
                                                   │
                          ┌────────────────────────┼────────────────────────┐
                          ▼                        ▼                        ▼
                ┌──────────────────┐    ┌──────────────────┐     ┌──────────────────┐
                │ skynet-agent (Go)│    │  Dashboard (Next)│     │  SkyNet platform │
                │ on every node    │    │  reads XNS API   │     │  (existing)      │
                │ • heartbeat      │    │  via /api/*      │     │                  │
                │ • watchdog       │    └──────────────────┘     └──────────────────┘
                │ • peer inject    │
                │ • offline buffer │
                └──────────────────┘
```

**One source of truth:** a typed `node spec` (HCL or YAML+JSONSchema). Everything
downstream — compose, systemd, K8s, nginx, agent config — is rendered from it.
Operators never hand-edit a compose file again.

---

## 4. Technology Choices

### 4.1 Control plane language: **Go**

**Why:**
- Team is already Go-heavy (go-ethereum fork, Terraform provider, K8s operator).
- Single static binary — no runtime to install on bare-metal/VPS targets.
- Same language for CLI, API server, and node agent reduces cognitive load
  and lets us share a `pkg/spec` types package across all three.
- `cobra` + `viper` for CLI ergonomics; `cue` or `gojsonschema` for spec
  validation; `connect-go` for gRPC/REST dual-serve.

**Trade-offs considered:**
- *Rust:* great fit technically (Reth integration, performance), but team
  expertise is shallow. Reject for control plane; revisit only if a hot path
  emerges.
- *Python:* fast to write, but the 2 existing Python scripts already feel
  out of place, and shipping Python to 100+ nodes means dependency hell.
- *TypeScript end-to-end:* tempting given the dashboard, but bad fit for the
  on-node agent (Node.js footprint, GC, packaging).

### 4.2 Configuration language: **CUE** (preferred) or **HCL**

The single biggest lever for fixing the 41-compose mess is a typed spec
language. Two viable choices:

- **CUE** — strong typing, constraints, can emit YAML/JSON natively. Best for
  catching the OPUS47-class bugs at validation time. Steeper learning curve.
- **HCL** — familiar to the team via Terraform. Weaker constraint system but
  zero learning cost.

**Recommendation: CUE**, because the failure mode we are designing against
(silent YAML drift) is exactly what CUE's constraint solver prevents. HCL
catches typos; CUE catches *semantic* mismatches like
`STATE_SCHEME=hash` paired with `--state.scheme=path`.

**Fallback:** YAML + JSONSchema (already partially done via
`configs/schema.json`). Acceptable, but lacks CUE's cross-field constraints.

### 4.3 Templating: **Go `text/template` + `embed.FS`**

Templates ship inside the `xnsctl` binary via `//go:embed`. No separate
template repo, no version skew. Renderers per output type
(`compose.tmpl`, `systemd.tmpl`, `nginx.tmpl`, `k8s.tmpl`).

### 4.4 API/backend: **Go service, gRPC + REST via Connect, Postgres**

- **Framework:** `connectrpc.com/connect` — same handler serves gRPC and
  REST/JSON. Dashboard uses REST; agents use gRPC for streaming heartbeats.
- **Storage:** PostgreSQL. Event log (append-only) + materialized views for
  current node state. Avoid a NoSQL store — we need transactional config
  versioning.
- **Schema:** Protobuf as the single source of truth for API + agent
  protocol. Generated Go, TS (for dashboard), and OpenAPI spec.
- **Auth:** mTLS for agent ↔ API. JWT (short-lived) for dashboard ↔ API.
  Per-node API keys retired.
- **Hosting:** single VM with Postgres + API + nginx, behind the existing
  `skynet.xdcindia.com` / `net.xdc.network`. No managed K8s required.
  Add a hot-standby for HA in phase 3.

### 4.5 Skynet agent redesign: **Go binary, ~5 MB, single static**

Replaces `docker/skynet-agent.sh`. Responsibilities unchanged; implementation
hardened:

| Concern | XNS 1.x (bash) | XNS 2.0 (Go) |
|---|---|---|
| Heartbeat | `curl` in a `while sleep 30` loop | Ticker + jittered backoff |
| Schema | Free-form JSON | Protobuf, versioned |
| Offline behavior | Loses data | Local SQLite buffer, replays on reconnect |
| Watchdog | `pgrep` + `docker restart` | Container & systemd-aware, with cooldown |
| Peer injection | `admin_addPeer` over HTTP | Same RPC, but typed client + dedup |
| Config | `/etc/xdc-node/skynet.conf` (sourced) | Same path, parsed (backward-compat) |
| Updates | Manual `git pull` | Self-update via signed release manifest |
| Observability | `logger -t xdc-skynet` | Structured logs (zap/zerolog) + Prom metrics |

The agent **must** keep reading `/etc/xdc-node/skynet.conf` and writing
`${XDC_STATE_DIR}/skynet.json` so a 1.x → 2.0 swap is a binary replacement.

### 4.6 Dashboard: **keep Next.js 14, add an API client layer**

No frontend rewrite. We add:
- `dashboard/lib/api/` — generated TS client from the protobuf API.
- `dashboard/app/api/` — thin Next.js Route Handlers that proxy to the Go
  API (keeps the auth boundary inside the same origin, avoids CORS).
- Replace any direct-RPC reads with API calls so the dashboard does not
  depend on JSON-RPC reachability of every node.

### 4.7 Container runtime: **stay on Docker Compose, generated**

Compose remains the deployment target for 90% of operators. We do not push
operators to K8s. Instead:
- 41 hand-edited files → 1 generator + ~5 base templates × profiles
  (mainnet/apothem/devnet × xdc2.6.8/gp5/erigon/nethermind/reth).
- K8s operator continues to exist for the operators who want it. The CRDs
  consume the same `pkg/spec` types as compose generation, so behavior is
  identical across runtimes.

### 4.8 Secrets: **age + per-host master key, optional Vault**

- Default: file-based secrets encrypted with `age` (Go-friendly, simple).
- Each node has a per-host key; control plane re-encrypts on rotation.
- Optional HashiCorp Vault backend for operators who already run it.
- API keys, JWTs, and validator keys never appear in compose files —
  they are mounted as Docker secrets or systemd `LoadCredential`.

---

## 5. Configuration Management — The Core Win

This is where XNS 2.0 pays for itself.

### 5.1 The `node spec`

A single typed document per node (or per node-class):

```cue
// node.cue — illustrative
node: {
    name:    "xdc-mainnet-01"      // matches XNS 1.x naming
    network: "mainnet"             // mainnet | apothem | devnet
    client:  "xdc2.6.8"            // xdc2.6.8 | gp5 | erigon | nethermind | reth
    role:    "fullnode"            // fullnode | masternode | rpc | archive
    runtime: "compose"             // compose | systemd | k8s

    rpc: {
        bind:    "127.0.0.1"       // OPUS47 fix F1 enforced by schema
        cors:    ["https://net.xdc.network"]
        vhosts:  ["net.xdc.network"]
    }

    state_scheme: "path"           // OPUS47 fix — single source, no drift
    snapshot:     "auto"
    peers:        #PeerPolicy
}
```

CUE constraints encode the OPUS47 lessons:
- `rpc.bind == "0.0.0.0"` requires `auth.required: true` (else validation fails).
- `state_scheme` is referenced by both Dockerfile arg and runtime flag —
  they cannot drift because they read from the same field.
- Container name is **derived** from `node.name`, not duplicated.

### 5.2 The render pipeline

```
node.cue ──► xnsctl validate ──► xnsctl plan ──► xnsctl apply
                  │                   │              │
                  │                   ▼              ▼
                  │             diff vs running   render + reload
                  ▼
            schema errors fail closed
```

`plan`/`apply` is Terraform-shaped on purpose — the team already thinks
this way.

### 5.3 Rollback

Every `apply` writes:
1. A versioned snapshot of the rendered artifacts (`/var/lib/xns/versions/<ts>/`).
2. An event row in the API event log.
3. A symlink swap (`current → <ts>`) so rollback is `xnsctl rollback` →
   atomic symlink flip + `compose up`.

This is the missing piece from XNS 1.x — there is currently *no* rollback.

---

## 6. API/Backend Architecture

### 6.1 Surface area (v1)

```
/v1/nodes                GET   list nodes (with filters)
/v1/nodes/{id}           GET   node detail (current state + last heartbeat)
/v1/nodes/{id}/config    GET   active spec
/v1/nodes/{id}/config    PUT   submit new spec (returns plan)
/v1/nodes/{id}/apply     POST  apply previously-planned spec
/v1/nodes/{id}/rollback  POST  roll back to version N
/v1/nodes/{id}/events    GET   event log (paginated)
/v1/heartbeats           POST  agent heartbeat (gRPC streaming)
/v1/fleet/health         GET   aggregate fleet health (dashboard)
/v1/fleet/peers          GET   peer graph (dashboard)
```

Protobuf-defined; OpenAPI auto-generated for documentation.

### 6.2 Storage model

- `nodes` — current node identity (immutable id, mutable name).
- `node_specs` — append-only versioned spec rows; `current_spec_id` on `nodes`.
- `heartbeats` — partitioned by month, hot data in last 7 days.
- `events` — append-only audit log (config changes, applies, rollbacks,
  agent restarts, watchdog interventions).
- Materialized views drive dashboard queries (block height, peer count,
  consensus state) so we don't query `heartbeats` directly.

### 6.3 Why not a managed BaaS

Hosting a Postgres + Go binary is cheap (€20/month VPS) and keeps the data
on infrastructure XDCIndia controls. The fleet is 100s of nodes, not
millions — a vertically-scaled Postgres easily handles it for years.

---

## 7. Skynet Agent Redesign — Detail

### 7.1 Protocol

```protobuf
service SkyNet {
  rpc Register(RegisterRequest) returns (RegisterResponse);
  rpc Heartbeat(stream HeartbeatRequest) returns (stream HeartbeatAck);
  rpc PullCommands(PullRequest) returns (stream Command);
}

message Heartbeat {
  string node_id = 1;
  uint64 block_number = 2;
  bytes  block_hash = 3;
  uint32 peer_count = 4;
  ConsensusState consensus = 5;
  ResourceMetrics resources = 6;
  google.protobuf.Timestamp timestamp = 7;
}
```

### 7.2 Operating modes

- **Online:** streaming bidi gRPC. Server can push commands (e.g. "add this peer").
- **Degraded:** falls back to REST POST per heartbeat (same payload, same auth).
- **Offline:** writes to local SQLite ring buffer (capped at e.g. 1 GB);
  replays oldest-first when connectivity returns.

### 7.3 Watchdog

State machine — not the current "if pgrep fails, restart" loop:
- `Healthy → Degraded` on N missed heartbeats from RPC.
- `Degraded → Restarting` after cooldown (default 5 min).
- `Restarting → Healthy` only after RPC + peer count + block-progress checks.
- Hard backoff on repeated failures; pages SkyNet platform after threshold.

### 7.4 Backward compatibility

- Reads `/etc/xdc-node/skynet.conf` as today.
- Writes the same `skynet.json` state file format.
- Accepts the same env var names (`SKYNET_API_URL`, `SKYNET_API_KEY`,
  `XDC_RPC_URL`, etc.).
- Drop-in replacement: `apt install xns-agent` swaps the binary; no
  config migration.

---

## 8. Testing Strategy

The current test gap is the single biggest delivery risk. XNS 2.0 ships
with tests as a first-class artifact, not an afterthought.

| Layer | Tool | What we test |
|---|---|---|
| Spec validation | CUE built-in / Go unit tests | Every OPUS47-class invariant |
| Renderers | Go golden-file tests | `node.cue → compose.yml` snapshots |
| Compose lint | `docker compose config` in CI (already added) | Syntactic correctness |
| API | Go unit + integration (testcontainers + Postgres) | Handlers, persistence |
| Agent | Go unit + a fake-RPC harness | Heartbeat, watchdog, offline buffer |
| End-to-end | Kind/k3d cluster + ephemeral Postgres in CI | Full apply/rollback cycle |
| Bash legacy | `bats` for the scripts we keep | Smoke coverage during migration |
| Dashboard | Playwright against a seeded API | Critical user journeys |

**CI gates:**
1. `cue vet` — spec must validate.
2. `go test ./...` — all Go packages.
3. `xnsctl render --dry-run` for every example spec → diff vs golden.
4. `docker compose config` for every rendered output.
5. Naming validator (already exists) — file vs container name.
6. `shellcheck` on remaining bash.

---

## 9. Migration Path

**Principle:** XNS 2.0 ships incrementally alongside 1.x. No flag day. No
"freeze the fleet for 3 months" migration.

### Phase 0 — Foundations (4 weeks, 2026-Q3 start)
- Stand up `xns/` Go module: `pkg/spec`, `pkg/render`, `cmd/xnsctl`.
- Author CUE schema covering existing 41 compose files.
- Generate the 41 compose files from CUE; diff against current; reconcile.
- Deliverable: `xnsctl render` produces byte-identical output to today's
  hand-edited files. **No fleet change yet.**

### Phase 1 — Generated config rollout (6 weeks)
- Replace hand-edited compose files with generated ones, file-by-file,
  PR-by-PR. Each PR: regenerate, diff = empty, merge.
- Add `xnsctl plan` / `apply` / `rollback`. Wrap existing scripts.
- Deliverable: 41 → 0 hand-edited compose files. `bash`-driven deploys
  still work; they now call `xnsctl` under the hood.

### Phase 2 — API + dashboard wiring (6 weeks)
- Ship `xns-api` Go service (single VM, Postgres). Define protobufs.
- Add `dashboard/app/api/` proxy routes; replace static-JSON reads.
- Backfill node registry from existing Ansible inventory + `servers.env`.
- Deliverable: dashboard loads from API, not RPC. SkyNet platform begins
  receiving structured heartbeats from a *parallel* test fleet.

### Phase 3 — Agent rollout (4 weeks)
- Ship `xns-agent` Go binary. Deploy to canary nodes alongside the bash
  agent (both running, agent has authoritative writes).
- After 2 weeks of canary, swap fleet-wide via Ansible. Bash agent is
  removed but kept in repo (`legacy/`) for one more release.
- Deliverable: bash `skynet-agent.sh` retired across fleet.

### Phase 4 — Hardening (4 weeks)
- Secrets migration to `age`.
- mTLS rollout for agent ↔ API.
- Rollback tested end-to-end on staging.
- Drift-detection cron (`xnsctl plan` on every node nightly; alerts on diff).
- Deliverable: XNS 2.0 GA.

### Phase 5 — Decommission (ongoing)
- Retire bash scripts as their replacements stabilize. Target: 162 → ≤30.
- Keep what wraps OS-level concerns (snapshot import, disk init, kernel
  tuning) — Go offers no advantage there.

**Cutover safety:** every phase preserves XNS 1.x behavior. A 2.0 rollback
is `apt-get install xns-agent=1.x`; a config rollback is `xnsctl rollback`.

---

## 10. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| CUE learning curve slows team | Pre-write 80% of schema in Phase 0; provide cookbook; HCL fallback if Phase 0 misses ETA by >2 weeks. |
| Render output drifts from current behavior | Phase 0 acceptance is byte-identical diff; CI enforces it. |
| API becomes a single point of failure | Phase 4 adds hot-standby; agent's offline buffer means API outage ≠ data loss. |
| Multi-client coverage (5 clients × 3 networks) explodes spec matrix | CUE composition (network × client → spec) keeps the matrix DRY. |
| Operators on bare metal balk at "yet another binary" | `xnsctl` is one static binary; agent is one static binary. No runtime to install. |
| Backward compatibility bugs during 1.x↔2.0 coexistence | Contract tests: bash 1.x scripts run against 2.0 API in CI. |
| K8s operator falls behind compose generator | Both consume `pkg/spec` — they cannot diverge by construction. |

---

## 11. What We Are *Not* Doing

Calling these out so they don't creep in:

- **Not** moving the fleet to managed Kubernetes. Operator stays optional.
- **Not** rewriting the dashboard. Next.js 14 + TS stays. We add an API tier underneath.
- **Not** replacing Ansible wholesale — Ansible still handles OS-level
  bootstrap (kernel, ulimits, docker install). XNS 2.0 owns everything
  *above* that line.
- **Not** introducing a service mesh, message broker, or event bus. Postgres
  + gRPC is enough for 100s of nodes. Revisit at 10,000.
- **Not** Rust. (Yet.) Maybe for the agent in 3.0 if Reth integration demands it.
- **Not** breaking XNS 1.x naming, paths, or env var conventions.

---

## 12. Success Criteria

XNS 2.0 GA is achieved when:

1. Zero hand-edited compose files in the repo.
2. `xnsctl validate` catches every OPUS47-class regression in CI before merge.
3. Dashboard loads exclusively from the API (no direct RPC reads).
4. Bash Skynet agent removed from production fleet.
5. Rollback drill on staging completes in <60 seconds.
6. Fleet config drift detection runs nightly and pages on diff.
7. Onboarding a new node = 1 spec file + `xnsctl apply`. No editing YAML.
8. Operators report shipping a config change in <10 min, end-to-end, with rollback available.

---

## 13. Open Questions for Review

1. **CUE vs HCL** — final call before Phase 0 kickoff. Architecture recommends CUE; team may prefer HCL for familiarity.
2. **API hosting** — single VM is fine for 2.0 GA; do we want active-active across two regions in 2.1?
3. **mTLS PKI** — roll our own CA via `step-ca`, or use existing internal CA at XDCIndia?
4. **Self-update for the agent** — do we want it on by default, or opt-in per node? (Security-vs-ops trade-off.)
5. **Legacy script policy** — hard delete after 2.0 GA, or keep `legacy/` indefinitely? Recommendation: delete after one minor release.

---

## 14. Appendix — Repository Layout (target)

```
xdc-node-setup/
├── xns/                           # NEW — Go monorepo
│   ├── cmd/
│   │   ├── xnsctl/                # operator CLI
│   │   ├── xns-api/               # control-plane API
│   │   └── xns-agent/             # on-node agent
│   ├── pkg/
│   │   ├── spec/                  # shared types (proto-generated)
│   │   ├── render/                # template renderers
│   │   ├── api/                   # protobufs + handlers
│   │   └── agent/                 # heartbeat, watchdog, buffer
│   └── schemas/                   # CUE schemas
├── dashboard/                     # Next.js, unchanged structure
│   ├── app/api/                   # NEW — proxy routes
│   └── lib/api/                   # NEW — generated TS client
├── docker/                        # generated artifacts (gitignored?)
├── k8s/operator/                  # consumes pkg/spec
├── terraform/provider/            # consumes pkg/spec
├── scripts/                       # shrinks to ≤30 OS-level scripts
└── legacy/                        # bash + 41 compose files for one release
```

---

**Next action:** review this document, lock the CUE-vs-HCL decision, and
greenlight Phase 0. Phase 0 is scoped so its acceptance criterion (byte-identical
generated output) protects the fleet from any 2.0 risk before we commit further.
