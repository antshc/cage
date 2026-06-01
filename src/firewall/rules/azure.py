import re

from mitmproxy import http

# Patched at startup by user-rules/azure.py via the firewall loader.
ALLOWED_PATTERNS: list[str] = []

# Auth hosts are never path-filtered — required for token acquisition.
_AUTH_HOSTS = {
    "login.microsoftonline.com",
    "microsoftonline.com",
}

ENVIRONMENT = {
    "hosts": {
        "login.microsoftonline.com",
        "microsoftonline.com",
        "management.azure.com",
    },
    "wildcards": {
        "*.blob.core.windows.net",
        "*.vault.azure.net",
        "*.queue.core.windows.net",
        "*.table.core.windows.net",
        "*.file.core.windows.net",
        "*.dfs.core.windows.net",
        "*.servicebus.windows.net",
        "*.azurecr.io",
    },
}


def check_request(flow: http.HTTPFlow) -> None:
    host = flow.request.pretty_host.lower()
    if host in _AUTH_HOSTS:
        return

    if not ALLOWED_PATTERNS:
        body = (
            "[Sandbox Firewall] Access to '{}{}' is blocked.\n"
            "No Azure resource patterns are configured.\n"
            "Add ALLOWED_PATTERNS to a user-rule file, e.g.:\n"
            "  ALLOWED_PATTERNS = [\n"
            r"      r'management\.azure\.com/subscriptions/<subscription-id>(/.*)?$'," + "\n"
            "  ]"
        ).format(host, flow.request.path)
        flow.response = http.Response.make(403, body.encode(), {"Content-Type": "text/plain"})
        return

    target = host + flow.request.path
    compiled = [re.compile(p, re.IGNORECASE) for p in ALLOWED_PATTERNS]
    if not any(r.search(target) for r in compiled):
        body = (
            "[Sandbox Firewall] Access to '{}{}' is blocked.\n"
            "No configured pattern matched. Allowed patterns:\n{}"
        ).format(host, flow.request.path, "\n".join("  " + p for p in ALLOWED_PATTERNS))
        flow.response = http.Response.make(403, body.encode(), {"Content-Type": "text/plain"})

