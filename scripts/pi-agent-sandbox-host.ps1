# Pi Agent Sandbox Harness — PowerShell
# Run from any directory; mounts CWD as Pi's workspace.
#
# Usage:
#   pi-agent-sandbox-host.ps1             # locked-down (no Docker)
#   pi-agent-sandbox-host.ps1 --docker    # with Docker-in-Docker support (host socket)
#   pi-agent-sandbox-host.ps1 --rebuild   # force a fresh image build (--no-cache)
#
# GitHub PAT for the github MCP server:
#   pi-agent-sandbox-host.ps1 --gh-mcp-token <PAT>

# Script runs from /scripts folder inside the Pragmatic.AgentSandbox repo.
# Dockerfile/compose in parent directory.
$RepoRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path

# Parse arguments
$EnableDocker = $false
$ForceRebuild = $false
$GithubToken = $null
if ($args -contains "--docker") {
    $EnableDocker = $true
}
if ($args -contains "--rebuild") {
    $ForceRebuild = $true
}
for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        "--gh-mcp-token" {
            if ($i + 1 -ge $args.Count) { Write-Error "--gh-mcp-token requires a value"; exit 1 }
            $GithubToken = $args[$i + 1]
            $i++
        }
    }
}

# Select mode and image name (single Dockerfile, INSTALL_DOCKER build arg)
if ($EnableDocker) {
    $ImageName = "pi-agent-sandbox-host-dind"
    $InstallDocker = "true"
    Write-Host "[pi-agent] Docker-in-Docker enabled (host socket)"
} else {
    $ImageName = "pi-agent-sandbox-host"
    $InstallDocker = "false"
    Write-Host "[pi-agent] Locked-down mode (no Docker)"
}

# Rebuild only when --rebuild was passed or the image doesn't exist yet.
$ImageExists = docker image inspect --format '{{.Created}}' $ImageName 2>$null
if (-not $ImageExists -or $ForceRebuild) {
    Write-Host "[pi-agent] Building image"
    docker build --no-cache -f "$RepoRoot/Dockerfile" --build-arg "INSTALL_DOCKER=$InstallDocker" -t $ImageName "$RepoRoot"
}

# Run Pi
$LaunchDir = Split-Path $PWD -Leaf

# Build common arguments
# // prefix on container paths disables Docker Desktop's Windows path conversion
# (needed after Windows updates that changed WSL2 path handling)
$DockerArgs = @(
    "--rm",
    "-w", "//home/appuser/mount/${LaunchDir}",
    "-v", "${PWD}://home/appuser/mount/${LaunchDir}:rw",
    "-v", "pi_cache://home/appuser/.pi/cache:rw",
    "-v", "pi_agent://home/appuser/.pi/agent:rw",
    "-v", "npm_cache://home/appuser/.npm:rw",
    "-v", "nuget_cache://home/appuser/.nuget:rw",
    "-e", "HOME=/home/appuser",
    "-e", "NODE_ENV=development",
    "--memory=8g",
    "--cpus=4.0",
    "-it"
)

if (-not $EnableDocker) {
    # Apply security restrictions for locked-down mode
    $DockerArgs += "--cap-drop=ALL"
    $DockerArgs += "--security-opt=no-new-privileges:true"
} else {
    # Mount Docker socket for DinD support
    $DockerArgs += "-v"
    $DockerArgs += "//var/run/docker.sock://var/run/docker.sock:rw"
    $DockerArgs += "-e"
    $DockerArgs += "PI_DOCKER_MODE=true"
}

if ($GithubToken) {
    # GitHub PAT for the github MCP server (mcp.json references ${GITHUB_TOKEN}).
    $DockerArgs += "-e"
    $DockerArgs += "GITHUB_TOKEN=$GithubToken"
    Write-Host "[pi-agent] GitHub PAT supplied - github MCP server enabled"
} else {
    Write-Host "[pi-agent] No GitHub PAT (--gh-mcp-token) - github MCP server will be inactive"
}

$DockerArgs += $ImageName

docker run $DockerArgs
