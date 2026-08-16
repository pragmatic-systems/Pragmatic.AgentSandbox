#!/usr/bin/env bash
# Seed .pi/agent with baked-in config, then launch Pi.
#
# The pi_agent volume is mounted over /home/appuser/.pi/agent, which shadows
# anything COPY'd there during the build. This entrypoint copies the baked-in
# files (stored under /opt/pi-agent/) into the live directory, but treats them
# differently:
#
#   - Repo-owned config (models.json, docker-mode-indicator.ts) is synced from
#     the image on every run when it differs, so config updates after a rebuild
#     are always picked up.
#   - User/Pi-owned files (settings.json) are created only on first run and
#     never overwritten, so Pi's own state (e.g. lastChangelogVersion) and any
#     user customization (theme, default model, extensions) survive restarts.
#
# Sessions, auth, and other agent data are never touched.

set -euo pipefail

AGENT_DIR="$HOME/.pi/agent"
SEED_DIR="/opt/pi-agent"

# Ensure the target directory exists (volume may be freshly created)
mkdir -p "$AGENT_DIR/extensions"

# Copy only if the destination doesn't exist (for user/Pi-owned files).
seed_if_missing() {
  local src="$1" dest="$2"
  if [ -e "$src" ] && [ ! -e "$dest" ]; then
    cp "$src" "$dest"
  fi
}

# Copy if the destination is missing or its content differs (for repo-owned files).
seed_if_changed() {
  local src="$1" dest="$2"
  if [ -e "$src" ] && { [ ! -e "$dest" ] || ! cmp -s "$src" "$dest"; }; then
    cp "$src" "$dest"
  fi
}

# Repo-owned: always sync from the image so rebuilds take effect.
seed_if_changed "$SEED_DIR/models.json" "$AGENT_DIR/models.json"
seed_if_changed "$SEED_DIR/docker-mode-indicator.ts" "$AGENT_DIR/docker-mode-indicator.ts"

# User/Pi-owned: seed on first run only, then leave untouched.
seed_if_missing "$SEED_DIR/settings.json" "$AGENT_DIR/settings.json"

# --- Cache age limits ---
# Prune both NuGet and npm caches for files not accessed in N days.
# Override via NUGET_CACHE_MAX_AGE_DAYS and NPM_CACHE_MAX_AGE_DAYS.
NUGET_CACHE_MAX_AGE_DAYS="${NUGET_CACHE_MAX_AGE_DAYS:-30}"
NPM_CACHE_MAX_AGE_DAYS="${NPM_CACHE_MAX_AGE_DAYS:-30}"

if [ -d "$HOME/.nuget/packages" ]; then
  count=$(find "$HOME/.nuget/packages" -type f -atime +"$NUGET_CACHE_MAX_AGE_DAYS" | wc -l)
  if [ "$count" -gt 0 ]; then
    echo "[cache] Pruning $count NuGet package files unused for ${NUGET_CACHE_MAX_AGE_DAYS} days"
    find "$HOME/.nuget/packages" -type f -atime +"$NUGET_CACHE_MAX_AGE_DAYS" -delete
    find "$HOME/.nuget/packages" -type d -empty -delete 2>/dev/null || true
  fi
fi

if [ -d "$HOME/.npm/_cacache" ]; then
  count=$(find "$HOME/.npm/_cacache" -type f -atime +"$NPM_CACHE_MAX_AGE_DAYS" | wc -l)
  if [ "$count" -gt 0 ]; then
    echo "[cache] Pruning $count npm cache files unused for ${NPM_CACHE_MAX_AGE_DAYS} days"
    find "$HOME/.npm/_cacache" -type f -atime +"$NPM_CACHE_MAX_AGE_DAYS" -delete
  fi
fi

# Hand off to Pi
exec pi
