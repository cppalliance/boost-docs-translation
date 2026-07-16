# Changelog

All notable changes to the **orchestration contract** of this repository are documented
in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for **this** repository only. Mirror content tags (`boost-1.90.0-algorithm-zh_Hans`)
are a separate namespace — see [README](README.md#releases) and
[`.github/workflows/assets/README.md`](.github/workflows/assets/README.md#tag-namespaces).

## [Unreleased]

### Added

- JSON Schema for the outbound Weblate add-or-update POST request:
  [weblate-add-or-update.request.schema.json](docs/schemas/weblate-add-or-update.request.schema.json)
  (`organization`, `version`, `extensions`, `add_or_update`).
- Documented Weblate success response bodies in
  [endpoint-contract.md](docs/endpoint-contract.md): HTTP **202** (`task_id`),
  HTTP **200** (`status: "ok"`).
- Lint/CI schema checks via pinned `check-jsonschema` (metaschema + fixture
  validation); bats validates captured Weblate request bodies against the schema
  and asserts success response fields.

### Changed

- Extracted shared dispatch helpers into
  [`scripts/trigger-dispatch-common.sh`](scripts/trigger-dispatch-common.sh)
  (`DEFAULT_REPO`, `DEFAULT_VERSION`, JSON build, `POST …/dispatches`); both
  `trigger-*.sh` wrappers source it.
- Mirror **`create-tag.yml`** bot identity now uses **`set_git_bot_config`** from
  **`env.sh`** / **`lib.sh`** instead of a hardcoded org email.
- Renamed and expanded operator quick reference to
  [GETTING-STARTED.md](docs/GETTING-STARTED.md): end-to-end walkthrough with
  per-step verification and create-tag coverage.
- [endpoint-contract.md](docs/endpoint-contract.md) Outbound Weblate section:
  request schema is now the source of truth for payload fields.

### Fixed

- Clone and finalize steps now fail fast: **`clone_repo`**, **`sync_translations_branch`**,
  and **`finalize_translations_*`** propagate non-zero status instead of continuing with
  incomplete state.
- **`combine_batch_and_finalize_rc`** collapses all three exit sources—batch
  **`submodule_fatal`**, **`finalize_rc`**, and optional **`weblate_rc`**—with documented
  last-wins priority; **`start-translation.yml`** **`start-local`** delegates to it instead
  of inline collapse logic.

## [1.0.0] - 2026-07-07

Initial semver baseline for the orchestration repo. Summarizes the operator and
consumer surface as it stood at this release; routine submodule pointer updates
are not listed.

### Added

- Core workflows: `add-submodules`, `start-translation`, and `sync-translation`
  triggered via `repository_dispatch` or (for sync) daily schedule.
- Local trigger scripts: `scripts/trigger-add-submodules.sh` and
  `scripts/trigger-start-translation.sh`.
- `client_payload` fields for dispatch events: `version`, `submodules`, `lang_codes`
  (`add-submodules`); `version`, `lang_codes`, `extensions` (`start-translation`).
- [Endpoint contract](docs/endpoint-contract.md): GitHub `POST …/dispatches` shapes,
  auth headers, success = HTTP **204**, and outbound Weblate POST contract.
- Weblate integration: `WEBLATE_ENDPOINT_PATH` consolidation, structured HTTP error
  handling, success codes **200** or **202**.
- Shell per-submodule batch return codes **0 / 1 / 2** with workflow job collapse
  rules documented in [ARCHITECTURE §6](docs/ARCHITECTURE.md#6-shell-return-codes)
  (code **2** is never propagated to GitHub Actions step exit).
- Branch and path constants in `.github/workflows/assets/env.sh`:
  `MASTER_BRANCH`, `LOCAL_BRANCH_PREFIX`, `TRANSLATION_BRANCH_PREFIX`,
  `WEBLATE_ENDPOINT_PATH`.
- Mirror asset `create-tag.yml` (copied into library mirrors; produces content tags,
  not orchestration semver).
- Test harness and CI: `make check` (ShellCheck, actionlint, bats suite).
- Operator quick reference: [GETTING-STARTED.md](docs/GETTING-STARTED.md) (formerly OPERATOR.md).

[Unreleased]: https://github.com/cppalliance/boost-docs-translation/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/cppalliance/boost-docs-translation/releases/tag/v1.0.0
