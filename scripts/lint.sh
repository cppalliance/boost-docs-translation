#!/usr/bin/env bash
# Run ShellCheck and actionlint (same checks as CI lint job).
# Versions below are pinned; binaries are downloaded to .cache/ with OS-specific
# checksums verified in CI (Linux and macOS).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SHELLCHECK_VERSION="v0.11.0"
ACTIONLINT_VERSION="1.7.7"

# Download, verify, extract, and cache a release binary under .cache/.
# Args: name version dest_var tarball expected_sha256 url inner_bin [format]
# format: xz (default) or gz
ensure_cached_binary() {
  local name="$1" version="$2" dest_var="$3" tarball="$4" expected_sha256="$5" url="$6" inner_bin="$7"
  local format="${8:-xz}"
  local cache_dir="$ROOT/.cache/$name"
  local extract_dir="$cache_dir/${name}-${version}"
  local bin="$cache_dir/${name}-bin-${version}"
  mkdir -p "$cache_dir"

  if [[ -x "$bin" ]]; then
    printf -v "$dest_var" '%s' "$bin"
    return 0
  fi

  local os inner_path="$extract_dir/$inner_bin"
  os="$(uname -s)"
  if [[ ! -f "$cache_dir/$tarball" ]]; then
    echo "lint: downloading ${name} ${version}..." >&2
    curl -fsSL -o "$cache_dir/$tarball" "$url"
  fi
  if [[ ! -f "$inner_path" ]]; then
    if [[ "$os" == "Linux" ]]; then
      echo "${expected_sha256}  $cache_dir/$tarball" | sha256sum -c -
    else
      echo "${expected_sha256}  $cache_dir/$tarball" | shasum -a 256 -c -
    fi
    rm -rf "$extract_dir"
    if [[ "$format" == xz ]]; then
      if ! tar -xJf "$cache_dir/$tarball" -C "$cache_dir"; then
        rm -rf "$extract_dir"
        echo "lint: failed to extract ${name} (is xz installed? apt install xz-utils)." >&2
        exit 1
      fi
    else
      mkdir -p "$extract_dir"
      if ! tar -xzf "$cache_dir/$tarball" -C "$extract_dir"; then
        rm -rf "$extract_dir"
        echo "lint: failed to extract ${name}." >&2
        exit 1
      fi
    fi
    if [[ ! -f "$inner_path" ]]; then
      rm -rf "$extract_dir"
      echo "lint: expected binary missing after extracting ${name}: $inner_path" >&2
      exit 1
    fi
  fi
  cp "$inner_path" "$bin"
  chmod +x "$bin"
  printf -v "$dest_var" '%s' "$bin"
}

ensure_shellcheck() {
  local version="$SHELLCHECK_VERSION" os arch tarball expected_sha256 url
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os" in
    Linux)
      case "$arch" in
        x86_64)
          tarball="shellcheck-${version}.linux.x86_64.tar.xz"
          expected_sha256="8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198"
          ;;
        aarch64|arm64)
          tarball="shellcheck-${version}.linux.aarch64.tar.xz"
          expected_sha256="12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588"
          ;;
        *)
          echo "lint: unsupported Linux architecture for shellcheck download: $arch" >&2
          exit 1
          ;;
      esac
      ;;
    Darwin)
      case "$arch" in
        x86_64)
          tarball="shellcheck-${version}.darwin.x86_64.tar.xz"
          expected_sha256="3c89db4edcab7cf1c27bff178882e0f6f27f7afdf54e859fa041fca10febe4c6"
          ;;
        arm64)
          tarball="shellcheck-${version}.darwin.aarch64.tar.xz"
          expected_sha256="56affdd8de5527894dca6dc3d7e0a99a873b0f004d7aabc30ae407d3f48b0a79"
          ;;
        *)
          echo "lint: unsupported macOS architecture for shellcheck download: $arch" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "lint: shellcheck auto-download unsupported on $os." >&2
      exit 1
      ;;
  esac
  url="https://github.com/koalaman/shellcheck/releases/download/${version}/${tarball}"
  ensure_cached_binary shellcheck "$version" SHELLCHECK_BIN "$tarball" "$expected_sha256" "$url" shellcheck xz
}

ensure_actionlint() {
  local version="$ACTIONLINT_VERSION" os arch tarball expected_sha256 url
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os" in
    Linux)
      case "$arch" in
        x86_64)
          tarball="actionlint_${version}_linux_amd64.tar.gz"
          expected_sha256="023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757"
          ;;
        aarch64|arm64)
          tarball="actionlint_${version}_linux_arm64.tar.gz"
          expected_sha256="401942f9c24ed71e4fe71b76c7d638f66d8633575c4016efd2977ce7c28317d0"
          ;;
        *)
          echo "lint: unsupported Linux architecture for actionlint download: $arch" >&2
          exit 1
          ;;
      esac
      ;;
    Darwin)
      case "$arch" in
        x86_64)
          tarball="actionlint_${version}_darwin_amd64.tar.gz"
          expected_sha256="28e5de5a05fc558474f638323d736d822fff183d2d492f0aecb2b73cc44584f5"
          ;;
        arm64)
          tarball="actionlint_${version}_darwin_arm64.tar.gz"
          expected_sha256="2693315b9093aeacb4ebd91a993fea54fc215057bf0da2659056b4bc033873db"
          ;;
        *)
          echo "lint: unsupported macOS architecture for actionlint download: $arch" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "lint: actionlint auto-download unsupported on $os." >&2
      exit 1
      ;;
  esac
  url="https://github.com/rhysd/actionlint/releases/download/v${version}/${tarball}"
  ensure_cached_binary actionlint "$version" ACTIONLINT_BIN "$tarball" "$expected_sha256" "$url" actionlint gz
}

ensure_shellcheck
ensure_actionlint

# actionlint shells out to shellcheck for workflow run: scripts; use our pinned binary.
_shellcheck_dir="$ROOT/.cache/shellcheck/shellcheck-${SHELLCHECK_VERSION}"
export PATH="${_shellcheck_dir}:${PATH}"

echo "lint: shellcheck ${SHELLCHECK_VERSION} ($("$SHELLCHECK_BIN" --version | head -1))" >&2
echo "lint: actionlint ${ACTIONLINT_VERSION} ($("$ACTIONLINT_BIN" -version | head -1))" >&2

"$SHELLCHECK_BIN" -x \
  .github/workflows/assets/env.sh \
  .github/workflows/assets/lib.sh \
  .github/workflows/assets/translation.sh \
  .github/workflows/assets/add_submodules.sh \
  .github/workflows/assets/submodule_ops.sh \
  scripts/*.sh \
  tests/helpers/*.bash

"$ACTIONLINT_BIN" -color

# shellcheck source=scripts/ensure_check_jsonschema.sh
source "$ROOT/scripts/ensure_check_jsonschema.sh"
ensure_check_jsonschema

echo "lint: check-jsonschema ${CHECK_JSONSCHEMA_VERSION}" >&2
shopt -s nullglob
schema_files=(docs/schemas/*.schema.json)
if [[ ${#schema_files[@]} -eq 0 ]]; then
  echo "lint: no JSON Schema files under docs/schemas/" >&2
  exit 1
fi
"$CHECK_JSONSCHEMA_BIN" --check-metaschema "${schema_files[@]}"
"$CHECK_JSONSCHEMA_BIN" --schemafile \
  docs/schemas/weblate-add-or-update.request.schema.json \
  tests/helpers/fixtures/weblate-add-or-update-request-valid.json
