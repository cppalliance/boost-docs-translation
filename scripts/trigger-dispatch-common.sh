#!/usr/bin/env bash
# Shared helpers for repository_dispatch trigger scripts.
# Safe to source: does not enable set -euo (callers own shell options).
# shellcheck shell=bash
# shellcheck disable=SC2034

DEFAULT_REPO="cppalliance/boost-docs-translation"
DEFAULT_VERSION="boost-1.90.0"

infer_repo_from_git() {
  local url root o r
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  url="$(git -C "$root" remote get-url origin 2>/dev/null)" || return 1
  if [[ "$url" =~ github\.com[:/]([^/]+)/([^[:space:]]+) ]]; then
    o="${BASH_REMATCH[1]}"
    r="${BASH_REMATCH[2]}"
    r="${r%.git}"
    r="${r%/}"
    echo "${o}/${r}"
    return 0
  fi
  return 1
}

resolve_trigger_repo() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    echo "$explicit"
    return 0
  fi
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    echo "$GITHUB_REPOSITORY"
    return 0
  fi
  local inferred
  inferred="$(infer_repo_from_git)" && {
    echo "$inferred"
    return 0
  }
  if [[ -n "${DEFAULT_REPO:-}" ]]; then
    echo "$DEFAULT_REPO"
    return 0
  fi
  return 1
}

resolve_trigger_token() {
  local explicit="${1:-}"
  local token="${explicit:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}"
  if [[ -z "$token" ]]; then
    echo "error: set GH_TOKEN (e.g. in repo-root .env), GITHUB_TOKEN, or pass --token" >&2
    return 1
  fi
  echo "$token"
}

require_curl() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "error: curl is required" >&2
    return 1
  fi
}

# Build repository_dispatch JSON. Remaining args are alternating KEY VALUE pairs;
# keys with empty values are omitted from client_payload.
build_dispatch_json() {
  local event_type="$1"
  shift
  if command -v jq >/dev/null 2>&1; then
    local json_pairs='[]' key val
    while [[ $# -gt 0 ]]; do
      key="$1"
      val="$2"
      shift 2
      json_pairs="$(jq -n --argjson arr "$json_pairs" --arg k "$key" --arg v "$val" \
        '$arr + [{key: $k, value: $v}]')"
    done
    jq -n --arg event_type "$event_type" --argjson kv_pairs "$json_pairs" \
      '{
        event_type: $event_type,
        client_payload: (
          {}
          | reduce $kv_pairs[] as $p (
              .;
              if ($p.value | length) > 0 then . + {($p.key): $p.value} else . end
            )
        )
      }'
    return 0
  fi
  local py=""
  command -v python3 >/dev/null 2>&1 && py="python3"
  [[ -z "$py" ]] && command -v python >/dev/null 2>&1 && py="python"
  if [[ -n "$py" ]]; then
    "$py" -c 'import json,sys
et=sys.argv[1]
pairs=sys.argv[2:]
d={}
for i in range(0,len(pairs),2):
    k,v=pairs[i],pairs[i+1]
    if v:
        d[k]=v
print(json.dumps({"event_type":et,"client_payload":d}))' \
      "$event_type" "$@"
    return 0
  fi
  return 1
}

post_repository_dispatch() {
  local repo="$1" token="$2" body="$3" label="$4"
  local resp url code
  resp="$(mktemp)"
  # shellcheck disable=SC2064
  trap 'rm -f "$resp"' RETURN
  url="https://api.github.com/repos/${repo}/dispatches"
  code="$(
    curl -sS -o "$resp" -w '%{http_code}' \
      -X POST \
      -H "Authorization: Bearer ${token}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      -d "$body" \
      "$url"
  )"
  if [[ "$code" == "204" ]]; then
    echo "Dispatched ${label} to ${repo} (HTTP ${code})."
    return 0
  fi
  echo "GitHub API error: HTTP ${code}" >&2
  if [[ -s "$resp" ]]; then
    cat "$resp" >&2
  fi
  return 1
}
