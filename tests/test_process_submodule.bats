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
  libs_ref="master"
  export MOCK_LIBRARIES_FIXTURE="$FIXTURES_DIR/libraries-single.json"

  create_bare_remote_with_clone "boost-algorithm"
  boost_bare="$BARE_REMOTE"
  boost_work="$WORK_REPO"
  mkdir -p "$boost_work/doc"
  echo "doc content" >"$boost_work/doc/page.adoc"
  git -C "$boost_work" add doc/
  git -C "$boost_work" commit -m "add doc"
  git -C "$boost_work" push origin master

  create_bare_remote_with_clone "mirror-algorithm"
  mirror_bare="$BARE_REMOTE"

  clone_repo() {
    local url="$1" branch="$2" dest="$3" keep="${4:-}"
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

  set +e
  process_one_submodule "algorithm"
  status=$?
  set -e

  [ "$status" -eq 0 ]
  [[ "${add_or_update[en]}" == *algorithm* ]]
}
