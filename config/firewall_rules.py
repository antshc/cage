import os
import sys
from importlib import import_module

from mitmproxy import http

# Add config dir to path so rules package is importable
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from rules import ENVIRONMENTS


# --- Build active ruleset from enabled environments ---

def _load_active_environments():
    envs_str = os.environ.get("FIREWALL_ENVS", ",".join(ENVIRONMENTS.keys()))
    return [e.strip() for e in envs_str.split(",") if e.strip()]


ACTIVE_ENVS = _load_active_environments()

ALLOWED_HOSTS: set[str] = set()
HOST_HANDLERS: dict[str, callable] = {}

for env_name in ACTIVE_ENVS:
    env = ENVIRONMENTS.get(env_name)
    if not env:
        continue
    ALLOWED_HOSTS.update(env.get("hosts", set()))

    # If the rule module defines check_request, register it for its hosts
    module = import_module(f"rules.{env_name}")
    if hasattr(module, "check_request"):
        for host in env.get("hosts", set()):
            HOST_HANDLERS[host] = module.check_request


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