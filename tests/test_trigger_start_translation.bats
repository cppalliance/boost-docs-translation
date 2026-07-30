#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$ROOT/scripts/trigger-start-translation.sh"
  # shellcheck source=tests/helpers/http_mock.bash
  source "$BATS_TEST_DIRNAME/helpers/http_mock.bash"
}

teardown() {
  restore_dispatch_curl_stub
}

@test "trigger-start-translation: --help exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"trigger-start-translation.sh"* ]]
}

@test "trigger-start-translation: unknown option errors with usage" {
  run "$SCRIPT" --not-a-flag
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --not-a-flag"* ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "trigger-start-translation: minimal dispatch includes defaults and omits lang_codes" {
  install_dispatch_curl_stub
  run "$SCRIPT" --repo owner/repo --token fake-token
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dispatched start-translation to owner/repo (HTTP 204)"* ]]
  body="$(extract_dispatch_request_body "$MOCK_DISPATCH_REQUEST_LOG")"
  echo "$body" | jq -e '.event_type == "start-translation"' >/dev/null
  echo "$body" | jq -e '.client_payload.version == "boost-1.90.0"' >/dev/null
  echo "$body" | jq -e '.client_payload.extensions == ".adoc, .qbk"' >/dev/null
  echo "$body" | jq -e '.client_payload | has("lang_codes") | not' >/dev/null
}

@test "trigger-start-translation: explicit --lang-codes included in payload" {
  install_dispatch_curl_stub
  run "$SCRIPT" --repo owner/repo --token fake-token --lang-codes zh_Hans
  [ "$status" -eq 0 ]
  body="$(extract_dispatch_request_body "$MOCK_DISPATCH_REQUEST_LOG")"
  echo "$body" | jq -e '.client_payload.lang_codes == "zh_Hans"' >/dev/null
}

@test "trigger-start-translation: non-204 from GitHub API fails" {
  install_dispatch_curl_stub
  MOCK_DISPATCH_STATUS=500
  MOCK_DISPATCH_RESPONSE_BODY='{"message":"Server Error"}'
  export MOCK_DISPATCH_STATUS MOCK_DISPATCH_RESPONSE_BODY
  run "$SCRIPT" --repo owner/repo --token fake-token
  [ "$status" -eq 1 ]
  [[ "$output" == *"GitHub API error: HTTP 500"* ]]
}
