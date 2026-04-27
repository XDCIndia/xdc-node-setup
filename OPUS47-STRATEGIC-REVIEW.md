# XDC Node Setup — Strategic Review (Opus 4.7)

**Date:** 2026-04-27
**Reviewer:** senior blockchain infrastructure architect
**Repo HEAD:** `ac9fa0b` (chore(gp5): bump GP5 image to v94-amd64 across all compose files)
**Scope:** 41 compose files, 18 Dockerfiles, 142 scripts, 12 open issues

---

## 0. Reconciliation with prior audit

Before the strategic findings, the prior audit's claims were re-verified against HEAD. Two stated facts are **incorrect at HEAD** and one needs reframing:

| Prior claim | Verified state at HEAD | Implication |
|---|---|---|
| `STATS_SECRET=***` literal in `gp5-pbss.yml`, `gp5-hbss.yml`, `gp5-pbss-v76.yml`, `docker-compose.gp5-apothem.yml` | Only `docker/apothem/gp5-pbss-v76.yml:37–39` has the bug, and the actual symptom is `$${VAR:-default}` (escaped `$$`) — not a literal `***`. The other three files use correct `${VAR:-default}`. | Audit was either out of date or copied from a stale snapshot. The fix surface is **1 file, 3 lines**, not 4 files. |
| `AUTHRPC_PORT=***` literal in 4 files | All four files contain real port numbers (`8551`, `9555`, `9556`, `8551`). The smell is different: ports are **hardcoded** with no env-var indirection, which is fragile under multi-instance reuse but not broken. | Reclassify from P0 (broken) to P2 (rigid). |
| `#265: 183 node gaslimit 420B (1000x normal)` | `docker/geth-pr5/start-gp5.sh:266` sets `--miner.gaslimit 420000000` = 420M (correct). No 420B value found anywhere in the tree. The "183" in the issue title is the server IP (`185.180.220.183`) per `docker-compose.apo-multiclient.yml:4`, not the gaslimit. | The misread is informative: the issue title format `<server>-<problem>-<value>` is being misparsed because there's no naming convention for issue titles. Verify the actual deployed value via `eth_getBlockByNumber` on the live 183 node before declaring a P1. |

The other audit findings (`gp5-pbss-v76.yml` STATE_SCHEME mismatch, v268 RPC on `0.0.0.0` with `*` CORS/vhosts, missing `version:`, no `stop_grace_period` on GP5, mixed restart policies) all reproduce.

---

## 1. Executive summary — top 5 risks by blast radius

Ordered by **(probability × harm × number of nodes affected)**, not by ticket priority.

### R1 — v268 RPC exposed on `0.0.0.0` with `--rpccorsdomain "*" --rpcvhosts "*"` and `admin` API enabled
**Files:** `docker/apothem/v268.yml:19–21`, `docker/mainnet/v268.yml:19–21`
**Blast radius:** every host running the v268 reference node — both networks. With `network_mode: host` the listener is on the host's public interface unless an external firewall blocks it. `admin` in `--rpcapi` includes `admin_addPeer`, `admin_startRPC`, etc. With unrestricted vhosts and CORS, this is exploitable from any browser tab on any compromised host on the LAN, and from the public internet wherever port 8650/8745 is reachable.
**Why this is #1:** authenticated DoS / peer table poisoning / log exfiltration of an entire fleet from one curl. Every other risk is local to a single node.

### R2 — `gp5-pbss-v76.yml` ethstats env vars are `$${VAR}` (escaped) → reporting as literal `${STATS_SECRET:-xdc_openscan_stats_2026}`
**File:** `docker/apothem/gp5-pbss-v76.yml:37–39`
**Blast radius:** ethstats authentication for the v76 node fails silently → node disappears from `stats.xdcindia.com` → operators don't notice it's gone → drift / unmonitored fork risk. Compose's `$$` is the documented escape for "pass `$` through to the container," so the variable literally never expands. `start-gp5.sh:240` then constructs `netstats="...:${STATS_SECRET:-...}@..."` from the now-malformed env var.
**Why this is #2:** silent observability failure on a single node, but it's the canary for the broader category — there is no compose-file linter in CI to catch the `$$` regression class.

### R3 — `gp5-pbss-v76.yml` is named PBSS but configured HBSS (`STATE_SCHEME=hash`)
**File:** `docker/apothem/gp5-pbss-v76.yml:27` (vs filename `gp5-pbss-v76.yml` and container name `168-gp5-full-pbss-apothem-168`)
**Blast radius:** an operator believing they are running the path-based snapshot benchmark for v76 will produce metrics from a hash-based node. Every comparison published from this node — sync speed (#256), restart panic surface (#257), peer compatibility (#258) — is mislabelled. This is a **scientific-integrity** bug, not a runtime bug.
**Why this is #3:** issue #256 explicitly compares "v80 ~500 bl/min vs single-peer ~125 bl/min" — if v76's apparent PBSS results were actually HBSS, conclusions about PBSS performance regressions are based on the wrong data.

### R4 — Cold-snapshot restart panic (#257) compounds with chaindata path drift (#260)
**Files:** `docker/geth-pr5/start-gp5.sh:52–73` (`find_chaindata_subdir`)
**Blast radius:** `start-gp5.sh` accepts three subdir conventions (`geth/`, `XDC/`, `xdcchain/`) and writes `static-nodes.json` to `geth/` (line 194) regardless. If existing chaindata sits under `XDC/`, static peers are written to a directory the binary doesn't read → static peers lost on every restart (matches #260). Combined with #257 (missing XDPoS voting snapshot → nil panic), a node restart can both panic *and* lose its peer hints, requiring manual intervention.
**Why this is #4:** the bug surface is only the GP5 fleet, but it's the most likely cause of operator pages.

### R5 — Configuration sprawl: 41 compose files, 5 stale `.backup-*` files in tree, 142 scripts
**Files:** `docker/docker-compose.yml.backup-1771183540`, `…-1771183550`, `…-20260311-082450`, `…-20260311-082532`, `…-pre-erigon`; `scripts/*.sh` (142 entries)
**Blast radius:** indirect, but high-probability. The combinatorial space is too large for any human reviewer to keep coherent — which is *exactly* how `$${VAR}` and `STATE_SCHEME=hash`-in-pbss-file got merged. Every future fix lands in N files and the regression in N+1.
**Why this is #5:** it is the *cause* of R1–R4 recurring after they are patched.

---

## 2. Root cause analysis — why these issues exist

The visible bugs are symptoms. The underlying process gaps:

### 2.1 No CI validation for compose files
None of the bugs in R1–R3 would survive a one-line CI step:
```
docker compose -f <file> config -q
yq '.services[].environment[] | select(test("\\$\\$"))' <file>   # catches $$ escapes
yq '.services[].command' <file> | grep -E 'rpcaddr 0\.0\.0\.0.*admin'  # catches R1
```
The repo has GitHub Actions infra but no compose-file gate. **This is the single highest-leverage fix.**

### 2.2 No issue/PR template enforcing scope
Issue #266 is a "meta audit" pointing at 7 categories. Issues #255–#265 mix P0/P1/enhancement in the same backlog with no labels visible from titles. The audit summary itself contained two factual errors (R1 reconciliation above), suggesting nobody re-verified before triage. **Triage is being done off stale notes, not the tree.**

### 2.3 Backup-by-suffix as version control
Five `docker-compose.yml.backup-*` files in `docker/` indicate the team is making in-place edits and saving timestamped copies as a safety net. Git is the safety net. The presence of these files in HEAD also pollutes `grep`/`find`/`docker compose` globs — a real risk when an operator runs `docker compose -f docker-compose.yml.backup-pre-erigon up -d` thinking it's the live file.

### 2.4 No naming convention enforcement
`scripts/lib/naming.sh` defines a 6-part XNS standard but it is **library code, not a gate**. Filenames (`gp5-pbss-v76.yml` with `STATE_SCHEME=hash`) and container names (`168-gp5-full-pbss-apothem-168` for an HBSS node) drift from each other because nothing checks them. A pre-commit hook running `naming.sh validate` against compose files would catch R3 at write-time.

### 2.5 Multiple stale review documents
`ARCHITECT-REVIEW-2026-02-13.md`, `ARCHITECTURE-REVIEW.md`, `PHASE2-EXECUTIVE-SUMMARY.md`, `PROD-READINESS-REVIEW.md`, `PHASE2-IMPLEMENTATION-REPORT.md`, `APOTHEM_FIXES.md` — six review/plan docs at the repo root. Review fatigue is real: writing the seventh (this document) without retiring the previous six is part of the problem. **Recommendation below in §4.5.**

### 2.6 v268 reference container inherits 2019-era defaults
`v268.yml` ships `--rpccorsdomain "*" --rpcvhosts "*" --rpcapi …,admin` because that's how `xinfinorg/xdposchain:v2.6.8` was historically run for developer convenience. Nobody re-evaluated when the reference image started running on production-adjacent hosts. **This is a posture-drift problem, not a config-typo problem** — it cannot be fixed by lint.

---

## 3. Fix prioritization matrix

Effort: **S** ≤ 2 hr, **M** ≤ 1 day, **L** ≤ 1 week.
Dependencies are the *minimum* prerequisites — items with no deps can run in parallel.

| ID | Issue | Pri | Effort | Depends on | Description |
|---|---|---|---|---|---|
| F1 | new | **P0** | S | — | Patch `v268.yml` (both): bind RPC/WS to `127.0.0.1`, drop `admin` from `--rpcapi`, set `--rpccorsdomain` and `--rpcvhosts` to a concrete host list. Front with nginx if external access is needed. |
| F2 | #262 (subset) | **P0** | S | — | Fix `gp5-pbss-v76.yml:37–39` — replace `$$` with `$`. Verify on stats.xdcindia.com that the node reappears. |
| F3 | #264 | **P1** | S | — | `gp5-pbss-v76.yml:27` — either rename file/container to `gp5-hbss-v76` *or* set `STATE_SCHEME=path`. Decide which by checking the actual on-disk schema (`ls $DATA_DIR/geth/state-*`). |
| F4 | new (CI gate) | **P1** | M | — | Add `.github/workflows/compose-lint.yml` running `docker compose config -q`, the `$$` regex check, and a CORS/vhosts/admin smell check. Block merge on failure. |
| F5 | #260 | **P1** | M | — | `start-gp5.sh:194,217` — write `static-nodes.json`/`trusted-nodes.json` into the *detected* `CHAIN_SUBDIR`, not hardcoded `geth/`. |
| F6 | #257 | **P1** | M | F5 | Cold-snapshot voting snapshot — investigate at the binary level; in `start-gp5.sh`, detect missing voting snapshot before launch and refuse with a clear error rather than letting the binary panic. |
| F7 | #263 | **P2** | S | F4 | AUTHRPC_PORT — wrap in `${AUTHRPC_PORT:-<default>}` everywhere for reuse parity with HTTP/WS/P2P ports. |
| F8 | #266 cat. 5,6,7 | **P2** | S | — | Add `version: '3.8'` (or remove `version:` everywhere — Compose v2 ignores it). Pick one. Add `stop_grace_period: 3m` to GP5 services. Standardize on `restart: unless-stopped` (matches v268). |
| F9 | new | **P2** | S | — | `git rm` the five `docker-compose.yml.backup-*` files. Add `*.backup-*` to `.gitignore`. |
| F10 | #261 | **P2** | M | F4 | XNS v2 — promote `naming.sh` from library to pre-commit gate; emit `XDC_IMAGE_VERSION` env in compose so SkyNet can read it. |
| F11 | #265 | **P2** | S | — | Verify actual gaslimit on 183 host: `curl -s http://185.180.220.183:8555 -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}'` → `result.gasLimit`. If correct, close issue with note. If wrong, find the override. |
| F12 | #258 | **P1** | L | F5 | P2P subprotocol disconnects vs v2.6.8 peers — needs go-ethereum-side investigation, not a compose fix. Out of scope for this review. |
| F13 | #256 | **P2** | L | F3, F12 | Sync speed regression — cannot be diagnosed cleanly until F3 (correct labelling) and F12 (peer-set normalization). |
| F14 | #255 | **P2** | S | — | Replace `RUN chmod +x` in Alpine Dockerfiles with `COPY --chmod=0755`. 6 files affected. |
| F15 | #259 | **P2** | S | F4 | Re-deploy `gp5-v103-apothem-125` via XNS rather than `docker run`. Operational, not code. |

**Critical path to "production-safe":** F1 → F2 → F3 → F4. ~1 day end-to-end with one engineer; F1 alone (~30 min) is the largest single risk reduction.

---

## 4. Architectural recommendations

These prevent the *next* audit from finding the same classes of issue.

### 4.1 Compose-file generation, not hand-editing
41 compose files share 80% of their content. Generate them from a single Jinja/yq template keyed on `(client, network, state_scheme, server_id)`. The artifact in git is the template + a `make compose` step that materializes the YAMLs. R3 (PBSS-named-but-HBSS) becomes structurally impossible.

### 4.2 Compose lint as a merge gate
See F4. Specifically check for:
- `$$` in `environment:` values
- `0.0.0.0` bind addresses with `*` cors/vhosts
- `admin` in `*api` flags on internet-facing services
- `restart:` value matches a single allowed set
- `version:` presence consistent across files

### 4.3 Promote `scripts/lib/naming.sh` to a validator
A single command `naming validate <compose-file>` that reads service name, container name, env vars, and filename, and asserts they agree with the XNS schema. Wire it into F4. Issue #261 (XNS v2) becomes "extend the validator," not "remember to update 41 files."

### 4.4 Separate the v268 reference profile from the production profile
`v268.yml` exists for two audiences with different security postures: developers running locally (want `0.0.0.0` + `*`) and operators running on internet hosts (want `127.0.0.1` + nginx). Provide both, named explicitly: `v268-dev.yml`, `v268-prod.yml`. Make `v268.yml` a symlink to `-prod` so the safe default wins on accident.

### 4.5 Retire stale review/plan documents
Move `ARCHITECT-REVIEW-2026-02-13.md`, `ARCHITECTURE-REVIEW.md`, `PHASE2-*.md`, `PROD-READINESS-REVIEW.md`, `APOTHEM_FIXES.md` to `docs/archive/` with a one-line note in each ("superseded by OPUS47-STRATEGIC-REVIEW.md, 2026-04-27"). Keep `ARCHITECTURE.md` as the current-state reference. Future reviews replace, not append.

### 4.6 One-issue-per-bug discipline
Close #266 (meta audit) and replace it with individual issues per category, each labelled `P0/P1/P2` and `area:compose|area:dockerfile|area:script`. Triage from the tree, not from the meta issue.

---

## 5. Validation plan (without breaking production)

Goal: every fix above is verified *before* it touches a node carrying real chain state.

### 5.1 Three-tier validation environment

| Tier | Purpose | Cost | What to validate |
|---|---|---|---|
| **T0 — local** | syntactic / structural | free | `docker compose config -q`, naming validator, lint regex |
| **T1 — devnet** | runtime, no chain state at risk | low | `make devnet-up`, full GP5 + v268 + skynet stack, run for 30 min, confirm peers connect, ethstats reports, no panics on restart |
| **T2 — Apothem canary** | adversarial, real network but throwaway state | low | Spin up one node per affected compose file in a fresh VM, sync to tip, kill -9 the container, restart, confirm `static-nodes.json` is read, voting snapshot loads, no nil panic |

**Mainnet nodes are never used as the validation target.** Promote to mainnet only after T2 passes.

### 5.2 Per-fix validation scripts

| Fix | T0 | T1 | T2 |
|---|---|---|---|
| F1 (RPC binding) | grep no `0.0.0.0`+`admin`+`*` triple | from another host: `curl http://<vm>:8650` must time out; `curl http://127.0.0.1:8650` from the host succeeds | n/a — local-bind change is host-isolated |
| F2 (`$$` fix) | `yq` regex finds zero `\$\$` | start container, `docker exec … env \| grep STATS_SECRET` returns expanded value | confirm node reappears on stats.xdcindia.com within 5 min |
| F3 (state scheme) | filename ↔ env var ↔ container name agree | start fresh node, confirm `geth/state-*` matches declared scheme | n/a |
| F4 (CI gate) | the workflow itself is the test; introduce a deliberate `$$` in a draft PR and confirm CI blocks | n/a | n/a |
| F5 (chaindata subdir) | unit-test `find_chaindata_subdir` against fixture dirs (`geth/`, `XDC/`, `xdcchain/`, none) | start with each layout, kill, restart, confirm static peers persist | restart real Apothem node, confirm peer count > 0 within 60s |
| F6 (voting snapshot) | mock missing snapshot file, confirm pre-flight fails fast with operator-readable error | restart with intentionally-deleted snapshot, observe friendly error not panic | n/a |
| F7–F9, F14 | compose lint passes | smoke test `up -d && down` | n/a |

### 5.3 Rollback plan
Every fix lands as a single PR with a clearly-named revert commit ready. For F1 specifically: keep the prior `v268.yml` as `v268-legacy.yml` for 30 days, document the fallback in the PR body, and tag the pre-fix commit. If a deployment regression appears (e.g. a developer's tooling actually depended on `0.0.0.0` binding), rollback is `cp v268-legacy.yml v268.yml && docker compose up -d`.

### 5.4 Monitoring during rollout
Watch three signals during the F1–F6 rollout window:
1. `stats.xdcindia.com` node count — must not drop
2. `net.xdc.network` (SkyNet) heartbeat success rate — must stay ≥ 99%
3. `eth_blockNumber` lag vs network tip across all canaries — must converge within 5 min of restart

If any signal breaches for ≥ 10 min on one node, halt the rollout, do not advance to the next.

---

## Appendix A — files referenced
- `docker/apothem/v268.yml:19–21` — R1 source
- `docker/mainnet/v268.yml:19–21` — R1 source
- `docker/apothem/gp5-pbss-v76.yml:27,37–39` — R2, R3 source
- `docker/geth-pr5/start-gp5.sh:52–73,194,217,266` — R4, gas-limit verification
- `docker/docker-compose.apo-multiclient.yml:4,27` — 183-host context
- `scripts/lib/naming.sh:28–48,68–91` — XNS standard
- `docker/docker-compose.yml.backup-*` (×5) — R5 / F9
