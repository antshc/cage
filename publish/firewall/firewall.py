import importlib.util
import os

from mitmproxy import http


ALLOWED_HOSTS: set[str] = set()
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

    if host not in ALLOWED_HOSTS:
        flow.response = http.Response.make(
            403,
            f"Blocked host: {host}".encode(),
            {"Content-Type": "text/plain"},
        )
        return

    handler = HOST_HANDLERS.get(host)
    if handler:
        handler(flow)