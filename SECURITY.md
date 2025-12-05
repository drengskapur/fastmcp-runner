# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it by:

1. **DO NOT** create a public GitHub issue
2. Email security concerns to the repository maintainers
3. Or use GitHub's [private vulnerability reporting](https://github.com/drengskapur/fastmcp-runner/security/advisories/new)

We will respond within 48 hours and work with you to understand and address the issue.

## Security Measures

This project implements the following security measures:

### Container Security
- **Base Image**: Uses Chainguard's wolfi-base (hardened, minimal attack surface)
- **Non-root Execution**: Application runs as UID 1000 after initial setup
- **Credential Scrubbing**: Registry credentials are cleared before application starts
- **Minimal Packages**: Only essential packages installed (crane, su-exec, uv)

### Supply Chain Security
- **Signed Images**: All images are signed with Sigstore/Cosign
- **SBOM**: Software Bill of Materials attached to every image
- **Provenance**: SLSA provenance attestation for build verification
- **Dependency Updates**: Automated via Renovate and Dependabot

### Scanning
- **Trivy**: Vulnerability and misconfiguration scanning
- **Hadolint**: Dockerfile best practices
- **CodeQL**: Static analysis (when applicable)
- **TruffleHog**: Secret detection in code history
- **Scorecard**: OpenSSF security best practices assessment

### Workflow Token Permissions

All GitHub Actions workflows follow the principle of least privilege:

- Top-level `permissions: {}` denies all permissions by default
- Each job explicitly requests only the minimum permissions required
- Write permissions are granted only where necessary:
  - `contents: write`: Creating release tags and updating changelogs
  - `packages: write`: Publishing container images to registries
  - `actions: write`: Triggering dependent workflows (scheduled rebuilds)
  - `security-events: write`: Uploading security scan results to GitHub

## Verifying Image Signatures

```bash
# Verify signature
cosign verify ghcr.io/drengskapur/fastmcp-runner:latest \
  --certificate-identity-regexp="https://github.com/drengskapur/fastmcp-runner" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"

# Verify SBOM attestation
cosign verify-attestation ghcr.io/drengskapur/fastmcp-runner:latest \
  --type spdx \
  --certificate-identity-regexp="https://github.com/drengskapur/fastmcp-runner" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
```
