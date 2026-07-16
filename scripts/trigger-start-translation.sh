#!/usr/bin/env bash
# Trigger the GitHub Actions workflow start-translation.yml via repository_dispatch.
#
# Branch/endpoint naming constants: WEBLATE_ENDPOINT_PATH, LOCAL_BRANCH_PREFIX,
# TRANSLATION_BRANCH_PREFIX, MASTER_BRANCH in .github/workflows/assets/env.sh.
#
# Requires: curl; jq or Python 3 (python3 / python) to build JSON
# Auth: repo-root .env (GH_TOKEN / GITHUB_TOKEN), env, or --token (repo scope for the target repo).
#
# Exit codes: 0 = success (including --help), 1 = any error. Does not use the asset-script
# 0/1/2 batch convention (see docs/ARCHITECTURE.md §6).
#
# Usage:
#   scripts/trigger-start-translation.sh [--repo OWNER/NAME] [--token PAT] \
#     [--version REF] [--lang-codes zh_Hans,ja] [--extensions '.adoc, .qbk']
#
# If --repo is omitted: GITHUB_REPOSITORY, then git origin, then DEFAULT_REPO below.
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
_ASSETS_DIR="$_REPO_ROOT/.github/workflows/assets"
# shellcheck source=/dev/null
source "$_ASSETS_DIR/env.sh"
# shellcheck source=/dev/null
source "$_ASSETS_DIR/lib.sh"
# shellcheck source=/dev/null
source "$_REPO_ROOT/scripts/trigger-dispatch-common.sh"
unset _REPO_ROOT _ASSETS_DIR

# ---------------------------------------------------------------------------
# Typical run — edit defaults below. CLI flags override.
# Omit lang_codes in payload when unset → workflow vars.LANG_CODES.
# Set DEFAULT_VERSION="" to omit version from payload → workflow uses develop.
# Extensions default to .adoc and .qbk; set DEFAULT_EXTENSIONS="" to omit from payload.
# ---------------------------------------------------------------------------
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
  --repo OWNER/REPO     Target repository (default: GITHUB_REPOSITORY, then origin, then DEFAULT_REPO)
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

require_curl || exit 1

TOKEN="$(resolve_trigger_token "$TOKEN")" || exit 1

REPO="$(resolve_trigger_repo "$REPO")" || {
  echo "error: could not determine repo; set DEFAULT_REPO, GITHUB_REPOSITORY, or --repo OWNER/REPO" >&2
  exit 1
}

VERSION="${VERSION:-$DEFAULT_VERSION}"
EXTENSIONS="${EXTENSIONS:-$DEFAULT_EXTENSIONS}"

validate_event_type "$EVENT_START_TRANSLATION"

body="$(build_dispatch_json "$EVENT_START_TRANSLATION" \
  version "$VERSION" lang_codes "$LANG_CODES" extensions "$EXTENSIONS")" || {
  echo "error: install jq, or Python 3 (python3 or python on PATH), to build the request JSON" >&2
  exit 1
}

post_repository_dispatch "$REPO" "$TOKEN" "$body" "start-translation"
