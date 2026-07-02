#!/usr/bin/env bats

setup() {
  # shellcheck source=tests/helpers/test_helper.bash
  source "$BATS_TEST_DIRNAME/helpers/test_helper.bash"
  load_translation
  init_process_globals
  init_add_or_update_lang "en"
  add_or_update["en"]="algorithm system"
  exts_json='[".adoc"]'
  libs_ref="develop"
  WEBLATE_TOKEN="test-token"
}

teardown() {
  stop_weblate_mock_server
  restore_curl_stub
}

@test "trigger_weblate: POST succeeds on HTTP 202 with valid payload shape" {
  MOCK_WEBLATE_STATUS=202
  MOCK_WEBLATE_BODY='{"task_id":"abc123"}'
  start_weblate_mock_server

  set +e
  trigger_weblate "$MOCK_WEBLATE_BASE_URL" "$WEBLATE_TOKEN" "$libs_ref" "$exts_json" "en" \
    2>"$BATS_TMPDIR/weblate-202.stderr"
  status=$?
  set -e

  [ "$status" -eq 0 ]
  grep -q "Weblate add-or-update accepted (HTTP 202" "$BATS_TMPDIR/weblate-202.stderr"
  [ -f "$MOCK_WEBLATE_REQUEST_LOG" ]
  grep -q "HEADER:Authorization: Token $WEBLATE_TOKEN" "$MOCK_WEBLATE_REQUEST_LOG"
  grep -q "HEADER:Content-Type: application/json" "$MOCK_WEBLATE_REQUEST_LOG"
  body_json=$(sed -n '/^BODY_START$/,/^BODY_END$/p' "$MOCK_WEBLATE_REQUEST_LOG" | sed '1d;$d')
  [ "$(echo "$body_json" | jq -r '.organization')" = "$MODULE_ORG" ]
  [ "$(echo "$body_json" | jq -r '.version')" = "$libs_ref" ]
  echo "$body_json" | jq -e --argjson expected_exts "$exts_json" \
    '.extensions | type == "array" and . == $expected_exts' >/dev/null
  echo "$body_json" | jq -e \
    '.add_or_update | type == "object" and has("en") and (.en | type == "array") and .en == ["algorithm","system"]' >/dev/null
  grep -q "boost-endpoint/add-or-update" "$MOCK_WEBLATE_REQUEST_LOG"
}

@test "trigger_weblate: POST succeeds on HTTP 200" {
  MOCK_WEBLATE_STATUS=200
  MOCK_WEBLATE_BODY='{"status":"ok"}'
  start_weblate_mock_server

  set +e
  trigger_weblate "$MOCK_WEBLATE_BASE_URL" "$WEBLATE_TOKEN" "$libs_ref" "$exts_json" "en" \
    2>"$BATS_TMPDIR/weblate-200.stderr"
  status=$?
  set -e

  [ "$status" -eq 0 ]
  grep -q "Weblate returned HTTP 200" "$BATS_TMPDIR/weblate-200.stderr"
}

@test "trigger_weblate: auth failure on HTTP 403" {
  MOCK_WEBLATE_STATUS=403
  MOCK_WEBLATE_BODY='{"detail":"Forbidden"}'
  start_weblate_mock_server

  run trigger_weblate "$MOCK_WEBLATE_BASE_URL" "$WEBLATE_TOKEN" "$libs_ref" "$exts_json" "en"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Weblate auth failure (HTTP 403)"* ]]
  [[ "$output" == *"Verify WEBLATE_TOKEN"* ]]
  [[ "$output" == *"Response detail: Forbidden"* ]]
}

@test "trigger_weblate: rate-limit failure on HTTP 429" {
  MOCK_WEBLATE_STATUS=429
  MOCK_WEBLATE_BODY='{"detail":"Too many requests"}'
  start_weblate_mock_server

  run trigger_weblate "$MOCK_WEBLATE_BASE_URL" "$WEBLATE_TOKEN" "$libs_ref" "$exts_json" "en"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Weblate rate limit (HTTP 429)"* ]]
  [[ "$output" == *"Wait and retry"* ]]
}

@test "trigger_weblate: payload failure on HTTP 409" {
  MOCK_WEBLATE_STATUS=409
  MOCK_WEBLATE_BODY='{"detail":"Conflict"}'
  start_weblate_mock_server

  run trigger_weblate "$MOCK_WEBLATE_BASE_URL" "$WEBLATE_TOKEN" "$libs_ref" "$exts_json" "en"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Weblate payload rejected (HTTP 409)"* ]]
  [[ "$output" == *"Review add_or_update"* ]]
  [[ "$output" == *"Response detail: Conflict"* ]]
}

@test "trigger_weblate: client error on unhandled HTTP 405" {
  MOCK_WEBLATE_STATUS=405
  MOCK_WEBLATE_BODY='{"detail":"Method not allowed"}'
  start_weblate_mock_server

  run trigger_weblate "$MOCK_WEBLATE_BASE_URL" "$WEBLATE_TOKEN" "$libs_ref" "$exts_json" "en"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Weblate client error (HTTP 405)"* ]]
  [[ "$output" == *"Inspect the request payload"* ]]
}

@test "trigger_weblate: unexpected response on non-4xx/5xx HTTP status" {
  MOCK_WEBLATE_STATUS=301
  MOCK_WEBLATE_BODY='{"detail":"Moved permanently"}'
  start_weblate_mock_server

  run trigger_weblate "$MOCK_WEBLATE_BASE_URL" "$WEBLATE_TOKEN" "$libs_ref" "$exts_json" "en"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Weblate unexpected response (HTTP 301)"* ]]
  [[ "$output" == *"Check the endpoint URL"* ]]
}

@test "trigger_weblate: server error on HTTP 503" {
  MOCK_WEBLATE_STATUS=503
  MOCK_WEBLATE_BODY='{"detail":"Service unavailable"}'
  start_weblate_mock_server

  run trigger_weblate "$MOCK_WEBLATE_BASE_URL" "$WEBLATE_TOKEN" "$libs_ref" "$exts_json" "en"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Weblate server/network error (HTTP 503)"* ]]
  [[ "$output" == *"Retry later"* ]]
}

@test "trigger_weblate: timeout on curl exit 28" {
  install_curl_timeout_stub
  export MOCK_CURL_TIMEOUT=1

  run trigger_weblate "http://127.0.0.1:9" "$WEBLATE_TOKEN" "$libs_ref" "$exts_json" "en"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Weblate request timed out (curl exit 28)"* ]]
  [[ "$output" == *"Retry later"* ]]
}

@test "trigger_weblate: server error on curl connection failure" {
  install_curl_stub
  export MOCK_CURL_EXIT=7

  run trigger_weblate "http://127.0.0.1:9" "$WEBLATE_TOKEN" "$libs_ref" "$exts_json" "en"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Weblate server/network error (curl exit 7)"* ]]
  [[ "$output" == *"Retry later"* ]]
}
