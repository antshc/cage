# Copilot Sandbox — Quickstart

A sandboxed Docker container for the Copilot agent. All outbound traffic is forced through a mitmproxy firewall — only Copilot, GitHub, npm, and NuGet endpoints are permitted by default.

## Prerequisites

- Docker with Compose v2
- A GitHub token with Copilot access

## 1. Set your token

```bash
export COPILOT_GITHUB_TOKEN=<your-github-token>
```

## 2. Mount your workspace

Edit `docker-compose.yml` and uncomment the workspace volume, pointing it to your project:

```yaml
volumes:
  # ...
  - /absolute/path/to/your/project:/home/ubuntu/workspace
```

## 3. Run

```bash
# docker run (interactive REPL)
  docker run --rm -it \
    --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID --cap-drop ALL \
    -e COPILOT_GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" \
    # GitHub CLI (gh) auth: mount ~/.config/gh (preferred) OR set GH_TOKEN.
    # -v "$HOME/.config/gh:/home/ubuntu/.config/gh:ro" \
    # -e GH_TOKEN="$GH_TOKEN" \
    -v "/absolute/path/to/runtime/logs/mitmproxy:/var/log/mitmproxy" \
    -v "/absolute/path/to/runtime/logs/copilot:/var/log/copilot" \
    -v "$(pwd):/home/ubuntu/workspace" \
    # Optional: mount host git config for correct git identity inside the container.
    # -v "$HOME/.gitconfig:/home/ubuntu/.gitconfig:ro" \
    # Optional: expose host Docker socket for integration tests (grants full Docker/host access).
    # -v "/var/run/docker.sock:/var/run/docker.sock" \
    # Optional: forward localhost ports to host services (e.g. DynamoDB, Redis):
    # --sysctl net.ipv4.conf.all.route_localnet=1 \
    # --add-host host.docker.internal:host-gateway \
    # -e HOST_DOCKER_DNAT_PORTS=8000 \
    khdevnet/sandbox copiloty
```

> You can also pass a prompt directly: `docker run ... khdevnet/sandbox copiloty "explain this codebase"`

## 4. Register a shell alias (optional)

Add a shell function to your profile so `copiloty` mounts whichever directory you're currently in as the workspace:

```bash
# ~/.bashrc or ~/.zshrc
export COPILOT_GITHUB_TOKEN=<your-github-token>

copiloty() {
  docker run --rm -it \
    --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID --cap-drop ALL \
    # -p 2000-2020:2000-2020 \
    -e COPILOT_GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" \
    # GitHub CLI (gh) auth: mount ~/.config/gh (preferred) OR set GH_TOKEN.
    # -v "$HOME/.config/gh:/home/ubuntu/.config/gh:ro" \
    # -e GH_TOKEN="$GH_TOKEN" \
    -v "/absolute/path/to/runtime/logs/mitmproxy:/var/log/mitmproxy" \
    -v "/absolute/path/to/runtime/logs/copilot:/var/log/copilot" \
    -v "$(pwd):/home/ubuntu/workspace" \
    # Optional: mount host git config for correct git identity inside the container.
    # -v "$HOME/.gitconfig:/home/ubuntu/.gitconfig:ro" \
    # Optional: expose host Docker socket for integration tests (grants full Docker/host access).
    # -v "/var/run/docker.sock:/var/run/docker.sock" \
    # Optional: forward localhost ports to host services (e.g. DynamoDB, Redis):
    # --sysctl net.ipv4.conf.all.route_localnet=1 \
    # --add-host host.docker.internal:host-gateway \
    # -e HOST_DOCKER_DNAT_PORTS=8000-8100,9500-9600,2000,2001,10002 \
    khdevnet/sandbox copiloty
}
```

Reload your shell:

```bash
source ~/.bashrc   # or source ~/.zshrc
```

Then use it from any project directory:

```bash
cd /your/project

# Interactive REPL
copiloty

# With a prompt
copiloty "explain this codebase"
copiloty "fix the failing tests"
```



All Copilot CLI flags are configurable via environment variables — set them in your shell or add them to `docker-compose.yml` under `environment:`.

| Variable | Default | Description |
|----------|---------|-------------|
| `COPILOT_GITHUB_TOKEN` | *(required)* | GitHub token for Copilot CLI |
| `GH_TOKEN` | *(unset)* | Token for `gh` CLI — alternative to mounting `~/.config/gh` |
| `COPILOT_MODEL` | `claude-sonnet-4.6` | Model: `claude-haiku-4.5`, `claude-sonnet-4.6`, `claude-opus-4` |
| `COPILOT_EFFORT` | *(unset)* | Effort level: `low`, `medium`, `high`. Omitted when unset — not all models support it. |
| `COPILOT_OUTPUT_FORMAT` | `text` | Output format: `text`, `json`, `stream-json` |
| `COPILOT_LOG_LEVEL` | `info` | Log verbosity: `none`, `error`, `warning`, `info`, `debug`, `all` |
| `COPILOT_LOG_DIR` | `/var/log/copilot` | Directory for Copilot logs |
| `SANDBOX_TAG` | `latest` | Docker Hub image tag to pull |
| `HOST_DOCKER_DNAT_PORTS` | *(unset)* | Comma-separated ports/ranges forwarded from `127.0.0.1` to `host.docker.internal`. E.g. `8000` (DynamoDB), `8000,5432,6379`, `9200-9300` (range). Requires `net.ipv4.conf.all.route_localnet=1` (already set in docker-compose). |

```bash
# Use a more powerful model with high effort
COPILOT_MODEL=claude-sonnet-4.6 COPILOT_EFFORT=high \
  docker compose run --rm -it sandbox copiloty
```

## Logs

Proxy and Copilot CLI logs are written to `./logs/` on the host:

| Path | Contents |
|------|---------|
| `./logs/mitmproxy/` | Network proxy logs (timestamped) |
| `./logs/copilot/` | Copilot CLI session logs |

## Volume mounts

| Host path | Container path | Purpose |
|-----------|---------------|---------|
| `./logs/mitmproxy` | `/var/log/mitmproxy` | Mitmproxy logs (timestamped) |
| `./logs/copilot` | `/var/log/copilot` | Copilot CLI logs |
| `./workspace` | `/home/ubuntu/workspace` | Project workspace |
| `./my-rules` *(optional)* | `/etc/mitmproxy/user-rules` (read-only) | Extra firewall rules (extend defaults) |
| `./certs` *(optional)* | `/etc/sandbox/certs` (read-only) | CA certificates (see below) |
| `./setup.sh` *(optional)* | `/etc/sandbox/setup.sh` (read-only) | Startup script (see below) |
| `~/.gitconfig` *(optional)* | `/home/ubuntu/.gitconfig` (read-only) | Host git identity (see below) |
| `~/.config/gh` *(optional)* | `/home/ubuntu/.config/gh` (read-only) | GitHub CLI auth — required for `gh` commands inside the container |

## Git identity (optional)

Git resolves identity natively in priority order:
1. **Workspace `.git/config`** — repo-local `user.name`/`user.email` (set with `git config user.name` / `git config user.email`, without `--global`) — always wins
2. **Mounted `~/.gitconfig`** — host global git config, used as a fallback when the repo has no local user config

To mount your host git config, uncomment the line in `docker-compose.yml`:

```yaml
- ~/.gitconfig:/home/ubuntu/.gitconfig:ro
```

## Optional startup script

Create a `setup.sh` and mount it by uncommenting the line in `docker-compose.yml`:

```yaml
- ./setup.sh:/etc/sandbox/setup.sh:ro
```

The script runs as the `ubuntu` user after the proxy is ready, before your command. If it exits non-zero the container aborts.

Available env vars in the script: `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `HTTP_PROXY`, `HTTPS_PROXY`, `NODE_EXTRA_CA_CERTS`.

## CA certificates (optional)

To trust a private registry or internal CA, place `.crt` or `.pem` files in a `certs/` folder and uncomment the volume in `docker-compose.yml`:

```yaml
volumes:
  - ./certs:/etc/sandbox/certs:ro
```

At startup each certificate is installed into the system CA store (dotnet, git, curl, gh CLI) and appended to the Node CA bundle (node, npm, Copilot CLI).

## Extending the firewall

Default rules are baked into the image. Allowed hosts by default:

| Rule | Hosts |
|------|-------|
| azure | `login.microsoftonline.com`, `microsoftonline.com`, `management.azure.com` |
| copilot | `api.githubcopilot.com`, `api.business.githubcopilot.com`, `copilot-proxy.githubusercontent.com`, `telemetry.business.githubcopilot.com`, `default.exp-tas.com`, `api.github.com` |
| dotnet | `dot.net`, `dotnetcli.azureedge.net` |
| github | `github.com`, `api.github.com`, `objects.githubusercontent.com`, `raw.githubusercontent.com`, `release-assets.githubusercontent.com` |
| npm | `registry.npmjs.org` |
| nuget | `api.nuget.org`, `www.nuget.org` |
| pki | `ocsp.digicert.com`, `crl3.digicert.com`, `crl4.digicert.com`, `*.digicert.com`, `s.symcb.com`, `ts-crl.ws.symantec.com`, `www.microsoft.com` |

To allow additional hosts, add `.py` rule files to `my-rules/` — they extend the defaults without replacing them. See `my-rules/example.py` for the full convention.
