# Container Environment Instructions

<!-- This file is baked into the image and seeded into ~/.pi/agent/AGENTS.md on every container start. -->

## Environment

- You are running inside a Docker container.
- The workspace at `/home/appuser/mount/<project>` is a bind mount of a host directory — files you write here land on the host filesystem.
- Outbound internet access is available for package restore and tool install.
- LM Studio is reachable at `http://host.docker.internal:1234/v1`.
- Package caches (~/.npm, ~/.nuget) are pruned on startup based on access age.

## NuGet cache corruption (recurring)

This issue is a side effect of a shared shared Windows host + Linux container workspace.
Restore/build errors like `NU1102`/`NU1103`/`NU1403`, `NU1006`, "not a valid NuGet package", or SHA512 hash mismatches usually mean a corrupted global packages folder.
Don't patch around it: Wait for IDE/NCrunch file locks to release, then run `dotnet nuget locals global-packages --clear`, `dotnet nuget locals temp --clear`, `dotnet nuget locals http-cache --clear`, and rebuild with `dotnet cake --Target=BuildAndTest`. 
If `NUGET_PACKAGES` is set, the cache lives there instead of `~/.nuget/packages`.

## Git in the Linux container

If git fails with `fatal: detected dubious ownership`, it's the 9p mount showing files as `root:root` while the agent runs as a different uid — run `git config --global --add safe.directory /home/appuser/mount/<project>` (idempotent; needed again after a container rebuild). 
Never happens on the Windows host.

## Operating instructions

Do not attempt to work around the constraints of the container. If you are limited by tools or permissions beyond the ones described above, list the issues and return control to the user.

# Output style

- Be concise. Give short, direct answers; skip preamble, apologies, and restating the question.
- Act first, summarize briefly after. Do not narrate plans or reasoning in the final answer.
- Keep comments minimal: only add a comment when the "why" isn't obvious from the code itself (non-obvious constraint, workaround, or subtle invariant). Never narrate what the code does; don't add comments to self-explanatory code, imports, or simple getters.
