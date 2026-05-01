# Copilot Instructions

## Project

Sandboxed container for Copilot agent. All outbound HTTP/HTTPS routed through mitmproxy firewall.

## Structure

- `Dockerfile` — Ubuntu 24.04, .NET 8, Node 22, mitmproxy, gh CLI
- `entrypoint.sh` — root entrypoint: starts mitmproxy (as root), sets iptables rules, drops to `ubuntu` via gosu
- `config/firewall.py` — mitmproxy addon, loads rules from `config/rules/`
- `config/rules/` — per-service allowlists (hosts + optional `check_request`)
- `docker-compose.yml` — build & run config
- `hello/` — test .NET app

## Build

```bash
docker compose build
```

## Test dotnet app

```bash
docker compose run --rm sandbox dotnet run
```

### Test Copilot connectivity

```bash
docker compose run --rm sandbox copilot -p "hello world"
```

Requires `COPILOT_GITHUB_TOKEN` env var set on the host (loaded via docker-compose).

## Security

Review `SECURITY.md` before making changes. Do not introduce:
- sudo or privilege escalation
- writable mounts for system directories (CA store, `/etc`)
- direct network access bypassing the proxy
- new capabilities or Docker socket mounts

## Key Conventions

- Container user: `ubuntu` (UID 1000), no sudo
- Entrypoint runs as root only for iptables + mitmproxy + gosu, then drops to `ubuntu`
- mitmproxy runs as root (exempt from iptables UID 1000 rules, unkillable by ubuntu)
- mitmproxy CA trusted at build time (no runtime privilege escalation)
- iptables NAT REDIRECT forces all HTTP/HTTPS from UID 1000 through proxy
- `cap_drop: ALL` + `cap_add: NET_ADMIN, SETUID, SETGID` in docker-compose
- Firewall rules: add file in `config/rules/`, register in `config/rules/__init__.py`
- Workspace bind-mounted at `/home/ubuntu/workspace`
- Logs volume at `/var/log/mitmproxy`

## Optional startup script

Mount `/etc/sandbox/setup.sh` (`:ro`) to run custom setup steps as `ubuntu` after the proxy is ready but before the main command. If absent, startup continues silently. If it exits non-zero, the container aborts. Available env vars: `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `HTTP_PROXY`, `HTTPS_PROXY`, `NODE_EXTRA_CA_CERTS`. See `setup.sh` in the repo for an example.
