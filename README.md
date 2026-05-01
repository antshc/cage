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
  -v "$(pwd)/logs/copilot:/var/log/copilot" \
  -v "$(pwd)/hello:/home/ubuntu/workspace" \ inside the container with the mitmproxy firewall active.

### Run a specific command

```bash
docker run --rm \
  -e COPILOT_GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" \
  -v "$(pwd)/config:/etc/mitmproxy:ro" \
  -v "$(pwd)/logs:/var/log/mitmproxy" \
  -v "$(pwd)/logs/copilot:/var/log/copilot" \
  -v "$(pwd)/hello:/home/ubuntu/workspace" \
```

## Running prompts with `cop`

The default container command is `cop`, a wrapper around the Copilot CLI. Pass a prompt as arguments:

```bash
# Using docker compose
docker compose run --rm sandbox cop "explain this codebase"

# Using docker run
docker run --rm \
  -e COPILOT_GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" \
  -v "$(pwd)/config:/etc/mitmproxy/config:ro" \
  -v "$(pwd)/logs:/var/log/mitmproxy" \
  -v "$(pwd)/logs/copilot:/var/log/copilot" \
  -v "$(pwd)/hello:/home/ubuntu/workspace" \
  --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID --cap-drop ALL \
  sandbox cop "refactor this function to be async"
```

### Overriding defaults

All Copilot CLI flags are configurable via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `COPILOT_MODEL` | `claude-sonnet-4.6` | Model to use (`claude-sonnet-4.6`, `claude-opus-4`, `claude-haiku-4`) |
| `COPILOT_EFFORT` | *(unset)* | Effort level (`low`, `medium`, `high`). Omitted when unset — not supported by all models (e.g. haiku). |
| `COPILOT_OUTPUT_FORMAT` | `json` | Output format (`json`, `text`, `stream-json`) |
| `COPILOT_ALLOW_ALL_TOOLS` | `true` | Pass `--allow-all-tools` when `true` |
| `COPILOT_NO_ASK_USER` | `true` | Pass `--no-ask-user` when `true` |
| `COPILOT_LOG_LEVEL` | `debug` | Log verbosity |
| `COPILOT_LOG_DIR` | `/var/log/copilot` | Directory for Copilot logs (mount `./logs/copilot`) |

```bash
# Set effort explicitly (omitted by default — not all models support it)
COPILOT_MODEL=claude-opus-4 COPILOT_EFFORT=high \
  docker compose run --rm sandbox cop "deep analysis of the auth module"

# Use haiku for fast, lightweight tasks
COPILOT_MODEL=claude-haiku-4 \
  docker compose run --rm sandbox cop "summarize this file"
```

## Volume mounts

| Host path | Container path | Purpose |
|-----------|---------------|---------|
| `./firewall` | `/etc/mitmproxy/config` (read-only) | Firewall rules |
| `./logs/mitmproxy` | `/var/log/mitmproxy` | Mitmproxy logs (timestamped) |
| `./logs/copilot` | `/var/log/copilot` | Copilot CLI logs |
| `./workspace` | `/home/ubuntu/workspace` | Project workspace |
| `./setup.sh` *(optional)* | `/etc/sandbox/setup.sh` (read-only) | Startup script (see below) |

## Startup script (optional)

You can mount an optional shell script at `/etc/sandbox/setup.sh` to run custom setup steps at container startup. The script:

- Runs as the `ubuntu` user after mitmproxy and iptables are configured (network access through the proxy is available).
- Runs before the main container command.
- If absent, startup continues with no warning or error.
- If it exits non-zero, the container aborts with the same exit code.
- Is mounted `:ro` so the agent cannot modify it at runtime.

### Available environment variables

| Variable | Description |
|----------|-------------|
| `COPILOT_GITHUB_TOKEN` | GitHub token for Copilot |
| `GH_TOKEN` | GitHub token for gh CLI (same value) |
| `HTTP_PROXY` | `http://127.0.0.1:8080` |
| `HTTPS_PROXY` | `http://127.0.0.1:8080` |
| `NODE_EXTRA_CA_CERTS` | Path to mitmproxy CA cert (trusted by Node.js) |

### Enabling the setup script

Uncomment the volume entry in `docker-compose.yml`:

```yaml
volumes:
  - ./setup.sh:/etc/sandbox/setup.sh:ro
```

Or pass it directly to `docker run`:

```bash
docker run --rm \
  -e COPILOT_GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" \
  -v "$(pwd)/setup.sh:/etc/sandbox/setup.sh:ro" \
  sandbox
```

An example [`setup.sh`](setup.sh) is included in this repo showing how to install gh CLI extensions and npm packages.

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

Rules live in `firewall/rules/`. Each file defines an `ENVIRONMENT` dict with allowed hosts and optionally a `check_request(flow)` function for custom validation.

### 1. Create a new rule file

```python
# firewall/rules/myservice.py
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

### 3. Register it in `firewall/rules/__init__.py`

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
  -v "$(pwd)/firewall:/etc/mitmproxy/config:ro" \
  sandbox
```


