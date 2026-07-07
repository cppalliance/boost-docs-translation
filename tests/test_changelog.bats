#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CHANGELOG="$ROOT/CHANGELOG.md"
}

@test "CHANGELOG.md exists at repo root" {
  [ -f "$CHANGELOG" ]
}

@test "CHANGELOG.md follows Keep a Changelog structure" {
  grep -q '^# Changelog' "$CHANGELOG"
  grep -q '^## \[Unreleased\]' "$CHANGELOG"
  grep -q '^## \[1\.0\.0\]' "$CHANGELOG"
  grep -qi 'keepachangelog\.com' "$CHANGELOG"
}
