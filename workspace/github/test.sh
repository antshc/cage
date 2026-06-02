#!/usr/bin/env bash
set -euo pipefail

# Tests GitHub access from within the sandbox container.
# GitHub domains are excluded from mitmproxy TLS interception (--ignore-hosts)
# so that tools like gh CLI can connect directly with real certificates.

PASS=0
FAIL=0

assert_allowed() {
    local url="$1"
    local body
    body=$(curl -sk --max-time 15 "$url" 2>/dev/null || true)
    if echo "$body" | grep -q "\[Sandbox Firewall\]"; then
        echo "FAIL (unexpected firewall block): $url"
        ((FAIL++)) || true
    else
        echo "PASS: $url"
        ((PASS++)) || true
    fi
}

assert_blocked() {
    local url="$1"
    local body
    body=$(curl -sk --max-time 15 "$url" 2>/dev/null || true)
    if echo "$body" | grep -q "\[Sandbox Firewall\]"; then
        echo "PASS (blocked as expected): $url"
        ((PASS++)) || true
    else
        echo "FAIL (expected firewall block): $url"
        ((FAIL++)) || true
    fi
}

# --- gh CLI auth ---
# Verifies that gh auth status works through the transparent proxy with
# GitHub excluded from TLS interception (--ignore-hosts).
gh_output=$(timeout 15 gh auth status 2>&1) && gh_rc=0 || gh_rc=$?

assert_allowed "http://github.com/antshc/brain"
assert_allowed "http://github.com/some/other-repo"
assert_allowed "http://api.github.com/user"
assert_allowed "http://api.github.com/repos/antshc/brain/commits"
assert_allowed "http://api.github.com/"
assert_allowed "http://raw.githubusercontent.com/antshc/brain/main/README.md"
if [ "$gh_rc" -eq 0 ]; then
    echo "PASS: gh auth status"
    ((PASS++)) || true
elif [ "$gh_rc" -eq 124 ]; then
    echo "FAIL: gh auth status (timed out — HTTPS passthrough not working)"
    ((FAIL++)) || true
else
    echo "FAIL: gh auth status (exit code $gh_rc)"
    echo "  $gh_output"
    ((FAIL++)) || true
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
