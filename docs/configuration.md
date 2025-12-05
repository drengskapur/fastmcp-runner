# Configuration

FastMCP Runner is configured entirely through environment variables. This page documents all available options, their defaults, and how they interact.

## Required variables

These variables must be set for FastMCP Runner to start.

### `IMAGE`

The full OCI image reference to pull and run. This must include the registry hostname.

```
IMAGE=ghcr.io/your-org/your-mcp-app:latest
IMAGE=docker.io/library/your-app:v1.2.3
IMAGE=your-registry.example.com/team/app@sha256:abc123...
```

The registry hostname is extracted from this value automatically for authentication. Both tag references (`:latest`) and digest references (`@sha256:...`) are supported.

### `PORT`

The port number for the MCP server. Must be an integer between 1 and 65535.

```
PORT=8000
```

This value is passed to your application as the `PORT` environment variable and is used for the container's health check.

## Authentication

These variables control registry authentication. Both must be provided together, or both must be omitted for anonymous access.

### `REGISTRY_USER`

Username for registry authentication.

For GitHub Container Registry, this is your GitHub username. For Docker Hub, this is your Docker Hub username. For other registries, consult their documentation.

### `REGISTRY_PASSWORD`

Password or token for registry authentication.

For GitHub Container Registry, use a personal access token with `read:packages` scope. For Docker Hub, use an access token rather than your account password.

Credentials are cleared from the environment immediately after authentication and before your application starts.

## MCP transport configuration

These variables control how the MCP server communicates with clients.

### `MCP_TRANSPORT`

The transport protocol to use. Default: `streamable-http`

| Value | Description |
|-------|-------------|
| `streamable-http` | HTTP with streaming support (recommended) |
| `sse` | Server-Sent Events |

### `MCP_HOST`

The address to bind the server to. Default: `0.0.0.0`

In most deployments, the default is correct. You might change this if you need the server to bind only to a specific interface.

### `MCP_PATH`

The URL path for the MCP endpoint. Default: `/mcp`

### `HEALTHCHECK_PATH`

The URL path for health checks. Default: `/health`

The container's built-in health check uses this path to determine if the application is ready.

## Logging

### `LOG_LEVEL`

Controls log verbosity. Default: `info`

| Value | Description |
|-------|-------------|
| `debug` | Verbose output including generated scripts and internal state |
| `info` | Normal operation logging |
| `warn` | Warnings and errors only |
| `error` | Errors only |

### `LOG_FORMAT`

Controls log output format. Default: `text`

| Value | Description |
|-------|-------------|
| `text` | Human-readable format with timestamps |
| `json` | Structured JSON, one object per line |

JSON format is useful when aggregating logs in systems like Elasticsearch or CloudWatch.

Example text output:
```
2024-01-15T10:30:00Z [INFO]  FastMCP Runner starting
```

Example JSON output:
```json
{"ts":"2024-01-15T10:30:00Z","level":"info","msg":"FastMCP Runner starting"}
```

## Environment passthrough

### `MCP_ENV_*`

Any environment variable with the `MCP_ENV_` prefix is passed through to your application with the prefix stripped.

```bash
# These runner variables...
MCP_ENV_DATABASE_URL=postgres://localhost/db
MCP_ENV_API_KEY=secret
MCP_ENV_FEATURE_FLAGS=enable_new_ui,beta_features

# ...become these application variables:
DATABASE_URL=postgres://localhost/db
API_KEY=secret
FEATURE_FLAGS=enable_new_ui,beta_features
```

This mechanism allows you to configure your application without conflicting with FastMCP Runner's own configuration namespace.

Variable names must be valid shell identifiers (alphanumeric and underscore, not starting with a digit). Invalid names are silently ignored.

## Environment variable precedence

When your application receives environment variables, they come from multiple sources with the following precedence (highest to lowest):

1. **Runner overrides** — `PORT`, `HOST` (from `MCP_HOST`), `MCP_TRANSPORT`, `MCP_PATH`
2. **Passthrough variables** — `MCP_ENV_*` with prefix stripped
3. **Original image environment** — Variables baked into the pulled image's OCI config

This means if your image defines `PORT=3000` but you run with `-e PORT=8000`, your application sees `PORT=8000`.

## Complete example

A full configuration using all available options:

```bash
docker run \
  -e IMAGE=ghcr.io/your-org/your-mcp-app:v1.2.3 \
  -e PORT=8000 \
  -e REGISTRY_USER=your-username \
  -e REGISTRY_PASSWORD=ghp_xxxxxxxxxxxx \
  -e MCP_TRANSPORT=streamable-http \
  -e MCP_HOST=0.0.0.0 \
  -e MCP_PATH=/mcp \
  -e HEALTHCHECK_PATH=/health \
  -e LOG_LEVEL=info \
  -e LOG_FORMAT=json \
  -e MCP_ENV_DATABASE_URL=postgres://db.example.com/prod \
  -e MCP_ENV_REDIS_URL=redis://cache.example.com:6379 \
  -e MCP_ENV_API_KEY=prod-secret-key \
  -p 8000:8000 \
  ghcr.io/drengskapur/fastmcp-runner:latest-stable
```
