---
title: Architecture and Internals
description: How FastMCP Runner works internally. Startup sequence, OCI image extraction, privilege separation, and component overview using crane and su-exec.
---

# Architecture

This document explains how FastMCP Runner works internally. Understanding the architecture helps when debugging issues or evaluating whether it fits your use case.

## Design constraints

FastMCP Runner was built around a specific constraint: running MCP applications on platforms that restrict container execution. Hugging Face Spaces, for example, allows you to run approved base images but doesn't provide Docker socket access. You cannot run `docker pull` or `docker run` inside these environments.

The solution is to interact with container registries at the OCI layer rather than through Docker. FastMCP Runner uses [crane](https://github.com/google/go-containerregistry/tree/main/cmd/crane), a tool from Google's go-containerregistry project, to authenticate to registries, fetch image manifests, and export filesystem layers—all without requiring a container runtime.

## Startup sequence

When FastMCP Runner starts, the entrypoint script executes a linear sequence of operations. Each step must succeed for the next to proceed; failures terminate the container with an error message.

### 1. Input validation

The first operation validates that required environment variables are present and correctly formatted. `IMAGE` must be a syntactically valid OCI reference. `PORT` must be a number between 1 and 65535. Invalid input produces a clear error message and exits immediately.

This validation catches configuration errors before any network operations occur, making debugging faster.

### 2. Registry authentication

If `REGISTRY_USER` and `REGISTRY_PASSWORD` are provided, the runner authenticates to the registry extracted from the `IMAGE` variable. For `ghcr.io/org/repo:tag`, the registry is `ghcr.io`.

Authentication uses `crane auth login`, which stores credentials in a Docker-compatible config file. These credentials are cleared later in the startup sequence—see the [Security](security.md) documentation for details.

Anonymous access is attempted if no credentials are provided. This works for public images but will fail for private repositories.

### 3. Image introspection

Before pulling the full image, the runner fetches only the image configuration blob using `crane config`. This JSON document contains:

- `Env`: Environment variables to set
- `WorkingDir`: Directory to run commands from
- `Entrypoint`: The executable and initial arguments
- `Cmd`: Additional arguments appended to the entrypoint

The configuration is typically a few kilobytes, much smaller than the full image. This allows FastMCP Runner to understand how to run the application before committing to a potentially large download.

### 4. Launcher generation

A Python script (`parse-oci-config`) transforms the image configuration into an executable shell script. This launcher script:

- Exports environment variables from the original image
- Exports passthrough variables (`MCP_ENV_*` with prefix stripped)
- Applies runner overrides (`PORT`, `MCP_TRANSPORT`, etc.)
- Changes to the correct working directory
- Execs the application's entrypoint with its arguments

The launcher is written to `/tmp/launcher.sh` and made executable. When `LOG_LEVEL=debug`, the generated script is logged so you can see exactly what will run.

**Conflicting entrypoint handling**: If the image's entrypoint is `/entrypoint.sh`, `entrypoint.sh`, `/start.sh`, or `/init.sh`, the runner uses the `CMD` instead. This prevents infinite recursion where the generated launcher would call FastMCP Runner's own entrypoint script.

### 5. Filesystem extraction

The runner exports the image to a tar stream using `crane export` and extracts it to a staging directory. Not all files are copied to the runtime filesystem—FastMCP Runner explicitly allows only application-related paths:

**Allowed paths:**
- `/app` — Application code
- `/data` — Persistent data
- `/home` — User home directories
- `/opt` — Optional application packages
- `/srv` — Service data
- `/var/lib`, `/var/data` — Application state
- Python site-packages directories
- Node.js node_modules directories

**Excluded paths:**
- `/bin`, `/sbin` — System binaries
- `/lib`, `/lib64` — System libraries
- `/usr/bin`, `/usr/sbin` — System utilities
- `/etc` — System configuration
- `/boot`, `/root` — System directories

This allowlist prevents a malicious or misconfigured image from overwriting the runner's own binaries, libraries, or configuration. The pulled image can only affect application-level directories.

### 6. Privilege drop

The runner starts as root because it needs to create directories and set file ownership. Once the filesystem is prepared, it drops to UID 1000 (a non-root user created during image build) using `su-exec`.

`su-exec` is similar to `gosu`—it execs the target command directly without forking, so the application runs as PID 1 with proper signal handling.

### 7. Application execution

The final step execs the generated launcher script. From this point, FastMCP Runner's entrypoint is replaced by your application. The application receives signals directly and can shut down cleanly.

## Component overview

FastMCP Runner is packaged as a single container image containing:

| Component | Purpose |
|-----------|---------|
| `crane` | OCI registry client for authentication and image operations |
| `su-exec` | Privilege dropping without forking |
| `python3` | Runs the OCI config parser and applications using Python |
| `wget` | Used by the health check |
| `/entrypoint.sh` | Main orchestration script |
| `/usr/local/bin/parse-oci-config` | Python script that generates the launcher |
| `/usr/local/lib/log.sh` | POSIX shell logging library |

The base image is [Chainguard wolfi-base](https://images.chainguard.dev/directory/image/wolfi-base/overview), a minimal, hardened Linux distribution designed for container workloads. It includes only essential system packages, reducing attack surface.

## Execution environment

Your application runs with these characteristics:

- **User**: UID 1000 (non-root)
- **Working directory**: As specified in your image's `WorkingDir`, defaulting to `/app`
- **PID**: 1 (receives signals directly)
- **Filesystem**: Read-write access to `/app`, `/data`, `/tmp`, and home directory
- **Network**: Full network access (no restrictions imposed by the runner)

## Limitations

FastMCP Runner has inherent limitations from its architecture:

**No Docker socket access.** Your application cannot run Docker commands. If your MCP server needs to spawn containers, FastMCP Runner is not suitable.

**No persistent changes to system directories.** Changes your application makes to `/usr`, `/etc`, or other system paths during runtime are not persisted and may not work at all depending on mount configurations.

**Single application per container.** The runner executes one entrypoint. If your image contains multiple services, you'll need a process manager inside your image or separate deployments.

**Startup latency.** Pulling and extracting the image adds startup time compared to running your image directly. For large images, this can be significant. Consider optimizing your application image size if startup time matters.
