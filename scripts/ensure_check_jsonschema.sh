#!/usr/bin/env bash
# Bootstrap pinned check-jsonschema into .cache/ (shared by lint.sh and test helpers).
# Safe to source: does not enable set -euo (callers own shell options).
# shellcheck shell=bash

CHECK_JSONSCHEMA_VERSION="${CHECK_JSONSCHEMA_VERSION:-0.37.4}"

ensure_check_jsonschema() {
  local root version cache_dir venv_dir bin marker
  root="${REPO_ROOT:-}"
  if [[ -z "$root" ]]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
  version="$CHECK_JSONSCHEMA_VERSION"
  cache_dir="$root/.cache/check-jsonschema"
  venv_dir="$cache_dir/${version}"
  bin="$venv_dir/bin/check-jsonschema"
  marker="$venv_dir/.installed"

  if [[ -x "$bin" && -f "$marker" ]]; then
    CHECK_JSONSCHEMA_BIN="$bin"
    export CHECK_JSONSCHEMA_BIN
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "ensure_check_jsonschema: python3 is required" >&2
    return 1
  fi

  echo "ensure_check_jsonschema: installing check-jsonschema==${version} into ${venv_dir}..." >&2
  rm -rf "$venv_dir"
  python3 -m venv "$venv_dir" || return 1
  "$venv_dir/bin/pip" install --disable-pip-version-check --quiet \
    "check-jsonschema==${version}" || return 1
  if [[ ! -x "$bin" ]]; then
    echo "ensure_check_jsonschema: expected binary missing at $bin" >&2
    return 1
  fi
  printf '%s\n' "$version" >"$marker"
  CHECK_JSONSCHEMA_BIN="$bin"
  export CHECK_JSONSCHEMA_BIN
}

# When sourced, define the function; when executed, run it and print the bin path.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  ensure_check_jsonschema
  printf '%s\n' "$CHECK_JSONSCHEMA_BIN"
fi
