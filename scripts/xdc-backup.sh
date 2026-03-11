#!/bin/bash
#==============================================================================
# XDC Node Automated Backup and Recovery System
# Issue: #520 - Automated Backup and Recovery System
#==============================================================================

set -euo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/var/backups/xdc-node}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
MAX_BACKUPS="${MAX_BACKUPS:-10}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"
S3_BUCKET="${S3_BUCKET:-}"
S3_ENDPOINT="${S3_ENDPOINT:-}"
AWS_ACCESS_KEY="${AWS_ACCESS_KEY:-}"
AWS_SECRET_KEY="${AWS_SECRET_KEY:-}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"

# Node data directories (configurable)
GETH_DATA_DIR="${GETH_DATA_DIR:-/mnt/data/xdc-nodes/gp5/XDC}"
ERIGON_DATA_DIR="${ERIGON_DATA_DIR:-/mnt/data/erigon-xdc-mainnet}"
NM_DATA_DIR="${NM_DATA_DIR:-/var/lib/xdc-nodes/nethermain-mainnet}"
RETH_DATA_DIR="${RETH_DATA_DIR:-/mnt/data/reth-db}"

# Logging
LOG_FILE="${LOG_FILE:-/var/log/xdc-backup.log}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#==============================================================================
# Logging Functions
#==============================================================================
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$@${NC}"; }
log_error() { log "ERROR" "${RED}$@${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$@${NC}"; }

#==============================================================================
# Utility Functions
#==============================================================================
check_dependencies() {
    local deps=("tar" "gzip" "date" "du" "df")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Required dependency not found: $dep"
            exit 1
        fi
    done
    
    if [[ -n "$S3_BUCKET" ]] && ! command -v "aws" &> /dev/null; then
        log_warn "AWS CLI not found. S3 backups will be skipped."
    fi
    
    if [[ -n "$ENCRYPTION_KEY" ]] && ! command -v "gpg" &> /dev/null; then
        log_warn "GPG not found. Encryption will be skipped."
    fi
}

ensure_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_info "Creating backup directory: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
    fi
    
    # Check disk space
    local available=$(df -BG "$BACKUP_DIR" | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ $available -lt 50 ]]; then
        log_warn "Low disk space: ${available}GB available. Backups may fail."
    fi
}

#==============================================================================
# Backup Functions
#==============================================================================
backup_client() {
    local client="$1"
    local data_dir="$2"
    local backup_name="${client}-$(date +%Y%m%d-%H%M%S).tar.gz"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    if [[ ! -d "$data_dir" ]]; then
        log_warn "Data directory not found for $client: $data_dir"
        return 1
    fi
    
    log_info "Starting backup for $client..."
    log_info "Source: $data_dir"
    log_info "Destination: $backup_path"
    
    # Calculate size before backup
    local size_before=$(du -sb "$data_dir" | cut -f1)
    log_info "Data size: $(numfmt --to=iec $size_before)"
    
    # Create backup
    local start_time=$(date +%s)
    
    if tar -czf "$backup_path" -C "$(dirname "$data_dir")" "$(basename "$data_dir")" 2>/dev/null; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local size_after=$(stat -c%s "$backup_path")
        
        log_success "Backup completed for $client"
        log_info "Duration: ${duration}s"
        log_info "Backup size: $(numfmt --to=iec $size_after)"
        log_info "Compression ratio: $(echo "scale=2; $size_before / $size_after" | bc)x"
        
        # Encrypt if key provided
        if [[ -n "$ENCRYPTION_KEY" ]] && command -v gpg &> /dev/null; then
            encrypt_backup "$backup_path"
        fi
        
        # Upload to S3 if configured
        if [[ -n "$S3_BUCKET" ]] && command -v aws &> /dev/null; then
            upload_to_s3 "$backup_path" "$client"
        fi
        
        return 0
    else
        log_error "Backup failed for $client"
        rm -f "$backup_path"
        return 1
    fi
}

encrypt_backup() {
    local backup_path="$1"
    local encrypted_path="${backup_path}.gpg"
    
    log_info "Encrypting backup: $backup_path"
    
    if gpg --symmetric --cipher-algo AES256 --compress-algo 0 \
           --passphrase "$ENCRYPTION_KEY" --batch --yes \
           -o "$encrypted_path" "$backup_path" 2>/dev/null; then
        rm -f "$backup_path"
        log_success "Encryption completed: $encrypted_path"
    else
        log_error "Encryption failed for: $backup_path"
    fi
}

upload_to_s3() {
    local backup_path="$1"
    local client="$2"
    local filename=$(basename "$backup_path")
    local s3_key="xdc-node-backups/${client}/${filename}"
    
    log_info "Uploading to S3: s3://$S3_BUCKET/$s3_key"
    
    local extra_args=""
    [[ -n "$S3_ENDPOINT" ]] && extra_args="--endpoint-url $S3_ENDPOINT"
    
    if aws s3 cp "$backup_path" "s3://$S3_BUCKET/$s3_key" $extra_args 2>/dev/null; then
        log_success "S3 upload completed: $s3_key"
    else
        log_error "S3 upload failed for: $filename"
    fi
}

#==============================================================================
# Cleanup Functions
#==============================================================================
cleanup_old_backups() {
    log_info "Cleaning up old backups (retention: $BACKUP_RETENTION_DAYS days)..."
    
    local deleted=0
    
    # Delete backups older than retention period
    while IFS= read -r file; do
        log_info "Deleting old backup: $file"
        rm -f "$file"
        ((deleted++)) || true
    done < <(find "$BACKUP_DIR" -name "*.tar.gz*" -type f -mtime +$BACKUP_RETENTION_DAYS)
    
    # Keep only MAX_BACKUPS most recent
    local backup_count=$(find "$BACKUP_DIR" -name "*.tar.gz*" -type f | wc -l)
    if [[ $backup_count -gt $MAX_BACKUPS ]]; then
        local to_delete=$((backup_count - MAX_BACKUPS))
        log_info "Removing $to_delete old backups (exceeds max: $MAX_BACKUPS)"
        
        find "$BACKUP_DIR" -name "*.tar.gz*" -type f -printf '%T@ %p\n' | \
            sort -n | head -n "$to_delete" | cut -d' ' -f2- | \
            while read -r file; do
                rm -f "$file"
                ((deleted++)) || true
            done
    fi
    
    log_info "Cleanup completed. Deleted $deleted old backups."
}

#==============================================================================
# Restore Functions
#==============================================================================
list_backups() {
    log_info "Available backups in $BACKUP_DIR:"
    
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        log_warn "No backups found in $BACKUP_DIR"
        return 1
    fi
    
    printf "%-20s %-15s %-10s %s\n" "DATE" "CLIENT" "SIZE" "FILENAME"
    printf '%.0s-' {1..80}; echo
    
    for backup in "$BACKUP_DIR"/*.tar.gz*; do
        [[ -f "$backup" ]] || continue
        
        local filename=$(basename "$backup")
        local date=$(echo "$filename" | grep -oP '\d{8}-\d{6}' || echo "unknown")
        local client=$(echo "$filename" | cut -d'-' -f1)
        local size=$(du -h "$backup" | cut -f1)
        
        printf "%-20s %-15s %-10s %s\n" "$date" "$client" "$size" "$filename"
    done
}

restore_backup() {
    local backup_file="$1"
    local restore_dir="${2:-}"
    
    if [[ ! -f "$backup_file" ]]; then
        # Try to find in backup directory
        backup_file="$BACKUP_DIR/$backup_file"
        if [[ ! -f "$backup_file" ]]; then
            log_error "Backup file not found: $1"
            return 1
        fi
    fi
    
    # Decrypt if needed
    if [[ "$backup_file" == *.gpg ]]; then
        log_info "Decrypting backup..."
        local decrypted="${backup_file%.gpg}"
        if gpg --decrypt --passphrase "$ENCRYPTION_KEY" --batch --yes \
               -o "$decrypted" "$backup_file" 2>/dev/null; then
            backup_file="$decrypted"
        else
            log_error "Decryption failed"
            return 1
        fi
    fi
    
    # Determine restore directory
    if [[ -z "$restore_dir" ]]; then
        local client=$(basename "$backup_file" | cut -d'-' -f1)
        case "$client" in
            geth|gp5|stable) restore_dir="$GETH_DATA_DIR" ;;
            erigon) restore_dir="$ERIGON_DATA_DIR" ;;
            nethermind|nm) restore_dir="$NM_DATA_DIR" ;;
            reth) restore_dir="$RETH_DATA_DIR" ;;
            *) 
                log_error "Cannot determine restore directory for client: $client"
                return 1
                ;;
        esac
    fi
    
    log_warn "This will overwrite data in: $restore_dir"
    read -p "Are you sure? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Restore cancelled"
        return 0
    fi
    
    # Stop node before restore
    log_info "Stopping node before restore..."
    systemctl stop xdc-node 2>/dev/null || docker stop xdc-node 2>/dev/null || true
    
    # Backup current state before restore
    if [[ -d "$restore_dir" ]]; then
        local current_backup="${restore_dir}.backup-$(date +%Y%m%d-%H%M%S)"
        log_info "Backing up current state to: $current_backup"
        mv "$restore_dir" "$current_backup"
    fi
    
    # Extract backup
    log_info "Restoring from backup: $backup_file"
    mkdir -p "$restore_dir"
    
    if tar -xzf "$backup_file" -C "$(dirname "$restore_dir")"; then
        log_success "Restore completed successfully"
        log_info "Starting node..."
        systemctl start xdc-node 2>/dev/null || docker start xdc-node 2>/dev/null || true
    else
        log_error "Restore failed"
        # Try to restore from backup
        if [[ -d "$current_backup" ]]; then
            log_info "Restoring from pre-restore backup..."
            rm -rf "$restore_dir"
            mv "$current_backup" "$restore_dir"
        fi
        return 1
    fi
}

#==============================================================================
# Main Functions
#==============================================================================
show_help() {
    cat << EOF
XDC Node Automated Backup and Recovery System

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    backup [client]     Create backup for specific client or all clients
    restore [file]      Restore from backup file
    list                List available backups
    cleanup             Remove old backups
    verify [file]       Verify backup integrity
    cron                Run backup with cron-friendly output

CLIENTS:
    geth, gp5, stable   XDC Geth (PR5/Stable)
    erigon              Erigon-XDC
    nethermind, nm      Nethermind-XDC
    reth                Reth-XDC
    all                 All clients (default for backup)

ENVIRONMENT VARIABLES:
    BACKUP_DIR          Backup storage directory (default: /var/backups/xdc-node)
    BACKUP_RETENTION_DAYS   Days to keep backups (default: 7)
    MAX_BACKUPS         Maximum number of backups (default: 10)
    S3_BUCKET           S3 bucket for offsite backups
    S3_ENDPOINT         S3 endpoint URL (for MinIO, etc.)
    ENCRYPTION_KEY      GPG passphrase for backup encryption
    AWS_ACCESS_KEY      AWS access key for S3
    AWS_SECRET_KEY      AWS secret key for S3

EXAMPLES:
    # Backup all clients
    $0 backup

    # Backup specific client
    $0 backup erigon

    # List available backups
    $0 list

    # Restore from backup
    $0 restore erigon-20240311-120000.tar.gz

    # Run with cron (minimal output)
    $0 cron

EOF
}

run_backup() {
    local target="${1:-all}"
    local exit_code=0
    
    log_info "=== XDC Node Backup Started ==="
    log_info "Target: $target"
    
    check_dependencies
    ensure_backup_dir
    
    case "$target" in
        geth|gp5|stable)
            backup_client "geth" "$GETH_DATA_DIR" || exit_code=1
            ;;
        erigon)
            backup_client "erigon" "$ERIGON_DATA_DIR" || exit_code=1
            ;;
        nethermind|nm)
            backup_client "nethermind" "$NM_DATA_DIR" || exit_code=1
            ;;
        reth)
            backup_client "reth" "$RETH_DATA_DIR" || exit_code=1
            ;;
        all)
            backup_client "geth" "$GETH_DATA_DIR" || true
            backup_client "erigon" "$ERIGON_DATA_DIR" || true
            backup_client "nethermind" "$NM_DATA_DIR" || true
            backup_client "reth" "$RETH_DATA_DIR" || true
            ;;
        *)
            log_error "Unknown client: $target"
            exit 1
            ;;
    esac
    
    cleanup_old_backups
    
    log_info "=== Backup Process Completed ==="
    return $exit_code
}

run_cron() {
    # Cron-friendly version with minimal output
    LOG_LEVEL="WARN"
    run_backup "$@" 2>&1 | grep -E "(ERROR|SUCCESS|WARN)" || true
}

verify_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        backup_file="$BACKUP_DIR/$backup_file"
        if [[ ! -f "$backup_file" ]]; then
            log_error "Backup file not found: $1"
            return 1
        fi
    fi
    
    log_info "Verifying backup: $backup_file"
    
    # Check if file is valid gzip
    if gzip -t "$backup_file" 2>/dev/null; then
        log_success "Backup file is valid gzip archive"
    else
        log_error "Backup file is corrupted or invalid"
        return 1
    fi
    
    # List contents
    log_info "Backup contents:"
    tar -tzf "$backup_file" | head -20
    local total_files=$(tar -tzf "$backup_file" | wc -l)
    log_info "Total files in archive: $total_files"
}

#==============================================================================
# Main Entry Point
#==============================================================================
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        backup)
            run_backup "$@"
            ;;
        restore)
            restore_backup "$@"
            ;;
        list)
            list_backups
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        verify)
            verify_backup "$@"
            ;;
        cron)
            run_cron "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
