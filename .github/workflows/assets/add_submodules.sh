# shellcheck shell=bash
# add-submodules orchestration helpers.
# Source after env.sh and lib.sh. Requires globals:
# MODULE_ORG, MASTER_BRANCH, BOOST_ORG, BOOST_WORK, libs_ref, boost_org,
# lang_codes_arr, REPO_EXISTS_SKIP, META_MISSING, NO_DOC_PATHS, GITHUB_WORKSPACE.
# shellcheck disable=SC2034,SC2154

create_repo() {
  gh repo create "$1/$2" --public > /dev/null \
    || { echo "Create repo $1/$2 failed" >&2; return 2; }
}

set_default_branch() {
  gh api --method PATCH "repos/$1/$2" -f "default_branch=$3" \
    || { phase_err "set default branch to $3 failed for $1/$2."; return 2; }
}

create_new_repo_and_push() {
  local org="$1" sub_name="$2" sub_clone="$3" repo_url="$4" libs_ref="$5"
  create_repo "$org" "$sub_name" || return 2
  git -C "$sub_clone" init || return 2
  set_git_bot_config "$sub_clone" || return 2
  git -C "$sub_clone" add -A || return 2
  git -C "$sub_clone" commit -m "Create the original documentation of $libs_ref" || return 2
  git -C "$sub_clone" branch -M "$MASTER_BRANCH" || return 2
  git -C "$sub_clone" remote remove origin 2>/dev/null || true
  git -C "$sub_clone" remote add origin "$repo_url" || return 2
  git -C "$sub_clone" push -u origin "$MASTER_BRANCH" || return 2
  git -C "$sub_clone" push origin "$MASTER_BRANCH" || return 2
  for lang_code in "${lang_codes_arr[@]}"; do
    local local_br="${LOCAL_BRANCH_PREFIX}${lang_code}"
    git -C "$sub_clone" checkout -B "$local_br" "$MASTER_BRANCH" || return 2
    add_create_tag_workflow "$sub_clone" || return 2
    git -C "$sub_clone" push -u origin "$local_br" || return 2
  done
  set_default_branch "$org" "$sub_name" "$MASTER_BRANCH" || return 2
}

# Create one MODULE_ORG mirror repo from a boostorg lib (add-submodules only).
add_one_submodule() {
  local sub_name="$1" doc_paths

  if repo_exists "$MODULE_ORG" "$sub_name"; then
    REPO_EXISTS_SKIP+=("$sub_name")
    echo "  Skipping: $MODULE_ORG/$sub_name already exists." >&2; return 1
  fi

  doc_paths=$(get_doc_paths "$sub_name" "$libs_ref") || {
    META_MISSING+=("$sub_name")
    echo "  No libraries.json." >&2; return 2
  }
  [[ -z "$doc_paths" ]] && {
    NO_DOC_PATHS+=("$sub_name")
    echo "  No doc paths in metadata, skipping." >&2; return 1
  }

  local sub_clone="$BOOST_WORK/$sub_name"
  clone_repo "https://github.com/${boost_org}/${sub_name}.git" \
    "$libs_ref" "$sub_clone" || { echo "  Clone failed." >&2; return 2; }

  local -a paths_arr
  mapfile -t paths_arr <<< "$doc_paths"
  prune_to_doc_only "$sub_clone" "${paths_arr[@]}"

  local org_repo_url="https://github.com/${MODULE_ORG}/${sub_name}.git"
  create_new_repo_and_push "$MODULE_ORG" "$sub_name" "$sub_clone" "$org_repo_url" "$libs_ref" \
    || return 2
}
