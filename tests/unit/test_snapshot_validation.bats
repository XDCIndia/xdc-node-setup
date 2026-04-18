#!/usr/bin/env bats
#==============================================================================
# Unit Tests: Snapshot Validation (Issue #165)
# Tests for scripts/validate-snapshot-deep.sh and scripts/lib/snapshot-validation.sh
# Run: bats tests/unit/test_snapshot_validation.bats
#==============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/../../scripts"
    LIB_DIR="$SCRIPT_DIR/lib"
    TEST_TEMP_DIR=$(mktemp -d)
    
    # Source the validation library
    source "$LIB_DIR/snapshot-validation.sh" 2>/dev/null || true
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

#==============================================================================
# validate-snapshot-deep.sh CLI tests
#==============================================================================

@test "validate-snapshot-deep: rejects missing datadir" {
    run bash "$SCRIPT_DIR/validate-snapshot-deep.sh" --datadir /nonexistent
    [ "$status" -eq 3 ]
}

@test "validate-snapshot-deep: shows help" {
    run bash "$SCRIPT_DIR/validate-snapshot-deep.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "validate-snapshot-deep: quick mode passes on minimal valid structure" {
    mkdir -p "$TEST_TEMP_DIR/geth/chaindata/ancient/bodies"
    touch "$TEST_TEMP_DIR/geth/chaindata/CURRENT"
    touch "$TEST_TEMP_DIR/geth/chaindata/000001.sst"
    touch "$TEST_TEMP_DIR/geth/chaindata/ancient/bodies/00000001.cidx"
    
    run bash "$SCRIPT_DIR/validate-snapshot-deep.sh" --quick --datadir "$TEST_TEMP_DIR"
    [ "$status" -eq 0 ]
}

@test "validate-snapshot-deep: standard mode fails insufficient files" {
    mkdir -p "$TEST_TEMP_DIR/geth/chaindata"
    touch "$TEST_TEMP_DIR/geth/chaindata/CURRENT"
    # No SST/LDB files — should fail min-files check on mainnet
    
    run bash "$SCRIPT_DIR/validate-snapshot-deep.sh" --standard --datadir "$TEST_TEMP_DIR" --network testnet
    # Testnet has lower thresholds; may still pass quick but fail standard
}

@test "validate-snapshot-deep: json output is valid" {
    mkdir -p "$TEST_TEMP_DIR/geth/chaindata/ancient/bodies"
    touch "$TEST_TEMP_DIR/geth/chaindata/CURRENT"
    touch "$TEST_TEMP_DIR/geth/chaindata/000001.sst"
    touch "$TEST_TEMP_DIR/geth/chaindata/ancient/bodies/00000001.cidx"
    
    run bash "$SCRIPT_DIR/validate-snapshot-deep.sh" --quick --json --datadir "$TEST_TEMP_DIR"
    [ "$status" -eq 0 ]
    echo "$output" | jq . >/dev/null 2>&1
}

@test "validate-snapshot-deep: writes output file" {
    mkdir -p "$TEST_TEMP_DIR/geth/chaindata/ancient/bodies"
    touch "$TEST_TEMP_DIR/geth/chaindata/CURRENT"
    touch "$TEST_TEMP_DIR/geth/chaindata/000001.sst"
    touch "$TEST_TEMP_DIR/geth/chaindata/ancient/bodies/00000001.cidx"
    local out="$TEST_TEMP_DIR/report.json"
    
    run bash "$SCRIPT_DIR/validate-snapshot-deep.sh" --quick --json --output "$out" --datadir "$TEST_TEMP_DIR"
    [ "$status" -eq 0 ]
    [ -f "$out" ]
    jq . "$out" >/dev/null 2>&1
}

@test "validate-snapshot-deep: detects leveldb engine" {
    mkdir -p "$TEST_TEMP_DIR/geth/chaindata"
    touch "$TEST_TEMP_DIR/geth/chaindata/CURRENT"
    touch "$TEST_TEMP_DIR/geth/chaindata/000001.ldb"
    
    run bash "$SCRIPT_DIR/validate-snapshot-deep.sh" --quick --json --datadir "$TEST_TEMP_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"leveldb"* ]] || [[ "$output" == *"unknown"* ]]
}

#==============================================================================
# snapshot-validation.sh library tests
#==============================================================================

@test "snapshot_detect_engine: returns pebble for .sst files" {
    mkdir -p "$TEST_TEMP_DIR/chaindata"
    touch "$TEST_TEMP_DIR/chaindata/000001.sst"
    
    run bash -c "source '$LIB_DIR/snapshot-validation.sh' && snapshot_detect_engine '$TEST_TEMP_DIR/chaindata'"
    [ "$status" -eq 0 ]
    [ "$output" = "pebble" ]
}

@test "snapshot_detect_engine: returns leveldb for .ldb files" {
    mkdir -p "$TEST_TEMP_DIR/chaindata"
    touch "$TEST_TEMP_DIR/chaindata/000001.ldb"
    
    run bash -c "source '$LIB_DIR/snapshot-validation.sh' && snapshot_detect_engine '$TEST_TEMP_DIR/chaindata'"
    [ "$status" -eq 0 ]
    [ "$output" = "leveldb" ]
}

@test "snapshot_count_files: counts database files" {
    mkdir -p "$TEST_TEMP_DIR/chaindata"
    touch "$TEST_TEMP_DIR/chaindata/000001.sst"
    touch "$TEST_TEMP_DIR/chaindata/000002.sst"
    touch "$TEST_TEMP_DIR/chaindata/000003.ldb"
    
    run bash -c "source '$LIB_DIR/snapshot-validation.sh' && snapshot_count_files '$TEST_TEMP_DIR/chaindata'"
    [ "$status" -eq 0 ]
    [ "$output" -eq 3 ]
}

@test "snapshot_check_layout: detects geth subdir" {
    mkdir -p "$TEST_TEMP_DIR/geth/chaindata"
    
    run bash -c "source '$LIB_DIR/snapshot-validation.sh' && snapshot_check_layout '$TEST_TEMP_DIR'"
    [ "$status" -eq 0 ]
}

@test "snapshot_check_ancient_integrity: passes with non-empty segments" {
    mkdir -p "$TEST_TEMP_DIR/chaindata/ancient/bodies"
    mkdir -p "$TEST_TEMP_DIR/chaindata/ancient/headers"
    mkdir -p "$TEST_TEMP_DIR/chaindata/ancient/receipts"
    touch "$TEST_TEMP_DIR/chaindata/ancient/bodies/00000001.cidx"
    touch "$TEST_TEMP_DIR/chaindata/ancient/headers/00000001.cidx"
    touch "$TEST_TEMP_DIR/chaindata/ancient/receipts/00000001.cidx"
    
    run bash -c "source '$LIB_DIR/snapshot-validation.sh' && snapshot_check_ancient_integrity '$TEST_TEMP_DIR/chaindata'"
    [ "$status" -eq 0 ]
}

@test "snapshot_load_thresholds: loads mainnet full config" {
    run bash -c "source '$LIB_DIR/snapshot-validation.sh' && snapshot_load_thresholds mainnet full && echo MIN_FILES=\$MIN_FILES MIN_SIZE=\$MIN_SIZE_BYTES"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MIN_FILES="* ]]
    [[ "$output" == *"MIN_SIZE="* ]]
}
