#!/usr/bin/env bash
# Run ShellCheck and actionlint (same checks as CI lint job).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ensure_shellcheck() {
  if command -v shellcheck >/dev/null 2>&1; then
    SHELLCHECK_BIN="$(command -v shellcheck)"
    return
  fi

  local version="v0.11.0"
  local cache_dir="$ROOT/.cache/shellcheck"
  local bin="$cache_dir/shellcheck"
  mkdir -p "$cache_dir"

  if [[ -x "$bin" ]]; then
    SHELLCHECK_BIN="$bin"
    return
  fi

  local os arch tarball url expected_sha256
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
          echo "lint: install shellcheck manually (e.g. apt install shellcheck)." >&2
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
      echo "lint: shellcheck not found and auto-download unsupported on $os." >&2
      echo "lint: install shellcheck manually (e.g. apt install shellcheck)." >&2
      exit 1
      ;;
  esac

  url="https://github.com/koalaman/shellcheck/releases/download/${version}/${tarball}"
  if [[ ! -f "$cache_dir/$tarball" ]]; then
    echo "lint: downloading shellcheck ${version}..." >&2
    curl -fsSL -o "$cache_dir/$tarball" "$url"
  fi
  if [[ ! -d "$cache_dir/shellcheck-${version}" ]]; then
    if [[ "$os" == "Linux" ]]; then
      echo "${expected_sha256}  $cache_dir/$tarball" | sha256sum -c -
    else
      echo "${expected_sha256}  $cache_dir/$tarball" | shasum -a 256 -c -
    fi
    if ! tar -xJf "$cache_dir/$tarball" -C "$cache_dir"; then
      echo "lint: failed to extract shellcheck (is xz installed? apt install xz-utils)." >&2
      exit 1
    fi
  fi
  cp "$cache_dir/shellcheck-${version}/shellcheck" "$bin"
  chmod +x "$bin"
  SHELLCHECK_BIN="$bin"
}

ensure_shellcheck

"$SHELLCHECK_BIN" -x \
  .github/workflows/assets/env.sh \
  .github/workflows/assets/lib.sh \
  .github/workflows/assets/translation.sh \
  scripts/*.sh \
  tests/helpers/*.bash

ACTIONLINT_VERSION="1.7.7"
CACHE_DIR="$ROOT/.cache/actionlint"
ACTIONLINT_BIN="$CACHE_DIR/actionlint"
mkdir -p "$CACHE_DIR"

if [[ ! -x "$ACTIONLINT_BIN" ]]; then
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os" in
    Linux)
      case "$arch" in
        x86_64)
          tarball="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
          expected_sha256="023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757"
          ;;
        aarch64|arm64)
          tarball="actionlint_${ACTIONLINT_VERSION}_linux_arm64.tar.gz"
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
          tarball="actionlint_${ACTIONLINT_VERSION}_darwin_amd64.tar.gz"
          expected_sha256="28e5de5a05fc558474f638323d736d822fff183d2d492f0aecb2b73cc44584f5"
          ;;
        arm64)
          tarball="actionlint_${ACTIONLINT_VERSION}_darwin_arm64.tar.gz"
          expected_sha256="2693315b9093aeacb4ebd91a993fea54fc215057bf0da2659056b4bc033873db"
          ;;
        *)
          echo "lint: unsupported macOS architecture for actionlint download: $arch" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "lint: unsupported OS for actionlint download: $os" >&2
      exit 1
      ;;
  esac
  curl -fsSL -o "$CACHE_DIR/$tarball" \
    "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/${tarball}"
  if [[ "$os" == "Linux" ]]; then
    echo "${expected_sha256}  $CACHE_DIR/$tarball" | sha256sum -c -
  else
    echo "${expected_sha256}  $CACHE_DIR/$tarball" | shasum -a 256 -c -
  fi
  tar -xzf "$CACHE_DIR/$tarball" -C "$CACHE_DIR"
fi

"$ACTIONLINT_BIN" -color
