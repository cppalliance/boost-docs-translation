#!/usr/bin/env bats

setup() {
  # shellcheck source=tests/helpers/common.bash
  source "$BATS_TEST_DIRNAME/helpers/common.bash"
  # shellcheck source=tests/helpers/mock_gh.bash
  source "$BATS_TEST_DIRNAME/helpers/mock_gh.bash"
  # shellcheck source=tests/helpers/git_fixtures.bash
  source "$BATS_TEST_DIRNAME/helpers/git_fixtures.bash"
  load_add_submodules
  init_git_fixture_root
  install_mock_gh
  reset_mock_gh
  init_add_submodule_globals

  WORK_DIR="$(mktemp -d)"
  BOOST_WORK="$WORK_DIR/boost"
  mkdir -p "$BOOST_WORK"
}

teardown() {
  cleanup_github_url_rewrite
  restore_mock_gh
  cleanup_git_fixture_root
  rm -rf "${WORK_DIR:-}"
  unset CLONE_URLS
}

# Boost bare remote and a clone_repo stub that records URLs.
install_algorithm_add_fixtures() {
  libs_ref="$MASTER_BRANCH"
  boost_org="$BOOST_ORG"
  export MOCK_LIBRARIES_FIXTURE="$FIXTURES_DIR/libraries-single.json"
  export MOCK_REPO_VIEW_EXIT=1

  create_bare_remote_with_clone "boost-algorithm"
  boost_bare="$BARE_REMOTE"
  boost_work="$WORK_REPO"
  mkdir -p "$boost_work/doc"
  echo "doc content" >"$boost_work/doc/page.adoc"
  git -C "$boost_work" add doc/
  git -C "$boost_work" commit -m "add doc"
  git -C "$boost_work" push origin "$MASTER_BRANCH"

  configure_github_url_rewrite

  CLONE_URLS=()
  clone_repo() {
    local url="$1" branch="$2" dest="$3" keep="${4:-}"
    CLONE_URLS+=("$url")
    case "$url" in
      *"${BOOST_ORG}/algorithm"*)
        mkdir -p "$dest"
        git clone --branch "$branch" "$boost_bare" "$dest"
        [[ "$keep" == "keep" ]] || rm -rf "$dest/.git"
        ;;
      *)
        echo "unexpected clone url: $url" >&2
        return 1
        ;;
    esac
  }
}

@test "add_one_submodule: returns 1 when mirror repo already exists" {
  export MOCK_REPO_VIEW_EXIT=0

  set +e
  add_one_submodule "algorithm"
  status=$?
  set -e

  [ "$status" -eq 1 ]
  [[ " ${REPO_EXISTS_SKIP[*]} " == *" algorithm "* ]]
}

@test "add_one_submodule: returns 2 when metadata is missing" {
  export MOCK_REPO_VIEW_EXIT=1
  export MOCK_GH_API_EXIT=1

  set +e
  add_one_submodule "algorithm"
  status=$?
  set -e

  [ "$status" -eq 2 ]
  [[ " ${META_MISSING[*]} " == *" algorithm "* ]]
}

@test "add_one_submodule: returns 1 when metadata has no doc paths" {
  export MOCK_REPO_VIEW_EXIT=1
  export MOCK_LIBRARIES_FIXTURE="$FIXTURES_DIR/libraries-empty.json"

  set +e
  add_one_submodule "algorithm"
  status=$?
  set -e

  [ "$status" -eq 1 ]
  [[ " ${NO_DOC_PATHS[*]} " == *" algorithm "* ]]
}

@test "add_one_submodule: returns 2 when clone fails" {
  export MOCK_REPO_VIEW_EXIT=1
  export MOCK_LIBRARIES_FIXTURE="$FIXTURES_DIR/libraries-single.json"

  set +e
  add_one_submodule "algorithm"
  status=$?
  set -e

  [ "$status" -eq 2 ]
}

@test "add_one_submodule: returns 2 when repo create fails" {
  install_algorithm_add_fixtures
  export MOCK_REPO_CREATE_EXIT=1

  set +e
  add_one_submodule "algorithm"
  status=$?
  set -e

  [ "$status" -eq 2 ]
}

@test "add_one_submodule: returns 0 on success path" {
  install_algorithm_add_fixtures

  set +e
  add_one_submodule "algorithm"
  status=$?
  set -e

  [ "$status" -eq 0 ]
  [ "${#CLONE_URLS[@]}" -eq 1 ]
  [[ "${CLONE_URLS[0]}" == *"${BOOST_ORG}/algorithm"* ]]

  mirror_bare="$GIT_FIXTURE_ROOT/remotes/${MODULE_ORG}/algorithm.git"
  [ -d "$mirror_bare" ]
  git -C "$mirror_bare" show-ref --verify --quiet "refs/heads/$MASTER_BRANCH"
  git -C "$mirror_bare" show-ref --verify --quiet "refs/heads/${LOCAL_BRANCH_PREFIX}en"

  [ -f "$MOCK_GH_PATCH_LOG" ]
  grep -Fq "repos/${MODULE_ORG}/algorithm" "$MOCK_GH_PATCH_LOG"
  grep -Fq "default_branch=${MASTER_BRANCH}" "$MOCK_GH_PATCH_LOG"
  git -C "$mirror_bare" log -1 --format=%s "$MASTER_BRANCH" \
    | grep -F "Create the original documentation of $libs_ref"
}
