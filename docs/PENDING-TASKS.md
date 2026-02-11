# XDC Node Setup — Pending Tasks

> Updated: February 11, 2026

---

## 🔴 Critical (Bugs/Fixes)

- [ ] **E2E test on macOS** — Test full setup flow on macOS with Docker Desktop
- [ ] **Repo visibility** — Make GitHub repo public (currently private, curl 404s)
- [ ] **Dashboard deployment guide** — Step-by-step for Next.js dashboard

---

## 🟡 High Priority — Global Node Monitor for Network Owners

### What It Is
A **network-wide monitoring dashboard** for XDC Network owners/operators to monitor ALL nodes in the network — not just your own. Think Etherscan's node tracker + Beaconcha.in validator dashboard for XDC.

### Features Needed

#### 9.1 Global Network Dashboard (`dashboard/src/app/global/`)
- [ ] **Network Overview Page** — Total nodes, total masternodes, geographic distribution, client diversity, network health score
- [ ] **Global Node Map** — Interactive world map showing all XDC nodes by location (GeoIP from peer data)
- [ ] **Validator Leaderboard** — Rank all masternodes by: blocks signed, uptime, rewards, penalties
- [ ] **Network Health Score** — Aggregate score (0-100) based on: node count, diversity, uptime, sync status
- [ ] **Real-time Block Feed** — Live blocks with signer, timestamp, tx count, gas used
- [ ] **Epoch Dashboard** — Current epoch progress, masternode rotation, upcoming signers
- [ ] **Client Diversity Tracker** — Pie chart of XDPoSChain vs Erigon vs other clients
- [ ] **Network Upgrade Tracker** — % of nodes ready for upcoming hard forks

#### 9.2 Network Owner API (`/api/v1/network/`)
- [ ] `GET /api/v1/network/overview` — Network summary stats
- [ ] `GET /api/v1/network/nodes` — All known nodes with status
- [ ] `GET /api/v1/network/validators` — Active masternode list
- [ ] `GET /api/v1/network/validators/:address` — Single validator details
- [ ] `GET /api/v1/network/epochs` — Epoch history
- [ ] `GET /api/v1/network/health` — Network health score
- [ ] `GET /api/v1/network/diversity` — Client diversity stats
- [ ] `GET /api/v1/network/geo` — Geographic distribution
- [ ] `WebSocket /ws/blocks` — Real-time block stream
- [ ] `WebSocket /ws/network` — Real-time network stats

#### 9.3 Node Discovery Agent (`scripts/network-crawler.sh`)
- [ ] **P2P Network Crawler** — Discover all XDC nodes by crawling the peer network
- [ ] **Node Census** — Periodic census of all reachable nodes
- [ ] **Peer Metadata Collection** — Client version, protocol, capabilities per peer
- [ ] **GeoIP Mapping** — Map IP addresses to geographic locations
- [ ] **Store in DB** — SQLite database of discovered nodes + history
- [ ] **Scheduled crawl** — Cron job every 6 hours

#### 9.4 Alerting for Network Owners
- [ ] **Node count drop alert** — Alert if total network nodes drops below threshold
- [ ] **Client diversity alert** — Alert if single client >66% of network
- [ ] **Masternode offline alert** — Alert if specific masternodes go offline
- [ ] **Network partition alert** — Detect if network splits
- [ ] **Upgrade readiness alert** — Alert when <80% of nodes upgraded before fork

#### 9.5 Reports for Network Owners
- [ ] **Monthly Network Report** — PDF/HTML with: node growth, uptime stats, diversity trends, top validators
- [ ] **Incident Report Generator** — Auto-generate post-mortem for network events
- [ ] **Compliance Report** — Node distribution, decentralization metrics

---

## 🟢 Medium Priority

### Phase 5: Enterprise Features
- [ ] **Multi-region deployment** — One-click deploy across AWS/Hetzner/DO
- [ ] **SLA monitoring** — Uptime tracking with 99.9%/99.99% targets
- [ ] **Compliance automation** — CIS scans scheduled + evidence collection
- [ ] **Cost calculator** — Monthly cost estimates per deployment tier

### Phase 6: Developer Experience
- [ ] **Terraform provider** — `terraform-provider-xdc-node`
- [ ] **Kubernetes operator** — CRD for `XDCNode` resources
- [ ] **One-click cloud deploy** — AWS CloudFormation, DO 1-Click, Hetzner Cloud-init
- [ ] **SDK** — Python/Node.js SDK for XDC node management API

### Dashboard Improvements
- [ ] **Dark/Light theme toggle** in settings
- [ ] **Mobile app** (React Native) for node monitoring on phone
- [ ] **Webhook integrations** — PagerDuty, Slack, Discord notifications
- [ ] **Custom alert rules** — User-defined alert conditions
- [ ] **API key rotation** in dashboard

### Monitoring Improvements
- [ ] **Log aggregation** — Loki/ELK stack integration
- [ ] **Trace analysis** — Block processing trace visualization
- [ ] **Predictive disk alerts** — "Disk full in X days" based on growth rate
- [ ] **Historical data retention** — Long-term metrics storage (Thanos/Mimir)

---

## 🔵 Low Priority / Nice-to-Have

### Community & Ecosystem
- [ ] **Plugin system** — API for custom health checks, notification channels, metrics
- [ ] **Plugin marketplace** — Share community-built plugins
- [ ] **Interactive tutorials** — Step-by-step web-based guides
- [ ] **Video documentation** — YouTube tutorials for each feature
- [ ] **Localization** — Multi-language support (EN, KR, JP, ZH)
- [ ] **Community forum** — Integration with Discourse or GitHub Discussions

### Advanced Features
- [ ] **Chaos engineering automation** — Scheduled resilience tests
- [ ] **AI-powered anomaly detection** — ML-based unusual behavior detection
- [ ] **Smart contract monitoring** — Track key XDC contracts (bridge, staking)
- [ ] **MEV protection** — Detect and alert on MEV activity
- [ ] **Gas price oracle** — Network gas price tracking and prediction

---

## ✅ Completed

| Feature | Phase | Date |
|---------|-------|------|
| One-line installer | v1.0 | Feb 2026 |
| Security hardening | v1.0 | Feb 2026 |
| Health monitoring | v1.0 | Feb 2026 |
| Version management | v1.0 | Feb 2026 |
| Backup system | v1.0 | Feb 2026 |
| Notification system (TG, Email, Platform) | v1.0 | Feb 2026 |
| Docker deployment | v1.0 | Feb 2026 |
| Grafana dashboards | v1.0 | Feb 2026 |
| Prometheus alerting | v1.0 | Feb 2026 |
| Security scorecard | v1.0 | Feb 2026 |
| Web dashboard (Next.js) | Phase 2 | Feb 2026 |
| CLI tool (22 commands) | Phase 7 | Feb 2026 |
| Masternode wizard | v2.1 | Feb 2026 |
| Bootnode optimizer | v2.1 | Feb 2026 |
| Snapshot manager | v2.1 | Feb 2026 |
| XDC monitor (epoch, rewards, fork) | v2.1 | Feb 2026 |
| Sync optimizer | v2.1 | Feb 2026 |
| RPC security (4 profiles) | v2.1 | Feb 2026 |
| Network intelligence | v2.1 | Feb 2026 |
| Reward analytics | Phase 3 | Feb 2026 |
| Masternode clustering | Phase 3 | Feb 2026 |
| Stake management | Phase 3 | Feb 2026 |
| Consensus monitoring | Phase 4 | Feb 2026 |
| Network stats | Phase 4 | Feb 2026 |
| Governance tools | Phase 4 | Feb 2026 |
| Ansible playbooks | Enterprise | Feb 2026 |
| Terraform templates | Enterprise | Feb 2026 |
| K8s Helm chart | Enterprise | Feb 2026 |
| CIS benchmark (60+ checks) | Enterprise | Feb 2026 |
| Chaos testing | Enterprise | Feb 2026 |
| GitHub Actions CI | Enterprise | Feb 2026 |

---

*Total completed: 31 features | Pending: 45+ tasks*
*Priority: Global Node Monitor for Network Owners*
