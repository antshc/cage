# 50-permissions.sh — Fix ownership of mounted directories for the ubuntu user
# Sourced by entrypoint.sh (inherits: UBUNTU_UID)
#
# Environment variables:
#   PUID  — UID to run as (default: 1000). If different, remaps the ubuntu user.
#   PGID  — GID to run as (default: 1000). If different, remaps the ubuntu group.
#   CHOWN_DIRS — Colon-separated list of additional directories to chown for ubuntu.
#                Example: CHOWN_DIRS=/var/log/ralph:/opt/app/data

# --- Remap ubuntu UID/GID if PUID/PGID differ from defaults ---
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

if [ "$PGID" -ne 1000 ]; then
  groupmod -g "$PGID" ubuntu 2>/dev/null || true
fi
if [ "$PUID" -ne 1000 ]; then
  usermod -u "$PUID" -g "$PGID" ubuntu 2>/dev/null || true
fi

# Update UBUNTU_UID to reflect the (possibly remapped) value
UBUNTU_UID="$PUID"

# --- Chown well-known writable paths ---
# These are directories that the ubuntu user needs write access to at runtime.
# Silently skip read-only mounts or missing paths.
_WRITABLE_PATHS=(
  /tmp
  /var/log
  /home/ubuntu/workspace
  /home/ubuntu/workspace.worktrees
  /home/ubuntu/.copilot
  /home/ubuntu/.venvs
  /home/ubuntu/.local
)

for _path in "${_WRITABLE_PATHS[@]}"; do
  [ -d "$_path" ] && chown -R "$PUID:$PGID" "$_path" 2>/dev/null || true
done

# --- Chown additional directories from CHOWN_DIRS env var ---
if [ -n "${CHOWN_DIRS:-}" ]; then
  IFS=':' read -ra _EXTRA_DIRS <<< "$CHOWN_DIRS"
  for _dir in "${_EXTRA_DIRS[@]}"; do
    _dir="${_dir// /}"
    [ -z "$_dir" ] && continue
    [ -d "$_dir" ] && chown -R "$PUID:$PGID" "$_dir" 2>/dev/null || true
  done
fi

# --- Fix Docker socket access (idempotent; no-op when socket is absent) ---
if [ -S /var/run/docker.sock ]; then
  chgrp ubuntu /var/run/docker.sock 2>/dev/null || chmod 666 /var/run/docker.sock
fi
