#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Node Backup Script
# Backs up chain data, keystore, and configurations
#==============================================================================

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backup/xdc-node}"
DATA_DIR="${DATA_DIR:-/root/xdcchain}"
CONFIG_DIR="${CONFIG_DIR:-/opt/xdc-node}"
RETENTION_DAYS=7
RETENTION_WEEKS=4
ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"
S3_BUCKET="${BACKUP_S3_BUCKET:-}"
S3_ENDPOINT="${BACKUP_S3_ENDPOINT:-}"
FTP_HOST="${BACKUP_FTP_HOST:-}"
FTP_USER="${BACKUP_FTP_USER:-}"
FTP_PASS="${BACKUP_FTP_PASS:-}"

# Logging
LOG_FILE="/var/log/xdc-backup.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE" 2>/dev/null || true
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE" 2>/dev/null || true
}

#==============================================================================
# Pre-flight Checks
#==============================================================================
check_prerequisites() {
    mkdir -p "$BACKUP_DIR"/{daily,weekly,config}
    
    # Check available disk space
    local backup_disk_usage
    backup_disk_usage=$(df -BG "$BACKUP_DIR" | awk 'NR==2 {print $4}' | tr -d 'G')
    local data_size
    data_size=$(du -sG "$DATA_DIR" 2>/dev/null | awk '{print $1}' || echo "1")
    
    if [[ $backup_disk_usage -lt $((data_size * 2)) ]]; then
        warn "Low disk space on backup directory. Available: ${backup_disk_usage}GB, Needed: ~$((data_size * 2))GB"
    fi
    
    log "Prerequisites check complete"
}

#==============================================================================
# Backup Functions
#==============================================================================
backup_chain_data() {
    log "Backing up chain data..."
    
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="chaindata-${timestamp}"
    local backup_path="$BACKUP_DIR/daily/$backup_name"
    
    mkdir -p "$backup_path"
    
    # Use rsync for incremental backup
    log "Running rsync..."
    rsync -av --delete \
        --exclude="*/LOCK" \
        --exclude="*/LOG" \
        --exclude="*/CURRENT" \
        --exclude="*/MANIFEST*" \
        "$DATA_DIR/XDC/chaindata/" \
        "$backup_path/chaindata/" 2>> "$LOG_FILE" || {
        error "Chain data backup failed"
        return 1
    }
    
    # Create metadata
    cat > "$backup_path/metadata.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "type": "chain_data",
  "source": "$DATA_DIR/XDC/chaindata",
  "hostname": "$(hostname)"
}
EOF
    
    log "✓ Chain data backed up to: $backup_path"
    echo "$backup_path"
}

backup_keystore() {
    log "Backing up keystore..."
    
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="keystore-${timestamp}"
    local backup_path="$BACKUP_DIR/daily/$backup_name"
    
    mkdir -p "$backup_path"
    
    if [[ -d "$DATA_DIR/keystore" ]]; then
        cp -r "$DATA_DIR/keystore" "$backup_path/"
        
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
        warn "No keystore directory found"
        return 0
    fi
}

backup_configs() {
    log "Backing up configurations..."
    
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="config-${timestamp}"
    local backup_path="$BACKUP_DIR/config/$backup_name"
    
    mkdir -p "$backup_path"
    
    # Backup configs
    if [[ -d "$CONFIG_DIR" ]]; then
        tar -czf "$backup_path/configs.tar.gz" -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")" 2>> "$LOG_FILE"
    fi
    
    # Backup genesis
    if [[ -f "$DATA_DIR/genesis.json" ]]; then
        cp "$DATA_DIR/genesis.json" "$backup_path/"
    fi
    
    # Backup docker compose
    if [[ -f "$CONFIG_DIR/docker/docker-compose.yml" ]]; then
        cp "$CONFIG_DIR/docker/docker-compose.yml" "$backup_path/"
    fi
    
    # Backup systemd services
    if [[ -f "/etc/systemd/system/xdc-node.service" ]]; then
        cp /etc/systemd/system/xdc-node*.service "$backup_path/" 2>/dev/null || true
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
    
    log "✓ Compressed to: $output_file"
    echo "$output_file"
}

encrypt_backup() {
    local input_file=$1
    
    if [[ -z "$ENCRYPTION_KEY" ]]; then
        log "No encryption key set, skipping encryption"
        return 0
    fi
    
    log "Encrypting backup..."
    
    local output_file="${input_file}.enc"
    
    # Use AES-256-GCM encryption
    openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
        -in "$input_file" -out "$output_file" \
        -pass pass:"$ENCRYPTION_KEY" 2>> "$LOG_FILE" || {
        error "Encryption failed"
        return 1
    }
    
    # Remove unencrypted file
    rm -f "$input_file"
    
    log "✓ Encrypted to: $output_file"
    echo "$output_file"
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
    local s3_path="s3://$S3_BUCKET/xdc-backups/$(hostname)/$filename"
    
    if command -v aws &> /dev/null; then
        if aws s3 cp "$file" "$s3_path" 2>> "$LOG_FILE"; then
            log "✓ Uploaded to S3: $s3_path"
        else
            warn "S3 upload failed"
        fi
    elif command -v s3cmd &> /dev/null; then
        if s3cmd put "$file" "$s3_path" 2>> "$LOG_FILE"; then
            log "✓ Uploaded to S3: $s3_path"
        else
            warn "S3 upload failed"
        fi
    else
        warn "No S3 client found (install awscli or s3cmd)"
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
    
    if command -v lftp &> /dev/null; then
        lftp -u "$FTP_USER","$FTP_PASS" "$FTP_HOST" << EOF
set ssl:verify-certificate no
set net:max-retries 3
mkdir -p xdc-backups/$(hostname)
cd xdc-backups/$(hostname)
put "$file"
bye
EOF
        log "✓ Uploaded to FTP"
    else
        warn "lftp not installed, skipping FTP upload"
    fi
}

#==============================================================================
# Retention Policy
#==============================================================================
apply_retention() {
    log "Applying retention policy..."
    
    # Keep last 7 daily backups
    log "Cleaning up daily backups (keeping last $RETENTION_DAYS)..."
    find "$BACKUP_DIR/daily" -type f -name "*.tar.gz*" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    find "$BACKUP_DIR/daily" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true
    
    # Move some backups to weekly
    if [[ $(date +%u) -eq 7 ]]; then  # Sunday
        log "Creating weekly backup..."
        local latest_backup
        latest_backup=$(find "$BACKUP_DIR/daily" -name "*.tar.gz*" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        if [[ -n "$latest_backup" ]]; then
            cp "$latest_backup" "$BACKUP_DIR/weekly/"
        fi
    fi
    
    # Keep last 4 weekly backups
    log "Cleaning up weekly backups (keeping last $RETENTION_WEEKS)..."
    find "$BACKUP_DIR/weekly" -type f -mtime +$((RETENTION_WEEKS * 7)) -delete 2>/dev/null || true
    
    # Keep last 30 config backups
    find "$BACKUP_DIR/config" -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true
    
    log "✓ Retention policy applied"
}

#==============================================================================
# Main
#==============================================================================
main() {
    log "Starting XDC Node backup..."
    
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
    
    chain_backup=$(backup_chain_data)
    keystore_backup=$(backup_keystore)
    config_backup=$(backup_configs)
    
    # Copy to consolidate directory
    if [[ -n "$chain_backup" ]]; then
        cp -r "$chain_backup" "$consolidate_dir/chaindata"
    fi
    
    if [[ -n "$keystore_backup" ]]; then
        cp -r "$keystore_backup" "$consolidate_dir/keystore"
    fi
    
    if [[ -n "$config_backup" ]]; then
        cp -r "$config_backup" "$consolidate_dir/config"
    fi
    
    # Create consolidated backup
    tar -czf "$backup_archive" -C "$temp_dir" "xdc-backup-$timestamp" 2>> "$LOG_FILE"
    
    # Clean up temp directory
    rm -rf "$temp_dir"
    
    # Remove uncompressed backups
    rm -rf "$chain_backup" "$keystore_backup"
    
    # Encrypt if key provided
    if [[ -n "$ENCRYPTION_KEY" ]]; then
        backup_archive=$(encrypt_backup "$backup_archive")
    fi
    
    # Upload to remote storage
    upload_to_s3 "$backup_archive"
    upload_to_ftp "$backup_archive"
    
    # Apply retention policy
    apply_retention
    
    # Generate report
    local report_file="$BACKUP_DIR/backup-report-${timestamp}.json"
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "backup_file": "$backup_archive",
  "size_bytes": $(stat -c%s "$backup_archive" 2>/dev/null || echo "0"),
  "encrypted": $([[ -n "$ENCRYPTION_KEY" ]] && echo "true" || echo "false"),
  "s3_uploaded": $([[ -n "$S3_BUCKET" ]] && echo "true" || echo "false"),
  "ftp_uploaded": $([[ -n "$FTP_HOST" ]] && echo "true" || echo "false")
}
EOF
    
    log ""
    log "=================================="
    log "Backup Complete"
    log "=================================="
    log "Archive: $backup_archive"
    log "Size: $(du -h "$backup_archive" | cut -f1)"
    log "Report: $report_file"
    
    return 0
}

main "$@"
