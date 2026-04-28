# XNS CLI v2.0 — Design Specification

## Vision

The best blockchain node setup CLI in all of Web3. One binary to rule them all — XDC, Ethereum, and beyond. Replaces 162 bash scripts with a typed, testable, cross-platform Go tool.

## Name

`xns` — XDC Node Setup (v2.0)

## Architecture

```
xns/
├── cmd/xns/           — CLI entrypoint (cobra)
├── pkg/
│   ├── config/        — ~/.xns/config.yaml loader + validator
│   ├── templates/     — 5 embedded compose templates (go:embed)
│   ├── profiles/      — Network profiles (mainnet, apothem, devnet)
│   ├── client/        — Client-specific logic (gp5, xdc, erigon, nm, reth)
│   ├── fleet/         — Multi-server fleet operations
│   ├── sync/          — Replay, validation, snapshot management
│   ├── monitor/       — Health checks, stats, SkyNet integration
│   └── reconcile/     — Cross-repo issue tracker sync
├── internal/
│   ├── docker/        — Docker compose generation + execution
│   ├── ssh/           — Fleet SSH key management + remote exec
│   └── rpc/           — XDC/eth JSON-RPC client
├── templates/
│   ├── compose/
│   │   ├── base.yml          — Shared services (stats, skynet-agent)
│   │   ├── gp5.yml           — GP5-specific
│   │   ├── xdc.yml           — v2.6.8-specific
│   │   ├── erigon.yml        — Erigon-specific
│   │   └── nethermind.yml    — Nethermind-specific
│   └── scripts/
│       └── init-chaindata.sh — Chaindata initialization helper
└── fixtures/
    └── apothem-switch-window.json — CI test data
```

## Commands

### `xns node` — Single Node Management

```bash
# Initialize a new node (interactive or from config)
xns node init --network apothem --client gp5 --datadir /data/xdc

# Start node with Docker Compose
xns node up --network apothem --client gp5

# Stop node
xns node down

# Show node status
xns node status

# View logs
xns node logs --follow

# Restore from snapshot
xns node restore --snapshot https://xdc.network/snapshots/xdc-apothem-52M.tar.zst

# Export chaindata for migration
xns node export --output /backup/chaindata.tar.zst
```

### `xns fleet` — Multi-Server Fleet

```bash
# Deploy fleet from config
xns fleet deploy --config fleet.yaml --dry-run

# Rolling update with auto-rollback
xns fleet rolling-update --image xdcindia/gp5:v96 --fleet apothem \
  --abort-on validators-not-legit \
  --abort-on header-body-desync \
  --timeout 300

# Fleet status across all servers
xns fleet status --fleet apothem

# Add trusted peers to all fleet nodes
xns fleet add-peers --peers enode://... --fleet mainnet

# Execute command across fleet
xns fleet exec --command "docker ps" --fleet apothem
```

### `xns sync` — Sync Operations & Validation

```bash
# Bit-for-bit replay validation against v2.6.8 archive
xns sync replay --network apothem --from 56828250 --to 56831400 \
  --archive http://archive-node:8545 \
  --against xdcindia/gp5:latest

# Check sync health
xns sync health --node http://localhost:8545

# Compare two nodes (canary mode)
xns sync compare --primary http://node1:8545 --canary http://node2:8545 \
  --every 1h --alert-on-diff

# Download and verify snapshot
xns sync snapshot --download https://xdc.network/snapshots/... \
  --verify --output /data/snapshots/
```

### `xns validator` — Validator/Masternode Management

```bash
# Register as masternode (XDC-specific)
xns validator register --network mainnet --address 0x... --name "MyNode"

# Check validator status
xns validator status --address 0x...

# Withdraw/retire
xns validator retire --address 0x...

# List candidates
xns validator candidates --network mainnet
```

### `xns issue` — Cross-Repo Tracker Management

```bash
# Reconcile issues across repos
xns issue reconcile --repo XDCIndia/go-ethereum --repo XDCIndia/xdc-node-setup

# Show open critical issues
xns issue list --severity critical --repo XDCIndia/go-ethereum

# Link commit to issue
xns issue link --issue 441 --commit fb60d1d2e --repo XDCIndia/go-ethereum

# Generate weekly report
xns issue report --since 7d --format md --output weekly.md
```

### `xns config` — Configuration Management

```bash
# Initialize config
xns config init

# Validate current config
xns config validate

# Show effective config (merged defaults + user + env)
xns config show

# Set value
xns config set --key fleet.apothem.image --value xdcindia/gp5:v96

# Edit config
xns config edit
```

## Config Schema (~/.xns/config.yaml)

```yaml
version: "2.0"

# Global defaults
defaults:
  datadir: /data/xdc
  log_level: info
  restart_policy: always
  network_mode: host  # XDC requires host networking

# Network profiles
networks:
  mainnet:
    chain_id: 50
    bootnodes: [...]
    stats_endpoint: stats.xdcindia.com:443
    snapshot_url: https://xdc.network/snapshots/xdc-mainnet-latest.tar.zst
    ports:
      rpc: 8545
      ws: 8549
      p2p: 30303
      metrics: 6060
  apothem:
    chain_id: 51
    bootnodes: [...]
    stats_endpoint: stats.xdcindia.com:443
    snapshot_url: https://xdc.network/snapshots/xdc-apothem-latest.tar.zst
    ports:
      rpc: 9645
      ws: 9649
      p2p: 30320
      metrics: 6061
  devnet:
    chain_id: 551
    bootnodes: [...]
    ports:
      rpc: 10545
      p2p: 30330

# Client configurations
clients:
  gp5:
    image: xdcindia/gp5-xdc
    binary: XDC
    sync_mode: full
    gc_mode: full
    snapshot: false
    extra_args: []
  xdc:
    image: xdcindia/xdc:v2.6.8
    binary: XDC
    sync_mode: full
  erigon:
    image: xdcindia/erigon-xdc
    p2p_ports: [30304, 30311]  # Two sentries
    network_mode: host  # Required for IPv4
  nethermind:
    image: xdcindia/nethermind-xdc
    state_root_cache: true
  reth:
    image: xdcindia/reth-xdc

# Fleet definitions
fleets:
  apothem:
    servers:
      - host: xdc01.apothem.xdc.network
        user: ubuntu
        clients: [gp5, erigon]
      - host: xdc02.apothem.xdc.network
        user: ubuntu
        clients: [gp5]
    rolling_update:
      batch_size: 1
      timeout: 300
      abort_conditions:
        - "validators not legit"
        - "header/body desync > 8:1"
        - "already syncing > 100/min"
  mainnet:
    servers:
      - host: xdc01.mainnet.xdc.network
        user: ubuntu
        clients: [gp5]

# Validation settings
validation:
  replay:
    archive_node: http://archive.apothem.xdc.network:8545
    default_window: 3150  # 3.5 epochs
  health_check:
    interval: 30s
    timeout: 10s

# Monitoring
monitoring:
  skynet:
    enabled: true
    endpoint: https://skynet.xdcindia.com
  ethstats:
    enabled: true
    secret: xdc_openscan_stats_2026
```

## Template System

Instead of 41 compose files, use 5 templates + profile injection:

```go
// templates/compose/base.yml (go:embed)
var baseTemplate string

// templates/compose/gp5.yml (go:embed)
var gp5Template string

// Profile injection at runtime
type Profile struct {
    Network    string
    ChainID    int
    Ports      PortMap
    Image      string
    Binary     string
    ExtraArgs  []string
    Datadir    string
}

func GenerateCompose(profile Profile, client string) (string, error) {
    // 1. Parse base template
    // 2. Parse client-specific template
    // 3. Merge with profile values
    // 4. Output final compose YAML
}
```

## Implementation Roadmap

### Phase 0: Foundation (Week 1-2)
- [ ] Project scaffolding (`go mod init`, cobra, directory structure)
- [ ] Config loader + validator (CUE or JSON Schema)
- [ ] Embedded template system (go:embed)
- [ ] Docker compose generator

### Phase 1: Node Commands (Week 3-4)
- [ ] `xns node init`
- [ ] `xns node up/down/status/logs`
- [ ] `xns node restore` (snapshot download + verify)
- [ ] Single-node end-to-end test on Apothem

### Phase 2: Fleet Commands (Week 5-6)
- [ ] SSH key management + remote exec
- [ ] `xns fleet deploy`
- [ ] `xns fleet rolling-update` with abort conditions
- [ ] `xns fleet status`

### Phase 3: Sync & Validation (Week 7-8)
- [ ] `xns sync replay` (bit-for-bit validation)
- [ ] `xns sync health`
- [ ] `xns sync compare` (canary mode)
- [ ] CI integration (GitHub Actions)

### Phase 4: Validator & Issue (Week 9-10)
- [ ] `xns validator register/status/retire`
- [ ] `xns issue reconcile/list/link/report`
- [ ] Cross-repo GitHub API integration

### Phase 5: Polish & Release (Week 11-12)
- [ ] Documentation site (GitHub Pages)
- [ ] Shell completion (bash/zsh/fish)
- [ ] Homebrew tap / APT repo
- [ ] v2.0.0 release

## Key Design Decisions

1. **Go over Bash**: Typed, testable, cross-platform, single binary distribution
2. **Templates over Files**: 5 templates × N profiles = infinite combinations, zero drift
3. **Config over Flags**: One authoritative `~/.xns/config.yaml`, env overrides, CLI flags override env
4. **Abort Conditions over Manual Monitoring**: Named regression guards (`--abort-on validators-not-legit`) prevent fleet-wide failures
5. **Validation-First**: `xns sync replay` is a first-class command, not an afterthought
6. **Cross-Repo Reconciliation**: `xns issue reconcile` closes the tracker-drift gap identified in Opus 4.7 report

## Why This Wins

| Competitor | Weakness | XNS v2.0 Advantage |
|-----------|----------|-------------------|
| eth-docker | Ethereum-only, complex YAML | Multi-chain, template-based, simpler |
| RocketPool | Staking-specific, no devnet | General node ops, validator + devnet |
| Dappnode | GUI-first, limited CLI | CLI-first, fleet-scale, CI-integrated |
| Foundry | Dev toolchain, no node ops | Production node deployment + validation |
| Custom bash (current) | Untestable, drifts, 162 scripts | Single binary, typed, tested, versioned |

## Success Metrics

- [ ] 162 bash scripts replaced by `xns` commands
- [ ] Fleet deployment time: 30 min → 5 min
- [ ] Issue tracker drift: weekly manual → `xns issue reconcile` (automated)
- [ ] Validation suite: manual → `xns sync replay` (CI-integrated)
- [ ] New node setup: 2 hours → 10 minutes

---
*Design Spec v1.0 — 2026-04-28*
*Author: Opus 4.7 + Kimi 2.6 for XDC Network*
