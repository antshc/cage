# Copilot Sandbox — Quickstart

A sandboxed Docker container for the Copilot agent. All outbound traffic is forced through a mitmproxy firewall — only Copilot, GitHub, npm, and NuGet endpoints are permitted by default.

## Prerequisites

- Docker with Compose v2
- A GitHub token with Copilot access

## 1. Set your token

The container supports three authentication methods — use whichever fits your setup:

| Method | How | Used by |
|--------|-----|---------|
| Mount `~/.config/gh` | `-v ~/.config/gh:/home/ubuntu/.config/gh:ro` in `docker-compose.yml` | `gh` CLI **and** Copilot CLI — if mounted, `COPILOT_GITHUB_TOKEN` is not required |
| `GH_TOKEN` env var | Set in shell or `docker-compose.yml` | `gh` CLI — alternative when you can't mount the config dir |
| `COPILOT_GITHUB_TOKEN` env var | Set in shell or `docker-compose.yml` | Copilot CLI — required only when `~/.config/gh` is not mounted |

Copilot CLI reads credentials from `~/.config/gh` when present (same source as `gh auth login`). The container will fail to start if neither `~/.config/gh` nor `COPILOT_GITHUB_TOKEN` is provided.

```bash
# Option A: token only
export COPILOT_GITHUB_TOKEN=<your-github-token>

# Option B: gh config mount (no token needed — configure docker-compose.yml)
# - ~/.config/gh:/home/ubuntu/.config/gh:ro
```

## 2. Mount your workspace

Edit `docker-compose.yml` and uncomment the workspace volume, pointing it to your project:

```yaml
volumes:
  # ...
  - /absolute/path/to/your/project:/home/ubuntu/workspace
```

## 3. Register a shell alias

```bash
# ~/.bashrc or ~/.zshrc
export COPILOT_GITHUB_TOKEN=<your-github-token>

alias ralph='COPILOT_GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" WORKSPACE="$(pwd)" docker compose -f ~/.ralph/docker-compose.yml run --rm --service-ports sandbox'
alias ralphb='COPILOT_GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" WORKSPACE="$(pwd)" docker compose -f ~/.ralph/docker-compose.yml -f ~/.ralph/docker-compose.bash.yml run --rm --service-ports sandbox'
```

All Copilot CLI flags are configurable via environment variables — set them in your shell or add them to `docker-compose.yml` under `environment:`.

| Variable | Default | Description |
|----------|---------|-------------|
| `COPILOT_GITHUB_TOKEN` | *(required if `~/.config/gh` not mounted)* | GitHub token for Copilot CLI |
| `GH_TOKEN` | *(unset)* | Token for `gh` CLI — alternative to mounting `~/.config/gh` |
| `COPILOT_MODEL` | `claude-sonnet-4.6` | Model: `claude-haiku-4.5`, `claude-sonnet-4.6`, `claude-opus-4` |
| `COPILOT_EFFORT` | *(unset)* | Effort level: `low`, `medium`, `high`. Omitted when unset — not all models support it. |
| `COPILOT_OUTPUT_FORMAT` | `json` | Output format: `text`, `json`, `stream-json` |
| `COPILOT_ADD_DIRS` | *(unset)* | Comma-separated extra dirs to add to the agent's file-access scope and `trustedFolders`. **Extends** the defaults (`~/workspace`, `~/workspace.worktrees`, `~/.copilot`) — does not replace them. |
| `COPILOT_LOG_LEVEL` | `info` | Log verbosity: `none`, `error`, `warning`, `info`, `debug`, `all` |
| `COPILOT_LOG_DIR` | `/var/log/copilot` | Directory for Copilot logs |
| `SANDBOX_TAG` | `latest` | Docker Hub image tag to pull |
| `HOST_DOCKER_DNAT_PORTS` | *(unset)* | Comma-separated ports/ranges forwarded from `127.0.0.1` to `host.docker.internal`. E.g. `8000` (DynamoDB), `8000,5432,6379`, `9200-9300` (range). Requires `net.ipv4.conf.all.route_localnet=1` (already set in docker-compose). |

## Logs

Proxy and Copilot CLI logs are written to `./logs/` on the host:

| Path | Contents |
|------|---------|
| `./logs/mitmproxy/` | Network proxy logs (timestamped) |
| `./logs/copilot/` | Copilot CLI session logs |

## Volume mounts

| Host path | Container path | Purpose |
|-----------|---------------|---------|
| `./logs/mitmproxy` | `/var/log/mitmproxy` | Proxy traffic logs written by mitmproxy (one file per session, timestamped) |
| `./logs/copilot` | `/var/log/copilot` | Copilot CLI session logs for debugging and audit |
| `./workspace` | `/home/ubuntu/workspace` | Project files — the working directory inside the container |
| `~/.gitconfig` | `/home/ubuntu/.gitconfig` (read-only) | Host global git identity used as fallback when the repo has no local user config |
| `~/.config/gh` | `/home/ubuntu/.config/gh` (read-only) | GitHub CLI auth tokens — required for `gh` commands inside the container |
| `./rules` *(optional)* | `/etc/mitmproxy/user-rules` (read-only) | Extra `.py` firewall rules that extend the built-in allowlist |
| `./certs` *(optional)* | `/etc/sandbox/certs` (read-only) | `.crt`/`.pem` files trusted at startup for private registries or internal CAs |
| `./setup.sh` *(optional)* | `/etc/sandbox/setup.sh` (read-only) | Shell script run as `ubuntu` after the proxy starts, before the main command |

## Git identity

Git resolves identity natively in priority order:
1. **Workspace `.git/config`** — repo-local `user.name`/`user.email` (set with `git config user.name` / `git config user.email`, without `--global`) — always wins
2. **Mounted `~/.gitconfig`** — host global git config, used as a fallback when the repo has no local user config

## GitHub CLI auth

Mount your host `~/.config/gh` so `gh` commands work inside the container:

```yaml
- ~/.config/gh:/home/ubuntu/.config/gh:ro
```

Alternatively, set `GH_TOKEN` in your shell or `docker-compose.yml` instead of mounting the config directory.

## Optional startup script

Create a `setup.sh` and mount it by uncommenting the line in `docker-compose.yml`:

```yaml
- ./setup.sh:/etc/sandbox/setup.sh:ro
```

The script runs as the `ubuntu` user after the proxy is ready, before your command. If it exits non-zero the container aborts.

Available env vars in the script: `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `HTTP_PROXY`, `HTTPS_PROXY`, `NODE_EXTRA_CA_CERTS`.

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

To allow additional hosts, add `.py` rule files to `rules/` — they extend the defaults without replacing them. See `rules/example.py` for the full convention.
