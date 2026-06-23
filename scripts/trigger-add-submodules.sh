#!/usr/bin/env bash
# Trigger the GitHub Actions workflow add-submodules.yml via repository_dispatch.
#
# Branch/endpoint naming constants: LOCAL_BRANCH_PREFIX, TRANSLATION_BRANCH_PREFIX,
# MASTER_BRANCH in .github/workflows/assets/env.sh.
#
# Requires: curl; jq or Python 3 (python3 / python) to build JSON
# Auth: repo-root .env (GH_TOKEN / GITHUB_TOKEN), env, or --token (repo scope for the target repo).
#
# Usage:
#   scripts/trigger-add-submodules.sh [--repo OWNER/NAME] [--token PAT] \
#     [--version REF] [--submodules 'a, b'] [--lang-codes zh_Hans,ja]
#
# If --repo is omitted: GITHUB_REPOSITORY, then DEFAULT_REPO below, then git origin.

set -euo pipefail

_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$_REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$_REPO_ROOT/.env"
  set +a
fi
_ASSETS_DIR="$_REPO_ROOT/.github/workflows/assets"
# shellcheck source=/dev/null
source "$_ASSETS_DIR/env.sh"
# shellcheck source=/dev/null
source "$_ASSETS_DIR/lib.sh"
unset _REPO_ROOT _ASSETS_DIR

# ---------------------------------------------------------------------------
# Typical run — edit these. CLI flags override (except --token uses env/PAT).
# ---------------------------------------------------------------------------
DEFAULT_REPO="cppalliance/boost-docs-translation"
DEFAULT_VERSION="boost-1.90.0"
DEFAULT_SUBMODULES="unordered, json"

usage() {
  cat <<'EOF'
Trigger add-submodules.yml via repository_dispatch (POST .../dispatches).

Usage:
  scripts/trigger-add-submodules.sh [--repo OWNER/NAME] [--token PAT] \
    [--version REF] [--submodules 'a, b'] [--lang-codes zh_Hans,ja]

Requires: curl; jq or Python 3 (python3 / python)
Auth: .env (GH_TOKEN), GH_TOKEN / GITHUB_TOKEN in env, or --token (needs repo scope on the target).

Options:
  --repo OWNER/REPO     Target repository (default: GITHUB_REPOSITORY, then DEFAULT_REPO, then origin)
  --token PAT           GitHub token
  --version REF         Boost ref; default DEFAULT_VERSION in script
  --submodules LIST     default DEFAULT_SUBMODULES in script
  --lang-codes CSV      optional; omit → workflow uses repo vars.LANG_CODES
EOF
}

REPO=""
TOKEN=""
VERSION=""
SUBMODULES=""
LANG_CODES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"; shift 2 || exit 1 ;;
    --token)
      TOKEN="${2:-}"; shift 2 || exit 1 ;;
    --version)
      VERSION="${2:-}"; shift 2 || exit 1 ;;
    --submodules)
      SUBMODULES="${2:-}"; shift 2 || exit 1 ;;
    --lang-codes)
      LANG_CODES="${2:-}"; shift 2 || exit 1 ;;
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
  local version="$1" submodules="$2" lang_codes="$3"
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg event_type "$EVENT_ADD_SUBMODULES" \
      --arg version "$version" \
      --arg submodules "$submodules" \
      --arg lang_codes "$lang_codes" \
      '{
        event_type: $event_type,
        client_payload: (
          {}
          | if ($version | length) > 0 then . + {version: $version} else . end
          | if ($submodules | length) > 0 then . + {submodules: $submodules} else . end
          | if ($lang_codes | length) > 0 then . + {lang_codes: $lang_codes} else . end
        )
      }'
    return 0
  fi
  local py=""
  command -v python3 >/dev/null 2>&1 && py="python3"
  [[ -z "$py" ]] && command -v python >/dev/null 2>&1 && py="python"
  if [[ -n "$py" ]]; then
    "$py" -c "import json,sys; et,v,s,lc=sys.argv[1:5]; d={k:x for k,x in (('version',v),('submodules',s),('lang_codes',lc)) if x}; print(json.dumps({'event_type':et,'client_payload':d}))" \
      "$EVENT_ADD_SUBMODULES" "$version" "$submodules" "$lang_codes"
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
SUBMODULES="${SUBMODULES:-$DEFAULT_SUBMODULES}"

validate_event_type "$EVENT_ADD_SUBMODULES"

body="$(dispatch_json "$VERSION" "$SUBMODULES" "$LANG_CODES")" || {
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
  echo "Dispatched add-submodules to ${REPO} (HTTP ${code})."
  exit 0
fi

echo "GitHub API error: HTTP ${code}" >&2
if [[ -s "$resp" ]]; then
  cat "$resp" >&2
fi
exit 1
