#!/usr/bin/env bash
# Trigger the GitHub Actions workflow add-submodules.yml via repository_dispatch.
#
# Branch/endpoint naming constants: LOCAL_BRANCH_PREFIX, TRANSLATION_BRANCH_PREFIX,
# MASTER_BRANCH in .github/workflows/assets/env.sh.
#
# Requires: curl; jq or Python 3 (python3 / python) to build JSON
# Auth: repo-root .env (GH_TOKEN / GITHUB_TOKEN), env, or --token (repo scope for the target repo).
#
# Exit codes: 0 = success (including --help), 1 = any error. Does not use the asset-script
# 0/1/2 batch convention (see docs/ARCHITECTURE.md §6).
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
# shellcheck source=/dev/null
source "$_REPO_ROOT/scripts/trigger-dispatch-common.sh"
unset _REPO_ROOT _ASSETS_DIR

# ---------------------------------------------------------------------------
# Typical run — edit these. CLI flags override (except --token uses env/PAT).
# ---------------------------------------------------------------------------
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

require_curl || exit 1

TOKEN="$(resolve_trigger_token "$TOKEN")" || exit 1

REPO="$(resolve_trigger_repo "$REPO")" || {
  echo "error: could not determine repo; set DEFAULT_REPO, GITHUB_REPOSITORY, or --repo OWNER/REPO" >&2
  exit 1
}

VERSION="${VERSION:-$DEFAULT_VERSION}"
SUBMODULES="${SUBMODULES:-$DEFAULT_SUBMODULES}"

validate_event_type "$EVENT_ADD_SUBMODULES"

body="$(build_dispatch_json "$EVENT_ADD_SUBMODULES" \
  version "$VERSION" submodules "$SUBMODULES" lang_codes "$LANG_CODES")" || {
  echo "error: install jq, or Python 3 (python3 or python on PATH), to build the request JSON" >&2
  exit 1
}

post_repository_dispatch "$REPO" "$TOKEN" "$body" "add-submodules"
