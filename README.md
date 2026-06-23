# boost-docs-translation

Super-repository for Boost library documentation translations: it holds `libs/*`
submodules that point at per-library mirrors, keeps **`MASTER_BRANCH`** (`master`) and
**`${LOCAL_BRANCH_PREFIX}{lang_code}`** (e.g. `local-zh_Hans`) branches aligned with upstream **`boostorg`** sources, and
notifies a Weblate instance when components change. A daily workflow advances
submodule pointers on every **`${LOCAL_BRANCH_PREFIX}*`** branch to match each library repo’s
corresponding **`${LOCAL_BRANCH_PREFIX}*`** tip.

Branch and endpoint path constants are defined in **`.github/workflows/assets/env.sh`**
(`MASTER_BRANCH`, `LOCAL_BRANCH_PREFIX`, `TRANSLATION_BRANCH_PREFIX`, `WEBLATE_ENDPOINT_PATH`).

The GitHub org used for those library mirrors defaults to **this repository’s
org**; set repository variable **`SUBMODULES_ORG`** to use a
different org.

For system context, branch model, and data flows, see **[ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

---

## Integration contracts

HTTP surfaces are described in **[`docs/endpoint-contract.md`](docs/endpoint-contract.md)**.

---

## Workflows

### `add-submodules.yml` — Create library mirrors and register submodules

**Trigger:** `repository_dispatch` with `event_type: add-submodules`

```json
{
  "event_type": "add-submodules",
  "client_payload": { "version": "boost-1.90.0" }
}
```

For each Boost library name in the resolved list:

1. Skips if **`{MODULE_ORG}/{submodule}`** already exists (`MODULE_ORG` is
   **`SUBMODULES_ORG`** if set, otherwise the translations repo’s org).
2. Fetches **`meta/libraries.json`** from **`boostorg/{submodule}`** to determine doc
   paths, clones that repo at the given ref, and prunes to doc folders only.
3. Creates **`{MODULE_ORG}/{submodule}`**, pushes doc content to **`MASTER_BRANCH`**, creates
   **`${LOCAL_BRANCH_PREFIX}{lang_code}`** branches for each configured language, and copies
   **`create-tag.yml`** from **`.github/workflows/assets/`** into the new repo.
4. Updates submodule links in this repo under **`libs/`** on **`MASTER_BRANCH`** and each
   **`${LOCAL_BRANCH_PREFIX}{lang_code}`** branch.

| `client_payload` field | Required | Description                                                                                                                                                            |
| ---------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `version`              | no       | Boost ref (e.g. `boost-1.90.0`). Defaults to `develop`.                                                                                                                |
| `submodules`           | no       | List-like string (e.g. `[algorithm, system]`). If omitted, submodule names are taken from **`.gitmodules` on `boostorg/boost`** at **`version`** (only `libs/` paths). |
| `lang_codes`           | no       | Comma-separated language codes (e.g. `zh_Hans,ja`). Defaults to **`vars.LANG_CODES`**; the workflow fails if neither this field nor **`LANG_CODES`** is set.           |

---

### `start-translation.yml` — Sync existing mirrors and notify Weblate

**Trigger:** `repository_dispatch` with `event_type: start-translation`

```json
{
  "event_type": "start-translation",
  "client_payload": { "version": "boost-1.90.0" }
}
```

Reads the submodule list from **this repo’s `.gitmodules`** on **`MASTER_BRANCH`** (only
**`libs/`** entries). For each language and each submodule:

1. Ensures this repo has a **`${LOCAL_BRANCH_PREFIX}{lang_code}`** branch.
2. Syncs **`{MODULE_ORG}/{lib}` `MASTER_BRANCH`** from the upstream **`boostorg`** repo
   (same prune rules as **`add-submodules`**).
3. In the library repo: creates **`${LOCAL_BRANCH_PREFIX}{lang_code}`** if missing, or merges
   **`MASTER_BRANCH`** into it when there is **no** open PR into **`${LOCAL_BRANCH_PREFIX}{lang_code}`**
   whose head branch starts with **`${TRANSLATION_BRANCH_PREFIX}{lang_code}-`**; otherwise skips
   that lib for that language so in-flight Weblate work is not overwritten.
4. Updates submodule pointers here on **`MASTER_BRANCH`** and each **`${LOCAL_BRANCH_PREFIX}{lang_code}`**
   branch ( **`${LOCAL_BRANCH_PREFIX}*`** updates are force-pushed when finalizing).
5. **POST**s JSON to **`{WEBLATE_URL}/${WEBLATE_ENDPOINT_PATH}`** with
   **`organization`**, **`version`**, optional **`extensions`**, and
   **`add_or_update`**: `{lang_code: [submodule names, ...]}` for libs that were
   actually updated for that language. Omits the call if the map would be empty.
   A typical server response is **HTTP 202** (async); **200** is also accepted.

| `client_payload` field | Required | Description                                                                                                                                                  |
| ---------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `version`              | no       | Boost ref (e.g. `boost-1.90.0`). Defaults to `develop`.                                                                                                      |
| `lang_codes`           | no       | Comma-separated language codes (e.g. `zh_Hans,ja`). Defaults to **`vars.LANG_CODES`**; the workflow fails if neither this field nor **`LANG_CODES`** is set. |
| `extensions`           | no       | File extensions for Weblate (e.g. `[.adoc, .md]`). Default: empty (no filter in the payload).                                                                |

---

### `sync-translation.yml` — Advance submodule pointers on `${LOCAL_BRANCH_PREFIX}*` branches

**Trigger:** `repository_dispatch` with `event_type: sync-translation`, or daily schedule (`0 0 * * *`)

```json
{ "event_type": "sync-translation" }
```

Discovers all remote **`${LOCAL_BRANCH_PREFIX}*`** branches in this repo, then for each one: checks
it out with submodules, sets each submodule’s tracking branch to that name,
runs **`git submodule update --remote`**, commits if pointers changed, and
**force-pushes** the branch.

No `client_payload` fields.

---

## Assets

Shared workflow snippets live under **`.github/workflows/assets/`**.

### `create-tag.yml`

Copied into each library mirror repo when **`${LOCAL_BRANCH_PREFIX}{lang_code}`** is created.
When a Weblate PR (**`${TRANSLATION_BRANCH_PREFIX}{lang_code}-{version}`** → **`${LOCAL_BRANCH_PREFIX}{lang_code}`**)
is merged, it creates tag **`{version}-{repo}-{lang_code}`** if it does not already
exist.

See [`.github/workflows/assets/README.md`](.github/workflows/assets/README.md) for
branch and tag naming details.

### `env.sh` and `lib.sh`

Sourced by **`add-submodules`** and **`start-translation`**: org/repo names, branch prefixes
(`MASTER_BRANCH`, `LOCAL_BRANCH_PREFIX`, `TRANSLATION_BRANCH_PREFIX`), Weblate path
(`WEBLATE_ENDPOINT_PATH`), clone and prune helpers, translations-repo branch setup,
submodule pointer updates, and list parsing.

---

## Scripts (local `repository_dispatch`)

From a clone of this repo:

- **`scripts/trigger-add-submodules.sh`** — fires **`add-submodules`**.
- **`scripts/trigger-start-translation.sh`** — fires **`start-translation`** (optional
  **`--version`**, **`--lang-codes`**, **`--extensions`**).

Copy **`.env.example`** to **`.env`** and set **`GH_TOKEN`** (or **`GITHUB_TOKEN`**)
with permission to call **`POST /repos/{owner}/{repo}/dispatches`** on the target
repo. The workflows still use GitHub **secrets** and **variables** on the server as
documented below.

---

## Required secrets

| Secret          | Used by             | Description                                                                                                                 |
| --------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `SYNC_TOKEN`    | all workflows       | PAT with **`repo`** scope; **`add-submodules`** also needs permission to create org repositories when creating new mirrors. |
| `WEBLATE_URL`   | `start-translation` | Base URL of the Weblate instance (the workflow appends **`WEBLATE_ENDPOINT_PATH`**).                                |
| `WEBLATE_TOKEN` | `start-translation` | API token for that endpoint.                                                                                                |

## Repository variables

| Variable         | Used by                               | Description                                                                                                                                                                                                                       |
| ---------------- | ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `LANG_CODES`     | `add-submodules`, `start-translation` | Default language codes when **`client_payload.lang_codes`** is omitted (comma- or bracket-list, e.g. `zh_Hans,ja`). Must be set here or passed in the dispatch payload.                                                           |
| `SUBMODULES_ORG` | `add-submodules`, `start-translation` | Optional. GitHub org for **`boostorg`** mirror repos (e.g. `CppDigest`). If unset, the org is the same as this repository’s owner. **`sync-translation`** relies on **`.gitmodules`** URLs already pointing at the correct hosts. |

## Development

Install git hooks (runs lint + tests before each commit):

```bash
scripts/install-git-hooks.sh
```

Requires **git** and **curl** for first-time setup. ShellCheck, actionlint, and bats are
downloaded automatically into `.cache/` when not already installed (`apt install bats`
is optional).

Run checks manually:

```bash
make lint    # ShellCheck + actionlint
make test    # bats test suite
make check   # lint + test (same as pre-commit)
```

CI runs **`make test`** and **`scripts/lint.sh`** on every push and pull request.

## License

This repository is distributed under the
[Boost Software License, Version 1.0](https://www.boost.org/LICENSE_1_0.txt)
(SPDX: `BSL-1.0`).

---
