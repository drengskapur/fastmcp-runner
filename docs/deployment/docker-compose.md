---
title: Deploy with Docker Compose
description: Run FastMCP Runner locally with Docker Compose. Configuration examples for development, multiple services, and production deployments.
---

# Docker Compose

Docker Compose is useful for local development and self-hosted deployments. While you could run your MCP application image directly with Docker, using FastMCP Runner provides a consistent deployment model across environments.

## Basic configuration

Create a `docker-compose.yml`:

```yaml
services:
  mcp:
    image: ghcr.io/drengskapur/fastmcp-runner:latest-stable
    ports:
      - "8000:8000"
    environment:
      IMAGE: ghcr.io/your-org/your-mcp-app:latest
      PORT: "8000"
      REGISTRY_USER: ${REGISTRY_USER}
      REGISTRY_PASSWORD: ${REGISTRY_PASSWORD}
```

Create a `.env` file for credentials (do not commit this file):

```bash
REGISTRY_USER=your-username
REGISTRY_PASSWORD=your-token
```

Start the service:

```bash
docker compose up
```

## With application configuration

Pass environment variables to your MCP application using the `MCP_ENV_` prefix:

```yaml
services:
  mcp:
    image: ghcr.io/drengskapur/fastmcp-runner:latest-stable
    ports:
      - "8000:8000"
    environment:
      IMAGE: ghcr.io/your-org/your-mcp-app:latest
      PORT: "8000"
      REGISTRY_USER: ${REGISTRY_USER}
      REGISTRY_PASSWORD: ${REGISTRY_PASSWORD}
      # Application configuration
      MCP_ENV_DATABASE_URL: postgres://db:5432/myapp
      MCP_ENV_REDIS_URL: redis://cache:6379
      MCP_ENV_LOG_LEVEL: info
```

## With dependent services

A complete stack with database and cache:

```yaml
services:
  mcp:
    image: ghcr.io/drengskapur/fastmcp-runner:latest-stable
    ports:
      - "8000:8000"
    environment:
      IMAGE: ghcr.io/your-org/your-mcp-app:latest
      PORT: "8000"
      REGISTRY_USER: ${REGISTRY_USER}
      REGISTRY_PASSWORD: ${REGISTRY_PASSWORD}
      MCP_ENV_DATABASE_URL: postgres://postgres:postgres@db:5432/myapp
      MCP_ENV_REDIS_URL: redis://cache:6379
    depends_on:
      db:
        condition: service_healthy
      cache:
        condition: service_started

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: myapp
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  cache:
    image: redis:7-alpine
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:
```

## Persistent data

Mount a volume to `/data` if your MCP application needs persistent storage:

```yaml
services:
  mcp:
    image: ghcr.io/drengskapur/fastmcp-runner:latest-stable
    ports:
      - "8000:8000"
    environment:
      IMAGE: ghcr.io/your-org/your-mcp-app:latest
      PORT: "8000"
    volumes:
      - mcp_data:/data

volumes:
  mcp_data:
```

## Health checks

Docker Compose can use FastMCP Runner's built-in health check:

```yaml
services:
  mcp:
    image: ghcr.io/drengskapur/fastmcp-runner:latest-stable
    ports:
      - "8000:8000"
    environment:
      IMAGE: ghcr.io/your-org/your-mcp-app:latest
      PORT: "8000"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      start_period: 60s
      retries: 3
```

Increase `start_period` for large application images that take longer to pull.

## Resource limits

Set memory and CPU limits to prevent runaway resource usage:

```yaml
services:
  mcp:
    image: ghcr.io/drengskapur/fastmcp-runner:latest-stable
    ports:
      - "8000:8000"
    environment:
      IMAGE: ghcr.io/your-org/your-mcp-app:latest
      PORT: "8000"
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 1G
        reservations:
          cpus: "0.25"
          memory: 256M
```

## Debugging

Enable verbose logging to troubleshoot startup issues:

```yaml
services:
  mcp:
    image: ghcr.io/drengskapur/fastmcp-runner:latest-stable
    environment:
      IMAGE: ghcr.io/your-org/your-mcp-app:latest
      PORT: "8000"
      LOG_LEVEL: debug
      LOG_FORMAT: text
```

View logs:

```bash
docker compose logs -f mcp
```

## Production considerations

For production deployments, consider:

**Use specific version tags** rather than `latest-stable`:

```yaml
image: ghcr.io/drengskapur/fastmcp-runner:v0.1.0
```

**Store secrets securely** using Docker secrets or an external secrets manager rather than environment variables in the compose file.

**Configure restart policies**:

```yaml
services:
  mcp:
    restart: unless-stopped
```

**Use a reverse proxy** (nginx, Traefik, Caddy) for TLS termination and load balancing rather than exposing the MCP server directly.
