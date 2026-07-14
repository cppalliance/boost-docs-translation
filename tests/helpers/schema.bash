# shellcheck shell=bash
# JSON Schema helpers for bats (check-jsonschema + request/response extractors).
# shellcheck disable=SC1091

SCHEMAS_DIR="${SCHEMAS_DIR:-$REPO_ROOT/docs/schemas}"

# shellcheck source=../../scripts/ensure_check_jsonschema.sh
source "$REPO_ROOT/scripts/ensure_check_jsonschema.sh"

# Validate a JSON string against a schema file. Writes a temp instance file.
validate_json_against_schema() {
  local json="$1" schema_path="$2" tmp
  ensure_check_jsonschema || return 1
  tmp="$(mktemp)"
  printf '%s\n' "$json" >"$tmp"
  "$CHECK_JSONSCHEMA_BIN" --schemafile "$schema_path" "$tmp"
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

# Extract POST body from the Weblate mock request log (BODY_START … BODY_END).
extract_weblate_request_body_from_log() {
  local log_file="$1"
  sed -n '/^BODY_START$/,/^BODY_END$/p' "$log_file" | sed '1d;$d'
}

# Extract the last JSON object from a stderr/log file (pretty-printed or one-line).
extract_json_object_from_log() {
  local log_file="$1"
  python3 -c '
import json, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
# Prefer scanning for brace-balanced objects from the end.
candidates = []
depth = 0
start = None
for i, ch in enumerate(text):
    if ch == "{":
        if depth == 0:
            start = i
        depth += 1
    elif ch == "}" and depth:
        depth -= 1
        if depth == 0 and start is not None:
            candidates.append(text[start : i + 1])
            start = None
for blob in reversed(candidates):
    try:
        obj = json.loads(blob)
    except json.JSONDecodeError:
        continue
    if isinstance(obj, dict):
        print(json.dumps(obj))
        sys.exit(0)
sys.exit(1)
' "$log_file"
}
