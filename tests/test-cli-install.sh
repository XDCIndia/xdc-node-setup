#!/usr/bin/env bash
#==============================================================================
# XNS CLI Installation Smoke Test
# Validates that the xdc CLI is properly installed and functional
#==============================================================================

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
info() { echo -e "${YELLOW}ℹ${NC} $1"; }

errors=0

# Test 1: Binary exists at /usr/local/bin/xdc
if [[ -x /usr/local/bin/xdc ]]; then
    pass "Binary exists at /usr/local/bin/xdc"
else
    fail "Binary not found or not executable at /usr/local/bin/xdc"
    ((errors++))
fi

# Test 2: xdc --help returns 0
if xdc --help >/dev/null 2>&1; then
    pass "'xdc --help' executes successfully"
else
    fail "'xdc --help' failed"
    ((errors++))
fi

# Test 3: xdc --version returns 0
if xdc --version >/dev/null 2>&1; then
    pass "'xdc --version' executes successfully"
else
    fail "'xdc --version' failed"
    ((errors++))
fi

# Test 4: Bash completions installed
if [[ -f /etc/bash_completion.d/xdc ]]; then
    pass "Bash completions installed at /etc/bash_completion.d/xdc"
else
    info "Bash completions not found at /etc/bash_completion.d/xdc (optional)"
fi

# Test 5: Zsh completions installed
if [[ -f /usr/local/share/zsh/site-functions/_xdc ]]; then
    pass "Zsh completions installed at /usr/local/share/zsh/site-functions/_xdc"
else
    info "Zsh completions not found at /usr/local/share/zsh/site-functions/_xdc (optional)"
fi

# Test 6: Verify binary is not a broken symlink
if [[ -L /usr/local/bin/xdc ]]; then
    target=$(readlink -f /usr/local/bin/xdc)
    if [[ -x "$target" ]]; then
        pass "Symlink target is executable: $target"
    else
        fail "Symlink target is missing or not executable: $target"
        ((errors++))
    fi
fi

# Summary
echo ""
if [[ "$errors" -eq 0 ]]; then
    pass "All required CLI installation checks passed"
    exit 0
else
    fail "$errors required check(s) failed"
    exit 1
fi
