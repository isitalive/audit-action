#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# IsItAlive Audit Action — main script
#
# Audits manifest files (package.json, go.mod) for dependency health.
# Uses a GET-first pattern for CDN-cached results ($0), falling back to
# authenticated POST on cache miss.
#
# Env vars (set by action.yml):
#   INPUT_FAIL_THRESHOLD  — score threshold (0 = never fail)
#   INPUT_FILES           — newline-separated manifest paths (auto-detect if empty)
#   INPUT_API_KEY         — API key for private repos
#   INPUT_API_URL         — API base URL
#   INPUT_STRATEGY        — 'cache-first' or 'fresh'
#   GITHUB_TOKEN          — GitHub token for PR comments
#   ACTIONS_ID_TOKEN_REQUEST_URL  — set by GitHub for OIDC
#   ACTIONS_ID_TOKEN_REQUEST_TOKEN — set by GitHub for OIDC
# ---------------------------------------------------------------------------

set -euo pipefail

API_URL="${INPUT_API_URL:-https://isitalive.dev}"
FAIL_THRESHOLD="${INPUT_FAIL_THRESHOLD:-0}"
STRATEGY="${INPUT_STRATEGY:-cache-first}"
ANY_BELOW_THRESHOLD="false"

# ---------------------------------------------------------------------------
# Auth — OIDC token or API key
# ---------------------------------------------------------------------------

get_auth_token() {
  # API key takes priority
  if [[ -n "${INPUT_API_KEY:-}" ]]; then
    echo "${INPUT_API_KEY}"
    return
  fi

  # Try GitHub Actions OIDC (zero-config for public repos)
  if [[ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" && -n "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]]; then
    local oidc_token
    oidc_token=$(curl -sS -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
      "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=https://isitalive.dev" \
      | jq -r '.value // empty')
    if [[ -n "${oidc_token}" ]]; then
      echo "${oidc_token}"
      return
    fi
  fi

  echo ""
}

AUTH_TOKEN=$(get_auth_token)

# ---------------------------------------------------------------------------
# Find manifest files
# ---------------------------------------------------------------------------

find_manifests() {
  if [[ -n "${INPUT_FILES:-}" ]]; then
    echo "${INPUT_FILES}"
  else
    # Auto-detect in repo root
    local found=""
    for f in package.json go.mod; do
      if [[ -f "$f" ]]; then
        found="${found}${f}"$'\n'
      fi
    done
    echo "${found}"
  fi
}

MANIFESTS=$(find_manifests | grep -v '^$' || true)

if [[ -z "${MANIFESTS}" ]]; then
  echo "::notice::No manifest files found (package.json, go.mod). Nothing to audit."
  exit 0
fi

# ---------------------------------------------------------------------------
# Detect manifest format from filename
# ---------------------------------------------------------------------------

detect_format() {
  local file="$1"
  local basename
  basename=$(basename "$file")
  case "$basename" in
    package.json)       echo "package.json" ;;
    go.mod)             echo "go.mod" ;;
    *)
      echo "::warning::Unsupported manifest format: $basename (skipping)"
      echo ""
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Audit each manifest
# ---------------------------------------------------------------------------

MARKDOWN_REPORT=""
EXIT_CODE=0

while IFS= read -r FILE; do
  [[ -z "$FILE" ]] && continue
  [[ ! -f "$FILE" ]] && { echo "::warning::File not found: $FILE (skipping)"; continue; }

  FORMAT=$(detect_format "$FILE")
  [[ -z "$FORMAT" ]] && continue

  CONTENT=$(cat "$FILE")
  HASH=$(echo -n "$CONTENT" | sha256sum | cut -d' ' -f1)

  echo "::group::Auditing $FILE (hash: ${HASH:0:12}...)"

  RESULT=""
  SOURCE=""

  # ── Strategy: cache-first → try GET, then POST ──────────────────────
  if [[ "$STRATEGY" == "cache-first" ]]; then
    GET_RESPONSE=$(curl -sS -w "\n%{http_code}" \
      "${API_URL}/api/manifest/hash/${HASH}" 2>/dev/null || true)
    GET_STATUS=$(echo "$GET_RESPONSE" | tail -1)
    GET_BODY=$(echo "$GET_RESPONSE" | sed '$d')

    if [[ "$GET_STATUS" == "200" ]]; then
      echo "✅ CDN cache hit — $0 cost"
      RESULT="$GET_BODY"
      SOURCE="cdn-hit"
    fi
  fi

  # ── POST (on cache miss or 'fresh' strategy) ────────────────────────
  if [[ -z "$RESULT" ]]; then
    if [[ -z "$AUTH_TOKEN" ]]; then
      echo "::error::Authentication required for POST /api/manifest. Set 'api-key' input or enable OIDC with 'permissions: id-token: write'."
      exit 1
    fi

    POST_BODY=$(jq -nc --arg format "$FORMAT" --arg content "$CONTENT" \
      '{format: $format, content: $content}')

    POST_RESPONSE=$(curl -sS -w "\n%{http_code}" \
      -X POST "${API_URL}/api/manifest" \
      -H "Authorization: Bearer ${AUTH_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$POST_BODY" 2>/dev/null || true)
    POST_STATUS=$(echo "$POST_RESPONSE" | tail -1)
    POST_BODY_RESP=$(echo "$POST_RESPONSE" | sed '$d')

    if [[ "$POST_STATUS" == "200" ]]; then
      echo "📊 Scored via API"
      RESULT="$POST_BODY_RESP"
      SOURCE="api"
    elif [[ "$POST_STATUS" == "304" ]]; then
      echo "✅ ETag match — manifest unchanged"
      MARKDOWN_REPORT+=$'\n'"**$FILE** — unchanged (ETag match)"
      echo "::endgroup::"
      continue
    elif [[ "$POST_STATUS" == "429" ]]; then
      echo "::warning::Rate limit or quota exceeded for $FILE"
      echo "$POST_BODY_RESP" | jq . 2>/dev/null || echo "$POST_BODY_RESP"
      echo "::endgroup::"
      continue
    else
      echo "::error::API error ($POST_STATUS) auditing $FILE"
      echo "$POST_BODY_RESP" | jq . 2>/dev/null || echo "$POST_BODY_RESP"
      echo "::endgroup::"
      continue
    fi
  fi

  # ── Parse results and build report ──────────────────────────────────
  SCORED=$(echo "$RESULT" | jq -r '.scored // 0')
  TOTAL=$(echo "$RESULT" | jq -r '.total // 0')
  AVG_SCORE=$(echo "$RESULT" | jq -r '.summary.avgScore // 0')

  # Build dependency table
  DEP_TABLE=$(echo "$RESULT" | jq -r '
    .dependencies[]
    | select(.score != null)
    | "| \(.name) | \(.score) | \(
        if .score >= 80 then "✅ healthy"
        elif .score >= 60 then "🟡 stable"
        elif .score >= 40 then "⚠️ degraded"
        elif .score >= 20 then "🔴 critical"
        else "💀 unmaintained"
        end
      ) | [\(.github // "—")](https://isitalive.dev/github/\(.github // "")) |"
  ' 2>/dev/null || echo "| (no scored deps) | — | — | — |")

  FILE_REPORT="### \`$FILE\` (avg: ${AVG_SCORE}, ${SCORED}/${TOTAL} scored, source: ${SOURCE})

| Dependency | Score | Verdict | Details |
|-----------|-------|---------|---------
${DEP_TABLE}
"
  MARKDOWN_REPORT+=$'\n'"$FILE_REPORT"

  # ── Check threshold ─────────────────────────────────────────────────
  if [[ "$FAIL_THRESHOLD" -gt 0 ]]; then
    BELOW=$(echo "$RESULT" | jq -r \
      --argjson threshold "$FAIL_THRESHOLD" \
      '[.dependencies[] | select(.score != null and .score < $threshold)] | length')
    if [[ "$BELOW" -gt 0 ]]; then
      ANY_BELOW_THRESHOLD="true"
      echo "::warning::$BELOW dependencies scored below threshold ($FAIL_THRESHOLD)"
      EXIT_CODE=1
    fi
  fi

  echo "::endgroup::"
done <<< "$MANIFESTS"

# ---------------------------------------------------------------------------
# Post PR comment (if in a pull request context)
# ---------------------------------------------------------------------------

if [[ -n "${GITHUB_EVENT_NAME:-}" && "$GITHUB_EVENT_NAME" == "pull_request" ]]; then
  PR_NUMBER=$(jq -r '.pull_request.number' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "")

  if [[ -n "$PR_NUMBER" && "$PR_NUMBER" != "null" ]]; then
    COMMENT_BODY="## 🔍 IsItAlive — Dependency Health Report
${MARKDOWN_REPORT}

---
*[Powered by IsItAlive](https://isitalive.dev) • [View action](https://github.com/isitalive/audit-action)*"

    # Find existing comment by the bot to update instead of duplicating
    EXISTING_COMMENT_ID=$(curl -sS \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
      | jq -r '[.[] | select(.body | contains("IsItAlive — Dependency Health Report"))] | last | .id // empty')

    COMMENT_JSON=$(jq -nc --arg body "$COMMENT_BODY" '{body: $body}')

    if [[ -n "$EXISTING_COMMENT_ID" ]]; then
      # Update existing comment
      curl -sS -X PATCH \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY}/issues/comments/${EXISTING_COMMENT_ID}" \
        -d "$COMMENT_JSON" > /dev/null
      echo "Updated existing PR comment #${EXISTING_COMMENT_ID}"
    else
      # Create new comment
      curl -sS -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
        -d "$COMMENT_JSON" > /dev/null
      echo "Posted new PR comment"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Write summary to GITHUB_STEP_SUMMARY
# ---------------------------------------------------------------------------

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "## 🔍 IsItAlive — Dependency Health Report" >> "$GITHUB_STEP_SUMMARY"
  echo "${MARKDOWN_REPORT}" >> "$GITHUB_STEP_SUMMARY"
fi

# ---------------------------------------------------------------------------
# Set outputs
# ---------------------------------------------------------------------------

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "summary<<EOF"
    echo "${MARKDOWN_REPORT}"
    echo "EOF"
    echo "any-below-threshold=${ANY_BELOW_THRESHOLD}"
  } >> "$GITHUB_OUTPUT"
fi

exit "$EXIT_CODE"
