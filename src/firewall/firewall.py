import importlib.util
import ipaddress
import os
import socket

from mitmproxy import http

# RFC1918 private address ranges plus loopback — a general networking standard,
# not specific to Docker. Any host resolving to these ranges is considered internal
# and bypasses the allowlist (covers Docker containers, VMs, LAN services, etc.).
_PRIVATE_NETWORKS = [
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
    ipaddress.ip_network("127.0.0.0/8"),
]


def _is_private_host(host: str) -> bool:
    """Return True if the host resolves to a private/RFC1918 address."""
    try:
        ip = ipaddress.ip_address(socket.gethostbyname(host))
        return any(ip in net for net in _PRIVATE_NETWORKS)
    except (socket.gaierror, ValueError):
        return False


ALLOWED_HOSTS: set[str] = set()
ALLOWED_WILDCARDS: list[str] = []  # suffixes like ".digicert.com" from "*.digicert.com"
HOST_HANDLERS: dict[str, callable] = {}


def _load_rules_from_dir(rules_dir: str) -> None:
    """Load ENVIRONMENT and optional check_request from every .py file in rules_dir."""
    if not os.path.isdir(rules_dir):
        return
    for fname in sorted(os.listdir(rules_dir)):
        if not fname.endswith(".py"):
            continue
        fpath = os.path.join(rules_dir, fname)
        spec = importlib.util.spec_from_file_location(fname[:-3], fpath)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        env = getattr(module, "ENVIRONMENT", {})
        hosts = env.get("hosts", set())
        ALLOWED_HOSTS.update(hosts)
        for pattern in env.get("wildcards", set()):
            if pattern.startswith("*."):
                ALLOWED_WILDCARDS.append(pattern[1:])  # store as ".digicert.com"
        if hasattr(module, "check_request"):
            for host in hosts:
                HOST_HANDLERS[host] = module.check_request


# --- Built-in rules: every .py file present in rules/ is active ---

_BUILTIN_RULES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rules")
_load_rules_from_dir(_BUILTIN_RULES_DIR)

# --- User-supplied extension rules (active when mounted) ---

_load_rules_from_dir("/etc/mitmproxy/user-rules")


# --- Main request handler ---

def request(flow: http.HTTPFlow) -> None:
    host = flow.request.pretty_host.lower()

    # Allow RFC1918/private destinations (Docker host containers, internal services)
    if _is_private_host(host):
        return

    if host not in ALLOWED_HOSTS and not any(host.endswith(w) for w in ALLOWED_WILDCARDS):
        body = (
            f"[Sandbox Firewall] Access to '{host}' is blocked.\n"
            f"This is not a rejection from the remote site — the sandbox proxy blocked the request.\n"
            f"To allow this host, add it to a rule file in my-rules/ and mount the directory:\n"
            f"  -v ./my-rules:/etc/mitmproxy/user-rules:ro\n"
            f"See my-rules/example.py for the format."
        )
        flow.response = http.Response.make(
            403,
            body.encode(),
            {"Content-Type": "text/plain"},
        )
        return

    handler = HOST_HANDLERS.get(host)
    if handler:
        handler(flow)