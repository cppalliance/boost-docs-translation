# shellcheck shell=bash
# Shared helpers for bats tests.
# shellcheck disable=SC2034

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ASSETS_DIR="$REPO_ROOT/.github/workflows/assets"
FIXTURES_DIR="$REPO_ROOT/tests/helpers/fixtures"

load_env() {
  export GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-testorg/boost-docs-translation}"
  # shellcheck source=/dev/null
  source "$ASSETS_DIR/env.sh"
}

load_lib() {
  load_env
  # shellcheck source=/dev/null
  source "$ASSETS_DIR/lib.sh"
}

load_translation() {
  load_lib
  export GITHUB_WORKSPACE="$REPO_ROOT"
  # shellcheck source=/dev/null
  source "$ASSETS_DIR/translation.sh"
}

# Run a function and capture its exit code (works under set -e in callers).
run_fn() {
  local errexit_was_on=0
  [[ $- == *e* ]] && errexit_was_on=1
  set +e
  "$@"
  local rc=$?
  if (( errexit_was_on )); then
    set -e
  else
    set +e
  fi
  return "$rc"
}

reset_process_globals() {
  ORG_REPO_MISSING=()
  META_MISSING=()
  NO_DOC_PATHS=()
  declare -gA add_or_update=()
  lang_codes_arr=()
  UPDATES=()
}

init_process_globals() {
  reset_process_globals
  # Fixed values so tests behave the same locally and in CI (GITHUB_REPOSITORY varies).
  MODULE_ORG="testorg"
  MASTER_BRANCH="master"
  BOOST_ORG="boostorg"
  libs_ref="develop"
  lang_codes_arr=("en")
  add_or_update["en"]=""
}
