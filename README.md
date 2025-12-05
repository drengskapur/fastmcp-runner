# FastMCP Runner

A generic OCI-based runner for MCP (Model Context Protocol) servers. Pulls container images from registries and runs them without requiring a Docker daemon.

## Overview

FastMCP Runner is a bootstrap container that pulls and executes MCP server images at runtime. It works with any MCP server packaged as a container image, not just FastMCP applications. This is useful for environments like Hugging Face Spaces where you cannot run arbitrary Docker images directly.

## Documentation

Full documentation is available at **[fastmcp-runner.readthedocs.io](https://fastmcp-runner.readthedocs.io)**

## Quick Start

```bash
docker run \
  -e IMAGE=ghcr.io/your-org/your-mcp-server:latest \
  -e PORT=8000 \
  -e REGISTRY_USER=username \
  -e REGISTRY_PASSWORD=token \
  -p 8000:8000 \
  ghcr.io/drengskapur/fastmcp-runner:latest-stable
```

For public images, omit `REGISTRY_USER` and `REGISTRY_PASSWORD`.

## Image Tags

| Tag | Description | Use Case |
|-----|-------------|----------|
| `latest` | Built on every push to main | Development, staging |
| `latest-stable` | Promoted via release workflow | **Production** |
| `vX.Y.Z` | Specific version | Pinned deployments |

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `IMAGE` | Yes | Full OCI image reference to pull and run |
| `PORT` | Yes | Port for the MCP server (1-65535) |
| `REGISTRY_USER` | No | Username for private registry authentication |
| `REGISTRY_PASSWORD` | No | Password/token for private registry authentication |
| `MCP_TRANSPORT` | No | Transport type: `streamable-http` (default) or `sse` |
| `MCP_HOST` | No | Bind address (default: `0.0.0.0`) |
| `MCP_PATH` | No | MCP endpoint path (default: `/mcp`) |
| `HEALTHCHECK_PATH` | No | Health check path (default: `/health`) |
| `LOG_LEVEL` | No | Logging level: `debug`, `info`, `warn`, `error` |
| `LOG_FORMAT` | No | Log format: `text` or `json` |
| `MCP_ENV_*` | No | Passthrough variables (prefix stripped before passing to app) |

## How It Works

1. Validates required environment variables
2. Authenticates to registry (if credentials provided), then clears credentials
3. Fetches image configuration to determine entrypoint and environment
4. Extracts application directories (`/app`, `/data`, `/home`, `/opt`, site-packages)
5. Drops privileges to non-root user (UID 1000)
6. Executes the image's configured entrypoint/command

## Security

- Credentials cleared immediately after authentication
- Application runs as non-root user (UID 1000)
- System directories excluded from extraction (only application paths copied)
- Base image: [Chainguard wolfi-base](https://images.chainguard.dev/directory/image/wolfi-base/overview)
- All images signed with Sigstore cosign

## Verify Image Signature

```bash
cosign verify ghcr.io/drengskapur/fastmcp-runner:latest-stable \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp 'https://github.com/drengskapur/fastmcp-runner/.*'
```

## Requirements

The target image must have:

- A valid entrypoint or command that starts an MCP server
- Application code in extractable paths (`/app`, `/opt`, `/home`, or site-packages)
- The server must bind to `0.0.0.0` and read port from `PORT` environment variable

## License

Apache 2.0
