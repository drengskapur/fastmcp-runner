# Contributing to fastmcp-runner

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing.

## Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](.github/CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/drengskapur/fastmcp-runner/issues)
2. If not, create a new issue using the bug report template
3. Include as much detail as possible:
   - Steps to reproduce
   - Expected behavior
   - Actual behavior
   - Environment details (OS, Docker version, etc.)

### Suggesting Features

1. Check existing [Issues](https://github.com/drengskapur/fastmcp-runner/issues) for similar suggestions
2. Create a new issue using the feature request template
3. Describe the use case and expected behavior

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Ensure your changes pass linting:
   ```bash
   docker run --rm -i hadolint/hadolint < Dockerfile
   ```
5. Commit your changes using [Conventional Commits](https://www.conventionalcommits.org/):
   ```
   feat: add new feature
   fix: resolve bug
   docs: update documentation
   chore: maintenance task
   ```
6. Push to your fork (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/fastmcp-runner.git
cd fastmcp-runner

# Build locally
docker build -t fastmcp-runner:local .

# Run linter
docker run --rm -i hadolint/hadolint < Dockerfile

# Run security scan
docker run --rm -v "$(pwd):/src:ro" aquasec/trivy:latest fs --scanners vuln,misconfig /src
```

### Testing Changes

```bash
# Build the image
docker build -t fastmcp-runner:test .

# Test with a public image (no auth required)
docker run --rm \
  -e REGISTRY=ghcr.io \
  -e REGISTRY_USER=test \
  -e REGISTRY_PASSWORD=test \
  -e IMAGE=ghcr.io/your-test-image:latest \
  -e PORT=7860 \
  -p 7860:7860 \
  fastmcp-runner:test
```

## Style Guide

### Dockerfile

- Follow [Dockerfile best practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- Use hadolint for linting
- Pin base image versions where appropriate
- Minimize layers and image size
- Document any hadolint ignores with comments

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` new feature
- `fix:` bug fix
- `docs:` documentation only
- `style:` formatting, no code change
- `refactor:` code change that neither fixes a bug nor adds a feature
- `test:` adding or updating tests
- `chore:` maintenance tasks

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
