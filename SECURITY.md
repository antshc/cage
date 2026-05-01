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
| ☐ | 🟡 Medium | Docker socket | If host Docker socket is mounted, agent gets full host access | Never mount `/var/run/docker.sock` |
| ☐ | 🟡 Medium | Environment variables | Secrets passed via env vars are readable by the agent | Minimize env vars, use mounted secrets files |
| ☑ | 🟡 Medium | Linux capabilities | Container runs with default capabilities | `cap_drop: ALL` + only `cap_add: NET_ADMIN` (for iptables) |
| ☑ | 🟡 Medium | Read-only config | Firewall config mounted as `:ro` | Done |
| ☑ | 🟡 Medium | Folder permissions | Sensitive directories locked down at build time | `/home/ubuntu` owned `root:root`; workspace `ubuntu:ubuntu 755`; `.copilot` `ubuntu:ubuntu 755`; `.cache/copilot` `ubuntu:ubuntu 755` (pre-created so Copilot CLI can extract its bundled package); `.mitmproxy` `root:root 750`; mitmproxy CA key `root 600`; CA cert `root 644`; `/etc/mitmproxy` `a+rx` (read/execute, no write for ubuntu) |
