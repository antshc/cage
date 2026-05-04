# sandbox

A sandboxed container environment for the Copilot agent. All outbound traffic is routed through a mitmproxy firewall (`firewall.py`) running on `127.0.0.1:18080`.

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
| `pki.py` | `ocsp.digicert.com`, `crl3.digicert.com`, `crl4.digicert.com`, `*.digicert.com`, `s.symcb.com`, `ts-crl.ws.symantec.com` |

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


