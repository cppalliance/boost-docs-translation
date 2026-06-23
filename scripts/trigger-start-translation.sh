#!/usr/bin/env bash
# Trigger the GitHub Actions workflow start-translation.yml via repository_dispatch.
#
# Branch/endpoint naming constants: WEBLATE_ENDPOINT_PATH, LOCAL_BRANCH_PREFIX,
# TRANSLATION_BRANCH_PREFIX, MASTER_BRANCH in .github/workflows/assets/env.sh.
#
# Requires: curl; jq or Python 3 (python3 / python) to build JSON
# Auth: repo-root .env (GH_TOKEN / GITHUB_TOKEN), env, or --token (repo scope for the target repo).
#
# Usage:
#   scripts/trigger-start-translation.sh [--repo OWNER/NAME] [--token PAT] \
#     [--version REF] [--lang-codes zh_Hans,ja] [--extensions '.adoc, .qbk']
#
# If --repo is omitted: GITHUB_REPOSITORY, then DEFAULT_REPO below, then git origin.
#
# The workflow still needs repo secrets SYNC_TOKEN, WEBLATE_URL, WEBLATE_TOKEN (and
# vars.LANG_CODES or lang_codes in the payload).

set -euo pipefail

_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$_REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$_REPO_ROOT/.env"
  set +a
fi
# shellcheck source=/dev/null
source "$_REPO_ROOT/.github/workflows/assets/env.sh"
unset _REPO_ROOT

# ---------------------------------------------------------------------------
# Typical run — edit defaults below. CLI flags override.
# Omit lang_codes in payload when unset → workflow vars.LANG_CODES.
# Set DEFAULT_VERSION="" to omit version from payload → workflow uses develop.
# Extensions default to .adoc and .qbk; set DEFAULT_EXTENSIONS="" to omit from payload.
# ---------------------------------------------------------------------------
DEFAULT_REPO="cppalliance/boost-docs-translation"
DEFAULT_VERSION="boost-1.90.0"
DEFAULT_EXTENSIONS=".adoc, .qbk"

usage() {
  cat <<'EOF'
Trigger start-translation.yml via repository_dispatch (POST .../dispatches).

Usage:
  scripts/trigger-start-translation.sh [--repo OWNER/NAME] [--token PAT] \
    [--version REF] [--lang-codes zh_Hans,ja] [--extensions '.adoc, .qbk']

Requires: curl; jq or Python 3 (python3 / python)
Auth: .env (GH_TOKEN), GH_TOKEN / GITHUB_TOKEN in env, or --token (needs repo scope on the target).

Options:
  --repo OWNER/REPO     Target repository (default: GITHUB_REPOSITORY, then DEFAULT_REPO, then origin)
  --token PAT           GitHub token
  --version REF       Boost ref; default DEFAULT_VERSION in script (clear default to omit → develop)
  --lang-codes CSV    optional; omit → workflow uses repo vars.LANG_CODES
  --extensions LIST   default DEFAULT_EXTENSIONS (.adoc, .qbk); clear default in script to omit
EOF
}

REPO=""
TOKEN=""
VERSION=""
LANG_CODES=""
EXTENSIONS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"; shift 2 || exit 1 ;;
    --token)
      TOKEN="${2:-}"; shift 2 || exit 1 ;;
    --version)
      VERSION="${2:-}"; shift 2 || exit 1 ;;
    --lang-codes)
      LANG_CODES="${2:-}"; shift 2 || exit 1 ;;
    --extensions)
      EXTENSIONS="${2:-}"; shift 2 || exit 1 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1 ;;
  esac
done

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl is required" >&2
  exit 1
fi

# Emit repository_dispatch JSON on stdout (jq preferred, else Python).
dispatch_json() {
  local version="$1" lang_codes="$2" extensions="$3"
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg version "$version" \
      --arg lang_codes "$lang_codes" \
      --arg extensions "$extensions" \
      '{
        event_type: "start-translation",
        client_payload: (
          {}
          | if ($version | length) > 0 then . + {version: $version} else . end
          | if ($lang_codes | length) > 0 then . + {lang_codes: $lang_codes} else . end
          | if ($extensions | length) > 0 then . + {extensions: $extensions} else . end
        )
      }'
    return 0
  fi
  local py=""
  command -v python3 >/dev/null 2>&1 && py="python3"
  [[ -z "$py" ]] && command -v python >/dev/null 2>&1 && py="python"
  if [[ -n "$py" ]]; then
    "$py" -c "import json,sys; v,lc,ex=sys.argv[1:4]; d={k:x for k,x in (('version',v),('lang_codes',lc),('extensions',ex)) if x}; print(json.dumps({'event_type':'start-translation','client_payload':d}))" \
      "$version" "$lang_codes" "$extensions"
    return 0
  fi
  return 1
}

TOKEN="${TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}"
if [[ -z "$TOKEN" ]]; then
  echo "error: set GH_TOKEN (e.g. in repo-root .env), GITHUB_TOKEN, or pass --token" >&2
  exit 1
fi

infer_repo_from_git() {
  local url root o r
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  url="$(git -C "$root" remote get-url origin 2>/dev/null)" || return 1
  if [[ "$url" =~ github\.com[:/]([^/]+)/([^[:space:]]+) ]]; then
    o="${BASH_REMATCH[1]}"
    r="${BASH_REMATCH[2]}"
    r="${r%.git}"
    r="${r%/}"
    echo "${o}/${r}"
    return 0
  fi
  return 1
}

if [[ -z "$REPO" ]]; then
  REPO="${GITHUB_REPOSITORY:-}"
fi
if [[ -z "$REPO" ]]; then
  REPO="${DEFAULT_REPO:-}"
fi
if [[ -z "$REPO" ]]; then
  REPO="$(infer_repo_from_git)" || {
    echo "error: could not determine repo; set DEFAULT_REPO, GITHUB_REPOSITORY, or --repo OWNER/REPO" >&2
    exit 1
  }
fi

VERSION="${VERSION:-$DEFAULT_VERSION}"
EXTENSIONS="${EXTENSIONS:-$DEFAULT_EXTENSIONS}"

body="$(dispatch_json "$VERSION" "$LANG_CODES" "$EXTENSIONS")" || {
  echo "error: install jq, or Python 3 (python3 or python on PATH), to build the request JSON" >&2
  exit 1
}

resp="$(mktemp)"
trap 'rm -f "$resp"' EXIT

url="https://api.github.com/repos/${REPO}/dispatches"
code="$(
  curl -sS -o "$resp" -w '%{http_code}' \
    -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    -d "$body" \
    "$url"
)"

if [[ "$code" == "204" ]]; then
  echo "Dispatched start-translation to ${REPO} (HTTP ${code})."
  exit 0
fi

echo "GitHub API error: HTTP ${code}" >&2
if [[ -s "$resp" ]]; then
  cat "$resp" >&2
fi
exit 1
