# IsItAlive — Audit Action

**Audit your dependencies for health, activity, and maintenance status on every PR.**

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Usage

### Public repos (zero config — GitHub OIDC)

No API key needed. The action uses GitHub's built-in OIDC tokens for authentication.

```yaml
name: Dependency Audit
on: [pull_request]

jobs:
  audit:
    runs-on: ubuntu-latest
    permissions:
      id-token: write        # Required for OIDC token
      pull-requests: write   # Required for PR comments
    steps:
      - uses: actions/checkout@v6

      - uses: isitalive/audit-action@v1
        with:
          fail-threshold: 20  # Fail if any dep scores below 20
```

### Private repos (API key)

```yaml
name: Dependency Audit
on: [pull_request]

jobs:
  audit:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
    steps:
      - uses: actions/checkout@v6

      - uses: isitalive/audit-action@v1
        with:
          api-key: ${{ secrets.ISITALIVE_API_KEY }}
          fail-threshold: 20
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `fail-threshold` | No | `0` | Fail if any dep scores below this (0 = never fail) |
| `files` | No | auto-detect | Newline-separated list of manifest files |
| `api-key` | No | — | API key for private repos (optional — OIDC works for public repos) |
| `strategy` | No | `cache-first` | `cache-first` or `fresh` |
| `max-retries` | No | `3` | Max retries for incomplete results (some deps still computing) |
| `retry-delay` | No | `5` | Seconds between retries (overridden by server `Retry-After`) |

## Outputs

| Output | Description |
|--------|-------------|
| `summary` | Markdown summary of audit results |
| `any-below-threshold` | `true` if any dep scored below threshold |

## What You Get

The action posts a PR comment like:

> ## 🔍 IsItAlive — Dependency Health Report
>
> [![IsItAlive](https://isitalive.dev/api/badge/github/your-org/your-repo)](https://isitalive.dev/github/your-org/your-repo)
>
> ### `package.json` — Score: 91/100 (7 dependencies)
>
> | Dependency | Score | Verdict | Details |
> |-----------|-------|---------|--------|
> | hono | 88 | ✅ healthy | [honojs/hono](https://isitalive.dev/github/honojs/hono) |

The badge links to your repo's full health report on [isitalive.dev](https://isitalive.dev).

## How It Works

1. **Hashes** each manifest file locally (SHA-256)
2. **POSTs** to `/api/manifest` with `X-Manifest-Hash` header — the server checks its cache before parsing the body (<1ms CPU on cache hits)
3. **On cache miss** — server parses and scores the manifest, returning results
4. **Posts/updates** a PR comment with the health report and repo badge
5. **Fails** the check if any dependency scores below the configured threshold

If no OIDC token or API key is available, the action posts a helpful notice and skips the manifest (instead of failing the workflow).

## Caching Strategy

| Strategy | Behavior | Freshness |
|----------|----------|-----------|
| `cache-first` (default) | POST with hash header → server checks cache | Up to 7 days |
| `fresh` | Always POST, skip cache | Latest data |

## Requirements

- `jq` and `curl` — pre-installed on all GitHub-hosted runners
- `sha256sum` — pre-installed on Ubuntu runners (use `shasum -a 256` on macOS)

## License

[MIT](LICENSE)
