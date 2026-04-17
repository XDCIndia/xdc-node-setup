#!/usr/bin/env bash
# ============================================================
# test-chaindata-detection.sh — Unit tests for chaindata.sh
# Issue: #164
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/lib/chaindata.sh"

TMP_BASE=$(mktemp -d)
trap 'rm -rf "$TMP_BASE"' EXIT

pass=0
fail=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="${3:-test}"
    if [[ "$expected" == "$actual" ]]; then
        echo "✓ $label"
        pass=$((pass + 1))
    else
        echo "✗ $label: expected '$expected', got '$actual'"
        fail=$((fail + 1))
    fi
}

# Test 1: Standard geth/ directory
mkdir -p "$TMP_BASE/geth/chaindata"
dd if=/dev/zero of="$TMP_BASE/geth/chaindata/dummy" bs=1M count=12 status=none
assert_eq "geth" "$(find_chaindata_dir "$TMP_BASE" 0)" "detects geth/ with sufficient size"
rm -rf "$TMP_BASE/geth"

# Test 2: Legacy XDC/ directory
mkdir -p "$TMP_BASE/XDC/chaindata"
dd if=/dev/zero of="$TMP_BASE/XDC/chaindata/dummy" bs=1M count=12 status=none
assert_eq "XDC" "$(find_chaindata_dir "$TMP_BASE" 0)" "detects legacy XDC/"
rm -rf "$TMP_BASE/XDC"

# Test 3: Legacy xdcchain/ directory
mkdir -p "$TMP_BASE/xdcchain/chaindata"
dd if=/dev/zero of="$TMP_BASE/xdcchain/chaindata/dummy" bs=1M count=12 status=none
assert_eq "xdcchain" "$(find_chaindata_dir "$TMP_BASE" 0)" "detects legacy xdcchain/"
rm -rf "$TMP_BASE/xdcchain"

# Test 4: Direct chaindata/
mkdir -p "$TMP_BASE/chaindata"
touch "$TMP_BASE/chaindata/CURRENT"
assert_eq "" "$(find_chaindata_dir "$TMP_BASE" 0)" "detects direct chaindata/"
rm -rf "$TMP_BASE/chaindata"

# Test 5: Empty base defaults to geth/
mkdir -p "$TMP_BASE/empty"
assert_eq "geth" "$(find_chaindata_dir "$TMP_BASE/empty")" "defaults to geth/ when empty"

# Test 6: find_chaindata_subdir_or_default with fresh init (small size)
mkdir -p "$TMP_BASE/fresh/geth/chaindata"
touch "$TMP_BASE/fresh/geth/chaindata/CURRENT"
assert_eq "geth" "$(find_chaindata_subdir_or_default "$TMP_BASE/fresh")" "find_chaindata_subdir_or_default sees fresh geth/"

# Test 7: chaindata_has_data
mkdir -p "$TMP_BASE/hasdata/geth/chaindata"
touch "$TMP_BASE/hasdata/geth/chaindata/1.ldb"
if chaindata_has_data "$TMP_BASE/hasdata"; then
    assert_eq "true" "true" "chaindata_has_data returns true when data exists"
else
    assert_eq "true" "false" "chaindata_has_data returns true when data exists"
fi

# Test 8: chaindata_path
mkdir -p "$TMP_BASE/path/XDC/chaindata"
assert_eq "$TMP_BASE/path/XDC/chaindata" "$(chaindata_path "$TMP_BASE/path")" "chaindata_path builds correct path"

echo ""
echo "=============================="
echo "Passed: $pass"
echo "Failed: $fail"
echo "=============================="

if [[ $fail -gt 0 ]]; then
    exit 1
fi
