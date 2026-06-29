# shellcheck shell=bash
# Shared orchestration for add-submodules and start-translation workflows.
# Source after env.sh and lib.sh; add-submodules also sources add_submodules.sh.
#
# Globals set/consumed:
#   WORK_DIR, BOOST_WORK, TRANS_DIR, ORG_WORK (optional)
#   submodule_names, submodule_fatal, libs_ref, boost_org
#   lang_codes_arr, SUBMODULES, LIBS_REF (env)
# shellcheck disable=SC2034,SC2154

# Create temp workspace dirs. Pass "with_org_work" to also set ORG_WORK.
init_translation_work_dirs() {
  local with_org_work="${1:-}"
  WORK_DIR=$(mktemp -d)
  trap 'rm -rf "$WORK_DIR"' EXIT
  BOOST_WORK="$WORK_DIR/boost"
  TRANS_DIR="$WORK_DIR/translations"
  mkdir -p "$BOOST_WORK" "$TRANS_DIR"
  if [[ "$with_org_work" == "with_org_work" ]]; then
    ORG_WORK="$WORK_DIR/$MODULE_ORG"
    mkdir -p "$ORG_WORK"
  fi
}

# Emit libs/ submodule basenames (one per line) from raw .gitmodules content.
libs_submodule_names_from_gitmodules_content() {
  local content="$1"
  echo "$content" \
    | grep '^\s*path\s*=' \
    | sed 's/.*=\s*//' \
    | { grep '^libs/' || true; } \
    | sed 's|^libs/||'
}

# Emit libs/ submodule basenames from a .gitmodules file path.
libs_submodule_names_from_gitmodules_file() {
  local gitmodules_file="$1"
  git config -f "$gitmodules_file" --get-regexp 'submodule\..*\.path' 2>/dev/null \
    | awk '{print $2}' \
    | { grep '^libs/' || true; } \
    | sed 's|^libs/||'
}

# Fetch boostorg/boost .gitmodules at ref; print raw content. Return 1 on failure.
fetch_boost_gitmodules_at_ref() {
  local ref="$1"
  gh api \
    "repos/boostorg/boost/contents/.gitmodules?ref=$ref" \
    -H "Accept: application/vnd.github.v3.raw" 2>/dev/null
}

# Populate global submodule_names from SUBMODULES env or boost .gitmodules at LIBS_REF.
# Return 1 when auto-discovery fetch fails.
resolve_add_submodules_names() {
  # shellcheck disable=SC2153
  local libs_ref_for_fetch="${libs_ref:-$LIBS_REF}"
  if [[ -n "${SUBMODULES:-}" ]]; then
    mapfile -t submodule_names < <(parse_list "$SUBMODULES")
    echo "Using ${#submodule_names[@]} submodules from input." >&2
    return 0
  fi
  echo "Fetching .gitmodules from boostorg/boost at ${libs_ref_for_fetch}..." >&2
  local gitmodules_content
  gitmodules_content=$(fetch_boost_gitmodules_at_ref "$libs_ref_for_fetch") || {
    phase_err "Failed to fetch .gitmodules"
    return 1
  }
  mapfile -t submodule_names < <(libs_submodule_names_from_gitmodules_content "$gitmodules_content")
  echo "Found ${#submodule_names[@]} libs submodules." >&2
}

# Clone translations repo and ensure local-{lang} branches exist.
ensure_all_translation_lang_branches() {
  local rc=0
  ensure_translations_cloned "$ORG" "$TRANSLATIONS_REPO" "$TRANS_DIR" || rc=$?
  if [[ $rc -eq 0 ]]; then
    local lang_code
    for lang_code in "${lang_codes_arr[@]}"; do
      ensure_local_branch_in_translations "$TRANS_DIR" "$lang_code" || rc=$?
      [[ $rc -ne 0 ]] && break
    done
  fi
  return "$rc"
}

# Run $1 (function name) for each remaining submodule name; update UPDATES / SUBMODULE_FATAL.
process_submodule_list() {
  local processor="$1"
  shift
  local -a names=("$@")
  local total=${#names[@]} i sub rc
  submodule_fatal=0
  for i in "${!names[@]}"; do
    sub="${names[$i]}"
    echo "[$(( i + 1 ))/$total] $sub ..." >&2
    if "$processor" "$sub"; then
      record_submodule_update "$sub" || true
    else
      rc=$?
      if [[ $rc -eq 2 ]]; then
        record_submodule_fatal "$sub"
        submodule_fatal=$((submodule_fatal + 1))
      fi
    fi
  done
  print_submodule_processing_summary
  [[ $submodule_fatal -gt 0 ]] && \
    phase_err "$submodule_fatal submodule(s) failed with errors."
}

# Combine submodule_fatal count with finalize_rc; return combined exit code.
combine_batch_and_finalize_rc() {
  local finalize_rc="${1:-0}"
  local exit_rc=0
  [[ "${submodule_fatal:-0}" -gt 0 ]] && exit_rc=1
  [[ "$finalize_rc" -ne 0 ]] && exit_rc=$finalize_rc
  return "$exit_rc"
}

# add-submodules.yml entry point (sources env.sh, lib.sh, add_submodules.sh before calling).
add_submodules_main() {
  local rc finalize_rc exit_rc

  init_translation_state
  init_add_submodule_summary_buckets

  begin_phase "$PHASE_SETUP" "Validate inputs and prepare workspace"
  validate_secrets
  parse_and_validate_lang_codes
  echo "Lang codes: ${lang_codes_arr[*]}" >&2

  init_translation_work_dirs
  gh auth setup-git
  libs_ref="${LIBS_REF:?}"
  boost_org="${BOOST_ORG:?}"
  end_phase

  begin_phase "$PHASE_ENSURE_BRANCHES" "Ensure local branches in translations repo"
  rc=0
  ensure_all_translation_lang_branches || rc=$?
  end_phase
  [[ $rc -ne 0 ]] && exit $rc

  begin_phase "$PHASE_PROCESS_SUBMODULES" "Process submodules"
  resolve_add_submodules_names || {
    end_phase
    exit 1
  }

  [[ ${#submodule_names[@]} -eq 0 ]] && {
    echo "No submodules to process, nothing to do." >&2
    end_phase
    exit 0
  }

  process_submodule_list add_one_submodule "${submodule_names[@]}"
  end_phase

  begin_phase "$PHASE_FINALIZE_TRANSLATIONS" "Finalize translations repo"
  finalize_rc=0
  finalize_translations_repo "$TRANS_DIR" "$LIBS_REF" "${lang_codes_arr[@]}" || finalize_rc=$?
  end_phase

  combine_batch_and_finalize_rc "$finalize_rc" || exit $?
  echo "Done." >&2
}
