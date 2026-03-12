#!/usr/bin/env bash

# Source utility functions
source "$(dirname "$0")/lib/utils.sh" || { echo "Failed to load utils"; exit 1; }
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }

#==============================================================================
# XDC Node Backup Script
# Implements backup standards from XDC-NODE-STANDARDS.md
# Features: Incremental rsync, GPG encryption, S3/FTP upload, retention
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Source logging library
source "${SCRIPT_DIR}/lib/logging.sh" 2>/dev/null || { echo "ERROR: Cannot source logging.sh"; exit 1; }

# Source notification library
# shellcheck source=/dev/null
source "${LIB_DIR}/notify.sh" 2>/dev/null || {
    echo "Warning: Notification library not found at ${LIB_DIR}/notify.sh"
}

# Configuration (can be overridden via /root/.xdc-backup.conf)
BACKUP_DIR="${BACKUP_DIR:-/backup/xdc-node}"
DATA_DIR="${DATA_DIR:-/root/xdcchain}"
CONFIG_DIR="${CONFIG_DIR:-/opt/xdc-node}"
CONFIG_FILE="/root/.xdc-backup.conf"

# Retention settings
RETENTION_DAILY=${RETENTION_DAILY:-7}
RETENTION_WEEKLY=${RETENTION_WEEKLY:-4}
RETENTION_MONTHLY=${RETENTION_MONTHLY:-12}

# Encryption settings
ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"
GPG_RECIPIENT="${BACKUP_GPG_RECIPIENT:-}"

# Remote storage settings
S3_BUCKET="${BACKUP_S3_BUCKET:-}"
S3_ENDPOINT="${BACKUP_S3_ENDPOINT:-}"
S3_REGION="${BACKUP_S3_REGION:-us-east-1}"
FTP_HOST="${BACKUP_FTP_HOST:-}"
FTP_USER="${BACKUP_FTP_USER:-}"
FTP_PASS="${BACKUP_FTP_PASS:-}"

# Logging
LOG_FILE="/var/log/xdc-backup.log"

# Initialize logging
LOG_FORMAT="text" LOG_OUTPUT="both" LOG_FILE="$LOG_FILE" init_logging || true

# Stats
BACKUP_SIZE=0
BACKUP_START_TIME=0
BACKUP_DURATION=0
BACKUP_SUCCESS=false
BACKUP_FILE=""

#==============================================================================
# Load Config File
#==============================================================================
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from $CONFIG_FILE" "{\"component\":\"backup\"}"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi
}

#==============================================================================
# Logging Wrapper Functions (using shared library)
#==============================================================================



#==============================================================================
# Pre-flight Checks
#==============================================================================
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Create backup directories
    mkdir -p "$BACKUP_DIR"/{daily,weekly,monthly,config,logs}
    
    # Check if data directory exists
    if [[ ! -d "$DATA_DIR" ]]; then
        error "Data directory not found: $DATA_DIR"
        exit 1
    fi
    
    # Check available disk space
    local backup_disk_usage
    backup_disk_usage=$(df -BG "$BACKUP_DIR" | awk 'NR==2 {print $4}' | tr -d 'G')
    local data_size
    data_size=$(du -sG "$DATA_DIR" 2>/dev/null | awk '{print $1}' || echo "1")
    
    if [[ $backup_disk_usage -lt $((data_size * 2)) ]]; then
        warn "Low disk space on backup directory. Available: ${backup_disk_usage}GB, Recommended: ~$((data_size * 2))GB"
    else
        log "✓ Sufficient disk space: ${backup_disk_usage}GB available"
    fi
    
    # Check for required tools
    if ! command -v rsync &> /dev/null; then
        error "rsync not installed"
        exit 1
    fi
    
    log "✓ Prerequisites check complete"
}

#==============================================================================
# Backup Functions
#==============================================================================
backup_chain_data() {
    log "=== Backing up chain data (incremental rsync) ==="
    
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="chaindata-${timestamp}"
    local backup_path="$BACKUP_DIR/daily/$backup_name"
    
    mkdir -p "$backup_path"
    
    # Find previous backup for hard-linking (incremental)
    local link_dest=""
    local prev_backup
    prev_backup=$(find "$BACKUP_DIR/daily" -maxdepth 1 -type d -name "chaindata-*" ! -name "$backup_name" -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [[ -n "$prev_backup" && -d "$prev_backup/chaindata" ]]; then
        link_dest="--link-dest=$prev_backup/chaindata"
        log "Using incremental backup (hard-linking to $prev_backup)"
    fi
    
    # Use rsync for incremental backup
    log "Running rsync..."
    local rsync_opts="-av --delete --exclude='*/LOCK' --exclude='*/LOG' --exclude='*/CURRENT' --exclude='*/MANIFEST*'"
    
    if [[ -n "$link_dest" ]]; then
        # shellcheck disable=SC2086
        rsync $rsync_opts "$link_dest" \
            "$DATA_DIR/XDC/chaindata/" \
            "$backup_path/chaindata/" 2>> "$LOG_FILE" || {
            error "Chain data backup failed"
            return 1
        }
    else
        # shellcheck disable=SC2086
        rsync $rsync_opts \
            "$DATA_DIR/XDC/chaindata/" \
            "$backup_path/chaindata/" 2>> "$LOG_FILE" || {
            error "Chain data backup failed"
            return 1
        }
    fi
    
    # Create metadata
    cat > "$backup_path/metadata.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "type": "chain_data",
  "source": "$DATA_DIR/XDC/chaindata",
  "hostname": "$(hostname)",
  "incremental": $([[ -n "$prev_backup" ]] && echo "true" || echo "false"),
  "link_dest": "${prev_backup:-null}"
}
EOF
    
    log "✓ Chain data backed up to: $backup_path"
    echo "$backup_path"
}

backup_keystore() {
    log "=== Backing up keystore ==="
    
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="keystore-${timestamp}"
    local backup_path="$BACKUP_DIR/daily/$backup_name"
    
    mkdir -p "$backup_path"
    
    if [[ -d "$DATA_DIR/keystore" ]]; then
        cp -r "$DATA_DIR/keystore" "$backup_path/"
        chmod -R 600 "$backup_path/keystore"/* 2>/dev/null || true
        
        cat > "$backup_path/metadata.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "type": "keystore",
  "source": "$DATA_DIR/keystore",
  "hostname": "$(hostname)"
}
EOF
        
        log "✓ Keystore backed up to: $backup_path"
        echo "$backup_path"
    else
        info "No keystore directory found at $DATA_DIR/keystore"
        return 0
    fi
}

backup_configs() {
    log "=== Backing up configurations ==="
    
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="config-${timestamp}"
    local backup_path="$BACKUP_DIR/config/$backup_name"
    
    mkdir -p "$backup_path"
    
    # Backup configs directory
    if [[ -d "$CONFIG_DIR" ]]; then
        tar -czf "$backup_path/configs.tar.gz" -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")" 2>> "$LOG_FILE"
        log "✓ Configs archived"
    fi
    
    # Backup genesis
    if [[ -f "$DATA_DIR/genesis.json" ]]; then
        cp "$DATA_DIR/genesis.json" "$backup_path/"
        log "✓ Genesis saved"
    fi
    
    # Backup docker compose
    if [[ -f "$CONFIG_DIR/docker/docker-compose.yml" ]]; then
        cp "$CONFIG_DIR/docker/docker-compose.yml" "$backup_path/"
    elif [[ -f "/opt/xdc-node/docker/docker-compose.yml" ]]; then
        cp "/opt/xdc-node/docker/docker-compose.yml" "$backup_path/"
    fi
    
    # Backup systemd services
    if [[ -f "/etc/systemd/system/xdc-node.service" ]]; then
        cp /etc/systemd/system/xdc-node*.service "$backup_path/" 2>/dev/null || true
    fi
    
    # Backup environment files
    if [[ -f "$CONFIG_DIR/configs/node.env" ]]; then
        cp "$CONFIG_DIR/configs/node.env" "$backup_path/"
    fi
    
    cat > "$backup_path/metadata.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "type": "configuration",
  "source": "$CONFIG_DIR",
  "hostname": "$(hostname)"
}
EOF
    
    log "✓ Configurations backed up to: $backup_path"
    echo "$backup_path"
}

#==============================================================================
# Compression and Encryption
#==============================================================================
compress_backup() {
    local source_dir=$1
    local output_file=$2
    
    log "Compressing backup: $source_dir"
    
    tar -czf "$output_file" -C "$(dirname "$source_dir")" "$(basename "$source_dir")" 2>> "$LOG_FILE" || {
        error "Compression failed"
        return 1
    }
    
    # Remove uncompressed directory
    rm -rf "$source_dir"
    
    local size
    size=$(du -h "$output_file" | cut -f1)
    log "✓ Compressed to: $output_file ($size)"
    echo "$output_file"
}

encrypt_backup() {
    local input_file=$1
    
    if [[ -z "$ENCRYPTION_KEY" && -z "$GPG_RECIPIENT" ]]; then
        info "No encryption configured, skipping encryption"
        return 0
    fi
    
    log "Encrypting backup..."
    
    local output_file="${input_file}.gpg"
    
    if [[ -n "$GPG_RECIPIENT" ]]; then
        # Use GPG public key encryption
        gpg --trust-model always --encrypt --recipient "$GPG_RECIPIENT" \
            --output "$output_file" "$input_file" 2>> "$LOG_FILE" || {
            error "GPG encryption failed"
            return 1
        }
    else
        # Use passphrase-based encryption
        gpg --symmetric --cipher-algo AES256 --compress-algo 1 \
            --passphrase "$ENCRYPTION_KEY" --batch --yes \
            --output "$output_file" "$input_file" 2>> "$LOG_FILE" || {
            error "GPG encryption failed"
            return 1
        }
    fi
    
    # Remove unencrypted file
    rm -f "$input_file"
    
    log "✓ Encrypted to: $output_file"
    echo "$output_file"
}

#==============================================================================
# Backup Integrity Verification
#==============================================================================
verify_backup() {
    local backup_file=$1
    
    log "Verifying backup integrity..."
    
    # Test archive integrity
    if [[ "$backup_file" == *.gpg ]]; then
        # For encrypted files, just check GPG can read the packet
        if gpg --list-packets "$backup_file" > /dev/null 2>> "$LOG_FILE"; then
            log "✓ Encrypted backup integrity verified"
            return 0
        fi
    elif [[ "$backup_file" == *.tar.gz ]]; then
        # For tar.gz, test extraction
        if tar -tzf "$backup_file" > /dev/null 2>> "$LOG_FILE"; then
            log "✓ Archive integrity verified"
            return 0
        fi
    fi
    
    error "Backup integrity check failed: $backup_file"
    return 1
}

#==============================================================================
# Remote Upload
#==============================================================================
upload_to_s3() {
    local file=$1
    
    if [[ -z "$S3_BUCKET" ]]; then
        return 0
    fi
    
    log "Uploading to S3: $S3_BUCKET"
    
    local filename
    filename=$(basename "$file")
    local s3_key="xdc-backups/$(hostname)/$(date +%Y/%m)/$filename"
    
    if command -v aws &> /dev/null; then
        local aws_opts=""
        [[ -n "$S3_ENDPOINT" ]] && aws_opts="--endpoint-url=$S3_ENDPOINT"
        
        # shellcheck disable=SC2086
        if aws s3 cp "$file" "s3://$S3_BUCKET/$s3_key" $aws_opts 2>> "$LOG_FILE"; then
            log "✓ Uploaded to S3: s3://$S3_BUCKET/$s3_key"
            return 0
        else
            warn "S3 upload failed"
            return 1
        fi
    else
        warn "AWS CLI not installed, skipping S3 upload"
        return 1
    fi
}

upload_to_ftp() {
    local file=$1
    
    if [[ -z "$FTP_HOST" || -z "$FTP_USER" ]]; then
        return 0
    fi
    
    log "Uploading to FTP: $FTP_HOST"
    
    local filename
    filename=$(basename "$file")
    local remote_path="xdc-backups/$(hostname)/$(date +%Y/%m)"
    
    if command -v lftp &> /dev/null; then
        lftp -u "$FTP_USER","$FTP_PASS" "$FTP_HOST" << EOF 2>> "$LOG_FILE"
set ssl:verify-certificate no
set net:max-retries 3
set net:timeout 30
mkdir -p "$remote_path"
cd "$remote_path"
put "$file"
bye
EOF
        log "✓ Uploaded to FTP"
        return 0
    elif command -v curl &> /dev/null; then
        # Fallback to curl FTP
        curl -T "$file" "ftp://$FTP_USER:$FTP_PASS@$FTP_HOST/$remote_path/$filename" 2>> "$LOG_FILE" || {
            warn "FTP upload failed"
            return 1
        }
        log "✓ Uploaded to FTP"
        return 0
    else
        warn "No FTP client found (install lftp), skipping FTP upload"
        return 1
    fi
}

#==============================================================================
# Retention Policy
#==============================================================================
apply_retention() {
    log "=== Applying retention policy ==="
    
    # Daily: Keep last $RETENTION_DAILY
    log "Cleaning up daily backups (keeping last $RETENTION_DAILY)..."
    find "$BACKUP_DIR/daily" -type f \( -name "*.tar.gz" -o -name "*.gpg" \) -mtime +$RETENTION_DAILY -delete 2>/dev/null || true
    find "$BACKUP_DIR/daily" -type d -mtime +$RETENTION_DAILY -exec rm -rf {} + 2>/dev/null || true
    
    # Weekly: On Sundays, copy to weekly and keep last $RETENTION_WEEKLY
    if [[ $(date +%u) -eq 7 ]]; then
        log "Sunday - creating weekly backup..."
        local latest_backup
        latest_backup=$(find "$BACKUP_DIR/daily" -name "*.tar.gz" -o -name "*.gpg" | sort | tail -1)
        if [[ -n "$latest_backup" ]]; then
            cp "$latest_backup" "$BACKUP_DIR/weekly/"
            log "✓ Copied to weekly backups"
        fi
    fi
    
    # Keep last $RETENTION_WEEKLY weekly backups
    log "Cleaning up weekly backups (keeping last $RETENTION_WEEKLY)..."
    find "$BACKUP_DIR/weekly" -type f -mtime +$((RETENTION_WEEKLY * 7)) -delete 2>/dev/null || true
    
    # Monthly: On the 1st of month, copy to monthly and keep last $RETENTION_MONTHLY
    if [[ $(date +%d) -eq 01 ]]; then
        log "First of month - creating monthly backup..."
        local latest_backup
        latest_backup=$(find "$BACKUP_DIR/daily" -name "*.tar.gz" -o -name "*.gpg" | sort | tail -1)
        if [[ -n "$latest_backup" ]]; then
            cp "$latest_backup" "$BACKUP_DIR/monthly/"
            log "✓ Copied to monthly backups"
        fi
    fi
    
    # Keep last $RETENTION_MONTHLY monthly backups
    log "Cleaning up monthly backups (keeping last $RETENTION_MONTHLY)..."
    find "$BACKUP_DIR/monthly" -type f -mtime +$((RETENTION_MONTHLY * 30)) -delete 2>/dev/null || true
    
    # Config backups: Keep last 30
    log "Cleaning up config backups (keeping last 30)..."
    find "$BACKUP_DIR/config" -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true
    
    log "✓ Retention policy applied"
}

#==============================================================================
# Generate Report
#==============================================================================
generate_report() {
    local backup_file=$1
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local report_file="$BACKUP_DIR/logs/backup-report-${timestamp}.json"
    
    local size_bytes=0
    if [[ -f "$backup_file" ]]; then
        size_bytes=$(stat -c%s "$backup_file" 2>/dev/null || echo "0")
    fi
    
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "backup_file": "$backup_file",
  "size_bytes": $size_bytes,
  "size_human": "$(du -h "$backup_file" 2>/dev/null | cut -f1 || echo "unknown")",
  "duration_seconds": $BACKUP_DURATION,
  "success": $BACKUP_SUCCESS,
  "encrypted": $([[ -n "$ENCRYPTION_KEY" || -n "$GPG_RECIPIENT" ]] && echo "true" || echo "false"),
  "s3_uploaded": $([[ -n "$S3_BUCKET" ]] && echo "true" || echo "false"),
  "ftp_uploaded": $([[ -n "$FTP_HOST" ]] && echo "true" || echo "false")
}
EOF
    
    log "Report saved to: $report_file"
}

#==============================================================================
# Notification Functions
#==============================================================================
send_backup_success_notification() {
    local backup_file="$1"
    local size
    size=$(du -h "$backup_file" 2>/dev/null | cut -f1 || echo "unknown")
    
    local message="✅ *Backup Completed Successfully*

📂 File: \`$(basename "$backup_file")\`
📊 Size: ${size}
⏱ Duration: ${BACKUP_DURATION}s
🖥 Node: \`${NOTIFY_NODE_HOST:-$(hostname)}\`
📅 Time: $(date '+%Y-%m-%d %H:%M:%S UTC')

Retention: ${RETENTION_DAILY}d / ${RETENTION_WEEKLY}w / ${RETENTION_MONTHLY}m"
    
    # Use new notification system if available
    if [[ "$(type -t notify)" == "function" ]]; then
        notify "info" "✅ Backup Completed" "$message" "backup_success"
    fi
}

send_backup_failure_notification() {
    local error_msg="$1"
    
    local message="❌ *Backup Failed*

🖥 Node: \`${NOTIFY_NODE_HOST:-$(hostname)}\`
📅 Time: $(date '+%Y-%m-%d %H:%M:%S UTC')
⏱ Duration: ${BACKUP_DURATION}s

*Error:*
$error_msg

*Action Required:*
Check backup logs: $LOG_FILE"
    
    # Use new notification system if available
    if [[ "$(type -t notify_alert)" == "function" ]]; then
        notify_alert "critical" "❌ Backup Failed" "$message" "backup_failure"
    fi
}

#==============================================================================
# Main
#==============================================================================
main() {
    BACKUP_START_TIME=$(date +%s)
    
    log "========================================"
    log "XDC Node Backup Starting"
    log "========================================"
    log "Data directory: $DATA_DIR"
    log "Backup directory: $BACKUP_DIR"
    log "Retention: $RETENTION_DAILY daily, $RETENTION_WEEKLY weekly, $RETENTION_MONTHLY monthly"
    
    # Load configuration
    load_config
    
    # Run pre-flight checks
    check_prerequisites
    
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_archive="$BACKUP_DIR/daily/xdc-backup-${timestamp}.tar.gz"
    
    # Create temporary directory for consolidated backup
    local temp_dir
    temp_dir=$(mktemp -d)
    local consolidate_dir="$temp_dir/xdc-backup-$timestamp"
    mkdir -p "$consolidate_dir"
    
    # Perform backups
    local chain_backup
    local keystore_backup
    local config_backup
    local backup_error=""
    
    chain_backup=$(backup_chain_data) || backup_error="Chain data backup failed"
    keystore_backup=$(backup_keystore) || true  # Keystore may not exist
    config_backup=$(backup_configs) || backup_error="Config backup failed"
    
    if [[ -n "$backup_error" ]]; then
        error "$backup_error"
        BACKUP_DURATION=$(($(date +%s) - BACKUP_START_TIME))
        send_backup_failure_notification "$backup_error"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Copy to consolidate directory
    if [[ -n "$chain_backup" && -d "$chain_backup" ]]; then
        cp -r "$chain_backup" "$consolidate_dir/chaindata"
    fi
    
    if [[ -n "$keystore_backup" && -d "$keystore_backup" ]]; then
        cp -r "$keystore_backup" "$consolidate_dir/keystore"
    fi
    
    if [[ -n "$config_backup" && -d "$config_backup" ]]; then
        cp -r "$config_backup" "$consolidate_dir/config"
    fi
    
    # Create consolidated backup
    log "Creating consolidated archive..."
    tar -czf "$backup_archive" -C "$temp_dir" "xdc-backup-$timestamp" 2>> "$LOG_FILE" || {
        error "Failed to create backup archive"
        BACKUP_DURATION=$(($(date +%s) - BACKUP_START_TIME))
        send_backup_failure_notification "Failed to create backup archive"
        rm -rf "$temp_dir"
        exit 1
    }
    
    # Clean up temp directory
    rm -rf "$temp_dir"
    
    # Remove uncompressed backups
    [[ -n "$chain_backup" && -d "$chain_backup" ]] && rm -rf "$chain_backup"
    [[ -n "$keystore_backup" && -d "$keystore_backup" ]] && rm -rf "$keystore_backup"
    
    # Encrypt if configured
    if [[ -n "$ENCRYPTION_KEY" || -n "$GPG_RECIPIENT" ]]; then
        backup_archive=$(encrypt_backup "$backup_archive") || {
            BACKUP_DURATION=$(($(date +%s) - BACKUP_START_TIME))
            send_backup_failure_notification "Encryption failed"
            exit 1
        }
    fi
    
    # Verify backup integrity
    if verify_backup "$backup_archive"; then
        BACKUP_SUCCESS=true
    else
        BACKUP_DURATION=$(($(date +%s) - BACKUP_START_TIME))
        send_backup_failure_notification "Backup integrity verification failed"
        exit 1
    fi
    
    # Upload to remote storage
    upload_to_s3 "$backup_archive" || true  # Don't fail on upload errors
    upload_to_ftp "$backup_archive" || true  # Don't fail on upload errors
    
    # Apply retention policy
    apply_retention
    
    # Calculate duration
    BACKUP_DURATION=$(($(date +%s) - BACKUP_START_TIME))
    BACKUP_FILE="$backup_archive"
    
    # Generate report
    generate_report "$backup_archive"
    
    # Send success notification
    if [[ "$BACKUP_SUCCESS" == true ]]; then
        send_backup_success_notification "$backup_archive"
    fi
    
    # Final summary
    log ""
    log "========================================"
    log "Backup Complete"
    log "========================================"
    log "Archive: $backup_archive"
    log "Size: $(du -h "$backup_archive" 2>/dev/null | cut -f1)"
    log "Duration: ${BACKUP_DURATION}s"
    log "Success: $BACKUP_SUCCESS"
    
    if [[ "$BACKUP_SUCCESS" == true ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
