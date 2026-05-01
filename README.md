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
docker compose build
```

## Run

```bash
export COPILOT_GITHUB_TOKEN=<your-github-token>
docker compose run --rm sandbox cop "hello world"
```

### Use the pre-built Hub image (skip build)

```bash
docker compose -f docker-compose.yml -f docker-compose.hub.yml run --rm sandbox cop "hello world"
```

### Distribute to end users

Give users the `runtime/` folder. It contains only what's needed to pull and run without building:

```bash
cd runtime
export COPILOT_GITHUB_TOKEN=<token>
docker compose run --rm sandbox cop "explain this codebase"
```

## Running prompts with `cop`

The default container command is `cop`, a wrapper around the Copilot CLI. Pass a prompt as arguments:

```bash
# docker compose
docker compose run --rm sandbox cop "explain this codebase"

# docker run (built locally)
docker run --rm \
  --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID --cap-drop ALL \
  -e COPILOT_GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" \
  -v "$(pwd)/logs/mitmproxy:/var/log/mitmproxy" \
  -v "$(pwd)/logs/copilot:/var/log/copilot" \
  -v "$(pwd)/workspace:/home/ubuntu/workspace" \
  sandbox cop "explain this codebase"

# docker run (Hub image)
docker run --rm \
  --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID --cap-drop ALL \
  -e COPILOT_GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" \
  -v "$(pwd)/logs/mitmproxy:/var/log/mitmproxy" \
  -v "$(pwd)/logs/copilot:/var/log/copilot" \
  -v "$(pwd)/workspace:/home/ubuntu/workspace" \
  khdevnet/sandbox cop "explain this codebase"
```

### Overriding defaults

All Copilot CLI flags are configurable via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `COPILOT_MODEL` | `claude-haiku-4.5` | Model to use (`claude-haiku-4.5`, `claude-sonnet-4.6`, `claude-opus-4`) |
| `COPILOT_EFFORT` | *(unset)* | Effort level (`low`, `medium`, `high`). Omitted when unset — not supported by all models (e.g. haiku). |
| `COPILOT_OUTPUT_FORMAT` | `text` | Output format (`text`, `json`, `stream-json`) |
| `COPILOT_ALLOW_ALL_TOOLS` | `true` | Pass `--allow-all-tools` when `true` |
| `COPILOT_NO_ASK_USER` | `true` | Pass `--no-ask-user` when `true` |
| `COPILOT_LOG_LEVEL` | `debug` | Log verbosity |
| `COPILOT_LOG_DIR` | `/var/log/copilot` | Directory for Copilot logs (mount `./logs/copilot`) |

```bash
# Set effort explicitly (omitted by default — not all models support it)
COPILOT_MODEL=claude-opus-4 COPILOT_EFFORT=high \
  docker compose run --rm sandbox cop "deep analysis of the auth module"

# Use sonnet for a balance of quality and speed
COPILOT_MODEL=claude-sonnet-4.6 \
  docker compose run --rm sandbox cop "refactor this module"
```

## Volume mounts

| Host path | Container path | Purpose |
|-----------|---------------|---------|
| `./logs/mitmproxy` | `/var/log/mitmproxy` | Mitmproxy logs (timestamped) |
| `./logs/copilot` | `/var/log/copilot` | Copilot CLI logs |
| `./workspace` | `/home/ubuntu/workspace` | Project workspace |
| `./my-rules` *(optional)* | `/etc/mitmproxy/user-rules` (read-only) | Extra firewall rules (extend defaults) |
| `./certs` *(optional)* | `/etc/sandbox/certs` (read-only) | CA certificates (see below) |
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
| `NODE_EXTRA_CA_CERTS` | Path to CA bundle trusted by Node.js (mitmproxy cert + any user certs) |

### Enabling the setup script

Uncomment the volume entry in `docker-compose.yml`:

```yaml
volumes:
  - ./setup.sh:/etc/sandbox/setup.sh:ro
```

Or pass it directly with `docker compose run` by adding the volume to `docker-compose.yml` and running:

```bash
docker compose run --rm sandbox
```

An example [`setup.sh`](setup.sh) is included in this repo showing how to install gh CLI extensions and npm packages.

## CA certificates (optional)

To trust a private registry or internal CA (e.g. a corporate NuGet feed, private npm registry, or self-signed HTTPS endpoint), mount a directory of `.crt` or `.pem` files:

```yaml
# docker-compose.yml
volumes:
  - ./certs:/etc/sandbox/certs:ro
```

At startup (as root, before the proxy starts) each certificate is:
- Installed into the system CA store via `update-ca-certificates` — trusted by dotnet, git, curl, gh CLI
- Appended to the Node CA bundle — trusted by node, npm, and the Copilot CLI

No image rebuild is needed. The mitmproxy CA cert is always included in the bundle.

## Agent user

The container starts as root to apply iptables network rules, then drops to user `ubuntu` (UID 1000) via `gosu`. mitmproxy runs as a dedicated `_mitmproxy` user. No sudo access is granted to `ubuntu`.

## Security hardening

See [SECURITY.md](SECURITY.md).

## Firewall rules

Default rules are baked into the image (`src/firewall/rules/`). Every `.py` file in that directory is active — delete a file and rebuild to disable it. Hosts allowed by default:

| File | Allowed hosts |
|------|---------------|
| `copilot.py` | `api.githubcopilot.com`, `api.business.githubcopilot.com`, `copilot-proxy.githubusercontent.com`, `telemetry.business.githubcopilot.com`, `default.exp-tas.com`, `api.github.com` |
| `github.py` | `github.com`, `api.github.com`, `objects.githubusercontent.com`, `raw.githubusercontent.com` |
| `npm.py` | `registry.npmjs.org` |
| `nuget.py` | `api.nuget.org`, `www.nuget.org` |

### Adding rules without rebuilding

Mount a directory of `.py` files at `/etc/mitmproxy/user-rules` — they are loaded on top of the defaults:

```yaml
volumes:
  - ./my-rules:/etc/mitmproxy/user-rules:ro
```

See `runtime/my-rules/example.py` for the full convention and an annotated template.

### Adding built-in rules (requires rebuild)

Create a new file in `src/firewall/rules/` and rebuild the image.

#### 1. Create a new rule file

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

#### 2. Adding URL path restrictions

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

#### 3. Rebuild

```bash
docker compose build
```


