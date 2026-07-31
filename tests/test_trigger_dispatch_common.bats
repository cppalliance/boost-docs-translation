#!/usr/bin/env bats

setup() {
  # shellcheck source=tests/helpers/http_mock.bash
  source "$BATS_TEST_DIRNAME/helpers/http_mock.bash"
  dispatch_common_setup
  # shellcheck source=/dev/null
  source "$ROOT/scripts/trigger-dispatch-common.sh"
}

teardown() {
  common_teardown
}

@test "build_dispatch_json: sets event_type and includes non-empty fields" {
  run build_dispatch_json "add-submodules" \
    version "boost-1.90.0" submodules "a, b" lang_codes ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.event_type == "add-submodules"' >/dev/null
  echo "$output" | jq -e '.client_payload.version == "boost-1.90.0"' >/dev/null
  echo "$output" | jq -e '.client_payload.submodules == "a, b"' >/dev/null
  echo "$output" | jq -e '.client_payload | has("lang_codes") | not' >/dev/null
}

@test "build_dispatch_json: omits all-empty client_payload keys" {
  run build_dispatch_json "start-translation" version "" lang_codes "" extensions ""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.event_type == "start-translation"' >/dev/null
  echo "$output" | jq -e '.client_payload == {}' >/dev/null
}

@test "build_dispatch_json: python fallback when jq unavailable" {
  run bash -c '
    command() {
      if [[ "$1" == "-v" && "$2" == "jq" ]]; then
        return 1
      fi
      builtin command "$@"
    }
    source "'"$ROOT"'/scripts/trigger-dispatch-common.sh"
    if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
      exit 77
    fi
    build_dispatch_json "start-translation" version "boost-1.90.0" lang_codes "" extensions ".adoc"
  '
  if [[ "$status" -eq 77 ]]; then
    skip "python not available"
  fi
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.event_type == "start-translation"' >/dev/null
  echo "$output" | jq -e '.client_payload.version == "boost-1.90.0"' >/dev/null
  echo "$output" | jq -e '.client_payload.extensions == ".adoc"' >/dev/null
  echo "$output" | jq -e '.client_payload | has("lang_codes") | not' >/dev/null
}

@test "infer_repo_from_git: parses https remote URL" {
  run infer_repo_from_git "https://github.com/owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$output" = "owner/repo" ]
}

@test "infer_repo_from_git: parses scp-style remote URL" {
  run infer_repo_from_git "git@github.com:org/project.git"
  [ "$status" -eq 0 ]
  [ "$output" = "org/project" ]
}

@test "infer_repo_from_git: rejects non-GitHub URL" {
  run infer_repo_from_git "https://gitlab.com/group/project.git"
  [ "$status" -eq 1 ]
}

@test "resolve_trigger_repo: explicit repo wins" {
  run resolve_trigger_repo "explicit/owner"
  [ "$status" -eq 0 ]
  [ "$output" = "explicit/owner" ]
}

@test "resolve_trigger_repo: falls back to GITHUB_REPOSITORY" {
  run bash -c '
    source "'"$ROOT"'/scripts/trigger-dispatch-common.sh"
    export GITHUB_REPOSITORY="envorg/envrepo"
    resolve_trigger_repo ""
  '
  [ "$status" -eq 0 ]
  [ "$output" = "envorg/envrepo" ]
}

@test "resolve_trigger_repo: falls back to DEFAULT_REPO" {
  run bash -c '
    cd "$(mktemp -d)"
    source "'"$ROOT"'/scripts/trigger-dispatch-common.sh"
    unset GITHUB_REPOSITORY
    resolve_trigger_repo ""
  '
  [ "$status" -eq 0 ]
  [ "$output" = "cppalliance/boost-docs-translation" ]
}

@test "resolve_trigger_repo: returns 1 when all sources unset" {
  run bash -c '
    cd "$(mktemp -d)"
    source "'"$ROOT"'/scripts/trigger-dispatch-common.sh"
    unset GITHUB_REPOSITORY
    DEFAULT_REPO=""
    resolve_trigger_repo ""
  '
  [ "$status" -eq 1 ]
}

@test "resolve_trigger_token: explicit token" {
  run bash -c '
    source "'"$ROOT"'/scripts/trigger-dispatch-common.sh"
    export GH_TOKEN="ambient-should-not-win"
    resolve_trigger_token "explicit-token"
  '
  [ "$status" -eq 0 ]
  [ "$output" = "explicit-token" ]
}

@test "resolve_trigger_token: falls back to GH_TOKEN" {
  run bash -c '
    source "'"$ROOT"'/scripts/trigger-dispatch-common.sh"
    export GH_TOKEN="from-env"
    unset GITHUB_TOKEN
    resolve_trigger_token ""
  '
  [ "$status" -eq 0 ]
  [ "$output" = "from-env" ]
}

@test "resolve_trigger_token: returns 1 when missing" {
  run bash -c '
    source "'"$ROOT"'/scripts/trigger-dispatch-common.sh"
    unset GH_TOKEN GITHUB_TOKEN
    resolve_trigger_token ""
  '
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: set GH_TOKEN"* ]]
}

@test "post_repository_dispatch: succeeds on HTTP 204" {
  local payload='{"event_type":"add-submodules","client_payload":{}}'
  run post_repository_dispatch "owner/repo" "fake-token" "$payload" "add-submodules"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dispatched add-submodules to owner/repo (HTTP 204)"* ]]
  [ -f "$MOCK_DISPATCH_REQUEST_LOG" ]
  grep -q 'api.github.com/repos/owner/repo/dispatches' "$MOCK_DISPATCH_REQUEST_LOG"
}

@test "post_repository_dispatch: fails on non-204" {
  local payload='{"event_type":"add-submodules","client_payload":{}}'
  MOCK_DISPATCH_STATUS=403
  MOCK_DISPATCH_RESPONSE_BODY='{"message":"Forbidden"}'
  export MOCK_DISPATCH_STATUS MOCK_DISPATCH_RESPONSE_BODY
  run post_repository_dispatch "owner/repo" "fake-token" "$payload" "add-submodules"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GitHub API error: HTTP 403"* ]]
}
