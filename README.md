# boost-docs-translation

Mirrors Boost library documentation repositories into the CppDigest org, maintains
submodule links on `master` and `local-{lang_code}` branches, and keeps local-branch
pointers up to date on a daily schedule.

---

## Integration contracts

HTTP surfaces are described in **[`docs/endpoint-contract.md`](docs/endpoint-contract.md)**.

---

## Workflows

### `add-submodules.yml` — Add new submodules

**Trigger:** `repository_dispatch` with `event_type: add-submodules`

```json
{"event_type": "add-submodules", "client_payload": {"version": "boost-1.90.0"}}
```

For each Boost library submodule:
1. Skips if the repo already exists in the CppDigest org.
2. Fetches `meta/libraries.json` to determine doc paths, clones the `boostorg` repo at
   the given ref, and prunes to doc folders only.
3. Creates `CppDigest/<submodule>`, pushes doc content to `master`, creates
   `local-{lang_code}` branches for each language, and installs `create-tag.yml`
   (from `assets/`) into the new repo.
4. Updates submodule links in this repo (`libs/`) on `master` and each `local-{lang_code}` branch.

| `client_payload` field | Required | Description |
|---|---|---|
| `version` | no | Boost ref (e.g. `boost-1.90.0`). Defaults to `develop`. |
| `submodules` | no | List-like string (e.g. `[algorithm, system]`). If omitted, reads from `.gitmodules`. |
| `lang_codes` | no | Comma-separated language codes (e.g. `zh_Hans,ja`). Defaults to `vars.LANG_CODES`. |

---

### `start-translation.yml` — Sync existing submodules

**Trigger:** `repository_dispatch` with `event_type: start-translation`

```json
{"event_type": "start-translation", "client_payload": {"version": "boost-1.90.0"}}
```

Reads the submodule list from `.gitmodules` of this repo (only `libs/` entries).
For each lang code and each submodule:
1. Ensures this repo has a `local-{lang_code}` branch.
2. Syncs `CppDigest/{lib}` master from the upstream `boostorg` repo.
3. Manages the `local-{lang_code}` branch in the lib repo: creates it if missing,
   or merges master into it if no open translation PR exists; skips if a PR is open.
4. Updates submodule pointers on `master` and each `local-{lang_code}` branch.
5. POSTs to Weblate with an `add_or_update` map of `{lang_code: [submodules, ...]}`.
   Skipped if all entries are empty (no submodules were updated).

| `client_payload` field | Required | Description |
|---|---|---|
| `version` | no | Boost ref (e.g. `boost-1.90.0`). Defaults to `develop`. |
| `lang_codes` | no | Comma-separated language codes (e.g. `zh_Hans,ja`). Defaults to `vars.LANG_CODES`. |
| `extensions` | no | File extensions for Weblate (e.g. `[.adoc, .md]`). Default: empty (all supported). |

---

### `sync-translation.yml` — Sync local-branch pointers

**Trigger:** `repository_dispatch` with `event_type: sync-translation`, or daily schedule (`0 0 * * *`)

```json
{"event_type": "sync-translation"}
```

Discovers all remote `local-*` branches in this repo, then for each one:
checks it out with submodules, advances every submodule pointer to the tip of that
submodule's own `local-*` branch, commits, and force-pushes.

No `client_payload` fields.

---

## Assets

### `.github/workflows/assets/create-tag.yml`

A workflow template copied into each CppDigest lib repo by `add-submodules.yml` and
`start-translation.yml`. Triggers when a Weblate translation PR
(`translation-{lang_code}-{version}` → `local-{lang_code}`) is merged, and creates a
versioned tag of the form `{version}-{repo}-{lang_code}`
(e.g. `boost-1.90.0-algorithm-zh_Hans`). Skipped if the tag already exists.

See [`assets/README.md`](.github/workflows/assets/README.md) for details.

---

## Required secrets

| Secret | Used by | Description |
|---|---|---|
| `SYNC_TOKEN` | all workflows | PAT with `repo` scope (and org repo-create permission for `add-submodules`). |
| `WEBLATE_URL` | `start-translation` | Weblate instance URL. |
| `WEBLATE_TOKEN` | `start-translation` | Weblate API token. |

## Repository variables

| Variable | Used by | Description |
|---|---|---|
| `LANG_CODES` | `add-submodules`, `start-translation` | Optional. Default comma-separated language codes (e.g. `zh_Hans,ja`). |

---
