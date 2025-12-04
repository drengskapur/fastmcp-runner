# syntax=docker/dockerfile:1

# hadolint ignore=DL3007
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

: "${REGISTRY_USER:?}"
: "${REGISTRY_PASSWORD:?}"
: "${IMAGE:?}"
: "${PORT:?}"

# Extract registry from image (e.g., ghcr.io from ghcr.io/user/repo:tag)
REGISTRY="${IMAGE%%/*}"
echo "$REGISTRY_PASSWORD" | crane auth login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin 2>/dev/null
crane export "$IMAGE" - | tar xf - -C / -o app data
chown -R 1000:1000 /app /data 2>/dev/null || true
rm -rf ~/.docker

exec su-exec user env -i \
    HOME=/home/user \
    PATH=/usr/local/bin:/usr/bin:/bin \
    uv run fastmcp run fastmcp.json \
        --transport streamable-http \
        --host 0.0.0.0 \
        --port "$PORT"
EOF

# Note: Entrypoint runs as root to extract files, then drops to user via su-exec

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:${PORT}/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
