#!/usr/bin/env bash
# Pre-commit checks: lint (ShellCheck + actionlint) and bats tests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "pre-commit: running lint..." >&2
"$ROOT/scripts/lint.sh"

echo "pre-commit: running tests..." >&2
"$ROOT/scripts/test.sh"

echo "pre-commit: all checks passed." >&2
