#!/usr/bin/env bats

setup() {
  # shellcheck source=tests/helpers/test_helper.bash
  source "$BATS_TEST_DIRNAME/helpers/test_helper.bash"
  load_translation
  init_git_fixture_root
  libs_ref="develop"
}

teardown() {
  cleanup_git_fixture_root
}

# Bare mirror remote + working clone as dest_repo; plain directory as sub_clone source.
install_sync_repo_master_fixtures() {
  create_bare_remote_with_clone "mirror"
  mirror_bare="$BARE_REMOTE"
  dest_repo="$GIT_FIXTURE_ROOT/mirror-dest"
  git clone "$mirror_bare" "$dest_repo"
  git -C "$dest_repo" config user.email "test@test.local"
  git -C "$dest_repo" config user.name "Test"

  sub_clone="$GIT_FIXTURE_ROOT/sub-clone"
  mkdir -p "$sub_clone/doc"
  echo "doc content" >"$sub_clone/doc/page.adoc"
  echo "license" >"$sub_clone/LICENSE"
}

@test "sync_repo_master: copies source, commits, and pushes to remote" {
  install_sync_repo_master_fixtures
  remote_before=$(git -C "$mirror_bare" rev-parse "$MASTER_BRANCH")

  set +e
  sync_repo_master "$dest_repo" "$sub_clone" "$libs_ref"
  status=$?
  set -e

  [ "$status" -eq 0 ]
  remote_after=$(git -C "$mirror_bare" rev-parse "$MASTER_BRANCH")
  [ "$remote_before" != "$remote_after" ]
  git -C "$mirror_bare" log -1 --format=%s "$MASTER_BRANCH" \
    | grep -F "Update the original documentation of $libs_ref"
  [ "$(git -C "$dest_repo" config user.email)" = "$BOT_EMAIL" ]
  [ "$(git -C "$dest_repo" config user.name)" = "$BOT_NAME" ]
  [ -f "$dest_repo/doc/page.adoc" ]
  [ ! -d "$dest_repo/src" ]
}

@test "sync_repo_master: skips commit when content already matches remote" {
  install_sync_repo_master_fixtures

  sync_repo_master "$dest_repo" "$sub_clone" "$libs_ref"
  remote_after_first=$(git -C "$mirror_bare" rev-parse "$MASTER_BRANCH")

  set +e
  sync_repo_master "$dest_repo" "$sub_clone" "$libs_ref"
  status=$?
  set -e

  [ "$status" -eq 0 ]
  remote_after_second=$(git -C "$mirror_bare" rev-parse "$MASTER_BRANCH")
  [ "$remote_after_first" = "$remote_after_second" ]
}

@test "sync_repo_master: returns 2 when remote rejects non-fast-forward push" {
  install_sync_repo_master_fixtures
  sync_repo_master "$dest_repo" "$sub_clone" "$libs_ref"

  push_commit_to_remote_branch "$mirror_bare" "$MASTER_BRANCH" "concurrent advance"

  echo "new doc" >"$sub_clone/doc/page.adoc"

  set +e
  sync_repo_master "$dest_repo" "$sub_clone" "$libs_ref"
  status=$?
  set -e

  [ "$status" -eq 2 ]
  git -C "$mirror_bare" log -1 --format=%s "$MASTER_BRANCH" | grep -q "concurrent advance"
}
