# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0] - 2026-03-21

### Added

- Initial release of `isitalive/audit-action`
- Composite GitHub Action for dependency health auditing in CI
- **Zero-config OIDC authentication** for public repos — no API key needed
- API key support for private repos via `api-key` input
- `cache-first` strategy: GET cached results from CDN ($0 on hit), POST only on miss
- `fresh` strategy: always POST for tier-fresh data
- Auto-detection of `package.json` and `go.mod` in repo root
- Configurable `fail-threshold` to fail the check on low-scoring dependencies
- PR comment with dependency health report (creates or updates)
- `GITHUB_STEP_SUMMARY` integration for workflow run summaries
- Action outputs: `summary` (markdown) and `any-below-threshold` (boolean)
- MIT license
