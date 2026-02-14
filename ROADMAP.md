# XDC Node Setup Roadmap 2026-2028
## One-Click XDC Infrastructure

**Document Version:** 1.0  
**Last Updated:** February 14, 2026  
**Classification:** Investor-Grade Strategic Roadmap

---

## Executive Summary

### Vision Statement
XDC Node Setup aims to become the **"One-Click XDC Infrastructure"** platform — an enterprise-grade node deployment toolkit that makes running XDC infrastructure as simple as clicking a button. We are the self-hosted alternative to Alchemy Node, giving enterprises and power users complete control over their infrastructure while eliminating the complexity of manual setup and maintenance.

### Current State (February 2026)
| Metric | Value |
|--------|-------|
| Deployment Methods | Docker, Kubernetes, Ansible, Terraform |
| Interface | CLI-first with basic automation |
| Security | Hardening scripts, best practices |
| Monitoring | Integrated health checks |
| Users | Early adopters, technical users |

### Target State (End of 2028)
| Metric | Target |
|--------|--------|
| Deployed Nodes | 25,000+ |
| Supported Clients | Geth, Erigon, Besu, Nethermind |
| Cloud Marketplaces | AWS, Azure, GCP, DO, Hetzner |
| GUI Adoption | 80% of deployments via GUI |
| Annual Recurring Revenue | $4.5M+ |
| Market Position | Default choice for XDC node deployment |

### Competitive Differentiation
Unlike generic cloud providers or complex DIY setups, XDC Node Setup delivers:
- **Protocol-Optimized Defaults**: XDC-specific tuning out of the box
- **Multi-Client Support**: No vendor lock-in, switch clients seamlessly
- **Enterprise Security**: SOC 2 compliant, audit-ready configurations
- **Visual Management**: GUI for operators who prefer clicks over commands
- **Ecosystem Integration**: Native staking, monitoring, and backup integrations

---

## Current Sprint — Pending Tasks (Feb 2026)

### ✅ Completed (Feb 14, 2026)
- [x] Fix `/var/lib/xdc` permission denied — switched to configurable XDC_STATE_DIR (commit 5b430eb)
- [x] Fix `free: command not found` — portable /proc/meminfo parsing
- [x] Fix data directory not found — auto-create before disk checks
- [x] Cleanup stray EOF file
- [x] Network-based directory structure: `{network}/xdcchain` + `{network}/.xdc-node` (mainnet/testnet/devnet)
- [x] Dashboard + Prometheus + Alertmanager auto-start with `xdc start` (removed profiles gate)
- [x] config.toml as single source of truth for XDC startup (all 3 network start scripts)
- [x] Relative volume paths in docker-compose (no more /opt/xdc-node hardcoded)
- [x] SkyNet auto-registration on install
- [x] CLI renamed xdc-node → xdc (16 commands)
- [x] ARM64/macOS support with Rosetta emulation
- [x] Dual RPC flag detection (--rpc vs --http)
- [x] Docker entrypoint.sh for XDC-mainnet → XDC symlink
- [x] TOML config support
- [x] Shell completions (bash/zsh)
- [x] Fix install.sh project directory creation (setup runs from proper install directory)
- [x] Fix setup.sh PROJECT_ROOT to use SCRIPT_DIR instead of PWD
- [x] config.toml generation during setup with network-specific settings
- [x] Mount config.toml in docker-compose.yml

### 🔄 In Progress
- [ ] Validate config.toml is actually used by XDC binary at startup
- [ ] Test install.sh → setup.sh flow on clean system (both repo and curl install methods)

### 🔴 Bugs / High Priority
- [ ] `admin_addPeer` RPC not available — verify `--rpcapi` includes `admin` in running container
- [ ] Dashboard not loading on first attempt — may need wait-for-healthy logic before nginx starts
- [ ] `top` command may fail on minimal systems (same portability issue as `free`)
- [ ] Verify Docker doesn't expose RPC externally (should be 127.0.0.1:9545 only)

### 🏗️ Technical Backlog
- [ ] End-to-end install test on clean Ubuntu 22.04 + clean macOS ARM64
- [ ] `xdc snapshot download` — needs real snapshot URLs in configs/snapshots.json
- [ ] Verify `xdc config` command works with TOML
- [ ] Verify shell completions install correctly
- [ ] Production build validation for dashboard
- [ ] Server hardening on 95.217.56.168 (scored 50/100)
- [ ] Update README.md with new directory structure + CLI examples
- [ ] Video guides / interactive tutorials
- [ ] Man pages (referenced in CHANGELOG but not created)
- [ ] Verify SkyNet agent scripts on remote servers use updated endpoints (netown→skynet rename)
- [ ] `xdc monitor` credential rotation tracking
- [ ] Global Node Monitor (P2P crawler, validator leaderboard, network map)

### 🚀 Q1 2026 Roadmap (Current Quarter)
- [ ] AWS AMI (us-east-1, eu-west-1, ap-southeast-1)
- [ ] DigitalOcean 1-Click Marketplace listing
- [ ] Azure ARM templates
- [ ] GCP Deployment Manager configs
- [ ] Terraform modules validation
- [ ] CLI v2.0 UX improvements

### 🔮 Future (Q2-Q4 2026)
- GUI Installer (React web-based) — visual deployment wizard for non-technical users
- Auto-update system — seamless client updates with rollback capabilities
- Multi-client support — easy switching between Geth and Erigon implementations
- Node marketplace — curated directory of verified hosting providers and managed services
- Staking integration — one-click validator setup and delegation management
- Mobile companion app — iOS/Android monitoring and basic node controls

### 🌐 2027-2028 Vision
Transform XDC Node Setup into the industry-standard infrastructure deployment platform:

**Multi-Client Maturity:** Support for Geth, Erigon, Besu, and Nethermind with seamless switching and performance benchmarking tools.

**Managed Service:** Fully managed node offering with 99.99% SLA, 24/7 monitoring, and automatic failover for enterprise customers.

**AI Operations:** Predictive scaling, automated security patching, intelligent client selection, anomaly detection, and self-healing infrastructure.

**Market Position:** 25,000+ deployed nodes, $4.5M ARR, becoming the default choice for XDC infrastructure deployment with presence across all major cloud marketplaces (AWS, Azure, GCP, DigitalOcean, Hetzner).

---

## 2026: Product-Market Fit & Foundation

### Q1 2026: CLI Stabilization & Cloud Templates (Jan-Mar)

**Theme:** Harden existing tools, expand cloud coverage

| Week | Milestone | Deliverables | Success Criteria |
|------|-----------|--------------|------------------|
| W1-W2 | AWS AMI release | Production-ready AMI with auto-configuration, CloudFormation templates | 100+ AMI launches |
| W3-W4 | DigitalOcean 1-Click | Marketplace droplet, pre-configured firewalls, monitoring | 50+ 1-click installs |
| W5-W6 | Azure integration | ARM templates, Azure Marketplace listing, AKS support | Beta customers |
| W7-W8 | GCP integration | Deployment Manager templates, GKE support, Marketplace prep | Working prototypes |
| W9-W10 | Terraform modules | Modular, composable infrastructure as code | 10+ modules |
| W11-W12 | Documentation & tutorials | Video guides, interactive tutorials, troubleshooting wizard | 90% setup success rate |

**Q1 Deliverables:**
- [ ] AWS AMI (us-east-1, eu-west-1, ap-southeast-1)
- [ ] DigitalOcean Marketplace listing
- [ ] Azure ARM templates
- [ ] GCP Deployment Manager configs
- [ ] Updated CLI v2.0 with better UX

**Revenue Target:** $15,000 (enterprise support contracts)

---

### Q2 2026: GUI Installer Launch (Apr-Jun)

**Theme:** Democratizing node deployment with visual tools

| Month | Milestone | Deliverables |
|-------|-----------|--------------|
| April | GUI alpha | Web-based installer (React), basic configuration wizard |
| April | Auto-update system | Seamless client updates, rollback capabilities, update scheduling |
| May | GUI beta | Advanced configuration, cloud provider selection, cost estimation |
| May | Multi-client support | Geth + Erigon support with easy switching |
| June | GUI general availability | Production-ready GUI, onboarding flows, in-app guidance |
| June | Mobile companion app | iOS/Android app for monitoring and basic controls |

**GUI Feature Set:**
```
┌─────────────────────────────────────────────────────────────┐
│  XDC Node Setup - Visual Deployment                         │
├─────────────────────────────────────────────────────────────┤
│  1. Choose Cloud Provider                                   │
│     [AWS] [Azure] [GCP] [DigitalOcean] [Hetzner] [Bare]     │
│                                                             │
│  2. Select Client                                           │
│     [Geth - Recommended] [Erigon - Fast Sync]               │
│                                                             │
│  3. Configure Node                                          │
│     Node Type: [Validator] [RPC Node] [Archive]             │
│     Region:    [us-east-1 ▼]                                │
│     Size:      [t3.large ▼]                                 │
│                                                             │
│  4. Review & Deploy                                         │
│     Estimated Cost: $45/month                               │
│     [Deploy Node]                                           │
└─────────────────────────────────────────────────────────────┘
```

**Q2 Success Metrics:**
- [ ] 500+ GUI-based deployments
- [ ] 70% GUI vs CLI adoption ratio
- [ ] <5 minute average deployment time
- [ ] 95% first-time success rate

**Revenue Target:** $50,000 (GUI subscriptions + marketplace)

---

### Q3 2026: Node Marketplace & Staking Integration (Jul-Sep)

**Theme:** Building an ecosystem around node infrastructure

| Month | Milestone | Deliverables |
|-------|-----------|--------------|
| July | Node marketplace launch | Verified hosting providers, managed service listings, reviews |
| July | Staking integration | One-click staking, validator setup, delegation management |
| August | Backup & restore | Automated backups, point-in-time recovery, cross-region restore |
| August | Disaster recovery | Multi-region failover, automated recovery procedures |
| September | Performance optimization | Auto-tuning, resource recommendations, cost optimization |
| September | Enterprise features | SSO, audit logging, compliance reports |

**Node Marketplace Features:**
- **Hosting Directory**: Curated list of verified hosting providers
- **Managed Services**: Professional node management offerings
- **Hardware Vendors**: Pre-configured hardware solutions
- **Service Ratings**: Community reviews and performance scores
- **SLA Comparisons**: Side-by-side provider comparisons

**Staking Integration:**
- One-click validator initialization
- Stake amount recommendations
- Commission rate optimization
- Delegation management UI
- Reward tracking and reporting
- Auto-compound configuration

**Q3 Success Metrics:**
- [ ] 20 marketplace providers
- [ ] 200 staking-enabled nodes
- [ ] 1,000 total deployed nodes
- [ ] $100K monthly volume through marketplace

**Revenue Target:** $150,000 (marketplace fees + staking services)

---

### Q4 2026: Enterprise Hardening & Scale (Oct-Dec)

**Theme:** Enterprise readiness and operational excellence

| Month | Milestone | Deliverables |
|-------|-----------|--------------|
| October | SOC 2 Type I | Compliance certification, security documentation |
| October | Advanced monitoring | Prometheus/Grafana integration, custom alerts, log aggregation |
| November | Team collaboration | Multi-user accounts, role-based access, approval workflows |
| November | API gateway | RESTful API, webhook support, CI/CD integrations |
| December | Enterprise SLA | 99.9% uptime guarantee, priority support, dedicated success manager |
| December | 2026 recap & 2027 planning | Performance review, roadmap refinement, team expansion |

**Enterprise Features:**
- **Multi-Region Deployment**: Deploy nodes across regions simultaneously
- **Blue-Green Updates**: Zero-downtime client updates
- **Custom Images**: Enterprise-specific OS hardening
- **Private Registry**: Air-gapped deployments
- **Compliance Reports**: Automated SOC 2, ISO 27001 evidence

**Q4 Success Metrics:**
- [ ] 2,500 total deployed nodes
- [ ] 10 enterprise customers
- [ ] SOC 2 Type I certification
- [ ] 99.9% node uptime across managed fleet

**Revenue Target:** $350,000 (enterprise contracts)

---

## 2027: Scale & Ecosystem

### Q1 2027: Multi-Client Maturity & Hetzner Expansion

**Focus Areas:**
- Full Besu and Nethermind support
- Hetzner Cloud marketplace integration
- ARM64 architecture support
- Client performance benchmarking tool

**Deliverables:**
- [ ] 4 supported clients (Geth, Erigon, Besu, Nethermind)
- [ ] Client comparison dashboard
- [ ] Automated client switching
- [ ] Hetzner 1-click deploy

**Milestone:** 5,000 deployed nodes

---

### Q2 2027: Managed Node Service & Partnerships

**Managed Service Offering:**
- **Fully Managed Nodes**: We run the infrastructure, customer owns the keys
- **Validator Management**: 24/7 monitoring, automatic failover
- **SLA Guarantees**: 99.99% uptime with financial backing
- **White-Label Options**: Reseller program for hosting providers

**Strategic Partnerships:**
- AWS (Advanced Technology Partner)
- XDC Foundation (official tooling)
- Ledger (hardware wallet integration)
- Chainlink (oracle node support)

**Milestone:** $2M ARR

---

### Q3 2027: Advanced Automation & AI Operations

**AI-Powered Features:**
- Predictive resource scaling
- Automated security patching
- Intelligent client selection based on use case
- Anomaly detection and self-healing
- Cost optimization recommendations

**Automation Suite:**
- GitOps-based deployments
- Automated compliance checks
- Self-service troubleshooting
- ChatOps integration (Slack/Discord)

**Milestone:** 10,000 deployed nodes

---

### Q4 2027: Global Expansion & Enterprise Dominance

**Geographic Expansion:**
- Asia-Pacific region focus
- Localized documentation (Chinese, Korean, Japanese)
- Regional support teams
- Local payment methods

**Enterprise Dominance:**
- Fortune 500 customers
- Government and CBDC deployments
- Financial institution partnerships
- SOC 2 Type II certification

**Milestone:** 15,000 deployed nodes, 100 enterprise customers

---

## 2028: Market Leadership

### Annual Goals

| Category | Target |
|----------|--------|
| **Scale** | 25,000+ deployed nodes |
| **Revenue** | $4.5M ARR |
| **Team** | 45 FTEs |
| **Clients** | 5+ supported clients |
| **Market Position** | #1 XDC infrastructure deployment tool |

### Key Initiatives

1. **XDC 2.0 Readiness**
   - Immediate support for XDC 2.0 features
   - Migration tooling from XDC 1.0
   - New consensus mechanism support

2. **Decentralized Infrastructure Network**
   - Community-run deployment nodes
   - Tokenized infrastructure incentives
   - Decentralized governance of the toolkit

3. **Developer Experience Platform**
   - IDE plugins (VS Code, IntelliJ)
   - Local development environments
   - Testnet automation

4. **Enterprise Cloud Partnerships**
   - Co-sell agreements with AWS, Azure, GCP
   - Enterprise marketplace prominence
   - Joint customer success programs

---

## Revenue Model & Projections

### Pricing Tiers

| Tier | Price | Features |
|------|-------|----------|
| **Open Source** | Free | CLI tools, community support |
| **Pro** | $29/mo | GUI access, auto-updates, email support |
| **Team** | $99/mo | Multi-user, API access, priority support |
| **Enterprise** | Custom | SLA, SSO, custom features, dedicated support |
| **Managed** | $299/mo/node | Fully managed, 99.99% SLA |

### Revenue Streams

1. **Subscription Revenue** (60%): Monthly/annual plans
2. **Marketplace Commission** (20%): 10-15% on hosting/services
3. **Enterprise Services** (15%): Custom deployments, consulting
4. **Cloud Partnerships** (5%): Marketplace revenue share

### Revenue Forecast

| Year | ARR | Customers | Avg. Revenue/Customer |
|------|-----|-----------|----------------------|
| 2026 | $565,000 | 300 | $1,883 |
| 2027 | $2,800,000 | 1,200 | $2,333 |
| 2028 | $4,500,000 | 2,500 | $1,800 |

---

## Team Scaling Plan

### Current Team (2026 Start)
- 2 Founders (engineering focus)
- 1 DevOps engineer
- 1 Technical writer

### Hiring Timeline

| Quarter | New Hires | Team Size | Key Roles |
|---------|-----------|-----------|-----------|
| Q1 2026 | 2 | 6 | Cloud engineer, Support engineer |
| Q2 2026 | 3 | 9 | Frontend developers (GUI team) |
| Q3 2026 | 3 | 12 | Security engineer, DevRel |
| Q4 2026 | 3 | 15 | Enterprise sales, Customer success |
| Q1 2027 | 5 | 20 | Multi-client team, QA |
| Q2 2027 | 5 | 25 | Managed service ops, Marketing |
| Q3 2027 | 6 | 31 | AI/ML engineers, Expansion team |
| Q4 2027 | 6 | 37 | Regional support, Partnerships |
| 2028 | 8 | 45 | Full organizational maturity |

### Organizational Structure (End of 2028)

```
CEO/Founder
├── Engineering (20)
│   ├── Platform Team (6)
│   ├── Client Engineering (5)
│   ├── GUI Team (4)
│   ├── Security (3)
│   └── QA (2)
├── Operations (12)
│   ├── Managed Services (5)
│   ├── Customer Success (4)
│   └── Support (3)
├── Sales & Marketing (8)
│   ├── Enterprise Sales (4)
│   ├── Growth (3)
│   └── DevRel (1)
└── G&A (5)
    ├── Finance (2)
    ├── HR (2)
    └── Legal (1)
```

---

## KPIs and Success Metrics

### Product Metrics

| Metric | 2026 | 2027 | 2028 |
|--------|------|------|------|
| Total Deployed Nodes | 2,500 | 15,000 | 25,000+ |
| Active Managed Nodes | 500 | 5,000 | 12,000+ |
| GUI Adoption Rate | 70% | 80% | 85% |
| First-Deploy Success Rate | 95% | 97% | 98% |
| Average Deploy Time | <5 min | <3 min | <2 min |

### Business Metrics

| Metric | 2026 | 2027 | 2028 |
|--------|------|------|------|
| ARR | $565K | $2.8M | $4.5M |
| Net Revenue Retention | 100% | 125% | 130% |
| Customer Acquisition Cost | $300 | $250 | $200 |
| Gross Margin | 65% | 70% | 75% |
| Paying Customers | 300 | 1,200 | 2,500 |

### Operational Metrics

| Metric | Target |
|--------|--------|
| Node Uptime (Managed) | 99.99% |
| Support Response Time | <1 hour (enterprise), <4 hours (standard) |
| Security Incidents | Zero critical |
| Update Success Rate | 99.9% |
| Customer Satisfaction (NPS) | 50+ |

---

## Competitive Analysis

### Primary Competitors

| Competitor | Strengths | Weaknesses | Our Advantage |
|------------|-----------|------------|---------------|
| **Alchemy Node** | Brand recognition, enterprise trust | Centralized, expensive, limited control | Self-hosted, cost-effective, full control |
| **QuickNode** | Fast setup, good UX | Centralized, vendor lock-in | Self-hosted, multi-client, no lock-in |
| **Infura** | Ethereum focus, reliability | No XDC support, centralized | XDC-native, self-hosted option |
| **Pocket Network** | Decentralized | Complex setup, limited support | Easy setup, enterprise support |
| **DIY Setup** | Free, full control | Complex, time-consuming, error-prone | Automation, best practices, support |

### Competitive Moats

1. **XDC Protocol Expertise**: Deep knowledge of XDC-specific requirements
2. **Multi-Client Flexibility**: No vendor lock-in, future-proof
3. **Automation Depth**: Years of operational knowledge codified
4. **Community Trust**: Open source foundation, transparent operations
5. **Enterprise Relationships**: Long-term contracts, integration depth

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Cloud provider policy changes | Medium | High | Multi-cloud strategy, bare metal options |
| XDC protocol changes | Medium | Medium | Close XDC Foundation relationship, rapid updates |
| Security vulnerabilities | Low | Critical | Security-first culture, audits, bug bounties |
| Key competitor acquisition | Medium | Medium | Strong community, open source foundation |
| Talent acquisition | Medium | High | Remote-first, competitive compensation |

---

## Appendix

### Technology Stack Evolution

| Year | CLI | GUI | Infrastructure | Clients |
|------|-----|-----|----------------|---------|
| 2026 | Go | Next.js | Docker, K8s | Geth, Erigon |
| 2027 | Go, Rust | Next.js 15 | Multi-cloud | +Besu, Nethermind |
| 2028 | Rust | Next.js 16 | Distributed | +Custom clients |

### Cloud Provider Roadmap

| Provider | Q1 2026 | Q2 2026 | Q4 2026 | Q2 2027 |
|----------|---------|---------|---------|---------|
| AWS | ✅ AMI | ✅ CF | ✅ Marketplace | ✅ Co-sell |
| Azure | ✅ Templates | | ✅ Marketplace | |
| GCP | ✅ DM | | ✅ Marketplace | |
| DigitalOcean | ✅ 1-Click | | | |
| Hetzner | | | ✅ | |
| OVH | | | | ✅ |

### Integration Partners

| Partner | Type | Integration | Timeline |
|---------|------|-------------|----------|
| XDC SkyNet | Monitoring | Native integration | Q2 2026 |
| Ledger | Hardware | Key management | Q3 2026 |
| Chainlink | Oracle | Node support | Q4 2026 |
| Tenderly | DevOps | Deployment hooks | Q1 2027 |
| Forta | Security | Monitoring | Q2 2027 |

---

**Document Owner:** XDC Node Setup Product Team  
**Next Review:** May 2026  
**Distribution:** Investors, Leadership Team, Advisory Board

---

*"Infrastructure should be invisible — powerful, reliable, and effortless"*