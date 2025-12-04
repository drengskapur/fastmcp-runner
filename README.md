# fastmcp-runner

Generic bootstrap container for running FastMCP servers from private container registries.

## Overview

This container pulls and runs any FastMCP application from a private registry at runtime. Useful for environments like Hugging Face Spaces where you can't run arbitrary Docker images directly.

## Usage

```bash
docker run -e REGISTRY_USER=username \
           -e REGISTRY_PASSWORD=token \
           -e IMAGE=ghcr.io/org/my-fastmcp-app:latest \
           -e PORT=7860 \
           -p 7860:7860 \
           docker.io/drengskapur/fastmcp-runner:latest
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `REGISTRY_USER` | Yes | Username for registry authentication |
| `REGISTRY_PASSWORD` | Yes | Password or token for registry authentication |
| `IMAGE` | Yes | Full image reference to pull and run (registry extracted automatically) |
| `PORT` | Yes | Port for the FastMCP server |

## How It Works

1. Extracts registry hostname from `IMAGE` (e.g., `ghcr.io` from `ghcr.io/org/repo:tag`)
2. Authenticates to the registry, pulls image, and immediately clears credentials
3. Extracts `/app` and `/data` directories from the target image
4. Drops privileges to non-root user (UID 1000)
5. Runs the FastMCP server using `uv run fastmcp run`

## Security

- Credentials are cleared immediately after image pull (single chained command)
- Application runs as non-root user (UID 1000)
- Environment is sanitized before running the application (`env -i`)
- Base image: [Chainguard wolfi-base](https://images.chainguard.dev/directory/image/wolfi-base/overview) (hardened, minimal)

## Requirements

The target image must have:
- `/app` directory with a FastMCP project (`pyproject.toml`, `.venv`, `fastmcp.json`)
- Optionally `/data` directory for persistent data

## License

Apache 2.0
