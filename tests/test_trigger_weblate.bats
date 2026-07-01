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
  echo "$body_json" | jq -e '.organization' >/dev/null
  echo "$body_json" | jq -e '.version' >/dev/null
  echo "$body_json" | jq -e '.extensions' >/dev/null
  echo "$body_json" | jq -e '.add_or_update.en | index("algorithm")' >/dev/null
  echo "$body_json" | jq -e '.add_or_update.en | index("system")' >/dev/null
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

@test "trigger_weblate: fails on HTTP 403" {
  MOCK_WEBLATE_STATUS=403
  MOCK_WEBLATE_BODY='{"detail":"Forbidden"}'
  start_weblate_mock_server

  run trigger_weblate "$MOCK_WEBLATE_BASE_URL" "$WEBLATE_TOKEN" "$libs_ref" "$exts_json" "en"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Weblate returned HTTP 403"* ]]
}

@test "trigger_weblate: fails on HTTP 409" {
  MOCK_WEBLATE_STATUS=409
  MOCK_WEBLATE_BODY='{"detail":"Conflict"}'
  start_weblate_mock_server

  run trigger_weblate "$MOCK_WEBLATE_BASE_URL" "$WEBLATE_TOKEN" "$libs_ref" "$exts_json" "en"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Weblate returned HTTP 409"* ]]
}

@test "trigger_weblate: fails on curl timeout" {
  install_curl_timeout_stub
  export MOCK_CURL_TIMEOUT=1

  run trigger_weblate "http://127.0.0.1:9" "$WEBLATE_TOKEN" "$libs_ref" "$exts_json" "en"
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl exit 28"* ]]
}
