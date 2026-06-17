#!/usr/bin/env bash
# Point this repository at the version-controlled hooks in .githooks/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

chmod +x .githooks/pre-commit scripts/lint.sh scripts/test.sh scripts/pre-commit.sh

git config core.hooksPath .githooks
echo "Installed git hooks from .githooks/ (core.hooksPath=.githooks)." >&2
echo "Pre-commit runs: scripts/pre-commit.sh (lint + make test)." >&2
