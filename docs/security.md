---
title: Security Model
description: FastMCP Runner security architecture including credential handling, privilege separation, filesystem isolation, and supply chain security with Sigstore signing.
---

# Security

FastMCP Runner handles sensitive operations—registry credentials, arbitrary code execution, privilege management—and implements several controls to mitigate associated risks. This document explains the security model and helps you evaluate whether it meets your requirements.

## Threat model

FastMCP Runner is designed to run images you control in environments where you trust the orchestration layer but want defense in depth. The security controls protect against:

- **Credential leakage**: Registry passwords appearing in logs, environment, or the running application
- **Privilege escalation**: The pulled application gaining root access or modifying system files
- **Supply chain attacks**: Running tampered images without detection

The model assumes you trust the images you configure via `IMAGE`. If an attacker can modify that variable, they can run arbitrary code. FastMCP Runner does not sandbox untrusted images—it runs them with network access and filesystem writes to application directories.

## Credential handling

Registry credentials follow a strict lifecycle:

1. **Authentication**: `REGISTRY_USER` and `REGISTRY_PASSWORD` authenticate to the registry via `crane auth login`
2. **Immediate clearing**: After authentication, credentials are cleared from the environment and the Docker config directory is deleted
3. **Launcher generation**: The generated launcher script does not include credentials
4. **Application execution**: Your application never sees `REGISTRY_PASSWORD`

This prevents credentials from appearing in `/proc/*/environ`, being logged by your application, or persisting in container layers.

```bash
# In the entrypoint, after authentication:
rm -rf "${HOME}/.docker" 2>/dev/null || true
REGISTRY_PASSWORD=''; export REGISTRY_PASSWORD
```

## Filesystem isolation

When extracting the pulled image, FastMCP Runner copies only application-related paths:

```
/app          # Application code
/data         # Persistent data
/home         # User directories
/opt          # Optional packages
/srv          # Service data
/var/lib      # Application state
/var/data     # Application data
```

Python site-packages and Node.js node_modules are also copied from their standard locations.

System directories are explicitly excluded:

```
/bin, /sbin           # System binaries
/lib, /lib64          # System libraries
/usr/bin, /usr/sbin   # System utilities
/etc                  # System configuration
/boot, /root          # Protected directories
```

This allowlist prevents a pulled image from replacing the runner's own scripts, injecting malicious binaries into system paths, or modifying configuration files. Even if an attacker controls the image contents, they cannot overwrite `/entrypoint.sh` or `/usr/local/bin/parse-oci-config`.

## Privilege separation

The container starts as root because it needs to:

- Create directories with appropriate ownership
- Set permissions on extracted files
- Execute `su-exec` to drop privileges

Before running your application, the runner drops to UID 1000 using `su-exec`. This is a non-root user created during image build with no special capabilities.

Your application runs as this unprivileged user and cannot:

- Bind to ports below 1024 (not typically needed for MCP)
- Modify system files
- Access other users' files
- Change system configuration

## Image verification

All FastMCP Runner images are signed using [Sigstore cosign](https://docs.sigstore.dev/) with keyless signing. The signature attests that the image was built by GitHub Actions from this repository.

Verify before pulling:

```bash
cosign verify ghcr.io/drengskapur/fastmcp-runner:latest-stable \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp 'https://github.com/drengskapur/fastmcp-runner/.*'
```

Each image also has an SBOM (Software Bill of Materials) attestation listing all packages:

```bash
cosign verify-attestation ghcr.io/drengskapur/fastmcp-runner:latest-stable \
  --type spdx \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp 'https://github.com/drengskapur/fastmcp-runner/.*'
```

## Supply chain security

The build pipeline implements several supply chain controls:

**Pinned dependencies**: All GitHub Actions in the CI workflows are pinned to specific commit SHAs, not mutable tags. This prevents a compromised action from affecting builds.

**Base image pinning**: The Dockerfile pins the base image to a SHA256 digest rather than a mutable tag:

```dockerfile
FROM cgr.dev/chainguard/wolfi-base@sha256:42012fa...
```

**SLSA provenance**: Build provenance attestations are generated and attached to images, providing a verifiable record of how the image was built.

**Automated updates**: Renovate automatically creates pull requests for dependency updates, keeping the image current with security patches.

## Security scanning

The repository runs multiple security scanners on every push:

- **Trivy**: Scans for vulnerabilities in OS packages and misconfigurations in the Dockerfile
- **Hadolint**: Lints the Dockerfile against best practices
- **TruffleHog**: Scans for accidentally committed secrets
- **OpenSSF Scorecard**: Evaluates supply chain security practices

Scan results are uploaded to GitHub's Security tab and visible in pull requests.

## Reporting vulnerabilities

If you discover a security vulnerability, report it through [GitHub's private vulnerability reporting](https://github.com/drengskapur/fastmcp-runner/security/advisories/new). Do not open a public issue.

We aim to respond within 48 hours and will work with you to understand the issue before any public disclosure.

## What this does not protect against

FastMCP Runner is not a sandbox. It does not protect against:

- **Malicious images you configure**: If you set `IMAGE` to a malicious image, that code runs with full application-level access
- **Network-based attacks**: Your application has unrestricted network access
- **Resource exhaustion**: No CPU, memory, or disk limits are enforced by the runner (configure these in your orchestration layer)
- **Vulnerabilities in your application**: The runner executes your code as provided

For untrusted workloads, consider additional isolation at the orchestration layer—separate namespaces, network policies, resource quotas, and runtime security tools like Falco or gVisor.
