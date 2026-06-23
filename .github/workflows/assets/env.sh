# shellcheck shell=bash
# shellcheck disable=SC2034
# Variables in this file are consumed by lib.sh and workflow run blocks after `source`.

# Common variables for all workflows. Source this file before lib.sh.

ORG="${GITHUB_REPOSITORY%%/*}"
TRANSLATIONS_REPO="${GITHUB_REPOSITORY##*/}"

BOT_NAME="Boost-Translation-CI-Bot"
BOT_EMAIL="Boost-Translation-CI-Bot@$ORG.local"

BOOST_ORG="boostorg"
MASTER_BRANCH="master"
LOCAL_BRANCH_PREFIX="local-"
TRANSLATION_BRANCH_PREFIX="translation-"
WEBLATE_ENDPOINT_PATH="boost-endpoint/add-or-update/"

# Per-library GitHub org (e.g. CppDigest for https://github.com/CppDigest/<lib>).
# Pass SUBMODULES_ORG in workflow env (repository variable) to use a different org; otherwise
# it defaults to ORG.
if [[ -n "${SUBMODULES_ORG:-}" ]]; then
  MODULE_ORG="$SUBMODULES_ORG"
else
  MODULE_ORG="$ORG"
fi
