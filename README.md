# sandbox

A sandboxed container environment for the Copilot agent. All outbound traffic is routed through a mitmproxy firewall (`firewall.py`) running on `127.0.0.1:8080`.

## Installed packages

| Category | Packages |
|----------|----------|
| Base image | .NET SDK 8.0 |
| Runtimes | Node.js 22, Python 3 |
| CLI tools | git, gh (GitHub CLI), curl, wget, jq, unzip, openssh-client |
| Security | ca-certificates, gnupg, iptables, gosu |
| Proxy | mitmproxy (mitmdump) |
| Copilot | @github/copilot (npm global) |

## Build

```bash
docker build -t sandbox .
```

## Run

```bash
docker run --rm -it \
  -e COPILOT_GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" \
  -v "$(pwd)/config:/etc/mitmproxy:ro" \
  -v "$(pwd)/logs:/var/log/mitmproxy" \
  -v "$(pwd)/hello:/home/ubuntu/workspace" \ inside the container with the mitmproxy firewall active.

### Run a specific command

```bash
docker run --rm \
  -e COPILOT_GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" \
  -v "$(pwd)/config:/etc/mitmproxy:ro" \
  -v "$(pwd)/logs:/var/log/mitmproxy" \
  -v "$(pwd)/hello:/home/ubuntu/workspace" \
```

## Volume mounts

| Host path | Container path | Purpose |
|-----------|---------------|---------|
| `./config` | `/etc/mitmproxy` (read-only) | Firewall rules + entrypoint |
| `./logs` | `/var/log/mitmproxy` | Mitmproxy logs (timestamped) |
| `./hello` (or project) | `/home/ubuntu/workspace` | Project workspace |

## Environment setup

The entrypoint requires `COPILOT_GITHUB_TOKEN` to be set. Pass it at runtime:

```bash
docker run --rm -it -e COPILOT_GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" \
  -v "$(pwd)/config:/etc/mitmproxy:ro" \
  -v "$(pwd)/logs:/var/log/mitmproxy" \
  sandbox
```

## Agent user

The container starts as root to apply iptables network rules, then drops to user `ubuntu` (UID 1000) via `gosu`. mitmproxy runs as a dedicated `_mitmproxy` user. No sudo access is granted to `ubuntu`.

## Security hardening

See [SECURITY.md](SECURITY.md).

## Adding firewall rules

Rules live in `config/rules/`. Each file defines an `ENVIRONMENT` dict with allowed hosts and optionally a `check_request(flow)` function for custom validation.

### 1. Create a new rule file

```python
# config/rules/myservice.py
from mitmproxy import http

ENVIRONMENT = {
    "hosts": {
        "api.myservice.com",
        "cdn.myservice.com",
    },
}

# Optional: add custom request validation
def check_request(flow: http.HTTPFlow) -> None:
    if "/admin" in flow.request.path:
        flow.response = http.Response.make(
            403, b"Blocked admin path", {"Content-Type": "text/plain"}
        )
```

### 2. Adding URL path restrictions

Use `check_request(flow)` to enforce fine-grained path-based rules. The function receives the full `mitmproxy.http.HTTPFlow` object — inspect `flow.request.path`, `flow.request.method`, headers, etc.

**Block specific paths:**

```python
def check_request(flow: http.HTTPFlow) -> None:
    blocked_paths = ["/admin", "/internal", "/.env"]
    if any(p in flow.request.path for p in blocked_paths):
        flow.response = http.Response.make(
            403, b"Blocked path", {"Content-Type": "text/plain"}
        )
```

**Allow only matching path patterns (regex):**

```python
import re
from mitmproxy import http

ALLOWED_PATH = re.compile(r"^/api/v[0-9]+/")

ENVIRONMENT = {
    "hosts": {"api.example.com"},
}

def check_request(flow: http.HTTPFlow) -> None:
    if not ALLOWED_PATH.match(flow.request.path):
        flow.response = http.Response.make(
            403, b"Path not allowed", {"Content-Type": "text/plain"}
        )
```

**Restrict by method + path:**

```python
def check_request(flow: http.HTTPFlow) -> None:
    if flow.request.method not in ("GET", "HEAD"):
        flow.response = http.Response.make(
            403, b"Only read operations allowed", {"Content-Type": "text/plain"}
        )
```

**Scope to specific resource identifiers (e.g. subscriptions, projects):**

```python
import re
from mitmproxy import http

PATH_RE = re.compile(r"^/subscriptions/([^/]+)/resourceGroups/([^/?#]+)")

ENVIRONMENT = {
    "hosts": {"management.azure.com"},
    "subscriptions": {"00000000-0000-0000-0000-000000000000"},
    "resource_groups": {"rg-dev-sandbox", "rg-ci-tests"},
}

def check_request(flow: http.HTTPFlow) -> None:
    match = PATH_RE.match(flow.request.path)
    if not match:
        flow.response = http.Response.make(403, b"Blocked path", {"Content-Type": "text/plain"})
        return
    if match.group(1).lower() not in ENVIRONMENT["subscriptions"]:
        flow.response = http.Response.make(403, b"Blocked subscription", {"Content-Type": "text/plain"})
        return
    if match.group(2) not in ENVIRONMENT["resource_groups"]:
        flow.response = http.Response.make(403, b"Blocked resource group", {"Content-Type": "text/plain"})
```

### 3. Register it in `config/rules/__init__.py`

```python
from .myservice import ENVIRONMENT as MYSERVICE

ENVIRONMENTS = {
    # ... existing entries ...
    "myservice": MYSERVICE,
}
```

### 3. Enable it

All registered environments are active by default. To enable only specific ones, set `FIREWALL_ENVS`:

```bash
docker run --rm -e FIREWALL_ENVS=copilot,github,myservice \
  -v "$(pwd)/config:/etc/mitmproxy:ro" \
  sandbox
```


