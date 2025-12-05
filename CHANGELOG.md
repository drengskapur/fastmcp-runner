# Changelog

All notable changes to this project will be documented in this file.
## [unreleased]

### Documentation

- Add MkDocs documentation site by @jonathanagustin
- Add Read the Docs configuration by @jonathanagustin
- Update mkdocs-material to 9.7.0 by @jonathanagustin
- Fix inaccuracies and add missing documentation by @jonathanagustin
- Add SEO optimizations for Read the Docs by @jonathanagustin

### Miscellaneous Tasks

- Remove GitHub Pages in favor of Read the Docs by @jonathanagustin
## [0.1.0] - 2025-12-05

### Bug Fixes

- Use crane auth login with stderr suppressed by @jonathanagustin
- *(entrypoint)* Send log output to stderr by @jonathanagustin
- Address security findings and workflow issues by @jonathanagustin
- *(dockerfile)* Move trivy:ignore:DS002 to file header for proper detection by @jonathanagustin
- Skip conflicting entrypoints to prevent infinite recursion (#27) by @jonathanagustin

### Documentation

- Add community files and templates by @jonathanagustin
- Update README for simplified env vars by @jonathanagustin

### Features

- Initial fastmcp-runner bootstrap container by @jonathanagustin
- Add comprehensive CI/CD with signing, attestation, SBOM, and security scanning by @jonathanagustin
- Add explicit Python 3.12 installation by @jonathanagustin
- Add build-base for native Python extensions by @jonathanagustin
- Use pre-built venv when valid, fall back to uv run by @jonathanagustin
- *(ci)* Implement D2 versioning with automatic semver by @jonathanagustin

### Miscellaneous Tasks

- Add claude settings by @jonathanagustin
- Switch to Apache 2.0 license by @jonathanagustin
- Remove redundant py3.12-pip by @jonathanagustin
- Update branch protection for trunk-based dev by @jonathanagustin
- Add trivy ignore for Chainguard :latest tag by @jonathanagustin
- Move renovate.json to repo root (idiomatic location) by @jonathanagustin
- Move community health files to repo root by @jonathanagustin
- Add markdownlint configuration by @jonathanagustin
- Ignore boilerplate markdown files from linting by @jonathanagustin
- *(security)* Add .trivyignore and enhance security documentation by @jonathanagustin

### Refactor

- Use crane inline auth to avoid credential warning by @jonathanagustin
- Chain auth, export, and cleanup in single command by @jonathanagustin

### Security

- Harden security workflow with pinned actions by @jonathanagustin
- Add OpenSSF Scorecard workflow for supply-chain security by @jonathanagustin
- Harden all workflows with pinned actions by @jonathanagustin

### Ci

- Bump github/codeql-action from 3 to 4 (#1) by @dependabot[bot]
- Bump hadolint/hadolint-action from 3.1.0 to 3.3.0 (#2) by @dependabot[bot]
- Bump actions/attest-build-provenance from 2 to 3 (#3) by @dependabot[bot]
- Bump actions/checkout from 4 to 6 (#4) by @dependabot[bot]
- Remove CodeQL workflow (no Python source code) by @jonathanagustin
- Add Docker Hub publishing by @jonathanagustin
- Add weekly scheduled rebuild for base image updates by @jonathanagustin
- Add CodeQL workflow for GitHub Actions analysis by @jonathanagustin
- Add comprehensive security scanning workflow by @jonathanagustin
- Add Renovate config validator workflow by @jonathanagustin

