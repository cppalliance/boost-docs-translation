#!/usr/bin/env bats

setup() {
  # shellcheck source=tests/helpers/common.bash
  source "$BATS_TEST_DIRNAME/helpers/common.bash"
  # shellcheck source=tests/helpers/mock_gh.bash
  source "$BATS_TEST_DIRNAME/helpers/mock_gh.bash"
  # shellcheck source=tests/helpers/git_fixtures.bash
  source "$BATS_TEST_DIRNAME/helpers/git_fixtures.bash"
  load_translation
  install_mock_gh
  reset_mock_gh
  init_git_fixture_root
  init_process_globals

  WORK_DIR="$(mktemp -d)"
  BOOST_WORK="$WORK_DIR/boost"
  ORG_WORK="$WORK_DIR/$MODULE_ORG"
  mkdir -p "$BOOST_WORK" "$ORG_WORK"
}

teardown() {
  restore_mock_gh
  cleanup_git_fixture_root
  rm -rf "${WORK_DIR:-}"
  unset START_PHASE CLONE_URLS
}

# Boost + mirror bare remotes and a clone_repo stub that records URLs.
install_algorithm_process_fixtures() {
  libs_ref="$MASTER_BRANCH"
  export MOCK_LIBRARIES_FIXTURE="$FIXTURES_DIR/libraries-single.json"

  create_bare_remote_with_clone "boost-algorithm"
  boost_bare="$BARE_REMOTE"
  boost_work="$WORK_REPO"
  mkdir -p "$boost_work/doc"
  echo "doc content" >"$boost_work/doc/page.adoc"
  git -C "$boost_work" add doc/
  git -C "$boost_work" commit -m "add doc"
  git -C "$boost_work" push origin "$MASTER_BRANCH"

  create_bare_remote_with_clone "mirror-algorithm"
  mirror_bare="$BARE_REMOTE"
  create_remote_branch "$mirror_bare" "${LOCAL_BRANCH_PREFIX}en" "$MASTER_BRANCH"

  CLONE_URLS=()
  clone_repo() {
    local url="$1" branch="$2" dest="$3" keep="${4:-}"
    CLONE_URLS+=("$url")
    local bare=""
    case "$url" in
      *"${BOOST_ORG}/algorithm"*) bare="$boost_bare" ;;
      *"${MODULE_ORG}/algorithm"*) bare="$mirror_bare" ;;
      *) echo "unexpected clone url: $url (MODULE_ORG=$MODULE_ORG)" >&2; return 1 ;;
    esac
    mkdir -p "$dest"
    git clone --branch "$branch" "$bare" "$dest"
    [[ "$keep" == "keep" ]] || rm -rf "$dest/.git"
  }
}

@test "process_one_submodule: returns 2 when mirror repo missing" {
  export MOCK_REPO_VIEW_EXIT=1

  set +e
  process_one_submodule "missing-lib"
  status=$?
  set -e

  [ "$status" -eq 2 ]
  [[ " ${ORG_REPO_MISSING[*]} " == *" missing-lib "* ]]
}

@test "process_one_submodule: returns 1 when metadata has no doc paths" {
  export MOCK_LIBRARIES_FIXTURE="$FIXTURES_DIR/libraries-empty.json"

  set +e
  process_one_submodule "algorithm"
  status=$?
  set -e

  [ "$status" -eq 1 ]
  [[ " ${NO_DOC_PATHS[*]} " == *" algorithm "* ]]
}

@test "process_one_submodule: returns 0 on success path" {
  install_algorithm_process_fixtures

  set +e
  process_one_submodule "algorithm"
  status=$?
  set -e

  [ "$status" -eq 0 ]
  [[ "${add_or_update[en]}" == *algorithm* ]]
  [ "${#CLONE_URLS[@]}" -eq 2 ]
}

@test "process_one_submodule: returns 2 for invalid START_PHASE" {
  export START_PHASE=mirror

  set +e
  err=$(process_one_submodule "algorithm" 2>&1 >/dev/null)
  status=$?
  set -e

  [ "$status" -eq 2 ]
  [[ "$err" == *"invalid START_PHASE='mirror'"* ]]
}

@test "process_one_submodule: START_PHASE=mirrors returns after mirror sync" {
  export START_PHASE=mirrors
  install_algorithm_process_fixtures

  set +e
  process_one_submodule "algorithm"
  status=$?
  set -e

  [ "$status" -eq 0 ]
  [ "${#CLONE_URLS[@]}" -eq 2 ]
  [[ "${CLONE_URLS[0]}" == *"${BOOST_ORG}/algorithm"* ]]
  [[ "${CLONE_URLS[1]}" == *"${MODULE_ORG}/algorithm"* ]]
  [[ -z "${add_or_update[en]:-}" ]]
}

@test "process_one_submodule: START_PHASE=local skips upstream clone" {
  export START_PHASE=local
  install_algorithm_process_fixtures

  set +e
  process_one_submodule "algorithm"
  status=$?
  set -e

  [ "$status" -eq 0 ]
  [ "${#CLONE_URLS[@]}" -eq 1 ]
  [[ "${CLONE_URLS[0]}" == *"${MODULE_ORG}/algorithm"* ]]
  [[ "${CLONE_URLS[0]}" != *"${BOOST_ORG}/"* ]]
  [[ "${add_or_update[en]}" == *algorithm* ]]
}
