# sandbox

A sandboxed container environment with .NET 8, Node.js 22, and Python 3. All outbound traffic is routed through a mitmproxy firewall (`azure_firewall.py`) running on `127.0.0.1:8080`.

## Build

```bash
docker build -t sandbox .
```

## Run

```bash
docker run --rm -it -v "$(pwd)/config":/etc/mitmproxy sandbox
```

This starts an interactive bash shell inside the container with the mitmproxy firewall active.

### Mount a local workspace

```bash
docker run --rm -it -v "$(pwd)/config":/etc/mitmproxy -v "$(pwd)":/workspace sandbox
```

### Run a specific command

```bash
docker run --rm -v "$(pwd)/config":/etc/mitmproxy sandbox node --version
```

## Environment setup

Add your GitHub Copilot token to `~/.profile` so it's available in every session:

```bash
echo 'export COPILOT_GITHUB_TOKEN=<your-token>' >> ~/.profile
```

Then reload the profile or start a new shell:

```bash
source ~/.profile
```

Pass the token into the container at runtime:

```bash
docker run --rm -it -e COPILOT_GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" sandbox
```

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

### 2. Register it in `config/rules/__init__.py`

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
docker run --rm -e FIREWALL_ENVS=copilot,github,myservice -v "$(pwd)/config":/etc/mitmproxy sandbox
```