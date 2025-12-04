# fastmcp-runner

Generic bootstrap container for running FastMCP servers from private container registries.

## Overview

This container pulls and runs any FastMCP application from a private registry at runtime. Useful for environments like Hugging Face Spaces where you can't run arbitrary Docker images directly.

## Usage

```bash
docker run -e REGISTRY=ghcr.io \
           -e REGISTRY_USER=username \
           -e REGISTRY_PASSWORD=token \
           -e IMAGE=ghcr.io/org/my-fastmcp-app:latest \
           -e PORT=7860 \
           -p 7860:7860 \
           ghcr.io/drengskapur/fastmcp-runner:latest
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `REGISTRY` | Yes | Registry hostname (e.g., `ghcr.io`, `docker.io`) |
| `REGISTRY_USER` | Yes | Username for registry authentication |
| `REGISTRY_PASSWORD` | Yes | Password or token for registry authentication |
| `IMAGE` | Yes | Full image reference to pull and run |
| `PORT` | Yes | Port for the FastMCP server |

## How It Works

1. Authenticates to the specified container registry
2. Pulls and extracts `/app` and `/data` directories from the target image
3. Runs the FastMCP server using `uv run fastmcp`
4. Drops privileges to non-root user before running the application

## Security

- Credentials are cleared from the environment before the application starts
- Application runs as non-root user (UID 1000)
- Docker config is removed after authentication
- Base image: [Chainguard wolfi-base](https://images.chainguard.dev/directory/image/wolfi-base/overview) (hardened, minimal)

## Requirements

The target image must have:
- `/app` directory with a FastMCP project (`pyproject.toml`, `.venv`, `fastmcp.json`)
- Optionally `/data` directory for persistent data

## License

MIT
