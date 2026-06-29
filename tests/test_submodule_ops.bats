#!/usr/bin/env bats

setup() {
  # shellcheck source=tests/helpers/common.bash
  source "$BATS_TEST_DIRNAME/helpers/common.bash"
  load_submodule_ops
  init_translation_state
  init_submodule_summary_buckets
}

@test "libs_submodule_names_from_gitmodules_content: extracts libs basenames only" {
  local content output
  content='[submodule "libs/algorithm"]
	path = libs/algorithm
[submodule "tools/quickbook"]
	path = tools/quickbook
[submodule "libs/system"]
	path = libs/system
'
  output=$(libs_submodule_names_from_gitmodules_content "$content")
  [ "$output" = $'algorithm\nsystem' ]
}

@test "libs_submodule_names_from_gitmodules_file: reads paths from file" {
  local gitmodules
  gitmodules="$(mktemp)"
  cat >"$gitmodules" <<'EOF'
[submodule "libs/json"]
	path = libs/json
[submodule "other"]
	path = other/path
EOF
  run libs_submodule_names_from_gitmodules_file "$gitmodules"
  rm -f "$gitmodules"
  [ "$status" -eq 0 ]
  [ "$output" = "json" ]
}

@test "resolve_add_submodules_names: uses SUBMODULES when set" {
  SUBMODULES="algorithm, system"
  LIBS_REF="develop"
  resolve_add_submodules_names
  [ "${#submodule_names[@]}" -eq 2 ]
  [ "${submodule_names[0]}" = "algorithm" ]
  [ "${submodule_names[1]}" = "system" ]
}

@test "resolve_add_submodules_names: auto-discovers via fetch_boost_gitmodules_at_ref" {
  unset SUBMODULES
  libs_ref="boost-1.90.0"
  fetch_boost_gitmodules_at_ref() {
    echo '[submodule "libs/unordered"]
	path = libs/unordered
'
  }
  resolve_add_submodules_names
  [ "${#submodule_names[@]}" -eq 1 ]
  [ "${submodule_names[0]}" = "unordered" ]
}

@test "resolve_add_submodules_names: returns 1 when fetch fails" {
  unset SUBMODULES
  libs_ref="develop"
  fetch_boost_gitmodules_at_ref() { return 1; }
  set +e
  resolve_add_submodules_names
  status=$?
  set -e
  [ "$status" -eq 1 ]
}

@test "process_submodule_list: records updates and fatals by exit code" {
  stub_processor() {
    case "$1" in
      ok) return 0 ;;
      skip) return 1 ;;
      fail) return 2 ;;
    esac
  }

  set +e
  process_submodule_list stub_processor ok skip fail
  status=$?
  set -e
  [ "$status" -eq 1 ]
  [ "${#UPDATES[@]}" -eq 1 ]
  [ "${UPDATES[0]}" = "ok" ]
  [ "${#SUBMODULE_FATAL[@]}" -eq 1 ]
  [ "${SUBMODULE_FATAL[0]}" = "fail" ]
  [ "$submodule_fatal" -eq 1 ]
}

@test "process_submodule_list: returns 0 when no fatal failures" {
  stub_processor() { return 0; }
  process_submodule_list stub_processor ok ok
}

@test "combine_batch_and_finalize_rc: zero when no failures" {
  submodule_fatal=0
  run combine_batch_and_finalize_rc 0
  [ "$status" -eq 0 ]
}

@test "combine_batch_and_finalize_rc: 1 when submodule_fatal > 0" {
  submodule_fatal=2
  run combine_batch_and_finalize_rc 0
  [ "$status" -eq 1 ]
}

@test "combine_batch_and_finalize_rc: finalize rc wins when non-zero" {
  submodule_fatal=0
  run combine_batch_and_finalize_rc 3
  [ "$status" -eq 3 ]
}

@test "combine_batch_and_finalize_rc: finalize rc wins over batch fatal" {
  submodule_fatal=2
  run combine_batch_and_finalize_rc 3
  [ "$status" -eq 3 ]
}

@test "combine_batch_and_finalize_rc: submodule_fatal sets exit 1 even if finalize is 0" {
  submodule_fatal=1
  run combine_batch_and_finalize_rc 0
  [ "$status" -eq 1 ]
}

@test "init_translation_work_dirs: creates BOOST_WORK and optional ORG_WORK" {
  run bash -c '
    set -euo pipefail
    # shellcheck source=tests/helpers/common.bash
    source "$1/helpers/common.bash"
    load_submodule_ops
    init_translation_work_dirs with_org_work
    [[ -d "$BOOST_WORK" && -d "$TRANS_DIR" && -d "$ORG_WORK" ]]
    [[ "$ORG_WORK" == "$WORK_DIR/$MODULE_ORG" ]]
  ' _ "$BATS_TEST_DIRNAME"
  [ "$status" -eq 0 ]
}
