# Video Guide Scripts

Outlines for video tutorials accompanying the written guides.

## Video Series: XDC Node Setup

### Video 1: Getting Started (5–7 min)

**Title**: "Set Up Your First XDC Node in 5 Minutes"

**Outline**:
1. **Intro** (0:00–0:30) — What is XDC Network? Why run a node?
2. **Prerequisites** (0:30–1:00) — Show system requirements, install Docker
3. **Install** (1:00–2:00) — Run install script, show output
4. **Configure** (2:00–3:00) — `xdc setup` wizard walkthrough
5. **Start & Verify** (3:00–4:30) — `xdc start`, `xdc status`, `xdc health`
6. **Monitor Sync** (4:30–5:30) — Watch sync progress, explain stages
7. **Outro** (5:30–6:00) — Next steps, link to masternode guide

**Screen recordings needed**:
- Terminal: full install → start flow
- Browser: XDC explorer showing your node

---

### Video 2: Masternode Setup (8–10 min)

**Title**: "Become an XDC Masternode Validator"

**Outline**:
1. **Intro** (0:00–0:30) — What is a masternode? Rewards overview
2. **Prerequisites** (0:30–1:30) — 10M XDC stake, synced node, static IP
3. **Wallet Setup** (1:30–3:00) — Create wallet, fund it, verify balance
4. **Register** (3:00–5:00) — `xdc masternode register`, confirm on-chain
5. **Configure & Restart** (5:00–6:30) — `xdc setup --masternode`, restart
6. **Verify** (6:30–8:00) — Check signing status, monitor blocks
7. **Security Tips** (8:00–9:00) — Firewall, SSH, backups
8. **Outro** (9:00–9:30) — Monitoring guide link

---

### Video 3: Erigon Migration (4–5 min)

**Title**: "Switch to Erigon: Faster Sync, Less Disk"

**Outline**:
1. **Intro** (0:00–0:30) — Geth vs Erigon comparison
2. **Backup** (0:30–1:00) — Save current config
3. **Migrate** (1:00–2:30) — Stop, switch client, start
4. **Monitor Stages** (2:30–3:30) — Show Erigon sync stages
5. **Verify** (3:30–4:00) — Confirm client switch
6. **Rollback** (4:00–4:30) — How to switch back if needed

---

### Video 4: Monitoring & Alerts (6–8 min)

**Title**: "Monitor Your XDC Node Like a Pro"

**Outline**:
1. **Intro** (0:00–0:30) — Why monitoring matters
2. **Built-in Tools** (0:30–2:00) — `xdc status`, `xdc health`, `xdc logs`
3. **Deploy Stack** (2:00–3:30) — `xdc monitoring start`, show Prometheus
4. **Grafana Dashboards** (3:30–5:30) — Walk through pre-built dashboards
5. **Alerts** (5:30–7:00) — Configure Slack/email alerts, show alert firing
6. **Outro** (7:00–7:30) — Best practices recap

## Production Notes

- **Resolution**: 1920×1080 (1080p)
- **Terminal font**: 16pt monospace, dark theme, high contrast
- **Voiceover**: Clear, paced, with captions
- **Repo link**: Show in video description
- **Chapters**: Add YouTube chapters matching the outline timestamps
