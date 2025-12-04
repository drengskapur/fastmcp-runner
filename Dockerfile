# syntax=docker/dockerfile:1.7-labs

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# FastMCP Runner
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Generic OCI-based MCP server runner for serverless platforms.
# Pulls container images and runs them WITHOUT requiring a Docker daemon.
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │                           SECURITY MODEL                                 │
# ├─────────────────────────────────────────────────────────────────────────┤
# │  • Credentials cleared immediately after registry auth                  │
# │  • Staged extraction prevents system file overwrites                    │
# │  • Non-root execution via su-exec privilege drop                        │
# │  • Input validation on all external parameters                          │
# │  • No shell expansion in critical paths                                 │
# │  • Signed images with cosign verification support                       │
# └─────────────────────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │                         ENVIRONMENT VARIABLES                           │
# ├─────────────────────────────────────────────────────────────────────────┤
# │  Required:                                                              │
# │    IMAGE          OCI image reference (e.g., ghcr.io/org/mcp:latest)   │
# │    PORT           Port to expose (1-65535)                              │
# │                                                                         │
# │  Authentication (optional):                                             │
# │    REGISTRY_USER      Registry username                                 │
# │    REGISTRY_PASSWORD  Registry password/token                           │
# │                                                                         │
# │  Configuration (optional):                                              │
# │    MCP_TRANSPORT      Transport: streamable-http|sse (default: s-http) │
# │    MCP_HOST           Bind address (default: 0.0.0.0)                   │
# │    MCP_PATH           URL path (default: /mcp)                          │
# │    HEALTHCHECK_PATH   Health endpoint (default: /health)                │
# │    LOG_LEVEL          debug|info|warn|error (default: info)             │
# │    LOG_FORMAT         text|json (default: text)                         │
# │                                                                         │
# │  Passthrough:                                                           │
# │    MCP_ENV_*          Stripped and passed to server                     │
# │                       Example: MCP_ENV_API_KEY=x → API_KEY=x            │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Verify image signature:
#   cosign verify ghcr.io/drengskapur/fastmcp-runner:latest-stable \
#     --certificate-oidc-issuer https://token.actions.githubusercontent.com \
#     --certificate-identity-regexp 'github.com/drengskapur/fastmcp-runner'
#
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Build arguments
ARG WOLFI_VERSION=latest
ARG PYTHON_VERSION=3.12

#──────────────────────────────────────────────────────────────────────────────
# Base stage - minimal runtime dependencies
#──────────────────────────────────────────────────────────────────────────────
# hadolint ignore=DL3007
# trivy:ignore:AVD-DS-0001
FROM cgr.dev/chainguard/wolfi-base:${WOLFI_VERSION} AS base

ARG PYTHON_VERSION

# hadolint ignore=DL3018
RUN apk add --no-cache \
        crane \
        python-${PYTHON_VERSION} \
        su-exec \
        wget \
    && adduser \
        --disabled-password \
        --gecos "" \
        --home /home/user \
        --shell /sbin/nologin \
        --uid 1000 \
        user

#──────────────────────────────────────────────────────────────────────────────
# Runtime stage
#──────────────────────────────────────────────────────────────────────────────
FROM base AS runtime

# Python configuration
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONFAULTHANDLER=1

# Default configuration (overridable)
ENV LOG_LEVEL=info \
    LOG_FORMAT=text \
    MCP_TRANSPORT=streamable-http \
    MCP_HOST=0.0.0.0 \
    MCP_PATH=/mcp \
    HEALTHCHECK_PATH=/health

WORKDIR /app

#──────────────────────────────────────────────────────────────────────────────
# Logging library
#──────────────────────────────────────────────────────────────────────────────
COPY --chmod=444 <<'LOGLIB' /usr/local/lib/log.sh
#!/bin/sh
# POSIX-compliant structured logging

_log_level_num() {
    case "$1" in
        debug) echo 0 ;;
        info)  echo 1 ;;
        warn)  echo 2 ;;
        error) echo 3 ;;
        *)     echo 1 ;;
    esac
}

_should_log() {
    [ "$(_log_level_num "$1")" -ge "$(_log_level_num "${LOG_LEVEL:-info}")" ]
}

_log() {
    _level="$1"; shift
    _should_log "$_level" || return 0

    _ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [ "${LOG_FORMAT:-text}" = "json" ]; then
        # JSON structured logging
        _msg=$(printf '%s' "$*" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')
        printf '{"ts":"%s","level":"%s","msg":"%s"}\n' "$_ts" "$_level" "$_msg" >&2
    else
        # Human-readable
        case "$_level" in
            debug) _prefix="[DEBUG]" ;;
            info)  _prefix="[INFO] " ;;
            warn)  _prefix="[WARN] " ;;
            error) _prefix="[ERROR]" ;;
        esac
        printf '%s %s %s\n' "$_ts" "$_prefix" "$*" >&2
    fi
}

log_debug() { _log debug "$@"; }
log_info()  { _log info "$@"; }
log_warn()  { _log warn "$@"; }
log_error() { _log error "$@" >&2; }

log_fatal() {
    _log error "$@" >&2
    exit 1
}
LOGLIB

#──────────────────────────────────────────────────────────────────────────────
# OCI config parser
#──────────────────────────────────────────────────────────────────────────────
COPY --chmod=555 <<'PARSER' /usr/local/bin/parse-oci-config
#!/usr/bin/env python3
"""
Parse OCI container config and generate a POSIX shell launcher.

Reads OCI config JSON from stdin, outputs executable shell script to stdout.
Handles environment passthrough, working directory, and command assembly.
"""

from __future__ import annotations

import json
import os
import shlex
import sys
from typing import Any


def quote(s: str) -> str:
    """Shell-quote a string, handling edge cases."""
    if not s:
        return "''"
    return shlex.quote(s)


def parse_env_var(env: str) -> tuple[str, str] | None:
    """Parse KEY=value string, returning None for malformed entries."""
    if "=" not in env:
        return None
    key, _, value = env.partition("=")
    # Validate key is a valid shell identifier
    if not key or not key.replace("_", "").isalnum() or key[0].isdigit():
        return None
    return key, value


def get_passthrough_env() -> dict[str, str]:
    """Get MCP_ENV_* variables with prefix stripped."""
    result = {}
    prefix = "MCP_ENV_"
    for key, value in os.environ.items():
        if key.startswith(prefix):
            stripped = key[len(prefix):]
            if stripped and stripped.replace("_", "").isalnum():
                result[stripped] = value
    return result


def generate_launcher(config: dict[str, Any]) -> str:
    """Generate shell launcher script from OCI config."""
    lines = [
        "#!/bin/sh",
        "set -eu",
        "",
        "# Container environment",
    ]

    # Original container environment
    for env in config.get("Env", []):
        parsed = parse_env_var(env)
        if parsed:
            key, value = parsed
            lines.append(f"export {key}={quote(value)}")

    lines.append("")
    lines.append("# Passthrough environment (MCP_ENV_* -> *)")

    # Passthrough vars
    for key, value in sorted(get_passthrough_env().items()):
        lines.append(f"export {key}={quote(value)}")

    lines.append("")
    lines.append("# Runner overrides (highest priority)")
    lines.append('export PORT="${PORT}"')

    if os.environ.get("MCP_HOST"):
        lines.append(f"export HOST={quote(os.environ['MCP_HOST'])}")
    if os.environ.get("MCP_TRANSPORT"):
        lines.append(f"export MCP_TRANSPORT={quote(os.environ['MCP_TRANSPORT'])}")
    if os.environ.get("MCP_PATH"):
        lines.append(f"export MCP_PATH={quote(os.environ['MCP_PATH'])}")

    # Working directory
    workdir = config.get("WorkingDir") or "/app"
    lines.append("")
    lines.append(f"cd {quote(workdir)}")

    # Command assembly
    entrypoint = config.get("Entrypoint") or []
    cmd = config.get("Cmd") or []
    full_cmd = entrypoint + cmd

    if not full_cmd:
        return "#!/bin/sh\necho 'error: no entrypoint or cmd in container' >&2\nexit 1\n"

    lines.append("")
    lines.append("# Execute server")
    lines.append("exec " + " ".join(quote(arg) for arg in full_cmd))
    lines.append("")

    return "\n".join(lines)


def main() -> int:
    """Main entry point."""
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"error: invalid JSON input: {e}", file=sys.stderr)
        return 1

    config = data.get("config", {})
    if not isinstance(config, dict):
        print("error: 'config' must be an object", file=sys.stderr)
        return 1

    print(generate_launcher(config))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PARSER

#──────────────────────────────────────────────────────────────────────────────
# Main entrypoint
#──────────────────────────────────────────────────────────────────────────────
# hadolint ignore=DL4006
COPY --chmod=555 <<'ENTRYPOINT' /entrypoint.sh
#!/bin/sh
set -eu

# shellcheck source=/usr/local/lib/log.sh
. /usr/local/lib/log.sh

#───────────────────────────────────────────────────────────────────────────────
# Cleanup handler
#───────────────────────────────────────────────────────────────────────────────
STAGING_DIR=""
cleanup() {
    log_debug "Cleanup triggered"
    # Clear credentials
    rm -rf "${HOME:?}/.docker" 2>/dev/null || true
    REGISTRY_PASSWORD=''; export REGISTRY_PASSWORD
    # Remove staging directory
    if [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ]; then
        rm -rf "$STAGING_DIR" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

#───────────────────────────────────────────────────────────────────────────────
# Input validation
#───────────────────────────────────────────────────────────────────────────────
validate_inputs() {
    # IMAGE is required
    if [ -z "${IMAGE:-}" ]; then
        log_fatal "IMAGE environment variable is required"
    fi

    # PORT is required and must be valid
    if [ -z "${PORT:-}" ]; then
        log_fatal "PORT environment variable is required"
    fi

    case "$PORT" in
        ''|*[!0-9]*)
            log_fatal "PORT must be a number, got: $PORT"
            ;;
    esac

    if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        log_fatal "PORT must be 1-65535, got: $PORT"
    fi

    # IMAGE format validation (basic sanity check)
    # Allow: lowercase, digits, dots, dashes, underscores, slashes, colons, @
    case "$IMAGE" in
        *[!a-zA-Z0-9_./:@-]*)
            log_fatal "IMAGE contains invalid characters: $IMAGE"
            ;;
    esac

    # Must have at least registry/image structure
    case "$IMAGE" in
        */*/*|*/*)
            : # Valid: registry/org/repo or org/repo
            ;;
        *)
            log_warn "IMAGE may be missing registry prefix: $IMAGE"
            ;;
    esac

    log_debug "Input validation passed"
}

#───────────────────────────────────────────────────────────────────────────────
# Registry authentication
#───────────────────────────────────────────────────────────────────────────────
authenticate() {
    REGISTRY="${IMAGE%%/*}"

    if [ -n "${REGISTRY_USER:-}" ] && [ -n "${REGISTRY_PASSWORD:-}" ]; then
        log_info "Authenticating to registry: $REGISTRY"

        if ! printf '%s' "$REGISTRY_PASSWORD" | \
             crane auth login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin 2>/dev/null; then
            log_fatal "Registry authentication failed for $REGISTRY"
        fi

        log_debug "Authentication successful"
    else
        log_debug "No registry credentials provided, using anonymous access"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Image introspection
#───────────────────────────────────────────────────────────────────────────────
introspect_image() {
    log_info "Fetching image config: $IMAGE"

    if ! CONFIG_JSON=$(crane config "$IMAGE" 2>&1); then
        log_fatal "Failed to fetch image config: $CONFIG_JSON"
    fi

    # Validate it's actual JSON
    if ! printf '%s' "$CONFIG_JSON" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
        log_fatal "Invalid JSON in image config"
    fi

    log_debug "Image config retrieved successfully"
    printf '%s' "$CONFIG_JSON"
}

#───────────────────────────────────────────────────────────────────────────────
# Generate launcher script
#───────────────────────────────────────────────────────────────────────────────
generate_launcher() {
    _config="$1"
    _output="$2"

    log_info "Generating launcher script"

    if ! printf '%s' "$_config" | parse-oci-config > "$_output"; then
        log_fatal "Failed to parse OCI config"
    fi

    chmod 500 "$_output"

    if [ "${LOG_LEVEL:-info}" = "debug" ]; then
        log_debug "Generated launcher:"
        cat "$_output" | while IFS= read -r line; do
            log_debug "  $line"
        done
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Filesystem extraction with safety controls
#───────────────────────────────────────────────────────────────────────────────
extract_filesystem() {
    log_info "Extracting image filesystem"

    STAGING_DIR=$(mktemp -d)
    log_debug "Staging directory: $STAGING_DIR"

    # Export image to staging area
    if ! crane export "$IMAGE" - 2>/dev/null | tar xf - -C "$STAGING_DIR" 2>/dev/null; then
        log_warn "Some extraction errors occurred (non-fatal)"
    fi

    # Safe paths to overlay - application code and dependencies only
    # Explicitly NOT copying: /bin /sbin /etc /lib /usr/bin /usr/sbin /boot /root
    SAFE_PATHS="
        app
        data
        home
        opt
        srv
        var/lib
        var/data
    "

    for dir in $SAFE_PATHS; do
        if [ -d "$STAGING_DIR/$dir" ]; then
            log_debug "Copying /$dir"
            mkdir -p "/$dir"
            cp -a "$STAGING_DIR/$dir/." "/$dir/" 2>/dev/null || true
        fi
    done

    # Python packages (site-packages directories)
    for pypath in "$STAGING_DIR"/usr/lib/python*/site-packages \
                  "$STAGING_DIR"/usr/local/lib/python*/site-packages; do
        if [ -d "$pypath" ]; then
            # Reconstruct target path
            _relpath="${pypath#"$STAGING_DIR"}"
            log_debug "Copying $_relpath"
            mkdir -p "$(dirname "$_relpath")"
            cp -a "$pypath" "$(dirname "$_relpath")/" 2>/dev/null || true
        fi
    done

    # Node modules (common locations)
    for nodepath in "$STAGING_DIR"/app/node_modules \
                    "$STAGING_DIR"/usr/local/lib/node_modules; do
        if [ -d "$nodepath" ]; then
            _relpath="${nodepath#"$STAGING_DIR"}"
            log_debug "Copying $_relpath"
            mkdir -p "$(dirname "$_relpath")"
            cp -a "$nodepath" "$(dirname "$_relpath")/" 2>/dev/null || true
        fi
    done

    # Cleanup staging
    rm -rf "$STAGING_DIR"
    STAGING_DIR=""

    log_debug "Filesystem extraction complete"
}

#───────────────────────────────────────────────────────────────────────────────
# Privilege management
#───────────────────────────────────────────────────────────────────────────────
setup_permissions() {
    log_debug "Setting up permissions"

    # Ensure standard directories exist
    mkdir -p /app /data /tmp 2>/dev/null || true

    if [ "$(id -u)" = "0" ]; then
        chown -R 1000:1000 /app /data 2>/dev/null || true
        chown 1000:1000 /tmp/launcher.sh 2>/dev/null || true
    fi
}

run_server() {
    _launcher="$1"

    log_info "Starting MCP server on port $PORT"

    # Clear credentials one final time before exec
    cleanup

    if [ "$(id -u)" = "0" ]; then
        log_debug "Dropping privileges to user 1000"
        exec su-exec user "$_launcher"
    else
        log_debug "Already running as non-root"
        exec "$_launcher"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Main
#───────────────────────────────────────────────────────────────────────────────
main() {
    log_info "FastMCP Runner starting"
    log_info "  Image: $IMAGE"
    log_info "  Port:  $PORT"
    log_info "  Transport: ${MCP_TRANSPORT:-streamable-http}"

    validate_inputs
    authenticate

    CONFIG_JSON=$(introspect_image)
    generate_launcher "$CONFIG_JSON" /tmp/launcher.sh
    extract_filesystem
    setup_permissions
    run_server /tmp/launcher.sh
}

main "$@"
ENTRYPOINT

#──────────────────────────────────────────────────────────────────────────────
# Filesystem setup
#──────────────────────────────────────────────────────────────────────────────
RUN mkdir -p /app /data \
    && chown -R user:user /app /data

#──────────────────────────────────────────────────────────────────────────────
# OCI Labels
#──────────────────────────────────────────────────────────────────────────────
LABEL org.opencontainers.image.title="FastMCP Runner" \
      org.opencontainers.image.description="Generic OCI-based MCP server runner for serverless platforms" \
      org.opencontainers.image.vendor="Drengskapur" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/drengskapur/fastmcp-runner" \
      org.opencontainers.image.documentation="https://github.com/drengskapur/fastmcp-runner#readme"

#──────────────────────────────────────────────────────────────────────────────
# Health check
#──────────────────────────────────────────────────────────────────────────────
HEALTHCHECK \
    --interval=30s \
    --timeout=10s \
    --start-period=30s \
    --retries=3 \
    CMD wget -q -O /dev/null "http://localhost:${PORT}${HEALTHCHECK_PATH:-/health}" || exit 1

ENTRYPOINT ["/entrypoint.sh"]
