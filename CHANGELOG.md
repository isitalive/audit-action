# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.3.0] - 2026-03-22

### Changed

- **POST-only manifest flow** (ADR-006) — removed `GET /api/manifest/hash/:hash` CDN lookup; POST now sends `X-Manifest-Hash` header for fast-path cache lookup in a single request
- Worker checks KV cache before parsing JSON body — cache hits return in <1ms CPU
- **401 = hard failure** — authentication errors now exit with code 1, failing the CI action instead of silently skipping
- README updated: documents POST-only flow, corrected `cost-summary` output field names, notes 401 as hard error

### Removed

- GET-first CDN cache pattern — Workers always invoke (~$0.30/M), making the GET a redundant round-trip at the same cost
- `If-None-Match` / 304 handling — CI has no local cache to serve on 304; server returns 200 with cached body via `X-Manifest-Hash` instead

## [0.2.0] - 2026-03-21

### Added

- **Retry logic** for incomplete API responses — when not all deps fit in the Worker time budget, the action now retries automatically (configurable via `max-retries` and `retry-delay` inputs)
- **Cost summary** in PR comments and step summary — shows CDN cache hits ($0) vs API calls (quota) and total deps scored
- New `cost-summary` output — JSON object with `cdn_hits`, `api_posts`, `api_partial`, `total_deps_scored`
- New `max-retries` input (default: `3`) — max retries for incomplete results
- New `retry-delay` input (default: `5`) — seconds between retries (overridden by server `Retry-After` header)

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
