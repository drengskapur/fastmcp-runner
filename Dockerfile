# syntax=docker/dockerfile:1.7

# FastMCP Runner - Generic OCI-based MCP server runner
#
# Pulls MCP server images from OCI registries and runs their entrypoint.
# Designed for serverless platforms (HuggingFace Spaces, Railway, etc.)
#
# How it works:
#   1. Validates input (IMAGE, PORT)
#   2. Authenticates to registry (if credentials provided)
#   3. Reads container config (ENTRYPOINT, CMD, ENV, WORKDIR)
#   4. Extracts image filesystem to staging, then selectively copies safe paths
#   5. Cleans up registry credentials (via trap on EXIT/INT/TERM)
#   6. Runs container's entrypoint as non-root user (if started as root)
#
# Environment Variables:
#   Required:
#     IMAGE  - OCI image to pull (e.g., ghcr.io/org/my-mcp:latest)
#     PORT   - Port to expose (passed to container as $PORT)
#
#   Optional (for private registries):
#     REGISTRY_USER     - Username for registry authentication
#     REGISTRY_PASSWORD - Password/token for registry authentication
#
#   Optional (environment passthrough):
#     MCP_ENV_*         - Any var prefixed with MCP_ENV_ is passed to the server
#                         with the prefix stripped. Example: MCP_ENV_API_KEY=secret
#                         becomes API_KEY=secret in the server environment.
#     MCP_HOST          - Override HOST env var in the container
#
# Usage:
#   # Public registry
#   docker run -p 7860:7860 \
#     -e IMAGE=ghcr.io/org/my-mcp:latest \
#     -e PORT=7860 \
#     fastmcp-runner
#
#   # Private registry with custom env vars
#   docker run -p 7860:7860 \
#     -e REGISTRY_USER=myuser \
#     -e REGISTRY_PASSWORD=ghp_xxxx \
#     -e IMAGE=ghcr.io/org/private-mcp:latest \
#     -e PORT=7860 \
#     -e MCP_ENV_API_TOKEN=secret \
#     fastmcp-runner
#
# Building your MCP server image:
#   Your image must define ENTRYPOINT or CMD that starts the server.
#   The server should listen on $PORT (passed from this runner).
#   Example Dockerfile:
#     FROM python:3.12-slim
#     COPY . /app
#     WORKDIR /app
#     RUN pip install .
#     ENV PORT=7860
#     ENTRYPOINT ["python", "-m", "myserver"]
#
# Tags:
#   - latest: Development/staging (built on push to main)
#   - latest-stable: Production (promoted via release workflow)
#   - vX.Y.Z: Specific versions
#
# Verify signature:
#   cosign verify ghcr.io/drengskapur/fastmcp-runner:latest-stable \
#     --certificate-oidc-issuer https://token.actions.githubusercontent.com \
#     --certificate-identity-regexp 'https://github.com/drengskapur/fastmcp-runner/.*'

ARG WOLFI_VERSION=latest
# hadolint ignore=DL3007
# trivy:ignore:AVD-DS-0001 (Chainguard recommends :latest for daily security updates)
FROM cgr.dev/chainguard/wolfi-base:${WOLFI_VERSION} AS base

# Single layer for all system deps
# hadolint ignore=DL3018
RUN apk add --no-cache \
        crane \
        python-3.12 \
        su-exec \
    && adduser -D -u 1000 -h /home/user -s /sbin/nologin user

# =============================================================================
# Runtime stage
# =============================================================================
FROM base AS runtime

ENV UV_PYTHON=python3.12 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Separate config parser for testability and readability
COPY --chmod=500 <<'PARSER' /usr/local/bin/parse-oci-config
#!/usr/bin/env python3
"""Parse OCI config and emit a POSIX shell launcher script."""

import json
import os
import shlex
import sys


def main() -> int:
    try:
        config = json.load(sys.stdin).get("config", {})
    except json.JSONDecodeError as e:
        print(f"error: invalid JSON: {e}", file=sys.stderr)
        return 1

    workdir = config.get("WorkingDir") or "/app"
    entrypoint = config.get("Entrypoint") or []
    cmd = config.get("Cmd") or []
    full_cmd = entrypoint + cmd

    if not full_cmd:
        print("error: container has no entrypoint or cmd", file=sys.stderr)
        return 1

    # Emit launcher
    print("#!/bin/sh")
    print("set -eu")
    print()

    # Container's original environment
    print("# Container environment")
    for env in config.get("Env", []):
        key, _, value = env.partition("=")
        if key:  # Skip malformed entries
            print(f"export {key}={shlex.quote(value)}")
    print()

    # Passthrough: MCP_ENV_* -> stripped prefix
    print("# Passthrough environment (MCP_ENV_* prefix stripped)")
    for key, value in os.environ.items():
        if key.startswith("MCP_ENV_"):
            stripped = key[8:]  # Remove MCP_ENV_ prefix
            if stripped:
                print(f"export {stripped}={shlex.quote(value)}")
    print()

    # Runner overrides (these win)
    print("# Runner overrides")
    print('export PORT="${PORT}"')
    if os.environ.get("MCP_HOST"):
        print(f'export HOST={shlex.quote(os.environ["MCP_HOST"])}')
    print()

    print(f"cd {shlex.quote(workdir)}")
    print()
    print("exec " + " ".join(shlex.quote(arg) for arg in full_cmd))

    return 0


if __name__ == "__main__":
    sys.exit(main())
PARSER

# hadolint ignore=DL4006
COPY --chmod=500 <<'ENTRYPOINT' /entrypoint.sh
#!/bin/sh
set -eu

# =============================================================================
# Validation
# =============================================================================
: "${IMAGE:?IMAGE environment variable is required}"
: "${PORT:?PORT environment variable is required}"

# Basic input sanitization
case "$IMAGE" in
    *[!a-zA-Z0-9_./:@-]*)
        echo "error: IMAGE contains invalid characters" >&2
        exit 1
        ;;
esac

case "$PORT" in
    ''|*[!0-9]*)
        echo "error: PORT must be numeric" >&2
        exit 1
        ;;
esac

if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "error: PORT must be 1-65535" >&2
    exit 1
fi

# =============================================================================
# Registry authentication (if credentials provided)
# =============================================================================
REGISTRY="${IMAGE%%/*}"

authenticate() {
    if [ -n "${REGISTRY_USER:-}" ] && [ -n "${REGISTRY_PASSWORD:-}" ]; then
        printf '%s' "$REGISTRY_PASSWORD" | \
            crane auth login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin 2>/dev/null
    fi
}

cleanup_creds() {
    rm -rf "${HOME:?}/.docker" 2>/dev/null || true
    # Can't truly unset in parent, but clear for subprocesses
    REGISTRY_PASSWORD=''
    export REGISTRY_PASSWORD
}

trap cleanup_creds EXIT INT TERM

# =============================================================================
# Image introspection
# =============================================================================
echo "FastMCP Runner"
echo "  Image:  $IMAGE"
echo "  Port:   $PORT"
echo ""

authenticate

echo "Reading container config..."
CONFIG_JSON=$(crane config "$IMAGE")

# Generate launcher from OCI config
echo "$CONFIG_JSON" | parse-oci-config > /tmp/launcher.sh
chmod 500 /tmp/launcher.sh

# Debug output (truncated)
echo ""
echo "Generated launcher:"
head -30 /tmp/launcher.sh
echo "[...]"
echo ""

# =============================================================================
# Filesystem extraction
# =============================================================================
echo "Extracting image layers..."

# Extract to staging area first, then selective copy
# This prevents overwriting system files like /bin, /etc
STAGING=$(mktemp -d)
crane export "$IMAGE" - | tar xf - -C "$STAGING" 2>/dev/null || true

# Safe paths to overlay (app code, not system)
for dir in app home opt srv var/lib data; do
    if [ -d "$STAGING/$dir" ]; then
        mkdir -p "/$dir"
        cp -a "$STAGING/$dir/." "/$dir/" 2>/dev/null || true
    fi
done

# Copy Python site-packages if present
for pypath in "$STAGING"/usr/lib/python*/site-packages; do
    if [ -d "$pypath" ]; then
        target="/usr/lib/$(basename "$(dirname "$pypath")")/site-packages"
        mkdir -p "$target"
        cp -a "$pypath/." "$target/" 2>/dev/null || true
    fi
done

rm -rf "$STAGING"

# Ensure standard dirs exist with correct ownership
mkdir -p /data /app 2>/dev/null || true

# =============================================================================
# Privilege drop and exec
# =============================================================================
cleanup_creds
echo "Starting server on port $PORT..."

if [ "$(id -u)" = "0" ]; then
    chown -R 1000:1000 /app /data /tmp/launcher.sh 2>/dev/null || true
    exec su-exec user /tmp/launcher.sh
else
    exec /tmp/launcher.sh
fi
ENTRYPOINT

# Minimal filesystem for security
RUN mkdir -p /app /data \
    && chown -R user:user /app /data

# Labels for discoverability
LABEL org.opencontainers.image.title="FastMCP Runner" \
      org.opencontainers.image.description="Generic OCI-based MCP server runner" \
      org.opencontainers.image.source="https://github.com/drengskapur/fastmcp-runner" \
      org.opencontainers.image.licenses="Apache-2.0"

EXPOSE 7860

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -qO- "http://localhost:${PORT:-7860}/health" || exit 1

ENTRYPOINT ["/entrypoint.sh"]
