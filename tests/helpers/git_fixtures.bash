# shellcheck shell=bash
# Temp git repos for integration-style tests.
# shellcheck disable=SC2034

init_git_fixture_root() {
  GIT_FIXTURE_ROOT="$(mktemp -d)"
  export GIT_FIXTURE_ROOT
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

# Rewrite https://github.com/ pushes to local bare remotes under GIT_FIXTURE_ROOT/remotes/.
configure_github_url_rewrite() {
  GITHUB_URL_REWRITE_KEY="url.file://${GIT_FIXTURE_ROOT}/remotes/.insteadOf"
  git config --global "$GITHUB_URL_REWRITE_KEY" "https://github.com/"
}

cleanup_github_url_rewrite() {
  if [[ -n "${GITHUB_URL_REWRITE_KEY:-}" ]]; then
    git config --global --unset-all "$GITHUB_URL_REWRITE_KEY" 2>/dev/null || true
    unset GITHUB_URL_REWRITE_KEY
  fi
}

# Push a new commit onto a remote branch from a side clone (concurrent writer simulation).
push_commit_to_remote_branch() {
  local bare="$1" branch="$2" message="${3:-concurrent advance}"
  local tmp
  tmp="$(mktemp -d)"
  git clone "$bare" "$tmp"
  git -C "$tmp" config user.email "test@test.local"
  git -C "$tmp" config user.name "Test"
  git -C "$tmp" checkout "$branch"
  echo "$message" >>"$tmp/README"
  git -C "$tmp" add README
  git -C "$tmp" commit -m "$message"
  git -C "$tmp" push origin "$branch"
  rm -rf "$tmp"
}

# Prepend a git wrapper to PATH that advances remote branch before push --force-with-lease.
install_git_push_pre_hook() {
  local bare="$1" branch="$2" message="${3:-concurrent advance}"
  local wrapper_dir="$GIT_FIXTURE_ROOT/bin"
  REAL_GIT="$(command -v git)"
  export REAL_GIT
  export GIT_HOOK_BARE_REMOTE="$bare" GIT_HOOK_BRANCH="$branch" GIT_HOOK_MESSAGE="$message"
  mkdir -p "$wrapper_dir"
  cat >"$wrapper_dir/git" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-C" && "${3:-}" == "push" && "$*" == *"--force-with-lease"* ]]; then
  tmp="$(mktemp -d)"
  "$REAL_GIT" clone "$GIT_HOOK_BARE_REMOTE" "$tmp"
  "$REAL_GIT" -C "$tmp" config user.email "test@test.local"
  "$REAL_GIT" -C "$tmp" config user.name "Test"
  "$REAL_GIT" -C "$tmp" checkout "$GIT_HOOK_BRANCH"
  echo "$GIT_HOOK_MESSAGE" >>"$tmp/README"
  "$REAL_GIT" -C "$tmp" add README
  "$REAL_GIT" -C "$tmp" commit -m "$GIT_HOOK_MESSAGE"
  "$REAL_GIT" -C "$tmp" push origin "$GIT_HOOK_BRANCH"
  rm -rf "$tmp"
fi
exec "$REAL_GIT" "$@"
EOF
  chmod +x "$wrapper_dir/git"
  GIT_WRAPPER_DIR="$wrapper_dir"
  export PATH="$wrapper_dir:$PATH"
}

restore_git_push_pre_hook() {
  if [[ -n "${GIT_WRAPPER_DIR:-}" ]]; then
    PATH="${PATH#"$GIT_WRAPPER_DIR:"}"
    export PATH
    rm -rf "$GIT_WRAPPER_DIR"
    unset GIT_WRAPPER_DIR REAL_GIT
    unset GIT_HOOK_BARE_REMOTE GIT_HOOK_BRANCH GIT_HOOK_MESSAGE GIT_FETCH_COUNTER_FILE
  fi
}

# Prepend a git wrapper that hides --force-with-lease from push -h (simulates pre-2.8 git).
install_git_without_force_with_lease() {
  local wrapper_dir="$GIT_FIXTURE_ROOT/bin"
  REAL_GIT="$(command -v git)"
  export REAL_GIT
  mkdir -p "$wrapper_dir"
  cat >"$wrapper_dir/git" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "push" && "${2:-}" == "-h" ]]; then
  "$REAL_GIT" push -h 2>&1 | grep -v 'force-with-lease'
  exit 0
fi
exec "$REAL_GIT" "$@"
EOF
  chmod +x "$wrapper_dir/git"
  GIT_WRAPPER_DIR="$wrapper_dir"
  export PATH="$wrapper_dir:$PATH"
}

# Prepend a git wrapper that counts fetch invocations and optionally injects concurrent push.
install_git_fetch_counter() {
  local counter_file="$1"
  local bare="${2:-}" branch="${3:-}" message="${4:-concurrent advance}"
  local wrapper_dir="$GIT_FIXTURE_ROOT/bin"
  REAL_GIT="$(command -v git)"
  export REAL_GIT GIT_FETCH_COUNTER_FILE="$counter_file"
  export GIT_HOOK_BARE_REMOTE="$bare" GIT_HOOK_BRANCH="$branch" GIT_HOOK_MESSAGE="$message"
  mkdir -p "$wrapper_dir"
  cat >"$wrapper_dir/git" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-C" && "${3:-}" == "fetch" ]]; then
  echo 1 >>"$GIT_FETCH_COUNTER_FILE"
fi
if [[ "${1:-}" == "-C" && "${3:-}" == "push" && "$*" == *"--force-with-lease"* && -n "${GIT_HOOK_BARE_REMOTE:-}" ]]; then
  tmp="$(mktemp -d)"
  "$REAL_GIT" clone "$GIT_HOOK_BARE_REMOTE" "$tmp"
  "$REAL_GIT" -C "$tmp" config user.email "test@test.local"
  "$REAL_GIT" -C "$tmp" config user.name "Test"
  "$REAL_GIT" -C "$tmp" checkout "$GIT_HOOK_BRANCH"
  echo "$GIT_HOOK_MESSAGE" >>"$tmp/README"
  "$REAL_GIT" -C "$tmp" add README
  "$REAL_GIT" -C "$tmp" commit -m "$GIT_HOOK_MESSAGE"
  "$REAL_GIT" -C "$tmp" push origin "$GIT_HOOK_BRANCH"
  rm -rf "$tmp"
fi
exec "$REAL_GIT" "$@"
EOF
  chmod +x "$wrapper_dir/git"
  GIT_WRAPPER_DIR="$wrapper_dir"
  export PATH="$wrapper_dir:$PATH"
}
