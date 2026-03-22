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
| `api-key` | No | — | API key (required for private repos) |
| `strategy` | No | `cache-first` | `cache-first` or `fresh` |

## Outputs

| Output | Description |
|--------|-------------|
| `summary` | Markdown summary of audit results |
| `any-below-threshold` | `true` if any dep scored below threshold |

## How It Works

1. **Hashes** each manifest file locally (SHA-256)
2. **Tries GET** `/api/manifest/hash/{hash}` — served from CDN edge ($0 on hit)
3. **On 404** — POSTs the manifest to `/api/manifest` for scoring (auth required)
4. **Posts/updates** a PR comment with the health report
5. **Fails** the check if any dependency scores below the configured threshold

The GET-first pattern means if the same manifest was scored before (by anyone, globally), you get an instant CDN-cached result at zero cost.

## Caching Strategy

| Strategy | Behavior | Cost | Freshness |
|----------|----------|------|-----------|
| `cache-first` (default) | GET cache → POST on miss | Lowest | Up to 7 days |
| `fresh` | Always POST, skip cache | Uses quota | Tier-based (1h for free) |

## Requirements

- `jq` and `curl` — pre-installed on all GitHub-hosted runners
- `sha256sum` — pre-installed on Ubuntu runners (use `shasum -a 256` on macOS)

## License

[MIT](LICENSE)
