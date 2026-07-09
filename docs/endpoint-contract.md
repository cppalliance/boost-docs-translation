# Endpoint contract

**Status:** Operator-facing description of **inbound** HTTP surfaces used to trigger workflows in **this** repository. Labels: **documented** (paths and behavior match the checked-in workflows and scripts), **partial** (no helper script in-repo; still valid via GitHub API or schedule).

All file paths below are relative to the root of **this** repository.

## Overview

**GitHub REST API** — `POST /repos/{owner}/{repo}/dispatches` runs workflows via `repository_dispatch`. Helper scripts live under `scripts/`. `sync-translation` can also start on a **daily schedule** inside GitHub Actions (not an HTTP call you make). For the full end-to-end sequence (secrets → dispatch order → ongoing sync), see [GETTING-STARTED.md](GETTING-STARTED.md).

```mermaid
flowchart LR
  subgraph operators [Operators and scripts]
    trigStart[trigger-start-translation.sh]
    trigAdd[trigger-add-submodules.sh]
  end
  subgraph github [GitHub REST API]
    dispatches[POST repos dispatches]
  end
  subgraph gha [GitHub Actions in this repo]
    wfStart[start-translation.yml]
    wfAdd[add-submodules.yml]
    wfSync[sync-translation.yml]
    cronSync[daily schedule]
  end
  trigStart --> dispatches
  trigAdd --> dispatches
  dispatches --> wfStart
  dispatches --> wfAdd
  dispatches --> wfSync
  cronSync --> wfSync
```

---

## Versioning and stability

Orchestration releases of **this** repository are tagged **`vX.Y.Z`** (semver). Changes
to the surfaces below require a semver bump and an entry in
**[CHANGELOG.md](../CHANGELOG.md)**. See **[README § Releases](../README.md#releases)**
for the maintainer release checklist.

**Pinning:** consumers should pin automation to a git ref matching a **`v*`** tag or a
commit reachable from one.

### Versioned surface

Semver applies to documented changes in:

| Surface | Reference |
| ------- | --------- |
| `repository_dispatch` **`event_type`** values | `add-submodules`, `start-translation`, `sync-translation` |
| **`client_payload`** field names, optionality, semantics | [README](../README.md) workflow tables; sections below |
| Dispatch HTTP contract | URL, auth headers, success = HTTP **204** |
| Outbound Weblate POST | `organization`, `version`, `extensions`, `add_or_update`; success **200** or **202** |
| Shell batch return codes **0 / 1 / 2** and job collapse | [ARCHITECTURE §6](ARCHITECTURE.md#6-shell-return-codes) — code **2** never propagates to GitHub Actions step exit |
| Branch/path constants affecting behavior | `MASTER_BRANCH`, `LOCAL_BRANCH_PREFIX`, `TRANSLATION_BRANCH_PREFIX`, `WEBLATE_ENDPOINT_PATH` in [`env.sh`](../.github/workflows/assets/env.sh) |

### Semver rules

| Bump | When |
| ---- | ---- |
| **MAJOR** | Remove or rename event types or payload fields; change documented semantics or success criteria; change **0 / 1 / 2** meanings or job-exit collapse rules |
| **MINOR** | Additive optional fields, new event types, backward-compatible behavior |
| **PATCH** | Bug fixes, internal refactors, dependency bumps, documentation that does not change the contract |

**Out of scope for orchestration semver:** mirror content tags (`{version}-{repo}-{lang_code}`),
submodule pointer updates, and Boost release refs in `client_payload.version`.

---

## Endpoint inventory

| #   | Surface                | Method       | URL / path                                               | Defined or invoked in this repo                                                                                   | Label          |
| --- | ---------------------- | ------------ | -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | -------------- |
| 1   | GitHub Actions trigger | `POST`       | `https://api.github.com/repos/{owner}/{repo}/dispatches` | `scripts/trigger-start-translation.sh`, `scripts/trigger-add-submodules.sh`                                       | **documented** |
| 2   | GitHub Actions trigger | `POST`       | same as (1)                                              | `sync-translation.yml` (manual dispatch or any client with repo access); no `scripts/trigger-*.sh` for this event | **partial**    |
| 3   | GitHub Actions         | _(schedule)_ | _(runs inside GitHub; not an HTTP URL you call)_         | `sync-translation.yml` — cron `0 0 * * *` (daily UTC)                                                             | **partial**    |

---

## GitHub `repository_dispatch` (`POST …/dispatches`)

**Purpose:** Start a workflow in this repository using the [Create a repository dispatch event](https://docs.github.com/en/rest/repos/repos#create-a-repository-dispatch-event) API.

### Common contract (helper scripts)

| Item          | Value                                                                                                       |
| ------------- | ----------------------------------------------------------------------------------------------------------- |
| URL           | `https://api.github.com/repos/{owner}/{repo}/dispatches`                                                    |
| Method        | `POST`                                                                                                      |
| Auth          | `Authorization: Bearer {PAT}` (scripts use `GH_TOKEN` / `GITHUB_TOKEN` / `--token`)                         |
| Headers       | `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, `Content-Type: application/json` |
| Success       | HTTP **204** (scripts treat only `204` as success and print the body on failure)                            |
| Response body | Empty on success; scripts do not parse JSON on success.                                                     |

### `event_type: add-submodules`

| Item             | Detail                                                                                                                |
| ---------------- | --------------------------------------------------------------------------------------------------------------------- |
| Workflow         | `.github/workflows/add-submodules.yml`                                                                                |
| Body shape       | `{"event_type":"add-submodules","client_payload":{...}}`                                                              |
| `client_payload` | All optional: `version`, `submodules` (list-like string), `lang_codes` (comma-separated). See [README](../README.md). |
| Script           | `scripts/trigger-add-submodules.sh` builds JSON with `jq` or Python; omits empty optional fields.                     |

### `event_type: start-translation`

| Item             | Detail                                                                       |
| ---------------- | ---------------------------------------------------------------------------- |
| Workflow         | `.github/workflows/start-translation.yml`                                    |
| Body shape       | `{"event_type":"start-translation","client_payload":{...}}`                  |
| `client_payload` | Optional: `version`, `lang_codes`, `extensions`. See [README](../README.md). |
| Script           | `scripts/trigger-start-translation.sh`                                       |

### `event_type: sync-translation`

| Item           | Detail                                                                                                  |
| -------------- | ------------------------------------------------------------------------------------------------------- |
| Workflow       | `.github/workflows/sync-translation.yml`                                                                |
| Triggers       | `repository_dispatch` **or** schedule **`0 0 * * *`** (daily, UTC).                                     |
| Body shape     | `{"event_type":"sync-translation"}` — no `client_payload`.                                              |
| Script in repo | **None** — use the dispatches API, GitHub UI, or another automation with permission to post dispatches. |

---

## Outbound Weblate (`POST …/${WEBLATE_ENDPOINT_PATH}`)

**Purpose:** Notify the Weblate instance which components to add or update after git sync.

| Item       | Value                                                                                          |
| ---------- | ---------------------------------------------------------------------------------------------- |
| URL        | `{WEBLATE_URL}/${WEBLATE_ENDPOINT_PATH}` — path from **`WEBLATE_ENDPOINT_PATH`** in `env.sh` |
| Method     | `POST`                                                                                         |
| Auth       | `Authorization: Token {WEBLATE_TOKEN}`                                                         |
| Invoked by | `.github/workflows/start-translation.yml` (`start-local` job)                                |
| Success    | HTTP **200** or **202** (async accepted)                                                       |
