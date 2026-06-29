# shellcheck shell=bash
# start-translation orchestration helpers.
# Source after env.sh and lib.sh. Requires globals:
# MODULE_ORG, MASTER_BRANCH, BOOST_ORG, BOOST_WORK, ORG_WORK, libs_ref,
# lang_codes_arr, ORG_REPO_MISSING, META_MISSING,
# NO_DOC_PATHS, GITHUB_WORKSPACE, START_PHASE (optional: mirrors | local).
# Translation state (UPDATES, add_or_update): init via init_translation_state /
# init_add_or_update_lang; write via record_*; read by finalize_translations_* /
# trigger_weblate.
# shellcheck disable=SC2034,SC2154

# Wipe dest_repo (except .git), copy pruned source, commit, push master only.
sync_repo_master() {
  local dest_repo="$1" sub_clone="$2" libs_ref="$3"
  find "$dest_repo" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} + || return 2
  cp -r "$sub_clone/." "$dest_repo/" || return 2
  set_git_bot_config "$dest_repo"
  git -C "$dest_repo" add -A || return 2
  if ! git -C "$dest_repo" diff --cached --quiet; then
    git -C "$dest_repo" commit -m "Update the original documentation of $libs_ref" || return 2
  fi
  git -C "$dest_repo" push origin "$MASTER_BRANCH" || return 2
}

# Merge master into local-{lang_code} and push.
update_local_merge_from_master() {
  local repo_dir="$1" lang_code="$2"
  local local_br="${LOCAL_BRANCH_PREFIX}${lang_code}"
  set_git_bot_config "$repo_dir"
  git -C "$repo_dir" fetch origin "$MASTER_BRANCH" || return 2
  git -C "$repo_dir" fetch origin "$local_br" || return 2
  git -C "$repo_dir" checkout -B "$local_br" "origin/$local_br" || return 2
  git -C "$repo_dir" merge "origin/$MASTER_BRANCH" || return 2
  git -C "$repo_dir" push origin "${local_br}:${local_br}" || return 2
}

# Create local-{lang_code} in a library mirror repo from master, with create-tag.yml.
ensure_local_branch_in_repo() {
  local dest_repo="$1" sub_name="$2" lang_code="$3"
  local local_br="${LOCAL_BRANCH_PREFIX}${lang_code}"
  set_git_bot_config "$dest_repo"
  if git -C "$dest_repo" ls-remote --exit-code --heads origin "$local_br" &>/dev/null; then
    echo "  Branch $local_br already exists in $sub_name." >&2
    return 0
  fi
  echo "  Creating branch $local_br in $sub_name from $MASTER_BRANCH..." >&2
  git -C "$dest_repo" fetch origin "$MASTER_BRANCH" || return 2
  git -C "$dest_repo" checkout -B "$local_br" "origin/$MASTER_BRANCH" || return 2
  add_create_tag_workflow "$dest_repo" || return 2
  git -C "$dest_repo" push -u origin "$local_br" || return 2
  echo "  Created branch $local_br." >&2
}

# Handle local-{lang_code} branch in a library mirror repo after master is synced.
# Returns 0 if submodule should be added to add_or_update[lang_code]; 1 if skipped (open PR); 2 on git failure.
process_local_branch() {
  local dest_repo="$1" sub_name="$2" lang_code="$3"
  local local_br="${LOCAL_BRANCH_PREFIX}${lang_code}"
  if git -C "$dest_repo" ls-remote --exit-code --heads origin "$local_br" &>/dev/null; then
    has_open_translation_pr "$MODULE_ORG" "$sub_name" "$lang_code"
    case $? in
      0)
        OPEN_PR_SKIP+=("$sub_name")
        echo "  Open translation PR found for $sub_name ($local_br), skipping." >&2
        return 1
        ;;
      2) return 2 ;;
    esac
    update_local_merge_from_master "$dest_repo" "$lang_code" || return 2
  else
    ensure_local_branch_in_repo "$dest_repo" "$sub_name" "$lang_code" || return 2
  fi
  return 0
}

# Sync one existing MODULE_ORG mirror: mirror master and/or local branches.
sync_one_submodule() {
  local sub_name="$1" doc_paths
  local phase="${START_PHASE:-}"

  case "$phase" in
    ""|"${START_PHASE_MIRRORS}"|"${START_PHASE_LOCAL}") ;;
    *)
      echo "Error: [${CURRENT_PHASE:-$PHASE_PROCESS_SUBMODULES}] invalid START_PHASE='$phase'; expected ${START_PHASE_MIRRORS}, ${START_PHASE_LOCAL}, or unset." >&2
      return 2
      ;;
  esac

  if ! repo_exists "$MODULE_ORG" "$sub_name"; then
    ORG_REPO_MISSING+=("$sub_name")
    echo "  Error: $MODULE_ORG/$sub_name does not exist. Run add-submodules first." >&2
    return 2
  fi

  doc_paths=$(get_doc_paths "$sub_name" "$libs_ref") || {
    META_MISSING+=("$sub_name")
    echo "  No libraries.json." >&2; return 2
  }
  [[ -z "$doc_paths" ]] && {
    NO_DOC_PATHS+=("$sub_name")
    echo "  No doc paths in metadata, skipping." >&2; return 1
  }

  local org_repo_url="https://github.com/${MODULE_ORG}/${sub_name}.git"
  local dest_repo="$ORG_WORK/$sub_name"

  if [[ "$phase" != "${START_PHASE_LOCAL}" ]]; then
    local sub_clone="$BOOST_WORK/$sub_name"
    clone_repo "https://github.com/${BOOST_ORG}/${sub_name}.git" \
      "$libs_ref" "$sub_clone" || { echo "  Clone failed." >&2; return 2; }

    local -a paths_arr
    mapfile -t paths_arr <<< "$doc_paths"
    prune_to_doc_only "$sub_clone" "${paths_arr[@]}"

    clone_repo "$org_repo_url" "$MASTER_BRANCH" "$dest_repo" keep || {
      echo "  clone_repo failed." >&2; return 2
    }

    sync_repo_master "$dest_repo" "$sub_clone" "$libs_ref" || return 2

    if [[ "$phase" == "${START_PHASE_MIRRORS}" ]]; then
      return 0
    fi
  else
    clone_repo "$org_repo_url" "$MASTER_BRANCH" "$dest_repo" keep || {
      echo "  clone_repo failed." >&2; return 2
    }
    set_git_bot_config "$dest_repo"
  fi

  local any_added=0 rc
  for lang_code in "${lang_codes_arr[@]}"; do
    if process_local_branch "$dest_repo" "$sub_name" "$lang_code"; then
      record_add_or_update_submodule "$lang_code" "$sub_name" || return 2
      any_added=1
    else
      rc=$?
      [[ $rc -eq 2 ]] && return 2
    fi
  done
  [[ $any_added -eq 1 ]]
}

# POST add-or-update payload to Weblate for one language.
# Reads add_or_update[lang_code]; skips when empty; validates names before POST.
trigger_weblate() {
  # Locals differ from WEBLATE_* env names to avoid ShellCheck SC2153 misspelling hints.
  local api_base_url="$1" api_token="$2" libs_ref="$3" exts_json="$4" lang_code="$5"

  local subs="${add_or_update[$lang_code]:-}"
  [[ -z "$subs" ]] && {
    echo "Weblate skipped: no translations to update." >&2; return
  }

  validate_add_or_update_entry "$lang_code" "$subs" || return 1

  local subs_json add_or_update_json
  subs_json=$(echo "$subs" | tr ' ' '\n' | grep -v '^$' | jq -R . | jq -s .)
  add_or_update_json=$(jq -n --arg lc "$lang_code" --argjson s "$subs_json" \
    '{($lc): $s}')

  [[ "$add_or_update_json" == "{}" ]] && {
    echo "Weblate skipped: no translations to update." >&2; return
  }

  local payload
  payload=$(jq -n \
    --arg org "$MODULE_ORG" --arg ver "$libs_ref" \
    --argjson add "$add_or_update_json" --argjson ext "$exts_json" \
    '{organization:$org,add_or_update:$add,version:$ver,extensions:$ext}')

  echo "Weblate trigger parameters:" >&2
  echo "  organization: $MODULE_ORG" >&2
  echo "  version:      $libs_ref" >&2
  echo "  extensions:   $exts_json" >&2
  echo "  add_or_update:" >&2
  echo "$add_or_update_json" | jq -r 'to_entries[] | "    \(.key): \(.value | join(", "))"' >&2

  local resp http_code curl_exit=0
  resp=$(mktemp)
  http_code=$(curl -sS -o "$resp" -w "%{http_code}" --max-time 120 -X POST \
    -H "Authorization: Token $api_token" \
    -H "Content-Type: application/json" \
    -H "User-Agent: BoostDocsSync/1.0" \
    -d "$payload" \
    "${api_base_url%/}/${WEBLATE_ENDPOINT_PATH}" \
  ) || curl_exit=$?

  if [[ $curl_exit -ne 0 ]]; then
    phase_err "Weblate trigger failed (curl exit $curl_exit)."
    cat "$resp" >&2 || true
    rm -f "$resp"
    return 1
  fi

  case "$http_code" in
    202)
      echo "Weblate add-or-update accepted (HTTP 202, async)." >&2
      jq . "$resp" >&2 || cat "$resp" >&2
      ;;
    200)
      echo "Weblate returned HTTP 200 (sync server); treating as success." >&2
      cat "$resp" >&2 || true
      ;;
    *)
      phase_err "Weblate returned HTTP $http_code (expected 202)."
      cat "$resp" >&2 || true
      rm -f "$resp"
      return 1
      ;;
  esac
  rm -f "$resp"
}
