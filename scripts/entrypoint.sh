#!/bin/sh
# Seed .pi/agent with baked-in config on first run, then launch Pi.
#
# The pi_agent volume is mounted over /home/appuser/.pi/agent, which shadows
# anything COPY'd there during the build. This entrypoint copies the baked-in
# files (stored under /opt/pi-agent/) into the live directory only if they
# don't already exist — so user changes are preserved across runs.

set -eu

AGENT_DIR="$HOME/.pi/agent"
SEED_DIR="/opt/pi-agent"


# Ensure the target directory exists (volume may be freshly created)
mkdir -p "$AGENT_DIR/extensions"

# Seed each baked-in file if not already present
seeded=0
for f in "$SEED_DIR"/*; do
  dest="$AGENT_DIR/$(basename "$f")"
  if [ ! -e "$dest" ]; then
    cp "$f" "$dest"
    echo "[entrypoint] Seeded $(basename "$f")"
    seeded=$((seeded + 1))
  fi
done

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
