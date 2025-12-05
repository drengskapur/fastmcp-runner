# FastMCP Runner

FastMCP Runner is a bootstrap container that runs [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) servers from OCI container images. It pulls images from container registries, extracts their filesystems, and executes the MCP server—all without requiring a Docker daemon.

This design solves a specific problem: running containerized MCP applications on platforms that don't allow arbitrary Docker execution, such as Hugging Face Spaces or other serverless environments. Instead of running Docker-in-Docker or requiring privileged containers, FastMCP Runner uses [crane](https://github.com/google/go-containerregistry/tree/main/cmd/crane) to interact with registries directly and extracts only the application layer of your image.

## When to use this

FastMCP Runner is designed for a narrow use case: deploying MCP servers to environments where you control the outer container but cannot run Docker commands. If you're deploying to Kubernetes, ECS, or any platform that natively runs containers, you should run your MCP image directly rather than wrapping it in FastMCP Runner.

The typical deployment scenario looks like this: you have a private MCP application image in a container registry, and you want to run it on a platform that only allows pre-approved base images. You configure FastMCP Runner as the base image and pass your private image reference via environment variables. At startup, FastMCP Runner authenticates to your registry, pulls your image, and runs your application.

## How it works

When the container starts, FastMCP Runner performs these operations in sequence:

1. **Validates inputs** — Checks that required environment variables are present and well-formed. Invalid configurations fail immediately with descriptive errors.

2. **Authenticates to the registry** — If credentials are provided, authenticates using `crane auth login`. Credentials are cleared from the environment immediately after authentication.

3. **Fetches image configuration** — Retrieves the OCI config blob to determine the image's entrypoint, command, environment variables, and working directory.

4. **Extracts the filesystem** — Exports the image layers to a staging directory, then copies only safe paths (`/app`, `/data`, `/home`, `/opt`, site-packages) to the runtime filesystem. System directories are explicitly excluded to prevent the pulled image from overwriting critical files.

5. **Drops privileges** — Changes ownership of application directories to UID 1000 and uses `su-exec` to drop from root to a non-root user before executing the application.

6. **Executes the MCP server** — Runs the application's configured entrypoint with environment variables merged from the original image, passthrough variables (`MCP_ENV_*`), and runner configuration.

## Image tags

The project publishes images to both GitHub Container Registry and Docker Hub. The tagging scheme follows a development/production split:

| Tag | Purpose |
|-----|---------|
| `latest` | Built on every push to main. Use for development and testing. |
| `latest-stable` | Updated only when a release is created. Use for production. |
| `vX.Y.Z` | Immutable version tags. Use when you need reproducible deployments. |

Production deployments should use `latest-stable` or a specific version tag. The `latest` tag may contain unreleased changes.

## Verifying images

All published images are signed using [Sigstore cosign](https://docs.sigstore.dev/) with keyless signing. To verify an image before pulling:

```bash
cosign verify ghcr.io/drengskapur/fastmcp-runner:latest-stable \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp 'https://github.com/drengskapur/fastmcp-runner/.*'
```

Each release also includes an SBOM (Software Bill of Materials) attestation that you can verify:

```bash
cosign verify-attestation ghcr.io/drengskapur/fastmcp-runner:latest-stable \
  --type spdx \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp 'https://github.com/drengskapur/fastmcp-runner/.*'
```

## License

FastMCP Runner is released under the Apache 2.0 license.
