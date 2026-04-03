#!/usr/bin/env bash
# skyone-dashboard-config.sh — SkyOne Dashboard Config Generator (#107/#108)
# Generate SkyOne dashboard config with block rate chart, fleet switcher,
# log stream panel, and alert history.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKYONE_URL="${SKYONE_URL:-http://localhost:7070}"
CONFIG_DIR="${REPO_ROOT}/config/skyone"
OUTPUT_FILE="${CONFIG_DIR}/dashboard.json"

CLIENTS=("geth" "erigon" "nethermind" "reth")
declare -A CLIENT_PORTS=([geth]=7070 [erigon]=7071 [nethermind]=7072 [reth]=8588)

mkdir -p "$CONFIG_DIR"

log() { echo "[$(date +%H:%M:%S)] $*"; }

generate_fleet_config() {
  local fleet_json="["
  local first=true
  for client in "${CLIENTS[@]}"; do
    local port="${CLIENT_PORTS[$client]}"
    [[ "$first" == "true" ]] && first=false || fleet_json+=","
    fleet_json+=$(cat <<JSON
{
      "id": "${client}",
      "name": "XDC ${client^}",
      "rpc_url": "http://localhost:${port}",
      "ws_url": "ws://localhost:${port}/ws",
      "color": "$(case $client in geth) echo '#00b4d8';; erigon) echo '#7b2ff7';; nethermind) echo '#f7931a';; reth) echo '#e63946';; esac)",
      "enabled": true
    }
JSON
)
  done
  fleet_json+="]"
  echo "$fleet_json"
}

generate_block_rate_chart() {
  cat <<JSON
{
    "id": "block-rate-chart",
    "type": "timeseries",
    "title": "Block Rate (blocks/sec)",
    "description": "Real-time block processing rate across all clients",
    "position": {"x": 0, "y": 0, "w": 12, "h": 4},
    "config": {
      "metrics": [
        $(for client in "${CLIENTS[@]}"; do
            echo "{\"client\": \"${client}\", \"metric\": \"blocks_per_second\", \"label\": \"${client}\"},"
          done | sed '$ s/,$//')
      ],
      "refresh_interval_ms": 2000,
      "time_range": "1h",
      "y_axis_label": "Blocks/sec",
      "show_legend": true,
      "fill_opacity": 0.1
    }
  }
JSON
}

generate_fleet_switcher() {
  cat <<JSON
{
    "id": "fleet-switcher",
    "type": "fleet-selector",
    "title": "Client Fleet",
    "description": "Switch between XDC clients",
    "position": {"x": 0, "y": 4, "w": 3, "h": 6},
    "config": {
      "show_status_dot": true,
      "show_block_height": true,
      "show_peer_count": true,
      "show_sync_status": true,
      "allow_multi_select": true,
      "clients": [$(for c in "${CLIENTS[@]}"; do echo "\"$c\","; done | tr -d '\n' | sed 's/,$//')]
    }
  }
JSON
}

generate_log_stream() {
  cat <<JSON
{
    "id": "log-stream",
    "type": "log-viewer",
    "title": "Live Log Stream",
    "description": "Real-time container log viewer",
    "position": {"x": 3, "y": 4, "w": 9, "h": 6},
    "config": {
      "ws_endpoint": "${SKYONE_URL}/api/v2/logs/stream",
      "max_lines": 500,
      "auto_scroll": true,
      "show_timestamps": true,
      "show_client_filter": true,
      "log_levels": ["ERROR", "WARN", "INFO", "DEBUG"],
      "highlight_patterns": [
        {"pattern": "ERROR|FATAL|panic", "color": "#e63946"},
        {"pattern": "WARN|warning", "color": "#f7931a"},
        {"pattern": "imported|mined|sealed", "color": "#52b788"},
        {"pattern": "peer|connected|disconnected", "color": "#00b4d8"}
      ]
    }
  }
JSON
}

generate_alert_history() {
  cat <<JSON
{
    "id": "alert-history",
    "type": "alert-list",
    "title": "Alert History",
    "description": "Recent alerts and anomalies",
    "position": {"x": 0, "y": 10, "w": 6, "h": 4},
    "config": {
      "max_alerts": 50,
      "show_resolved": true,
      "alert_sources": ["consensus-monitor", "chaos-test", "benchmark", "sync-health"],
      "severity_colors": {
        "critical": "#e63946",
        "warning": "#f7931a",
        "info": "#00b4d8"
      },
      "alert_rules": [
        {"name": "Sync Stalled", "metric": "sync_lag_blocks", "threshold": 100, "severity": "warning"},
        {"name": "Peer Drop", "metric": "peer_count", "threshold": 3, "severity": "warning", "direction": "below"},
        {"name": "Memory High", "metric": "memory_mb", "threshold": 24576, "severity": "critical"},
        {"name": "Block Rate Low", "metric": "blocks_per_second", "threshold": 0.1, "severity": "critical", "direction": "below"}
      ]
    }
  }
JSON
}

generate_block_height_panel() {
  cat <<JSON
{
    "id": "block-height",
    "type": "stat-multi",
    "title": "Block Heights",
    "description": "Current block number per client",
    "position": {"x": 6, "y": 10, "w": 6, "h": 4},
    "config": {
      "clients": [$(for c in "${CLIENTS[@]}"; do echo "\"$c\","; done | tr -d '\n' | sed 's/,$//') ],
      "metric": "block_number",
      "show_delta": true,
      "delta_window": "5m",
      "format": "number"
    }
  }
JSON
}

generate_dashboard_config() {
  cat <<JSON
{
  "version": "2.0",
  "dashboard": {
    "id": "xdc-fleet",
    "title": "XDC Node Fleet — SkyOne",
    "description": "Multi-client XDC Network monitoring dashboard",
    "refresh_interval_ms": 5000,
    "theme": "dark",
    "grid_columns": 12,
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "generated_by": "skyone-dashboard-config.sh"
  },
  "fleet": $(generate_fleet_config),
  "panels": [
    $(generate_block_rate_chart),
    $(generate_fleet_switcher),
    $(generate_log_stream),
    $(generate_alert_history),
    $(generate_block_height_panel)
  ],
  "global_vars": {
    "network": "${NETWORK:-mainnet}",
    "skyone_api": "${SKYONE_URL}",
    "data_retention_hours": 168
  }
}
JSON
}

upload_to_skyone() {
  local config_file="$1"
  log "Uploading dashboard config to SkyNet..."
  curl -sf -X PUT "${SKYONE_URL}/api/v2/dashboard/config" \
    -H 'Content-Type: application/json' \
    -d "@${config_file}" 2>/dev/null \
    && log "✅ Dashboard config uploaded to SkyNet" \
    || log "⚠️  SkyNet upload failed (config saved locally)"
}

main() {
  log "=== SkyOne Dashboard Config Generator ==="

  local config
  config="$(generate_dashboard_config)"

  echo "$config" | python3 -m json.tool > "$OUTPUT_FILE" 2>/dev/null \
    || echo "$config" > "$OUTPUT_FILE"

  log "✅ Dashboard config written: ${OUTPUT_FILE}"

  # Print summary
  echo ""
  echo "Dashboard panels generated:"
  echo "  📊 Block Rate Chart (timeseries)"
  echo "  🚀 Fleet Switcher (multi-client selector)"
  echo "  📋 Live Log Stream (WebSocket)"
  echo "  🔔 Alert History (with rules)"
  echo "  📏 Block Heights (per-client stats)"
  echo ""
  echo "Fleet configured:"
  for client in "${CLIENTS[@]}"; do
    echo "  • ${client} → http://localhost:${CLIENT_PORTS[$client]}"
  done
  echo ""

  upload_to_skyone "$OUTPUT_FILE"
  log "Config saved to: ${OUTPUT_FILE}"
}

main "$@"
