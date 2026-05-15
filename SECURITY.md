# Security hardening

Known security gaps and their remediation status:

| Status | Severity | Risk | Issue | Fix |
|--------|----------|------|-------|-----|
| ☑ | 🔴 Critical | Sudo access | Agent had `NOPASSWD:ALL` sudo, could bypass container restrictions | Removed sudoers entry and sudo package |
| ☑ | 🔴 Critical | Proxy bypass | Agent can `unset HTTP_PROXY` or kill mitmproxy | iptables NAT REDIRECT forces all traffic through mitmproxy; mitmproxy runs as root (unkillable by ubuntu); entrypoint drops to ubuntu via gosu |
| ☑ | 🟠 High | Non-HTTP traffic | Raw TCP/UDP (SSH, DNS to external) isn't intercepted by mitmproxy | iptables OUTPUT DROP rule blocks all non-loopback traffic from ubuntu user |
| ☐ | 🟠 High | DNS exfiltration | DNS queries go directly to host resolver, bypassing proxy | Lock DNS to internal resolver only |
| ☑ | 🟠 High | Network allowlist | All HTTP/HTTPS traffic filtered through mitmproxy firewall rules | Done |
| ☑ | 🟠 High | Non-root user | Container runs as `ubuntu` (UID 1000), not root | Done |
| ☐ | 🟡 Medium | Host filesystem | Mounted volumes may be writable, agent can modify host files | Use `:ro` on all mounts except workspace |
| ☑ | 🟡 Medium | Docker socket | If host Docker socket is mounted, agent gets full host access | Opt-in only: mount `/var/run/docker.sock` by uncommenting the volume in `docker-compose.yml`. Risk accepted for trusted test environments; never enable for untrusted agent workloads |
| ☐ | 🟡 Medium | Environment variables | Secrets passed via env vars are readable by the agent | Minimize env vars, use mounted secrets files |
| ☑ | 🟡 Medium | Linux capabilities | Container runs with default capabilities | `cap_add: NET_ADMIN` only (for iptables); Docker's default caps (SETUID, SETGID, CHOWN, DAC_OVERRIDE) are sufficient for gosu and permission setup |
| ☑ | 🟡 Medium | Read-only config | Firewall config mounted as `:ro` | Done |
| ☑ | 🟡 Medium | Host service exposure via DNAT | `HOST_DOCKER_DNAT_PORTS` bypasses mitmproxy for the specified ports (non-HTTP TCP goes direct to `host.docker.internal`, not inspected by the firewall) | Opt-in only — unset by default; no DNAT rules are created unless the operator explicitly sets this variable; destination is `host.docker.internal` (RFC1918, already in the FILTER ACCEPT range) |
| ☑ | 🟡 Medium | Folder permissions | Sensitive directories locked down at build time | `/home/ubuntu` owned `root:root 755` (traversable by ubuntu, not writable); workspace `ubuntu:ubuntu 755`; `.copilot` `ubuntu:ubuntu 755`; `.cache/copilot` `ubuntu:ubuntu 755` (pre-created so Copilot CLI can extract its bundled package); `.mitmproxy` `root:root 750`; mitmproxy CA key `root 600`; CA cert `root 644`; `/etc/mitmproxy` `a+rx` (read/execute, no write for ubuntu) |
| ☑ | 🟡 Medium | Destructive git operations | Agent could run `git reset`, `git rebase`, or `git clean` to destroy uncommitted work or rewrite history | `--deny-tool` blocks these three shell commands; list is configurable via `COPILOT_DENY_TOOLS` |
| ☑ | 🟡 Medium | Unbounded autopilot loop | Agent could loop indefinitely, causing runaway changes or resource exhaustion | `--max-autopilot-continues` caps the loop at 20 iterations (overridable via `COPILOT_MAX_AUTOPILOT_CONTINUES`) |
| ☑ | 🟡 Medium | Agent filesystem scope | Agent had no explicit directory scope, could traverse arbitrary paths | `--add-dir` restricts agent context to `~/workspace`, `~/workspace.worktrees`, and `~/.copilot` (overridable via `COPILOT_ADD_DIRS`) |
