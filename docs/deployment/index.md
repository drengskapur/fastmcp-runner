# Deployment

FastMCP Runner can be deployed anywhere that runs containers. This section covers platform-specific configuration for common deployment targets.

## Choosing an image tag

For production deployments, use either `latest-stable` or a specific version tag:

```bash
# Recommended for production
ghcr.io/drengskapur/fastmcp-runner:latest-stable

# For reproducible deployments
ghcr.io/drengskapur/fastmcp-runner:v0.1.0
```

The `latest` tag tracks the main branch and may include unreleased changes. Use it only for development and testing.

## Registry credentials

Most deployments require credentials for pulling your private MCP application image. How you provide these depends on your platform:

- **Environment variables**: Set `REGISTRY_USER` and `REGISTRY_PASSWORD` directly
- **Secrets management**: Reference secrets from your platform's secret store
- **Service accounts**: Some platforms support workload identity or service account authentication

See the platform-specific guides for details on secrets configuration.

## Health checks

FastMCP Runner includes a built-in health check that polls the configured health endpoint:

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD wget -q -O /dev/null "http://localhost:${PORT}${HEALTHCHECK_PATH:-/health}" || exit 1
```

Configure your orchestrator's health checks to use this endpoint. The default path is `/health`; change it with the `HEALTHCHECK_PATH` environment variable if your application uses a different path.

## Resource requirements

FastMCP Runner itself is lightweight—the base image is under 50MB and the entrypoint adds minimal overhead. Resource requirements depend primarily on your MCP application.

As a starting point:

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| Memory | 256 MB | 512 MB + application needs |
| CPU | 0.25 cores | 0.5 cores + application needs |
| Disk | 100 MB | 500 MB + application image size |

The startup phase temporarily requires additional disk space for image extraction. Plan for roughly 2x your application image size during startup.

## Platform guides

- [Hugging Face Spaces](huggingface.md) — Docker Spaces deployment
- [Docker Compose](docker-compose.md) — Local and self-hosted deployments
