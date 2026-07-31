#!/usr/bin/env bats

setup() {
  # shellcheck source=tests/helpers/common.bash
  source "$BATS_TEST_DIRNAME/helpers/common.bash"
  load_notify
}

teardown() {
  # shellcheck source=tests/helpers/http_mock.bash
  source "$BATS_TEST_DIRNAME/helpers/http_mock.bash"
  restore_slack_curl_stub
}

@test "extract_sync_local_lang_from_job_name: parses matrix lang" {
  run extract_sync_local_lang_from_job_name "sync-local (zh_Hans)"
  [ "$status" -eq 0 ]
  [ "$output" = "zh_Hans" ]
}

@test "extract_sync_local_lang_from_job_name: parses prefixed workflow job name" {
  run extract_sync_local_lang_from_job_name "Sync translation / sync-local (ja)"
  [ "$status" -eq 0 ]
  [ "$output" = "ja" ]
}

@test "extract_sync_local_lang_from_job_name: discover returns empty" {
  run extract_sync_local_lang_from_job_name "discover"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "format_failed_jobs_summary: lists failed discover and sync-local jobs with langs" {
  local fixture
  fixture='{
    "jobs": [
      {"name": "discover", "conclusion": "failure"},
      {"name": "sync-local (zh_Hans)", "conclusion": "failure"},
      {"name": "sync-local (ja)", "conclusion": "failure"},
      {"name": "sync-local (en)", "conclusion": "success"},
      {"name": "notify-failure", "conclusion": "failure"}
    ]
  }'
  run bash -c "source '${ASSETS_DIR}/notify.sh'; format_failed_jobs_summary" <<<"$fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"• discover"* ]]
  [[ "$output" == *"sync-local (zh_Hans) — lang=zh_Hans"* ]]
  [[ "$output" == *"sync-local (ja) — lang=ja"* ]]
  [[ "$output" != *"sync-local (en)"* ]]
  [[ "$output" != *"notify-failure"* ]]
}

@test "build_slack_failure_payload: valid JSON with run URL and summary" {
  run build_slack_failure_payload \
    "Sync translation failed" \
    "https://github.com/org/repo/actions/runs/99" \
    $'  • discover\n  • sync-local (ja) — lang=ja' \
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  [[ "$output" == *"https://github.com/org/repo/actions/runs/99"* ]]
  [[ "$output" == *"Sync translation failed"* ]]
  [[ "$output" == *"lang=ja"* ]]
}

@test "send_slack_notification: missing SLACK_WEBHOOK_URL exits 1" {
  unset SLACK_WEBHOOK_URL
  run send_slack_notification '{"text":"hi"}'
  [ "$status" -eq 1 ]
  [[ "$output" == *"SLACK_WEBHOOK_URL"* ]]
}

@test "send_slack_notification: posts JSON to webhook URL" {
  # shellcheck source=tests/helpers/http_mock.bash
  source "$BATS_TEST_DIRNAME/helpers/http_mock.bash"
  install_slack_curl_stub
  export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T/B/x"
  run send_slack_notification '{"text":"alert"}'
  [ "$status" -eq 0 ]
  grep -q 'URL=https://hooks.slack.com/services/T/B/x' "$MOCK_SLACK_REQUEST_LOG"
  grep -q '"text":"alert"' "$MOCK_SLACK_REQUEST_LOG"
}

@test "workflow_run_url: uses GITHUB_SERVER_URL and GITHUB_REPOSITORY" {
  export GITHUB_SERVER_URL="https://github.example"
  export GITHUB_REPOSITORY="myorg/myrepo"
  export GITHUB_RUN_ID="42"
  run workflow_run_url
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.example/myorg/myrepo/actions/runs/42" ]
}

@test "notify_heartbeat_stale: builds payload with threshold detail" {
  # shellcheck source=tests/helpers/http_mock.bash
  source "$BATS_TEST_DIRNAME/helpers/http_mock.bash"
  install_slack_curl_stub
  export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T/B/x"
  run notify_heartbeat_stale "2026-01-01T00:00:00Z"
  [ "$status" -eq 0 ]
  grep -q 'Sync heartbeat alert' "$MOCK_SLACK_REQUEST_LOG"
  grep -q 'threshold=30h' "$MOCK_SLACK_REQUEST_LOG"
  grep -q 'sync-translation.yml' "$MOCK_SLACK_REQUEST_LOG"
}
