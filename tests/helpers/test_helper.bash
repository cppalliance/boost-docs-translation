# shellcheck shell=bash
# Facade for new bats tests: loads shared fixtures and mocks.
# shellcheck disable=SC1091

_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=tests/helpers/common.bash
source "$_HELPER_DIR/common.bash"
# shellcheck source=tests/helpers/git_fixtures.bash
source "$_HELPER_DIR/git_fixtures.bash"
# shellcheck source=tests/helpers/http_mock.bash
source "$_HELPER_DIR/http_mock.bash"

unset _HELPER_DIR
