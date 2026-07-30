#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$ROOT/scripts/trigger-add-submodules.sh"
  # shellcheck source=tests/helpers/http_mock.bash
  source "$BATS_TEST_DIRNAME/helpers/http_mock.bash"
}

teardown() {
  restore_dispatch_curl_stub
}

@test "trigger-add-submodules: --help exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"trigger-add-submodules.sh"* ]]
}

@test "trigger-add-submodules: missing --submodules errors with usage" {
  run "$SCRIPT" --repo owner/repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: --submodules is required"* ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "trigger-add-submodules: empty --submodules errors with usage" {
  run "$SCRIPT" --repo owner/repo --submodules ''
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: --submodules is required"* ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "trigger-add-submodules: explicit --submodules dispatches payload" {
  install_dispatch_curl_stub
  run "$SCRIPT" --repo owner/repo --token fake-token --submodules 'a, b'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dispatched add-submodules to owner/repo (HTTP 204)"* ]]
  body="$(extract_dispatch_request_body "$MOCK_DISPATCH_REQUEST_LOG")"
  echo "$body" | jq -e '.event_type == "add-submodules"' >/dev/null
  echo "$body" | jq -e '.client_payload.submodules == "a, b"' >/dev/null
}
