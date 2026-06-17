# shellcheck shell=bash
# Temp git repos for integration-style tests.
# shellcheck disable=SC2034

init_git_fixture_root() {
  GIT_FIXTURE_ROOT="$(mktemp -d)"
}

cleanup_git_fixture_root() {
  if [[ -n "${GIT_FIXTURE_ROOT:-}" && -d "$GIT_FIXTURE_ROOT" ]]; then
    rm -rf "$GIT_FIXTURE_ROOT"
  fi
  GIT_FIXTURE_ROOT=""
}

# Create a bare remote and a working clone with an initial commit on master.
# Sets BARE_REMOTE and WORK_REPO globals.
create_bare_remote_with_clone() {
  local name="$1"
  local bare="$GIT_FIXTURE_ROOT/${name}.git"
  local work="$GIT_FIXTURE_ROOT/${name}"

  git init --bare "$bare"
  git init "$work"
  git -C "$work" checkout -b master
  git -C "$work" config user.email "test@test.local"
  git -C "$work" config user.name "Test"
  git -C "$work" remote add origin "$bare"
  echo "init" >"$work/README"
  git -C "$work" add README
  git -C "$work" commit -m "init"
  git -C "$work" push -u origin master

  BARE_REMOTE="$bare"
  WORK_REPO="$work"
}

# Create a local branch on the bare remote (e.g. local-en).
create_remote_branch() {
  local bare="$1" branch="$2" from_branch="${3:-master}"
  local tmp
  tmp="$(mktemp -d)"
  git clone "$bare" "$tmp"
  git -C "$tmp" checkout -b "$branch" "origin/$from_branch"
  git -C "$tmp" push -u origin "$branch"
  rm -rf "$tmp"
}

# Populate a clone directory with doc-like content for prune tests.
create_prune_fixture_dir() {
  local dir="$1"
  mkdir -p "$dir/doc" "$dir/src" "$dir/.github/workflows" "$dir/minmax/other"
  echo "doc" >"$dir/doc/readme.txt"
  echo "src" >"$dir/src/main.cpp"
  echo "wf" >"$dir/.github/workflows/ci.yml"
  echo "other" >"$dir/minmax/other/data.txt"
}
