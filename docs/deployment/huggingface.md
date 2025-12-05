---
title: Deploy MCP Servers to Hugging Face Spaces
description: Step-by-step guide to deploying Model Context Protocol servers on Hugging Face Spaces using FastMCP Runner. Run private container images without Docker.
---

# Hugging Face Spaces

Hugging Face Spaces provides free hosting for machine learning demos and applications. Docker Spaces allow you to run custom containers, but with restrictions—you cannot run Docker commands inside your container. FastMCP Runner works around this limitation by pulling your MCP application at the OCI layer.

## Prerequisites

Before deploying to Hugging Face Spaces, you need:

1. A Hugging Face account
2. Your MCP application packaged as a container image
3. The image pushed to a container registry (GitHub Container Registry, Docker Hub, or Hugging Face's own registry)
4. Registry credentials if the image is private

## Creating a Space

Create a new Space at [huggingface.co/new-space](https://huggingface.co/new-space). Select "Docker" as the SDK.

In your Space's repository, create a `Dockerfile` that uses FastMCP Runner as the base:

```dockerfile
FROM ghcr.io/drengskapur/fastmcp-runner:latest-stable

# Hugging Face Spaces expects port 7860
ENV PORT=7860
```

That's the entire Dockerfile. The rest is configured through environment variables.

## Configuring secrets

Your Space needs credentials to pull your private MCP image. In the Space settings, add these secrets:

| Secret | Value |
|--------|-------|
| `REGISTRY_USER` | Your registry username |
| `REGISTRY_PASSWORD` | Your registry password or token |
| `IMAGE` | Full image reference (e.g., `ghcr.io/your-org/your-mcp-app:latest`) |

For GitHub Container Registry, create a personal access token with `read:packages` scope. For Docker Hub, use an access token.

Secrets are injected as environment variables when your Space runs. They are not visible in logs or to other users.

## Passing application configuration

If your MCP application needs additional configuration, add those as secrets with the `MCP_ENV_` prefix:

| Secret | Purpose |
|--------|---------|
| `MCP_ENV_API_KEY` | Passed to your app as `API_KEY` |
| `MCP_ENV_DATABASE_URL` | Passed to your app as `DATABASE_URL` |

## Example repository structure

A minimal Hugging Face Space for FastMCP Runner:

```
your-space/
├── Dockerfile
└── README.md
```

The `Dockerfile`:

```dockerfile
FROM ghcr.io/drengskapur/fastmcp-runner:latest-stable
ENV PORT=7860
```

The `README.md` (required for Spaces):

```markdown
---
title: My MCP Server
emoji: 🔧
colorFrom: blue
colorTo: indigo
sdk: docker
pinned: false
---

MCP server running via FastMCP Runner.
```

## Hardware tiers

Hugging Face Spaces offers several hardware tiers. The free tier works for many MCP applications:

| Tier | CPU | Memory | Cost |
|------|-----|--------|------|
| CPU Basic | 2 vCPU | 16 GB | Free |
| CPU Upgrade | 8 vCPU | 32 GB | $0.03/hr |

GPU tiers are available but typically unnecessary for MCP servers unless your application performs inference.

## Persistent storage

Hugging Face Spaces provides a `/data` directory that persists across restarts. FastMCP Runner extracts your application's `/data` directory here if it exists.

To use persistent storage, ensure your MCP application writes state to `/data` rather than other locations.

## Troubleshooting

**Space fails to start**

Check the build logs in the Space's "Logs" tab. Common issues:

- Missing or incorrect secrets
- Invalid image reference
- Authentication failures

Enable debug logging by adding `LOG_LEVEL=debug` as a Space secret.

**Application crashes after startup**

If FastMCP Runner starts but your application fails, the issue is likely in your application's configuration. Check that:

- All required environment variables are set as `MCP_ENV_*` secrets
- Your application's health check endpoint matches `HEALTHCHECK_PATH` (default: `/health`)
- Your application binds to `0.0.0.0`, not `localhost`

**Slow startup**

Large application images take longer to pull and extract. Optimize your image size by:

- Using multi-stage builds
- Excluding development dependencies
- Minimizing layer count

The free tier has limited bandwidth; startup may be faster on paid tiers.

## Updating your application

When you push a new version of your MCP application image, restart the Space to pull the latest:

1. Go to your Space's settings
2. Click "Restart Space" under "Factory reboot"

The Space will pull the latest image matching your `IMAGE` reference on next startup.
