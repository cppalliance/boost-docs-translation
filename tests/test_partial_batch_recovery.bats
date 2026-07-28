#!/usr/bin/env bats
#
# End-to-end: a partial batch failure recovers on re-run (#61).
#
# Runs process_submodule_list over real git fixtures with one submodule's remote
# transiently unavailable, so it fails while the others succeed. The re-run, with
# the remote restored, completes the previously-failed submodule and leaves the
# already-synced ones untouched (no new commit).

setup() {
  # shellcheck source=tests/helpers/test_helper.bash
  source "$BATS_TEST_DIRNAME/helpers/test_helper.bash"
  load_submodule_ops                    # lib.sh state/summary + process_submodule_list
  # shellcheck source=/dev/null
  source "$ASSETS_DIR/translation.sh"   # sync_repo_master
  init_git_fixture_root
  init_translation_state
  init_submodule_summary_buckets
  libs_ref="develop"
}

teardown() {
  cleanup_git_fixture_root
}

# Bare mirror remote + a dest clone + a source-content dir for one submodule.
install_recovery_fixture() {
  local sub="$1"
  create_bare_remote_with_clone "$sub"
  git clone "$GIT_FIXTURE_ROOT/${sub}.git" "$GIT_FIXTURE_ROOT/${sub}-dest"
  mkdir -p "$GIT_FIXTURE_ROOT/${sub}-src/doc"
  echo "$sub documentation" >"$GIT_FIXTURE_ROOT/${sub}-src/doc/page.adoc"
}

# process_submodule_list processor: mirror one submodule's source into its dest
# repo and push. Returns sync_repo_master's status (0 success, 2 failure).
recovery_processor() {
  local sub="$1"
  sync_repo_master "$GIT_FIXTURE_ROOT/${sub}-dest" "$GIT_FIXTURE_ROOT/${sub}-src" "$libs_ref"
}

remote_head() {
  git -C "$GIT_FIXTURE_ROOT/$1.git" rev-parse "$MASTER_BRANCH"
}

@test "process_submodule_list: a partial batch failure recovers on re-run" {
  install_recovery_fixture algorithm
  install_recovery_fixture json
  install_recovery_fixture system

  local algo_start json_start system_start
  algo_start=$(remote_head algorithm)
  json_start=$(remote_head json)
  system_start=$(remote_head system)

  # --- Run 1: json's remote is transiently unavailable (moved aside). ---
  mv "$GIT_FIXTURE_ROOT/json.git" "$GIT_FIXTURE_ROOT/json.git.offline"

  set +e
  process_submodule_list recovery_processor algorithm json system
  local rc1=$?
  set -e
  [ "$rc1" -eq 0 ]

  # algorithm and system are updated; json is the only fatal.
  [ "${UPDATES[*]}" = "algorithm system" ]
  [ "${SUBMODULE_FATAL[*]}" = "json" ]
  [ "$submodule_fatal" -eq 1 ]

  # The two healthy remotes advanced; the summary counts json as a failure.
  local algo_after1 system_after1
  algo_after1=$(remote_head algorithm)
  system_after1=$(remote_head system)
  [ "$algo_after1" != "$algo_start" ]
  [ "$system_after1" != "$system_start" ]

  local summary
  summary="$(print_submodule_processing_summary 2>&1)"
  echo "$summary" | grep -E "Successfully updated \(2\):.*algorithm.*system"
  echo "$summary" | grep -E "processing error \(1\):.*json"

  # --- Run 2: json's remote is restored; re-run the same batch fresh. ---
  mv "$GIT_FIXTURE_ROOT/json.git.offline" "$GIT_FIXTURE_ROOT/json.git"
  # The failed run committed locally but never pushed, so the remote is untouched.
  [ "$(remote_head json)" = "$json_start" ]

  # Production clones each destination fresh per run (sync_one_submodule works in
  # a mktemp -d workspace), so re-clone from each bare remote instead of reusing
  # run 1's checkout. This proves the recovering submodule re-commits and pushes
  # against the unchanged remote rather than pushing run 1's leftover local commit.
  for sub in algorithm json system; do
    rm -rf "$GIT_FIXTURE_ROOT/${sub}-dest"
    git clone "$GIT_FIXTURE_ROOT/${sub}.git" "$GIT_FIXTURE_ROOT/${sub}-dest"
  done

  init_translation_state
  init_submodule_summary_buckets

  set +e
  process_submodule_list recovery_processor algorithm json system
  local rc2=$?
  set -e
  [ "$rc2" -eq 0 ]

  # No fatals remain and json is now recovered.
  [ "$submodule_fatal" -eq 0 ]
  [ "${#SUBMODULE_FATAL[@]}" -eq 0 ]
  [ "${UPDATES[*]}" = "algorithm json system" ]
  [ "$(remote_head json)" != "$json_start" ]

  # The already-synced remotes are idempotent: no new commit on the re-run.
  [ "$(remote_head algorithm)" = "$algo_after1" ]
  [ "$(remote_head system)" = "$system_after1" ]
}
