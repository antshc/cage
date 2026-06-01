#!/usr/bin/env bash
set -euo pipefail

# Use HTTP (not HTTPS) so mitmproxy's request() hook fires before any upstream
# connection attempt. Blocked requests are returned as 403 by the firewall
# without requiring internet access to GitHub.

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

assert_allowed "http://github.com/antshc/brain"
assert_blocked  "http://github.com/some/blocked-repo"
assert_allowed "http://api.github.com/user"
assert_allowed "http://api.github.com/repos/antshc/brain/commits"
assert_allowed "http://api.github.com/"
assert_allowed "http://raw.githubusercontent.com/antshc/brain/main/README.md"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
