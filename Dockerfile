# syntax=docker/dockerfile:1

# FastMCP Runner - Generic OCI-based MCP server runner
#
# Pulls MCP server images from OCI registries and runs their entrypoint.
# Designed for serverless platforms (HuggingFace Spaces, Railway, etc.)
#
# How it works:
#   1. Authenticates to registry (if credentials provided)
#   2. Reads container config (ENTRYPOINT, CMD, ENV, WORKDIR)
#   3. Extracts image filesystem to /
#   4. Cleans up registry credentials
#   5. Runs container's entrypoint as non-root user (if started as root)
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
# Usage:
#   # Public registry
#   docker run -p 7860:7860 \
#     -e IMAGE=ghcr.io/org/my-mcp:latest \
#     -e PORT=7860 \
#     fastmcp-runner
#
#   # Private registry
#   docker run -p 7860:7860 \
#     -e REGISTRY_USER=myuser \
#     -e REGISTRY_PASSWORD=ghp_xxxx \
#     -e IMAGE=ghcr.io/org/private-mcp:latest \
#     -e PORT=7860 \
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
#     ENTRYPOINT ["python", "-m", "myserver", "--port", "${PORT}"]
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

# hadolint ignore=DL3007
# trivy:ignore:AVD-DS-0001 (Chainguard recommends :latest for daily security updates)
FROM cgr.dev/chainguard/wolfi-base:latest

# hadolint ignore=DL3018
RUN apk add --no-cache \
        build-base \
        crane \
        python-3.12 \
        su-exec \
        uv \
    && adduser -D -u 1000 user

# Force Python 3.12 as default
ENV UV_PYTHON=python3.12

WORKDIR /app

# hadolint ignore=DL4006
RUN <<'EOF' cat > /entrypoint.sh && chmod 500 /entrypoint.sh
#!/bin/sh
set -eu

: "${IMAGE:?IMAGE environment variable is required}"
: "${PORT:?PORT environment variable is required}"

echo "FastMCP Runner"
echo "  Image: $IMAGE"
echo "  Port:  $PORT"

# Extract registry from image (e.g., ghcr.io from ghcr.io/user/repo:tag)
REGISTRY="${IMAGE%%/*}"

# Authenticate if credentials provided (optional for public registries)
if [ -n "${REGISTRY_USER:-}" ] && [ -n "${REGISTRY_PASSWORD:-}" ]; then
    echo "Authenticating to $REGISTRY..."
    echo "$REGISTRY_PASSWORD" | crane auth login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin 2>/dev/null
fi

echo "Reading container config..."
CONFIG_JSON=$(crane config "$IMAGE")

echo "$CONFIG_JSON" | python3 -c "
import json
import sys
import shlex

config = json.load(sys.stdin).get('config', {})

# Get workdir, entrypoint, cmd
workdir = config.get('WorkingDir') or '/app'
entrypoint = config.get('Entrypoint') or []
cmd = config.get('Cmd') or []

# Build full command (entrypoint + cmd)
full_cmd = entrypoint + cmd
if not full_cmd:
    print('echo \"Error: No entrypoint or cmd in container config\"', file=sys.stderr)
    print('exit 1', file=sys.stderr)
    sys.exit(1)

print('#!/bin/sh')
print('set -eu')
print()

# Export environment variables from container
print('# Container environment')
for env in config.get('Env', []):
    key, _, value = env.partition('=')
    # Quote the value properly for shell
    print(f'export {key}={shlex.quote(value)}')

# Override with runner's PORT
print()
print('# Runner overrides')
print(f'export PORT=\"\${{PORT}}\"')
print()

# Change to workdir
print(f'cd {shlex.quote(workdir)}')
print()

# Execute command
print('# Run the container command')
print('exec ' + ' '.join(shlex.quote(arg) for arg in full_cmd))
" > /tmp/launcher.sh

chmod +x /tmp/launcher.sh

# Show what we're going to run
echo "Generated launcher:"
cat /tmp/launcher.sh | head -20
echo "..."

# Extract filesystem, then clean up credentials
echo ""
echo "Extracting image layers..."
crane export "$IMAGE" - | tar xf - -C / 2>/dev/null || true
rm -rf ~/.docker 2>/dev/null || true
unset REGISTRY_PASSWORD 2>/dev/null || true

# Ensure /data exists
mkdir -p /data 2>/dev/null || true

echo ""
echo "Starting server on port $PORT..."

# If running as root, drop to user 1000; otherwise run directly
if [ "$(id -u)" = "0" ]; then
    chown -R 1000:1000 /app /data 2>/dev/null || true
    exec su-exec user /tmp/launcher.sh
else
    exec /tmp/launcher.sh
fi
EOF

# Note: Entrypoint runs as root to extract files, then drops to user via su-exec

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:${PORT}/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
