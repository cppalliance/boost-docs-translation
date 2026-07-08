#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CHANGELOG="$ROOT/CHANGELOG.md"
}

@test "CHANGELOG.md exists at repo root" {
  [ -f "$CHANGELOG" ]
}

@test "CHANGELOG.md has top-level # Changelog heading" {
  grep -q '^# Changelog' "$CHANGELOG"
}

@test "CHANGELOG.md has ## [Unreleased] section" {
  grep -q '^## \[Unreleased\]' "$CHANGELOG"
}

@test "CHANGELOG.md has ## [1.0.0] release section" {
  grep -q '^## \[1\.0\.0\]' "$CHANGELOG"
}

@test "CHANGELOG.md references keepachangelog.com" {
  grep -qi 'keepachangelog\.com' "$CHANGELOG"
}
