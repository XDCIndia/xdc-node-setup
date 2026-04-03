# XDC Global Node Monitor

The Global Node Monitor is a P2P network crawler and validator monitoring system for the XDC Network. It provides real-time visibility into network topology, validator performance, and node health across the entire XDC ecosystem.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     XDC Global Node Monitor                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐     │
│  │   P2P Crawler   │    │Validator Monitor│    │   SkyNet API    │     │
│  │                 │    │                 │    │                 │     │
│  │ • devp2p        │    │ • XDCValidator  │    │ • Fleet data    │     │
│  │ • Peer discovery│    │ • Stake tracking│    │ • Node metrics  │     │
│  │ • Network graph │    │ • Uptime calc   │    │ • Geo location  │     │
│  └────────┬────────┘    └────────┬────────┘    └────────┬────────┘     │
│           │                      │                      │              │
│           └──────────────────────┼──────────────────────┘              │
│                                  ▼                                     │
│                    ┌─────────────────────────┐                        │
│                    │    Network Map DB       │                        │
│                    │  (Graph/Timeseries data)│                        │
│                    └────────────┬────────────┘                        │
│                                 │                                      │
│                    ┌────────────▼────────────┐                        │
│                    │      API Gateway        │                        │
│                    └────────────┬────────────┘                        │
│                                 │                                      │
│           ┌─────────────────────┼─────────────────────┐               │
│           ▼                     ▼                     ▼               │
│    ┌────────────┐      ┌────────────┐      ┌────────────┐            │
│    │  Web UI    │      │  Alerts    │      │  External  │            │
│    │  (Map)     │      │  (Prom)    │      │  APIs      │            │
│    └────────────┘      └────────────┘      └────────────┘            │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. P2P Crawler (`scripts/node-crawler.sh`)

The P2P crawler discovers XDC nodes by:

- **devp2p Protocol**: Implements the Ethereum peer discovery protocol
- **Recursive Peer Querying**: Starts with known bootnodes, queries each peer for their peers
- **Network Graph Building**: Constructs a graph of node connections
- **Metadata Collection**: Gathers client version, capabilities, and geolocation data

#### How It Works

1. **Seed Nodes**: Starts with known XDC bootnodes and SkyNet registered nodes
2. **Recursive Discovery**: For each discovered node, queries its peer table
3. **Graph Construction**: Builds a map of the network topology
4. **Data Storage**: Stores results in JSON format for further processing

#### Key Features

```bash
# Run the crawler
./scripts/node-crawler.sh

# Output: /tmp/xdc-network-map.json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "network": "mainnet",
  "total_nodes": 150,
  "nodes": [
    {
      "enode": "enode://...",
      "ip": "1.2.3.4",
      "port": 30303,
      "client": "XDC/v2.6.8",
      "peers": [...]
    }
  ]
}
```

### 2. Validator Leaderboard (`scripts/validator-leaderboard.sh`)

Queries the XDCValidator contract to provide:

- **Validator Rankings**: Sorted by stake amount
- **Status Tracking**: Active masternodes vs standby candidates
- **Uptime Estimation**: Based on block production history
- **Historical Data**: Track performance over time

#### Contract Integration

The script interacts with these contract methods:

| Method | Selector | Description |
|--------|----------|-------------|
| `getMasternodes()` | `0x06a49fce` | List of active validators |
| `getCandidates()` | `0x...` | List of standby candidates |
| `getCandidateCap(address)` | `0x0c4b7ae4` | Stake amount for address |

#### Output Formats

```bash
# Text output (default)
./scripts/validator-leaderboard.sh

# JSON output
./scripts/validator-leaderboard.sh json

# CSV output
./scripts/validator-leaderboard.sh csv
```

### 3. SkyNet Integration

Leverages SkyNet API for:

- **Fleet Data**: Aggregated metrics from registered nodes
- **Health Status**: Real-time node health information
- **Geolocation**: Geographic distribution of nodes

## Network Map Visualization (Future)

### Planned Web UI Features

1. **World Map View**
   - Interactive globe showing node locations
   - Heatmap of node density
   - Real-time connection lines between peers

2. **Validator Dashboard**
   - Live validator status
   - Block production timeline
   - Stake distribution charts

3. **Network Health Metrics**
   - Total node count over time
   - Average peer count per node
   - Geographic diversity score

4. **Alert System**
   - Validator offline notifications
   - Network partition detection
   - Unusual peer count fluctuations

## Data Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   XDC P2P    │────▶│   Crawler    │────▶│  Graph DB    │
│   Network    │     │   (cron)     │     │  (Neo4j)     │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                  │
┌──────────────┐     ┌──────────────┐            │
│ XDCValidator │────▶│  Leaderboard │────────────┤
│   Contract   │     │   Parser     │            │
└──────────────┘     └──────────────┘            │
                                                  ▼
                                        ┌──────────────────┐
                                        │   API Server     │
                                        │   (REST/WS)      │
                                        └────────┬─────────┘
                                                 │
                    ┌────────────────────────────┼────────────────────────────┐
                    ▼                            ▼                            ▼
            ┌──────────────┐            ┌──────────────┐            ┌──────────────┐
            │    Web UI    │            │   Grafana    │            │  AlertMgr    │
            │   (React)    │            │ Dashboards   │            │              │
            └──────────────┘            └──────────────┘            └──────────────┘
```

## Deployment

### Prerequisites

- Linux server (Ubuntu 22.04 recommended)
- Docker and Docker Compose
- jq, curl, bc
- Access to XDC RPC endpoints

### Installation

```bash
# Clone repository
git clone https://github.com/AnilChinchawale/xdc-node-setup.git
cd xdc-node-setup

# Install monitor components
sudo ./scripts/node-crawler.sh --install

# Set up cron for periodic crawling
echo "0 */6 * * * /opt/xdc-node/scripts/node-crawler.sh" | sudo crontab -
```

### Configuration

Create `/opt/xdc-node/config/monitor.env`:

```bash
# RPC endpoints
MAINNET_RPC=https://erpc.xinfin.network
TESTNET_RPC=https://erpc.apothem.network

# SkyNet API
SKYNET_API=https://skynet.xdcindia.com/api/v1
SKYNET_TOKEN=your_api_token

# Database
GRAPH_DB_URL=bolt://localhost:7687
GRAPH_DB_USER=neo4j
GRAPH_DB_PASS=secure_password

# Crawler settings
CRAWL_INTERVAL=3600  # seconds
MAX_PEERS_TO_QUERY=1000
TIMEOUT_SECONDS=30
```

## API Reference

### GET /api/v1/network/nodes

Returns list of discovered nodes.

```json
{
  "count": 150,
  "nodes": [
    {
      "id": "enode://...",
      "ip": "1.2.3.4",
      "geo": {"country": "US", "city": "New York"},
      "client": "XDC/v2.6.8",
      "last_seen": "2024-01-15T10:30:00Z"
    }
  ]
}
```

### GET /api/v1/validators/leaderboard

Returns validator rankings.

```json
{
  "updated": "2024-01-15T10:30:00Z",
  "validators": [
    {
      "rank": 1,
      "address": "xdc...",
      "stake": "10000000",
      "status": "active",
      "uptime": "99.9"
    }
  ]
}
```

### GET /api/v1/network/stats

Returns network statistics.

```json
{
  "total_nodes": 150,
  "active_validators": 108,
  "standby_candidates": 42,
  "avg_peers": 25,
  "countries": 23,
  "timestamp": "2024-01-15T10:30:00Z"
}
```

## Monitoring & Alerting

### Prometheus Metrics

```
# Network metrics
xdc_network_nodes_total 150
xdc_network_validators_active 108
xdc_network_validators_standby 42
xdc_network_avg_peer_count 25

# Validator metrics
xdc_validator_uptime{address="xdc..."} 99.9
xdc_validator_stake{address="xdc..."} 10000000

# Crawler metrics
xdc_crawler_last_run_timestamp 1705314600
xdc_crawler_nodes_discovered 150
xdc_crawler_duration_seconds 45
```

### Alert Rules

```yaml
- alert: ValidatorOffline
  expr: xdc_validator_uptime < 95
  for: 1h
  labels:
    severity: warning
  annotations:
    summary: "Validator {{ $labels.address }} has low uptime"

- alert: NetworkPartition
  expr: xdc_network_nodes_total < 100
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Possible network partition detected"
```

## Roadmap

### Phase 1: Foundation ✅
- [x] Basic P2P crawler
- [x] Validator leaderboard script
- [x] SkyNet integration

### Phase 2: Enhancement
- [ ] Real-time WebSocket API
- [ ] Graph database storage
- [ ] Historical trend analysis
- [ ] Enhanced geolocation

### Phase 3: Visualization
- [ ] Interactive world map
- [ ] Network topology graph
- [ ] Mobile-friendly dashboard
- [ ] Public API access

### Phase 4: Advanced Features
- [ ] Predictive analytics
- [ ] Network simulation
- [ ] Automated health reports
- [ ] Validator performance scoring

## Contributing

Contributions are welcome! Areas for contribution:

- Additional RPC endpoints
- Better geolocation accuracy
- Web UI development
- Documentation improvements
- Testing and bug reports

## Resources

- [XDC Network Documentation](https://docs.xdc.network)
- [devp2p Protocol](https://github.com/ethereum/devp2p)
- [XDCValidator Contract](https://github.com/XinFinOrg/XDCScan)
- [SkyNet Dashboard](https://skynet.xdcindia.com)
