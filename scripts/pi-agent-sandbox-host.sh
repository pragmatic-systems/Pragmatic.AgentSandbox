#!/usr/bin/env bash
# Pi Agent Sandbox Harness — Bash
# Run from any directory; mounts CWD as Pi's workspace.
#
# Usage:
#   pi-agent-sandbox-host             # locked-down (no Docker)
#   pi-agent-sandbox-host --docker     # with Docker-in-Docker support (host socket)

set -euo pipefail

# Resolve repo root (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse arguments
ENABLE_DOCKER=false
for arg in "$@"; do
  case "$arg" in
    --docker) ENABLE_DOCKER=true ;;
  esac
done

# Select mode and image tag (single Dockerfile, INSTALL_DOCKER build arg)
if [ "$ENABLE_DOCKER" = true ]; then
  IMAGE_NAME="pi-agent-sandbox-host-dind"
  INSTALL_DOCKER=true
  echo "[pi-agent] Docker-in-Docker enabled (host socket)"
else
  IMAGE_NAME="pi-agent-sandbox-host"
  INSTALL_DOCKER=false
  echo "[pi-agent] Locked-down mode (no Docker)"
fi

# Disable MSYS path conversion so Docker receives raw Unix paths
# (Git Bash auto-converts /... paths to C:/... which breaks WSL Docker daemons)
export MSYS_NO_PATHCONV=1

# Build image (no-op if already built)
docker build -f "$REPO_ROOT/Dockerfile" --build-arg INSTALL_DOCKER="$INSTALL_DOCKER" -t "$IMAGE_NAME" "$REPO_ROOT"

# Run Pi
LAUNCH_DIR="$(basename "$(pwd)")"

# Build common arguments
DOCKER_ARGS=(
  --rm
  -w "/home/appuser/mount/${LAUNCH_DIR}"
  -v "$(pwd):/home/appuser/mount/${LAUNCH_DIR}:rw"
  -v pi_cache:/home/appuser/.pi/cache:rw
  -v pi_agent:/home/appuser/.pi/agent:rw
  -v npm_cache:/home/appuser/.npm:rw
  -v nuget_cache:/home/appuser/.nuget:rw
  -e HOME=/home/appuser
  -e NODE_ENV=development
  --memory=8g
  --cpus=4.0
  -it
)

# Apply security restrictions for locked-down mode
if [ "$ENABLE_DOCKER" = false ]; then
  DOCKER_ARGS+=(
    --cap-drop=ALL
    --security-opt=no-new-privileges:true
  )
else
  # Mount Docker socket for Docker support
  DOCKER_ARGS+=(
    -v "/var/run/docker.sock:/var/run/docker.sock:rw"
    -e "PI_DOCKER_MODE=true"
  )
fi

DOCKER_ARGS+=("$IMAGE_NAME")

docker run "${DOCKER_ARGS[@]}"
