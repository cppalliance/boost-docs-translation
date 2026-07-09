#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  DOC="$ROOT/docs/GETTING-STARTED.md"
}

@test "GETTING-STARTED.md exists" {
  [ -f "$DOC" ]
}

@test "GETTING-STARTED.md has end-to-end title" {
  grep -q '^# Getting started (end to end)' "$DOC"
}

@test "GETTING-STARTED.md has prerequisite section" {
  grep -q '^## 0\. Prerequisites' "$DOC"
}

@test "GETTING-STARTED.md has local trigger setup section" {
  grep -q '^## 1\. Local trigger setup' "$DOC"
}

@test "GETTING-STARTED.md has add-submodules section" {
  grep -q '^## 2\. `add-submodules`' "$DOC"
}

@test "GETTING-STARTED.md has start-translation section" {
  grep -q '^## 3\. `start-translation`' "$DOC"
}

@test "GETTING-STARTED.md has sync-translation section" {
  grep -q '^## 4\. `sync-translation`' "$DOC"
}

@test "GETTING-STARTED.md has create-tag section" {
  grep -q '^## 5\. `create-tag`' "$DOC"
}

@test "GETTING-STARTED.md references env.sh constants" {
  grep -q '\.github/workflows/assets/env\.sh' "$DOC"
  grep -q 'MASTER_BRANCH' "$DOC"
  grep -q 'LOCAL_BRANCH_PREFIX' "$DOC"
  grep -q 'TRANSLATION_BRANCH_PREFIX' "$DOC"
  grep -q 'WEBLATE_ENDPOINT_PATH' "$DOC"
}

@test "GETTING-STARTED.md references all dispatch event types" {
  grep -q 'add-submodules' "$DOC"
  grep -q 'start-translation' "$DOC"
  grep -q 'sync-translation' "$DOC"
}

@test "GETTING-STARTED.md cross-links README secrets and variables" {
  grep -q 'README\.md#required-secrets' "$DOC"
  grep -q 'README\.md#repository-variables' "$DOC"
}

@test "OPERATOR.md is not present (renamed to GETTING-STARTED.md)" {
  [ ! -f "$ROOT/docs/OPERATOR.md" ]
}

@test "GETTING-STARTED.md has operator checklist table" {
  grep -q 'Operator checklist' "$DOC"
}

@test "GETTING-STARTED.md names trigger scripts" {
  grep -q 'scripts/trigger-add-submodules.sh' "$DOC"
  grep -q 'scripts/trigger-start-translation.sh' "$DOC"
}

@test "GETTING-STARTED.md names GH_TOKEN" {
  grep -q 'GH_TOKEN' "$DOC"
}

@test "GETTING-STARTED.md cross-links ARCHITECTURE shell return codes" {
  grep -q 'ARCHITECTURE.md#6-shell-return-codes' "$DOC"
}

@test "GETTING-STARTED.md documents dispatch-order guard" {
  grep -q 'add-submodules first' "$DOC"
}
