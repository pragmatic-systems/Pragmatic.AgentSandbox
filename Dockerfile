# -----------------------------------------------------------
# Pi Coding Agent — sandboxed harness
# -----------------------------------------------------------
# .NET SDK 10.0 base + .NET 8.0 & 9.0 + Node.js 22 + Pi
#
#   INSTALL_DOCKER=false (default)  Locked-down: no Docker CLI, no extra capabilities
#                                   docker build -t pi-agent-sandbox-host .
#
#   INSTALL_DOCKER=true             Docker mode: Docker CLI + docker group
#                                   (host socket is mounted by the launcher scripts)
#                                   docker build --build-arg INSTALL_DOCKER=true -t pi-agent-sandbox-host-dind .
# -----------------------------------------------------------

FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine

ARG INSTALL_DOCKER=false

# Install system packages (Docker CLI only in Docker mode)
RUN apk add --no-cache nodejs npm bash curl grep && \
    if [ "$INSTALL_DOCKER" = "true" ]; then apk add --no-cache docker; fi

# Install .NET 8.0 SDK
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && \
    bash /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet && \
    rm /tmp/dotnet-install.sh

# Install .NET 9.0 SDK
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && \
    bash /tmp/dotnet-install.sh --channel 9.0 --install-dir /usr/share/dotnet && \
    rm /tmp/dotnet-install.sh

# Install Pi
RUN npm install -g @earendil-works/pi-coding-agent@0.85.1

# --- Non-root user (docker group only in Docker mode) ---
RUN addgroup -S appgroup && adduser -S appuser -G appgroup && \
    if [ "$INSTALL_DOCKER" = "true" ]; then addgroup appuser docker; fi

# --- Directories ---
RUN mkdir -p /home/appuser/mount /home/appuser/.pi/agent/extensions /home/appuser/.npm /home/appuser/.nuget /opt/pi-agent && \
    chown -R appuser:appgroup /home/appuser

# --- Pi config (baked in to /opt, seeded at runtime by entrypoint) ---
# Stored outside .pi/agent so the pi_agent volume mount doesn't shadow them
COPY AGENTS.md /opt/pi-agent/AGENTS.md
COPY models.json /opt/pi-agent/models.json
COPY settings.json /opt/pi-agent/settings.json
COPY APPEND_SYSTEM.md /opt/pi-agent/APPEND_SYSTEM.md
COPY docker-mode-indicator.ts /opt/pi-agent/docker-mode-indicator.ts
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER appuser
WORKDIR /home/appuser/mount

ENV HOME=/home/appuser
ENV NODE_ENV=development

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
