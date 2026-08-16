# Pi Agent Sandbox Harness

A secure Docker container running the [Pi Coding Agent](https://pi.dev/) in a sandbox, with controlled filesystem access and LM Studio integration.

## Setup

Add the `scripts/` folder to your `%PATH%` (Windows) or `$PATH` (Linux/macOS):

### Windows (PowerShell)
```powershell
[Environment]::SetEnvironmentVariable("Path", "$env:Path;C:\path\to\Pragmatic.AgentSandbox\scripts", "User")
```

### Linux / macOS
```bash
export PATH="$PATH:/path/to/Pragmatic.AgentSandbox/scripts"
```

## Quick Start

Run `pi-agent-sandbox-host` from any directory — it mounts your current working directory as Pi's workspace:

```bash
cd /path/to/your/project
pi-agent-sandbox-host
```

When you exit Pi (Ctrl+C), the container is automatically cleaned up.

### Modes

| Mode | Command | Docker CLI | Host Socket | Security Hardening |
|---|---|---|---|---|
| **Locked-down** (default) | `pi-agent-sandbox-host` | ❌ | ❌ | `--cap-drop=ALL`, `no-new-privileges` |
| **Docker** (opt-in) | `pi-agent-sandbox-host --docker` | ✅ | ✅ | None (see Security) |

> **Tip:** The current mode is shown in the Pi footer status bar:
> - `🐳 Secure Sandbox (✅) locked down (✅)` — locked-down mode (default)
> - `🐳 Secure Sandbox (❗) docker in docker (❗)` — Docker mode (host socket mounted)

```bash
# With Docker support (opt-in, host socket mount)
pi-agent-sandbox-host --docker
```

## Prerequisites

- **Docker Desktop** running
- **LM Studio** running with the Local Server API enabled on port `1234`

## Runtime Environment

The container ships with:

| Tool | Version |
|---|---|
| .NET SDK | 10.0.100, 9.0, 8.0 |
| Node.js | 22 (Alpine) |
| Docker CLI | Alpine edge (Docker mode only) |

The container has **outbound internet access** by default, so Pi can install tools (e.g. `dotnet tool install`, `npm install`) and restore packages (`dotnet restore`, `npm ci`) at runtime.

## Architecture

### Locked-down mode
```
Host Machine
├── Your project directory
│   └── (mounted as /home/appuser/mount inside container)
└── Container: pi-agent-sandbox-host
    ├── Runs Pi (Node.js 22) + .NET SDK 10.0
    ├── Connects to LM Studio via host.docker.internal:1234
    ├── Outbound internet access (package restore, tool install)
    ├── Non-root user, no capabilities, no privilege escalation
    └── Auto-cleaned on exit (--rm)
```

### Docker mode
```
Host Machine
├── Your project directory
│   └── (mounted as /home/appuser/mount inside container)
└── Container: pi-agent-sandbox-host-dind
    ├── Runs Pi + Docker CLI
    ├── Connects to LM Studio via host.docker.internal:1234
    ├── Host Docker socket mounted (full Docker access)
    └── Auto-cleaned on exit (--rm)
```

## Security

| Control | Locked-down | Docker (`--docker`) | Details |
|---|---|---|---|
| Non-root user | ✅ | ✅ | Runs as `appuser` |
| No privileged mode | ✅ | ✅ | Default |
| No port exposure | ✅ | ✅ | No `ports:` block |
| Resource limits | ✅ | ✅ | 8GB/4 CPUs |
| `--cap-drop=ALL` | ✅ | ❌ | Requires full capabilities for Docker |
| `no-new-privileges` | ✅ | ❌ | Requires privilege escalation for Docker |
| Host Docker socket | ❌ | ✅ | Full access to host Docker daemon |

### Docker mode: trust trade-off

The `--docker` mode mounts the host Docker socket. **This gives the agent full control of the host Docker daemon.** A malicious or compromised agent can:

- Run `--privileged` containers
- Mount host filesystems (`-v /:/host`)
- Escape the container via `nsenter` or `--pid=host`
- Access any host resource the Docker daemon can reach

**There is no way to give an LLM Docker access without this risk.** Docker-in-Docker sidecars offer the same escape path — the agent controls any daemon it can talk to. The only difference is cosmetic sandboxing.

Only use `--docker` when you need Docker support and accept that the agent has full Docker access.

## Configuration

- **LM Studio API URL** is set via the `LMSTUDIO_API_URL` environment variable
- **Custom models/providers** are configured in `models.json` (baked into the image and synced into the `pi_agent` volume on every run when it has changed)
- **Pi cache** is persisted in a Docker volume (`pi_cache`)
- **Pi agent data** (sessions, settings, auth) is persisted in a Docker volume (`pi_agent`) so sessions survive restarts
- **npm cache** is persisted in a Docker volume (`npm_cache`)
- **NuGet cache** is persisted in a Docker volume (`nuget_cache`)

> **Note:** Caches live in Docker named volumes, not on the host filesystem. They persist across container runs but are not shared with the host's own package managers. Stale entries are auto-pruned on startup (see below).

### Cache age limits (configurable)

Both caches prune files not accessed within N days on every container start.

| Variable | Default | Effect |
|---|---|---|
| `NUGET_CACHE_MAX_AGE_DAYS` | `30` | Delete NuGet package files unused for N days |
| `NPM_CACHE_MAX_AGE_DAYS` | `30` | Delete npm cache files unused for N days |

Pass via `-e` in the host scripts or override directly in `docker run`.

### Updating `models.json`

`models.json` is baked into the image at build time, then synced into the `pi_agent` volume by the entrypoint if it differs from the live copy. edit `models.json` in the repo and simply re-run the host script: it rebuilds the image and seeds the new config automatically.

> **Note:** `models.json` is repo-owned, so edits made to it *inside the container* are overwritten on the next run. Customize it via the repo file instead. Other agent data (sessions, auth, `settings.json`) is preserved and never overwritten.

```bash
# After editing models.json in the repo:
pi-agent-sandbox-host
```

## Docker Support

By default, the container runs in **locked-down mode** — no Docker CLI is installed, no socket is mounted, and all Linux capabilities are dropped. To enable Docker support, pass `--docker`:

```bash
pi-agent-sandbox-host --docker
```

This mounts the host Docker socket, allowing Pi to run Docker commands (`docker build`, `docker run`, `docker compose`) against the host Docker daemon.

> **Security note:** Mounting the Docker socket grants the container full control of the host Docker environment. The `--cap-drop=ALL` and `--security-opt=no-new-privileges` restrictions are disabled in this mode. Only use `--docker` when Docker support is actually needed.
