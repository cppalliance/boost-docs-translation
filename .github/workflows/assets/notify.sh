# shellcheck shell=bash
# Slack failure notifications for sync-translation and heartbeat workflows.
# Source env.sh before notify.sh when using workflow globals (e.g. HEARTBEAT_MAX_AGE_HOURS).

# Return workflow run URL for the given run id (defaults to GITHUB_RUN_ID).
workflow_run_url() {
  local run_id="${1:-${GITHUB_RUN_ID:-}}"
  local server="${GITHUB_SERVER_URL:-https://github.com}"
  echo "${server}/${GITHUB_REPOSITORY}/actions/runs/${run_id}"
}

# Extract matrix lang from a sync-local job name, e.g. "sync-local (zh_Hans)" → zh_Hans.
# Prints nothing for non-matrix job names (e.g. discover).
extract_sync_local_lang_from_job_name() {
  local job_name="$1"
  local lang
  lang="$(sed -n 's/.*sync-local[[:space:]]*(\([^)]*\)).*/\1/p' <<<"$job_name")"
  if [[ -n "$lang" && "$lang" != "$job_name" ]]; then
    echo "$lang"
  fi
}

# Read gh api /actions/runs/.../jobs JSON from stdin; emit human-readable failed-job lines.
format_failed_jobs_summary() {
  jq -r '
    (if type == "object" and has("jobs") then .jobs else . end)
    | .[]
    | select(.conclusion == "failure")
    | select(.name | test("notify-failure") | not)
    | .name as $name
    | ($name | if test("sync-local \\(")
        then (capture("sync-local \\((?<lang>[^)]+)\\)") | .lang // "")
        else "" end) as $lang
    | if ($lang | length) > 0 then "  • \($name) — lang=\($lang)"
      else "  • \($name)" end
  '
}

# Build a Slack incoming-webhook JSON payload. Args: title run_url summary_lines detail (optional).
build_slack_failure_payload() {
  local title="$1" run_url="$2" summary="$3" detail="${4:-}"
  local text="${title}"$'\n'"Run: ${run_url}"
  if [[ -n "$summary" ]]; then
    text+=$'\n'"Failed jobs:"$'\n'"${summary}"
  fi
  if [[ -n "$detail" ]]; then
    text+=$'\n'"${detail}"
  fi
  jq -n --arg text "$text" '{text: $text}'
}

# POST JSON payload to SLACK_WEBHOOK_URL.
send_slack_notification() {
  local payload="$1"
  if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
    echo "error: SLACK_WEBHOOK_URL secret is not set." >&2
    return 1
  fi
  curl -fsS -X POST -H 'Content-Type: application/json' --data "$payload" "$SLACK_WEBHOOK_URL"
}

# Fetch failed jobs for a workflow run and format summary lines.
collect_workflow_failed_jobs_summary() {
  local run_id="${1:-${GITHUB_RUN_ID:-}}"
  gh run view "$run_id" --repo "$GITHUB_REPOSITORY" --json jobs \
    | format_failed_jobs_summary
}

# Notify Slack about sync-translation workflow failures (discover or sync-local).
notify_sync_translation_failure() {
  local run_id="${1:-${GITHUB_RUN_ID:-}}"
  local run_url summary payload
  run_url="$(workflow_run_url "$run_id")"
  summary="$(collect_workflow_failed_jobs_summary "$run_id")"
  payload="$(build_slack_failure_payload "Sync translation failed" "$run_url" "$summary" "")"
  send_slack_notification "$payload"
}

# Notify Slack when the daily sync heartbeat is stale.
notify_heartbeat_stale() {
  local last_ts="$1"
  local run_url workflow_url detail payload
  local server="${GITHUB_SERVER_URL:-https://github.com}"
  local last_desc="${last_ts:-none on record}"

  run_url="$(workflow_run_url)"
  workflow_url="${server}/${GITHUB_REPOSITORY}/actions/workflows/sync-translation.yml"
  detail="Daily sync heartbeat: last successful scheduled run is stale (last=${last_desc}, threshold=${HEARTBEAT_MAX_AGE_HOURS}h). The scheduled sync may have stopped."
  detail+=$'\n'"Workflow: ${workflow_url}"

  payload="$(build_slack_failure_payload "Sync heartbeat alert" "$run_url" "" "$detail")"
  send_slack_notification "$payload"
}
