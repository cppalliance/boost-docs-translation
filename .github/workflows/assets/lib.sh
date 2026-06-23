# shellcheck shell=bash
# Shared shell library for add-submodules and start-translation workflows.
# Source env.sh before lib.sh so ORG, MODULE_ORG, BOT_NAME, BOT_EMAIL, BOOST_ORG, MASTER_BRANCH,
# LOCAL_BRANCH_PREFIX, TRANSLATION_BRANCH_PREFIX, WEBLATE_ENDPOINT_PATH, and TRANSLATIONS_REPO
# are set. Workflows also set GITHUB_TOKEN, LANG_CODES, and (for start-translation)
# WEBLATE_URL / WEBLATE_TOKEN in the step env before sourcing.
# Call validate_secrets (or validate_secrets weblate) after sourcing env.sh and lib.sh.
# require_lang_codes may be called after sourcing lib.sh alone (early validation step).

# ── Helpers ──────────────────────────────────────────────────────────

set_git_bot_config() {
  git -C "$1" config user.email "$BOT_EMAIL"
  git -C "$1" config user.name "$BOT_NAME"
}

# ── GitHub API helpers (via gh CLI) ──────────────────────────────────

repo_exists() { gh repo view "$1/$2" &>/dev/null; }

# Returns 0 if org/repo has an open PR into local-{lang_code} with head matching
# "translation-{lang_code}-*"; 1 if none; 2 if the GitHub API check failed.
has_open_translation_pr() {
  local org="$1" repo="$2" lang_code="$3"
  local base_br="${LOCAL_BRANCH_PREFIX}${lang_code}"
  local output
  if ! output=$(gh pr list --repo "$org/$repo" --state open --base "$base_br" --json headRefName \
    --jq ".[] | select(.headRefName | startswith(\"${TRANSLATION_BRANCH_PREFIX}${lang_code}-\")) | .headRefName" \
    2>&1); then
    echo "  Error: could not list open PRs for $org/$repo (base=$base_br): $output" >&2
    return 2
  fi
  [[ -n "$output" ]]
}

# ── Git clone helpers ────────────────────────────────────────────────

# Clone repo at branch/tag into $3. Pass "keep" as $4 to preserve .git.
clone_repo() {
  mkdir -p "$3"
  git clone --branch "$2" "$1" "$3"
  [[ "${4:-}" == "keep" ]] || rm -rf "$3/.git"
}

# ── Doc-path helpers ─────────────────────────────────────────────────

# Fetch meta/libraries.json via gh API; emit one doc-path per line.
get_doc_paths() {
  local repo="$1" ref="$2" json
  json=$(gh api "repos/${BOOST_ORG}/${repo}/contents/meta/libraries.json?ref=${ref}" \
    -H "Accept: application/vnd.github.v3.raw" 2>/dev/null) || return 1
  echo "$json" | jq -r --arg repo "$repo" '
    (if type == "array" then . else [.] end)
    | .[]
    | select(type == "object")
    | select((.name // "") != "" and (.key // "") != "")
    | .key as $key
    | if $key == $repo then "doc"
      elif ($key | startswith($repo + "/")) then ($key[($repo | length + 1):] + "/doc")
      else ($key + "/doc")
      end
  '
}

# Prune a cloned repo to only root files + the given doc-path subtrees.
# E.g. ("doc") → keep all root files + entire doc/.
#      ("minmax/doc" "string/doc") → keep root files + those two subtrees.
prune_to_doc_only() {
  local dir="$1"; shift
  local keep_paths=("$@")
  [[ ${#keep_paths[@]} -eq 0 ]] && return

  local first_segs=()
  for p in "${keep_paths[@]}"; do first_segs+=("${p%%/*}"); done

  # Delete root-level dirs not needed by any keep path.
  # Use find instead of glob so dotdirs (e.g. .drone, .github) are included.
  while IFS= read -r item; do
    local name="${item##*/}"
    local needed=0
    for seg in "${first_segs[@]}"; do
      [[ "$name" == "$seg" ]] && { needed=1; break; }
    done
    [[ $needed -eq 0 ]] && rm -rf "$item"
  done < <(find "$dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)

  # For paths deeper than one level (e.g. "minmax/doc"), prune the
  # intermediate directory so only the target subdir survives.
  for p in "${keep_paths[@]}"; do
    local first="${p%%/*}"
    [[ "$first" == "$p" ]] && continue  # depth 1 ("doc"): keep entire dir
    local rest_first="${p#"${first}"/}"; rest_first="${rest_first%%/*}"
    for f in "$dir/$first"/*; do [[ -f "$f" ]] && rm -f "$f"; done
    while IFS= read -r item; do
      local name="${item##*/}"
      [[ "$name" == "$rest_first" ]] || rm -rf "$item"
    done < <(find "$dir/$first" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
  done
}

# ── Organization repo helpers ────────────────────────────────────────

# Copy create-tag.yml asset into repo.
add_create_tag_workflow() {
  local repo_dir="$1" wf_dir="$1/.github/workflows"
  mkdir -p "$wf_dir/assets"
  cp "$GITHUB_WORKSPACE/.github/workflows/assets/create-tag.yml" \
    "$wf_dir/create-tag.yml"
  cp "$GITHUB_WORKSPACE/.github/workflows/assets/env.sh" \
    "$wf_dir/assets/env.sh"
  git -C "$repo_dir" add ".github/workflows/create-tag.yml" ".github/workflows/assets/env.sh"
  git -C "$repo_dir" commit -m "Add create-tag workflow"
}

# ── Translations repo helpers ─────────────────────────────────────────

ensure_local_branch_in_translations() {
  local dir="$1" lang_code="$2"
  local branch="${LOCAL_BRANCH_PREFIX}${lang_code}"
  if git -C "$dir" ls-remote --exit-code --heads origin "$branch" &>/dev/null; then
    echo "  Branch $branch already exists in $TRANSLATIONS_REPO." >&2
  else
    echo "  Creating branch $branch in $TRANSLATIONS_REPO from $MASTER_BRANCH..." >&2
    git -C "$dir" checkout -B "$MASTER_BRANCH" "origin/$MASTER_BRANCH"
    git -C "$dir" checkout -b "$branch"
    rm -rf "$dir/libs" "$dir/.gitmodules"
    git -C "$dir" rm -rf --cached libs .gitmodules 2>/dev/null || true
    if ! git -C "$dir" diff --cached --quiet; then
      git -C "$dir" commit -m "Init $branch"
    fi
    git -C "$dir" push -u origin "$branch"
    echo "  Created branch $branch." >&2
  fi
}

ensure_translations_cloned() {
  [[ -d "$3/.git" ]] && return
  clone_repo "https://github.com/${1}/${2}.git" "$MASTER_BRANCH" "$3" keep
  set_git_bot_config "$3"
}

submodule_in_gitmodules() {
  git -C "$1" config --file .gitmodules --get "submodule.${2}.url" &>/dev/null
}

update_translations_submodule() {
  local dir="$1" org="$2" sub_name="$3" branch="$4"
  local libs_path="$dir/libs/$sub_name"
  local sub_path="libs/$sub_name"
  local sub_url="https://github.com/${org}/${sub_name}.git"

  if submodule_in_gitmodules "$dir" "$sub_path" && [[ -d "$libs_path" ]]; then
    if ! git -C "$dir" submodule update --init "$sub_path"; then
      echo "  submodule update --init failed for $sub_path" >&2
      return 1
    fi
    git -C "$dir" config "submodule.${sub_path}.branch" "$branch"
    if ! git -C "$dir" submodule update --remote "$sub_path"; then
      echo "  submodule update --remote failed for $sub_path" >&2; return 1
    fi
    git -C "$dir" add "$sub_path"
  else
    # Submodule not registered on this branch yet; add it fresh.
    rm -rf "$libs_path" "$dir/.git/modules/$sub_path"
    git -C "$dir" submodule add -b "$branch" "$sub_url" "$sub_path"
    git -C "$dir" add .gitmodules "$sub_path"
  fi
}

commit_and_push_translations_branch() {
  local dir="$1" branch="$2" libs_ref="$3" force="${4:-false}"
  git -C "$dir" status --short
  if git -C "$dir" diff --cached --quiet; then
    echo "  No staged submodule changes on $branch; skipping commit." >&2
  else
    git -C "$dir" commit -m "Update libs submodules to $libs_ref"
  fi
  if [[ "$force" == "true" ]]; then
    git -C "$dir" push --force-with-lease origin "$branch"
  else
    git -C "$dir" push origin "$branch"
  fi
}

# Update one branch of the translations super-repo (checkout → update pointers → push).
sync_translations_branch() {
  local dir="$1" branch="$2" libs_ref="$3" force="${4:-false}"
  git -C "$dir" checkout -B "$branch" "origin/$branch"
  for sub in "${UPDATES[@]}"; do
    update_translations_submodule "$dir" "$MODULE_ORG" "$sub" "$branch"
  done
  commit_and_push_translations_branch "$dir" "$branch" "$libs_ref" "$force"
}

finalize_translations_master() {
  local dir="$1" libs_ref="$2"
  [[ ${#UPDATES[@]} -eq 0 ]] && return
  git -C "$dir" fetch origin
  sync_translations_branch "$dir" "$MASTER_BRANCH" "$libs_ref"
}

finalize_translations_local() {
  local dir="$1" libs_ref="$2" lang_code="$3"
  [[ ${#UPDATES[@]} -eq 0 ]] && return
  git -C "$dir" fetch origin
  sync_translations_branch "$dir" "${LOCAL_BRANCH_PREFIX}${lang_code}" "$libs_ref" true
}

# Used by add-submodules.yml (start-translation calls finalize_translations_* directly).
finalize_translations_repo() {
  local dir="$1" libs_ref="$2"
  shift 2
  local lang_codes_arr=("$@")
  finalize_translations_master "$dir" "$libs_ref"
  for lang_code in "${lang_codes_arr[@]}"; do
    finalize_translations_local "$dir" "$libs_ref" "$lang_code"
  done
}

# ── Parsing helpers ───────────────────────────────────────────────────

# Parse "[zh_Hans, en]" or "zh_Hans,en" into one code per line.
parse_list() {
  local s="$1"
  s="${s//[[:space:]]/}"
  s="${s#[}"; s="${s%]}"
  [[ -z "$s" ]] && return
  IFS=',' read -ra parts <<< "$s"
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] && echo "$part"
  done
}

# Parse "[.adoc, .md]" or '[".adoc",".md"]' into one extension per line.
parse_extensions() {
  local s="$1"
  s="${s//[[:space:]]/}"; [[ -z "$s" ]] && return
  s="${s#[}"; s="${s%]}"
  local result=()
  IFS=',' read -ra parts <<< "$s"
  for part in "${parts[@]}"; do
    part="${part//\"/}"; part="${part//\'/}"
    [[ -z "$part" ]] && continue
    [[ "$part" == .* ]] || part=".${part}"
    result+=("$part")
  done
  printf '%s\n' "${result[@]}"
}

# Return 0 when $1 is a well-formed Weblate language code.
is_valid_lang_code() {
  local code="$1"
  [[ -n "$code" ]] || return 1
  # ISO 639-1/2/3 primary (2–3 letters) + optional BCP 47 subtags (_ or -).
  # Rejects spaces, slashes, and other git-ref-hostile characters.
  [[ "$code" =~ ^[A-Za-z]{2,3}([_-][A-Za-z0-9]{2,8})*$ ]]
}

# Exit 1 with a clear message if any argument is invalid.
validate_lang_codes() {
  local invalid=() code
  for code in "$@"; do
    is_valid_lang_code "$code" || invalid+=("$code")
  done
  if [[ ${#invalid[@]} -gt 0 ]]; then
    echo "Error: invalid language code(s): ${invalid[*]}" >&2
    echo "Expected ISO 639-1/2/3 or BCP 47 (e.g. en, zh_Hans, pt_BR)." >&2
    exit 1
  fi
}

# Exit 1 if LANG_CODES workflow env is unset or empty.
require_lang_codes() {
  [[ -n "${LANG_CODES:-}" ]] || {
    echo "Error: lang_codes not set in client_payload or vars.LANG_CODES." >&2
    exit 1
  }
}

# Exit 1 if a named variable is unset or empty.
_require_nonempty() {
  local var_name="$1" err_msg="$2"
  # :- keeps indirect expansion safe under set -u when the named var is unset.
  [[ -n "${!var_name:-}" ]] || { echo "$err_msg" >&2; exit 1; }
}

# validate_secrets [weblate]
# Call after: source env.sh && source lib.sh
# Reads workflow env + env.sh globals; exits 1 with a clear message on first failure.
validate_secrets() {
  local require_weblate=0
  [[ "${1:-}" == "weblate" ]] && require_weblate=1

  _require_nonempty GITHUB_TOKEN "Error: SYNC_TOKEN secret is not set."
  require_lang_codes
  _require_nonempty ORG "Error: ORG is not set."
  _require_nonempty MODULE_ORG "Error: MODULE_ORG is not set."
  _require_nonempty BOT_NAME "Error: BOT_NAME is not set."
  _require_nonempty BOT_EMAIL "Error: BOT_EMAIL is not set."
  _require_nonempty BOOST_ORG "Error: BOOST_ORG is not set."
  _require_nonempty MASTER_BRANCH "Error: MASTER_BRANCH is not set."
  _require_nonempty TRANSLATIONS_REPO "Error: TRANSLATIONS_REPO is not set."

  if [[ "$require_weblate" -eq 1 ]]; then
    _require_nonempty WEBLATE_URL "Error: WEBLATE_URL secret is not set."
    _require_nonempty WEBLATE_TOKEN "Error: WEBLATE_TOKEN secret is not set."
  fi
}
