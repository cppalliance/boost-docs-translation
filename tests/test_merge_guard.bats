#!/usr/bin/env bats

setup() {
  # shellcheck source=tests/helpers/common.bash
  source "$BATS_TEST_DIRNAME/helpers/common.bash"
  # shellcheck source=tests/helpers/mock_gh.bash
  source "$BATS_TEST_DIRNAME/helpers/mock_gh.bash"
  load_lib
  install_mock_gh
  reset_mock_gh
}

teardown() {
  restore_mock_gh
}

@test "has_open_translation_pr: returns true when open PR exists" {
  export MOCK_PR_LIST_STDOUT="translation-zh_Hans-foo"

  run has_open_translation_pr "testorg" "algorithm" "zh_Hans"
  [ "$status" -eq 0 ]
}

@test "has_open_translation_pr: returns false when no open PR" {
  unset MOCK_PR_LIST_STDOUT

  run has_open_translation_pr "testorg" "algorithm" "zh_Hans"
  [ "$status" -eq 1 ]
}

@test "has_open_translation_pr: API failure returns false (fail-open)" {
  export MOCK_PR_LIST_EXIT=1
  export MOCK_PR_LIST_STDERR="API rate limit exceeded"
  unset MOCK_PR_LIST_STDOUT

  run has_open_translation_pr "testorg" "algorithm" "zh_Hans"
  [ "$status" -eq 1 ]
}

@test "process_local_branch: returns 1 when open translation PR exists" {
  # shellcheck source=tests/helpers/git_fixtures.bash
  source "$BATS_TEST_DIRNAME/helpers/git_fixtures.bash"
  load_translation
  init_git_fixture_root
  init_process_globals

  create_bare_remote_with_clone "mirror"
  create_remote_branch "$BARE_REMOTE" "local-en" "master"
  dest_repo="$GIT_FIXTURE_ROOT/mirror-clone"
  git clone "$BARE_REMOTE" "$dest_repo"

  export MOCK_PR_LIST_STDOUT="translation-en-abc123"

  run process_local_branch "$dest_repo" "algorithm" "en"
  [ "$status" -eq 1 ]

  cleanup_git_fixture_root
}
