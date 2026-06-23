#!/usr/bin/env bats

setup() {
  # shellcheck source=tests/helpers/common.bash
  source "$BATS_TEST_DIRNAME/helpers/common.bash"
  load_lib
}

@test "parse_list: empty input produces no output" {
  run parse_list ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "parse_list: comma-separated codes" {
  run parse_list "zh_Hans,en"
  [ "$status" -eq 0 ]
  [ "$output" = $'zh_Hans\nen' ]
}

@test "parse_list: bracketed list with spaces" {
  run parse_list "[zh_Hans, en]"
  [ "$status" -eq 0 ]
  [ "$output" = $'zh_Hans\nen' ]
}

@test "parse_list: trailing comma ignored" {
  run parse_list "en,"
  [ "$status" -eq 0 ]
  [ "$output" = "en" ]
}

@test "parse_extensions: bracketed extensions" {
  run parse_extensions "[.adoc, .md]"
  [ "$status" -eq 0 ]
  [ "$output" = $'.adoc\n.md' ]
}

@test "parse_extensions: JSON-style quoted extensions" {
  run parse_extensions '[".adoc",".md"]'
  [ "$status" -eq 0 ]
  [ "$output" = $'.adoc\n.md' ]
}

@test "parse_extensions: bare extension gets dot prefix" {
  run parse_extensions "adoc"
  [ "$status" -eq 0 ]
  [ "$output" = ".adoc" ]
}

@test "parse_extensions: empty input produces no output" {
  run parse_extensions ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "is_valid_lang_code: accepts common BCP 47 codes" {
  is_valid_lang_code "en"
  is_valid_lang_code "zh_Hans"
  is_valid_lang_code "pt_BR"
}

@test "is_valid_lang_code: rejects invalid codes" {
  ! is_valid_lang_code ""
  ! is_valid_lang_code "en US"
  ! is_valid_lang_code "zh/Hans"
  ! is_valid_lang_code "a"
}

@test "parse_and_validate_lang_codes: valid LANG_CODES populates lang_codes_arr" {
  LANG_CODES="zh_Hans,en"
  parse_and_validate_lang_codes
  [ "${#lang_codes_arr[@]}" -eq 2 ]
  [ "${lang_codes_arr[0]}" = "zh_Hans" ]
  [ "${lang_codes_arr[1]}" = "en" ]
}

@test "parse_and_validate_lang_codes: missing LANG_CODES exits 1" {
  unset LANG_CODES
  run parse_and_validate_lang_codes
  [ "$status" -eq 1 ]
  [[ "$output" == *"lang_codes not set"* ]]
}

@test "parse_and_validate_lang_codes: invalid code exits 1" {
  LANG_CODES="en US"
  run parse_and_validate_lang_codes
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid language code"* ]]
}

@test "get_doc_paths: single-library repo emits doc" {
  # shellcheck source=tests/helpers/mock_gh.bash
  source "$BATS_TEST_DIRNAME/helpers/mock_gh.bash"
  install_mock_gh
  export MOCK_LIBRARIES_FIXTURE="$FIXTURES_DIR/libraries-single.json"

  run get_doc_paths "algorithm" "develop"
  [ "$status" -eq 0 ]
  [ "$output" = "doc" ]

  restore_mock_gh
}

@test "get_doc_paths: multi-library repo emits per-key doc paths" {
  # shellcheck source=tests/helpers/mock_gh.bash
  source "$BATS_TEST_DIRNAME/helpers/mock_gh.bash"
  install_mock_gh
  export MOCK_LIBRARIES_FIXTURE="$FIXTURES_DIR/libraries-multi.json"

  run get_doc_paths "container" "develop"
  [ "$status" -eq 0 ]
  [ "$output" = $'minmax/doc\nstring/doc' ]

  restore_mock_gh
}

@test "get_doc_paths: API failure returns non-zero" {
  # shellcheck source=tests/helpers/mock_gh.bash
  source "$BATS_TEST_DIRNAME/helpers/mock_gh.bash"
  install_mock_gh
  export MOCK_GH_API_EXIT=1

  run get_doc_paths "algorithm" "develop"
  [ "$status" -eq 1 ]

  restore_mock_gh
}

@test "prune_to_doc_only: keeps doc and root files, removes other dirs" {
  # shellcheck source=tests/helpers/git_fixtures.bash
  source "$BATS_TEST_DIRNAME/helpers/git_fixtures.bash"
  init_git_fixture_root
  local_dir="$GIT_FIXTURE_ROOT/prune-single"
  create_prune_fixture_dir "$local_dir"
  echo "root" >"$local_dir/LICENSE"

  prune_to_doc_only "$local_dir" "doc"

  [ -d "$local_dir/doc" ]
  [ -f "$local_dir/LICENSE" ]
  [ ! -d "$local_dir/src" ]
  [ ! -d "$local_dir/.github" ]

  cleanup_git_fixture_root
}

@test "prune_to_doc_only: multi-level path prunes intermediate dirs" {
  # shellcheck source=tests/helpers/git_fixtures.bash
  source "$BATS_TEST_DIRNAME/helpers/git_fixtures.bash"
  init_git_fixture_root
  local_dir="$GIT_FIXTURE_ROOT/prune-multi"
  create_prune_fixture_dir "$local_dir"

  prune_to_doc_only "$local_dir" "minmax/doc"

  [ -d "$local_dir/minmax" ]
  [ ! -d "$local_dir/minmax/other" ]
  [ ! -d "$local_dir/doc" ]
  [ ! -d "$local_dir/src" ]

  cleanup_git_fixture_root
}

@test "finalize_translations_master: no-op when UPDATES empty" {
  # shellcheck source=tests/helpers/git_fixtures.bash
  source "$BATS_TEST_DIRNAME/helpers/git_fixtures.bash"
  init_git_fixture_root
  create_bare_remote_with_clone "translations"
  trans_dir="$GIT_FIXTURE_ROOT/translations-work"
  git clone "$BARE_REMOTE" "$trans_dir"

  UPDATES=()
  SYNC_CALLS=()
  sync_translations_branch() { SYNC_CALLS+=("branch=$2 force=${4:-false}"); }

  finalize_translations_master "$trans_dir" "develop"
  [ "${#SYNC_CALLS[@]}" -eq 0 ]

  cleanup_git_fixture_root
}

@test "finalize_translations_master: syncs master without force" {
  # shellcheck source=tests/helpers/git_fixtures.bash
  source "$BATS_TEST_DIRNAME/helpers/git_fixtures.bash"
  init_git_fixture_root
  create_bare_remote_with_clone "translations"
  trans_dir="$GIT_FIXTURE_ROOT/translations-work"
  git clone "$BARE_REMOTE" "$trans_dir"

  UPDATES=("algorithm")
  SYNC_CALLS=()
  sync_translations_branch() { SYNC_CALLS+=("branch=$2 force=${4:-false}"); }

  finalize_translations_master "$trans_dir" "develop"
  [ "${#SYNC_CALLS[@]}" -eq 1 ]
  [ "${SYNC_CALLS[0]}" = "branch=master force=false" ]

  cleanup_git_fixture_root
}

@test "finalize_translations_local: syncs local branch with force" {
  # shellcheck source=tests/helpers/git_fixtures.bash
  source "$BATS_TEST_DIRNAME/helpers/git_fixtures.bash"
  init_git_fixture_root
  create_bare_remote_with_clone "translations"
  trans_dir="$GIT_FIXTURE_ROOT/translations-work"
  git clone "$BARE_REMOTE" "$trans_dir"

  UPDATES=("algorithm")
  SYNC_CALLS=()
  sync_translations_branch() { SYNC_CALLS+=("branch=$2 force=${4:-false}"); }

  finalize_translations_local "$trans_dir" "develop" "en"
  [ "${#SYNC_CALLS[@]}" -eq 1 ]
  [ "${SYNC_CALLS[0]}" = "branch=local-en force=true" ]

  cleanup_git_fixture_root
}

@test "finalize_translations_repo: syncs master then each local branch" {
  # shellcheck source=tests/helpers/git_fixtures.bash
  source "$BATS_TEST_DIRNAME/helpers/git_fixtures.bash"
  init_git_fixture_root
  create_bare_remote_with_clone "translations"
  trans_dir="$GIT_FIXTURE_ROOT/translations-work"
  git clone "$BARE_REMOTE" "$trans_dir"

  UPDATES=("algorithm")
  SYNC_CALLS=()
  sync_translations_branch() { SYNC_CALLS+=("branch=$2 force=${4:-false}"); }

  finalize_translations_repo "$trans_dir" "develop" "en" "zh_Hans"
  [ "${#SYNC_CALLS[@]}" -eq 3 ]
  [ "${SYNC_CALLS[0]}" = "branch=master force=false" ]
  [ "${SYNC_CALLS[1]}" = "branch=local-en force=true" ]
  [ "${SYNC_CALLS[2]}" = "branch=local-zh_Hans force=true" ]

  cleanup_git_fixture_root
}

@test "begin_phase and end_phase: emit group markers and track CURRENT_PHASE" {
  local out_file="$BATS_TMPDIR/phase.out"

  begin_phase "$PHASE_SETUP" "Test setup" >"$out_file"
  [ "$(cat "$out_file")" = "::group::[setup] Test setup" ]
  [ "$CURRENT_PHASE" = "setup" ]

  end_phase >"$out_file"
  [ "$(cat "$out_file")" = "::endgroup::" ]
  [ -z "$CURRENT_PHASE" ]
}

@test "phase_err: includes active phase in message" {
  begin_phase "$PHASE_PROCESS_SUBMODULES" "Process submodules"
  run phase_err "something failed"
  end_phase
  [ "$status" -eq 0 ]
  [[ "$output" == *"[process-submodules] something failed"* ]]
}

@test "phase_err: uses unknown when no phase is active" {
  CURRENT_PHASE=""
  run phase_err "early failure"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[unknown] early failure"* ]]
}

@test "is_valid_event_type: accepts declared event types" {
  is_valid_event_type "$EVENT_ADD_SUBMODULES"
  is_valid_event_type "$EVENT_START_TRANSLATION"
  is_valid_event_type "$EVENT_SYNC_TRANSLATION"
}

@test "is_valid_event_type: rejects unknown event types" {
  ! is_valid_event_type "not-a-real-event"
}

@test "validate_event_type: exits 1 on invalid input" {
  run validate_event_type "bad-event"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid event_type='bad-event'"* ]]
}

@test "validate_secrets weblate: accepts LANG_CODE without LANG_CODES" {
  GITHUB_TOKEN="token"
  LANG_CODE="zh_Hans"
  unset LANG_CODES
  WEBLATE_URL="https://weblate.example"
  WEBLATE_TOKEN="secret"
  validate_secrets weblate
}
