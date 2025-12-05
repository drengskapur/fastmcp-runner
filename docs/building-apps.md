# Building MCP Applications

This guide covers how to package your MCP application so it works with FastMCP Runner. The requirements are straightforward, but understanding them helps avoid common issues.

## Directory structure

FastMCP Runner expects your application in the `/app` directory. This is the standard location for application code in container images and what most frameworks use by default.

A typical structure:

```
/app
├── pyproject.toml      # Python project definition
├── src/
│   └── your_app/
│       ├── __init__.py
│       └── server.py   # MCP server implementation
└── ...                 # Framework-specific config files
```

If your application needs persistent data, place it in `/data`. FastMCP Runner preserves this directory and, on platforms like Hugging Face Spaces, maps it to persistent storage.

## Entrypoint requirements

Your image must define an entrypoint or command that starts the MCP server. FastMCP Runner reads this from the OCI config and executes it.

Example entrypoints:

```dockerfile
# Using uvicorn directly
CMD ["uvicorn", "src.your_app.server:app", "--host", "0.0.0.0", "--port", "8000"]

# Using a virtual environment
CMD ["/app/.venv/bin/python", "-m", "your_app.server"]

# Using a script defined in pyproject.toml
CMD ["uv", "run", "your-server"]
```

The command must:

1. Start an HTTP server on the port specified by `PORT` environment variable
2. Bind to `0.0.0.0` (or the address in `HOST` if you've configured it)
3. Respond to health checks at the configured health path (default `/health`)

## Environment variable handling

Your application receives environment variables from three sources, merged in this order:

1. Variables baked into your image's OCI config
2. Passthrough variables (`MCP_ENV_*` with prefix stripped)
3. Runner overrides (`PORT`, `HOST`, `MCP_TRANSPORT`, `MCP_PATH`)

Design your application to read configuration from environment variables. Avoid hardcoding values that might need to change between environments.

Common variables your application should respect:

| Variable | Purpose |
|----------|---------|
| `PORT` | Port to bind the HTTP server |
| `HOST` | Address to bind (default: `0.0.0.0`) |
| `MCP_TRANSPORT` | Transport type (`streamable-http` or `sse`) |
| `MCP_PATH` | URL path for MCP endpoint |

## Conflicting entrypoints

FastMCP Runner skips certain entrypoint scripts that would conflict with its own startup process:

- `/entrypoint.sh`
- `entrypoint.sh`
- `/start.sh`
- `/init.sh`

If your image uses one of these as its entrypoint, FastMCP Runner uses the `CMD` instead. This prevents infinite recursion where the runner would inadvertently call itself. If your image only has a conflicting entrypoint and no `CMD`, you'll need to restructure your Dockerfile.

## Example Dockerfile

A complete Dockerfile for a Python MCP application:

```dockerfile
FROM python:3.12-slim AS builder

WORKDIR /app

# Install uv for fast dependency management
RUN pip install uv

# Copy dependency files first for better caching
COPY pyproject.toml uv.lock ./

# Install dependencies
RUN uv sync --frozen --no-dev

# Copy application code
COPY src/ src/
COPY fastmcp.json ./

FROM python:3.12-slim

WORKDIR /app

# Copy virtual environment and application from builder
COPY --from=builder /app /app

# Create data directory for persistent storage
RUN mkdir -p /data

# Default port (overridden by FastMCP Runner)
ENV PORT=8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://localhost:${PORT}/health || exit 1

# Run the MCP server
CMD ["/app/.venv/bin/python", "-m", "uvicorn", "src.your_app.server:app", "--host", "0.0.0.0", "--port", "8000"]
```

Note that CMD cannot use shell variable expansion for `${PORT}` since Docker exec form doesn't process variables. Your application should read the `PORT` environment variable at runtime instead.

## Health checks

FastMCP Runner checks your application's health endpoint to determine readiness. The default path is `/health`, configurable via `HEALTHCHECK_PATH`.

Your health endpoint should:

- Return HTTP 200 when the server is ready to accept requests
- Respond quickly (under 10 seconds)
- Not require authentication

A minimal health endpoint:

```python
@app.get("/health")
async def health():
    return {"status": "ok"}
```

For more sophisticated health checks, verify database connections, cache availability, or other dependencies:

```python
@app.get("/health")
async def health():
    # Check database
    try:
        await db.execute("SELECT 1")
    except Exception:
        return JSONResponse({"status": "unhealthy", "reason": "database"}, status_code=503)

    return {"status": "ok"}
```

## Image size optimization

Smaller images pull faster, reducing startup time. Strategies for reducing image size:

**Use multi-stage builds** to exclude build tools from the final image:

```dockerfile
FROM python:3.12 AS builder
# Install build dependencies, compile code

FROM python:3.12-slim
# Copy only runtime artifacts
```

**Exclude development dependencies**:

```bash
uv sync --frozen --no-dev
```

**Use slim or alpine base images** when possible. Be aware that alpine uses musl libc, which can cause issues with some Python packages.

**Minimize layers** by combining related commands:

```dockerfile
RUN apt-get update && \
    apt-get install -y --no-install-recommends package && \
    rm -rf /var/lib/apt/lists/*
```

## Testing locally

Before deploying via FastMCP Runner, test your image directly:

```bash
# Build
docker build -t my-mcp-app .

# Run directly
docker run -p 8000:8000 -e PORT=8000 my-mcp-app

# Test health endpoint
curl http://localhost:8000/health

# Test MCP endpoint
curl http://localhost:8000/mcp
```

Then test through FastMCP Runner:

```bash
# Push to registry
docker tag my-mcp-app ghcr.io/your-org/my-mcp-app:test
docker push ghcr.io/your-org/my-mcp-app:test

# Run via FastMCP Runner
docker run -p 8000:8000 \
  -e IMAGE=ghcr.io/your-org/my-mcp-app:test \
  -e PORT=8000 \
  -e REGISTRY_USER=your-username \
  -e REGISTRY_PASSWORD=your-token \
  ghcr.io/drengskapur/fastmcp-runner:latest-stable
```

## Common issues

**Application can't find dependencies**

FastMCP Runner extracts Python site-packages from standard locations. If your application uses a non-standard virtual environment location, dependencies may not be found. Stick to conventional paths: `/app/.venv` or system site-packages.

**Health check fails**

Ensure your application:
- Binds to `0.0.0.0`, not `127.0.0.1` or `localhost`
- Reads the port from the `PORT` environment variable
- Has a health endpoint at the expected path

**Startup timeout**

Large images take time to pull. If your platform has a startup timeout, optimize your image size or increase the timeout. Consider using a registry geographically close to your deployment for faster pulls.

**File permission errors**

Your application runs as UID 1000. Ensure any files your application needs to write are in directories owned by this user (`/app`, `/data`, `/tmp`, or under `/home/user`).
