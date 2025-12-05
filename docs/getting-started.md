---
title: Getting Started with FastMCP Runner
description: Learn how to run your first MCP server using FastMCP Runner. Step-by-step guide for deploying containerized Model Context Protocol applications.
---

# Getting Started

This guide walks through running an MCP application using FastMCP Runner. By the end, you'll understand the basic configuration and be able to deploy your own MCP server.

## Prerequisites

You need an MCP application packaged as a container image and pushed to a registry. The image should have:

- An `/app` directory containing your application code
- A working entrypoint that starts the MCP server
- Optionally, a `/data` directory for persistent data

If you're building a new MCP application, see [Building MCP Applications](building-apps.md) for packaging requirements.

## Running locally

The simplest way to test FastMCP Runner is with Docker. This example pulls a hypothetical MCP application from GitHub Container Registry:

```bash
docker run \
  -e IMAGE=ghcr.io/your-org/your-mcp-app:latest \
  -e PORT=8000 \
  -e REGISTRY_USER=your-username \
  -e REGISTRY_PASSWORD=your-token \
  -p 8000:8000 \
  ghcr.io/drengskapur/fastmcp-runner:latest-stable
```

The container will authenticate to the registry, pull your application image, and start the MCP server on port 8000.

### Using public images

If your MCP application is in a public registry, you can omit the authentication variables:

```bash
docker run \
  -e IMAGE=ghcr.io/your-org/your-public-app:latest \
  -e PORT=8000 \
  -p 8000:8000 \
  ghcr.io/drengskapur/fastmcp-runner:latest-stable
```

### Passing environment variables to your application

Your MCP application likely needs its own configuration—API keys, database URLs, feature flags. FastMCP Runner passes through any environment variable prefixed with `MCP_ENV_`, stripping the prefix before passing it to your application.

```bash
docker run \
  -e IMAGE=ghcr.io/your-org/your-mcp-app:latest \
  -e PORT=8000 \
  -e MCP_ENV_DATABASE_URL=postgres://localhost/mydb \
  -e MCP_ENV_API_KEY=secret-key \
  -p 8000:8000 \
  ghcr.io/drengskapur/fastmcp-runner:latest-stable
```

Your application receives `DATABASE_URL` and `API_KEY` as regular environment variables.

## Verifying it works

Once the container starts, you should see log output indicating the startup sequence:

```
2024-01-15T10:30:00Z [INFO]  FastMCP Runner starting
2024-01-15T10:30:00Z [INFO]    Image: ghcr.io/your-org/your-mcp-app:latest
2024-01-15T10:30:00Z [INFO]    Port:  8000
2024-01-15T10:30:00Z [INFO]    Transport: streamable-http
2024-01-15T10:30:01Z [INFO]  Authenticating to registry: ghcr.io
2024-01-15T10:30:02Z [INFO]  Fetching image config: ghcr.io/your-org/your-mcp-app:latest
2024-01-15T10:30:03Z [INFO]  Generating launcher script
2024-01-15T10:30:03Z [INFO]  Extracting image filesystem
2024-01-15T10:30:05Z [INFO]  Starting MCP server on port 8000
```

The health endpoint should respond once the server is ready:

```bash
curl http://localhost:8000/health
```

## Common issues

**Authentication failures**

If you see "Registry authentication failed", verify:

- The `REGISTRY_USER` and `REGISTRY_PASSWORD` are correct
- For GitHub Container Registry, use a personal access token with `read:packages` scope
- For Docker Hub, use your Docker Hub username and an access token
- The registry hostname is extracted from the `IMAGE` variable automatically—you don't need to specify it separately

**Image not found**

If the image pull fails, check that:

- The full image reference is correct, including the registry hostname
- Your credentials have permission to pull the image
- The image tag exists

**Application fails to start**

If FastMCP Runner starts but your application crashes, enable debug logging to see more detail:

```bash
docker run \
  -e IMAGE=ghcr.io/your-org/your-mcp-app:latest \
  -e PORT=8000 \
  -e LOG_LEVEL=debug \
  -p 8000:8000 \
  ghcr.io/drengskapur/fastmcp-runner:latest-stable
```

Debug output includes the generated launcher script, which shows exactly what command is being executed and with what environment variables.

## Next steps

- [Configuration](configuration.md) — Full reference for all environment variables
- [Deployment](deployment/index.md) — Guides for specific platforms
- [Security](security.md) — Understanding the security model
