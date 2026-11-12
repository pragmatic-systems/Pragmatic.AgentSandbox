#!/usr/bin/env bash
# Seed .pi/agent with baked-in config, then launch Pi.
#
# The pi_agent volume is mounted over /home/appuser/.pi/agent, which shadows
# anything COPY'd there during the build. This entrypoint copies the baked-in
# files (stored under /opt/pi-agent/) into the live directory, but treats them
# differently:
#
#   - Repo-owned config (AGENTS.md, models.json, docker-mode-indicator.ts)
#     is synced from the image on every run when it differs, so config
#     updates after a rebuild are always picked up.
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
  if [[ -e "$src" ]] && [[ ! -e "$dest" ]]; then
    cp "$src" "$dest"
  fi
}

# Copy if the destination is missing or its content differs (for repo-owned files).
seed_if_changed() {
  local src="$1" dest="$2"
  if [[ -e "$src" ]] && { [[ ! -e "$dest" ]] || ! cmp -s "$src" "$dest"; }; then
    cp "$src" "$dest"
  fi
}

# Repo-owned: always sync from the image so rebuilds take effect.
seed_if_changed "$SEED_DIR/AGENTS.md" "$AGENT_DIR/AGENTS.md"
seed_if_changed "$SEED_DIR/models.json" "$AGENT_DIR/models.json"
seed_if_changed "$SEED_DIR/docker-mode-indicator.ts" "$AGENT_DIR/docker-mode-indicator.ts"

# User/Pi-owned: seed on first run only, then leave untouched.
seed_if_missing "$SEED_DIR/settings.json" "$AGENT_DIR/settings.json"

# --- Cache age limits ---
# Prune NuGet/npm caches for material not accessed in N days.
# Override via NUGET_CACHE_MAX_AGE_DAYS and NPM_CACHE_MAX_AGE_DAYS.
# NuGet pruning is at package-folder granularity (never per-file): a partial
# version folder is unusable (NU5037) and NuGet won't self-heal one, so a
# folder is kept whole or removed whole.
NUGET_CACHE_MAX_AGE_DAYS="${NUGET_CACHE_MAX_AGE_DAYS:-30}"
NPM_CACHE_MAX_AGE_DAYS="${NPM_CACHE_MAX_AGE_DAYS:-30}"

# If we have nuget packages
if [[ -d "$HOME/.nuget/packages" ]]; then

  # Packages pruned count
  pruned=0

  # Iterate package version folders: packages/<id>/<version>
  while IFS= read -r dir; do
    [[ -d "$dir" ]] || continue

    # Remove the folder if no file in it was accessed within N days. Any recently-used file keeps the package whole.
    if [[ -z "$(find "$dir" -type f -atime -"$NUGET_CACHE_MAX_AGE_DAYS" 2>/dev/null)" ]]; then
      rm -rf -- "$dir"
      pruned=$((pruned + 1))
    fi

    # Done when no package folders left to enumerate.
  done < <(find "$HOME/.nuget/packages" -mindepth 2 -maxdepth 2 -type d 2>/dev/null)

  # Print prune count if > 0
  if [[ "$pruned" -gt 0 ]]; then
    echo "[cache] Pruned $pruned stale NuGet package folder(s) (unused ${NUGET_CACHE_MAX_AGE_DAYS}+ days)"
  fi

  # Remove now-empty package id parent dirs.
  find "$HOME/.nuget/packages" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null || true
fi

# If we have an npm cache
if [[ -d "$HOME/.npm/_cacache" ]]; then

  # Count the files not accessed in N days
  count=$(find "$HOME/.npm/_cacache" -type f -atime +"$NPM_CACHE_MAX_AGE_DAYS" | wc -l)
  
  # If we find any, print count and delete npm cache
  if [[ "$count" -gt 0 ]]; then
    echo "[cache] Pruning $count npm cache files unused for ${NPM_CACHE_MAX_AGE_DAYS} days"
    find "$HOME/.npm/_cacache" -type f -atime +"$NPM_CACHE_MAX_AGE_DAYS" -delete
  fi
fi

# Hand off to Pi
exec pi
