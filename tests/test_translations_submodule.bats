#!/usr/bin/env bats

setup() {
  # shellcheck source=tests/helpers/test_helper.bash
  source "$BATS_TEST_DIRNAME/helpers/test_helper.bash"
  load_lib
  init_git_fixture_root
  init_process_globals
  git config --global protocol.file.allow always
  configure_github_url_rewrite
  libs_ref="develop"
}

teardown() {
  cleanup_github_url_rewrite
  git config --global --unset-all protocol.file.allow 2>/dev/null || true
  cleanup_git_fixture_root
}

# Mirror bare remote for libs/algorithm and translations super-repo clone.
install_translations_submodule_fixtures() {
  create_bare_remote_with_clone "algorithm-mirror"
  algo_bare="$BARE_REMOTE"
  algo_work="$WORK_REPO"
  mkdir -p "$algo_work/doc"
  echo "mirror doc" >"$algo_work/doc/page.adoc"
  git -C "$algo_work" add doc/
  git -C "$algo_work" commit -m "mirror content"
  git -C "$algo_work" push origin "$MASTER_BRANCH"

  mkdir -p "$GIT_FIXTURE_ROOT/remotes/${MODULE_ORG}"
  ln -sfn "$algo_bare" "$GIT_FIXTURE_ROOT/remotes/${MODULE_ORG}/algorithm.git"

  create_bare_remote_with_clone "translations"
  trans_bare="$BARE_REMOTE"
  trans_dir="$GIT_FIXTURE_ROOT/translations-work"
  git clone "$trans_bare" "$trans_dir"
  set_git_bot_config "$trans_dir"
}

@test "set_git_bot_config: sets bot identity on repository" {
  install_translations_submodule_fixtures

  set_git_bot_config "$trans_dir"
  [ "$(git -C "$trans_dir" config user.email)" = "$BOT_EMAIL" ]
  [ "$(git -C "$trans_dir" config user.name)" = "$BOT_NAME" ]
}

@test "submodule_in_gitmodules: detects registered submodule path" {
  install_translations_submodule_fixtures

  ! submodule_in_gitmodules "$trans_dir" "libs/algorithm"
  git -C "$trans_dir" submodule add -b "$MASTER_BRANCH" \
    "https://github.com/${MODULE_ORG}/algorithm.git" "libs/algorithm"
  submodule_in_gitmodules "$trans_dir" "libs/algorithm"
}

@test "update_translations_submodule: fresh add registers submodule and gitmodules" {
  install_translations_submodule_fixtures

  update_translations_submodule "$trans_dir" "$MODULE_ORG" "algorithm" "$MASTER_BRANCH"
  submodule_in_gitmodules "$trans_dir" "libs/algorithm"
  grep -Fq "libs/algorithm" "$trans_dir/.gitmodules"
  grep -Fq "github.com/${MODULE_ORG}/algorithm" "$trans_dir/.gitmodules"
  [ -d "$trans_dir/libs/algorithm" ]
}

@test "update_translations_submodule: existing entry updates branch tracking config" {
  install_translations_submodule_fixtures
  update_translations_submodule "$trans_dir" "$MODULE_ORG" "algorithm" "$MASTER_BRANCH"
  git -C "$trans_dir" commit -am "register submodule"

  echo "updated mirror" >"$algo_work/doc/page.adoc"
  git -C "$algo_work" add doc/
  git -C "$algo_work" commit -m "updated mirror"
  git -C "$algo_work" push origin "$MASTER_BRANCH"

  update_translations_submodule "$trans_dir" "$MODULE_ORG" "algorithm" "$MASTER_BRANCH"
  [ "$(git -C "$trans_dir" config submodule.libs/algorithm.branch)" = "$MASTER_BRANCH" ]
  ! git -C "$trans_dir" diff --cached --quiet
}

@test "commit_and_push_translations_branch: uses expected commit message" {
  install_translations_submodule_fixtures
  update_translations_submodule "$trans_dir" "$MODULE_ORG" "algorithm" "$MASTER_BRANCH"

  commit_and_push_translations_branch "$trans_dir" "$MASTER_BRANCH" "$libs_ref" false
  git -C "$trans_dir" log -1 --format=%s | grep -F "Update libs submodules to $libs_ref"
}

@test "update_translations_submodule: fails when submodule remote is missing" {
  install_translations_submodule_fixtures
  rm -rf "$GIT_FIXTURE_ROOT/remotes/${MODULE_ORG}/algorithm.git"

  set +e
  update_translations_submodule "$trans_dir" "$MODULE_ORG" "algorithm" "$MASTER_BRANCH"
  status=$?
  set -e

  [ "$status" -ne 0 ]
}
