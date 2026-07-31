# shellcheck shell=bash
# Local HTTP mock for Weblate POST tests (no real network).

MOCK_WEBLATE_PID=""
MOCK_WEBLATE_PORT=""
MOCK_WEBLATE_PORT_FILE=""
MOCK_WEBLATE_BASE_URL=""
MOCK_WEBLATE_REQUEST_LOG=""
MOCK_WEBLATE_SERVER_SCRIPT=""
_CURL_ORIG_PATH=""

common_setup() {
  local root_dir
  root_dir="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck disable=SC2034
  export ROOT="$root_dir"
}

dispatch_common_setup() {
  common_setup
  install_dispatch_curl_stub
}

common_teardown() {
  restore_dispatch_curl_stub
}

start_weblate_mock_server() {
  local status="${MOCK_WEBLATE_STATUS:-202}"
  local body="${MOCK_WEBLATE_BODY:-{\"status\":\"accepted\"}}"
  local delay="${MOCK_WEBLATE_DELAY_SEC:-0}"

  MOCK_WEBLATE_REQUEST_LOG="$(mktemp)"
  MOCK_WEBLATE_PORT_FILE="$(mktemp)"
  MOCK_WEBLATE_SERVER_SCRIPT="$(mktemp)"
  cat >"$MOCK_WEBLATE_SERVER_SCRIPT" <<'PYEOF'
import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

status = int(os.environ.get("MOCK_WEBLATE_STATUS", "202"))
body = os.environ.get("MOCK_WEBLATE_BODY", '{"status":"accepted"}')
delay = float(os.environ.get("MOCK_WEBLATE_DELAY_SEC", "0"))
request_log = os.environ["MOCK_WEBLATE_REQUEST_LOG"]
port_file = os.environ["MOCK_WEBLATE_PORT_FILE"]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_POST(self):
        if delay > 0:
            time.sleep(delay)
        length = int(self.headers.get("Content-Length", "0"))
        payload = self.rfile.read(length).decode("utf-8", errors="replace")
        with open(request_log, "w", encoding="utf-8") as f:
            f.write(f"PATH={self.path}\n")
            for key, value in self.headers.items():
                f.write(f"HEADER:{key}: {value}\n")
            f.write("BODY_START\n")
            f.write(payload)
            f.write("\nBODY_END\n")
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="utf-8") as f:
    f.write(str(server.server_port))
server.serve_forever()
PYEOF

  export MOCK_WEBLATE_STATUS="$status" MOCK_WEBLATE_BODY="$body" MOCK_WEBLATE_DELAY_SEC="$delay"
  export MOCK_WEBLATE_REQUEST_LOG MOCK_WEBLATE_PORT_FILE
  python3 "$MOCK_WEBLATE_SERVER_SCRIPT" &
  MOCK_WEBLATE_PID=$!

  local i=0 port="" sleep_sec=0.05
  while [[ -z "$port" ]]; do
    if [[ -s "$MOCK_WEBLATE_PORT_FILE" ]]; then
      port="$(<"$MOCK_WEBLATE_PORT_FILE")"
      if python3 -c "import socket; s=socket.create_connection(('127.0.0.1', $port), 0.2); s.close()" 2>/dev/null; then
        break
      fi
      port=""
    fi
    if ! kill -0 "$MOCK_WEBLATE_PID" 2>/dev/null; then
      stop_weblate_mock_server
      echo "http_mock: mock server exited before binding" >&2
      return 1
    fi
    i=$((i + 1))
    if [[ $i -gt 50 ]]; then
      stop_weblate_mock_server
      echo "http_mock: mock server failed to start" >&2
      return 1
    fi
    sleep "$sleep_sec"
    sleep_sec="$(awk "BEGIN {v=$sleep_sec*2; print (v>0.5?0.5:v)}")"
  done

  MOCK_WEBLATE_PORT="$port"
  MOCK_WEBLATE_BASE_URL="http://127.0.0.1:${MOCK_WEBLATE_PORT}/"
  export MOCK_WEBLATE_PORT MOCK_WEBLATE_BASE_URL
}

stop_weblate_mock_server() {
  if [[ -n "${MOCK_WEBLATE_PID:-}" ]]; then
    kill "$MOCK_WEBLATE_PID" 2>/dev/null || true
    wait "$MOCK_WEBLATE_PID" 2>/dev/null || true
  fi
  [[ -n "${MOCK_WEBLATE_SERVER_SCRIPT:-}" && -f "$MOCK_WEBLATE_SERVER_SCRIPT" ]] && rm -f "$MOCK_WEBLATE_SERVER_SCRIPT"
  [[ -n "${MOCK_WEBLATE_REQUEST_LOG:-}" && -f "$MOCK_WEBLATE_REQUEST_LOG" ]] && rm -f "$MOCK_WEBLATE_REQUEST_LOG"
  [[ -n "${MOCK_WEBLATE_PORT_FILE:-}" && -f "$MOCK_WEBLATE_PORT_FILE" ]] && rm -f "$MOCK_WEBLATE_PORT_FILE"
  MOCK_WEBLATE_PID=""
  MOCK_WEBLATE_PORT=""
  MOCK_WEBLATE_PORT_FILE=""
  MOCK_WEBLATE_BASE_URL=""
  MOCK_WEBLATE_REQUEST_LOG=""
  MOCK_WEBLATE_SERVER_SCRIPT=""
  unset MOCK_WEBLATE_STATUS MOCK_WEBLATE_BODY MOCK_WEBLATE_DELAY_SEC
}

_init_curl_wrapper_dir() {
  _CURL_ORIG_PATH="$PATH"
  CURL_WRAPPER_DIR="$(mktemp -d)"
  REAL_CURL="$(command -v curl)"
  export REAL_CURL CURL_WRAPPER_DIR
}

_activate_curl_wrapper() {
  chmod +x "$CURL_WRAPPER_DIR/curl"
  export PATH="$CURL_WRAPPER_DIR:$PATH"
}

_curl_stub_preamble() {
  cat <<'STUB_EOF'
if [[ -n "${MOCK_CURL_EXIT:-}" ]]; then
  echo "mock curl: simulated exit ${MOCK_CURL_EXIT}" >&2
  exit "$MOCK_CURL_EXIT"
fi
if [[ "${MOCK_CURL_TIMEOUT:-}" == "1" ]]; then
  echo "mock curl: simulated timeout" >&2
  exit 28
fi
STUB_EOF
}

_curl_stub_exec_line() {
  cat <<'STUB_EOF'
exec "$REAL_CURL" "$@"
STUB_EOF
}

install_curl_timeout_stub() {
  install_curl_stub
}

install_curl_stub() {
  _init_curl_wrapper_dir
  {
    echo '#!/usr/bin/env bash'
    _curl_stub_preamble
    _curl_stub_exec_line
  } >"$CURL_WRAPPER_DIR/curl"
  _activate_curl_wrapper
}

restore_curl_stub() {
  if [[ -n "${_CURL_ORIG_PATH:-}" ]]; then
    export PATH="$_CURL_ORIG_PATH"
  fi
  if [[ -n "${CURL_WRAPPER_DIR:-}" && -d "$CURL_WRAPPER_DIR" ]]; then
    rm -rf "$CURL_WRAPPER_DIR"
  fi
  unset CURL_WRAPPER_DIR REAL_CURL _CURL_ORIG_PATH MOCK_CURL_TIMEOUT MOCK_CURL_EXIT
}

install_slack_curl_stub() {
  _init_curl_wrapper_dir
  MOCK_SLACK_REQUEST_LOG="$(mktemp)"
  export MOCK_SLACK_REQUEST_LOG
  {
    echo '#!/usr/bin/env bash'
    _curl_stub_preamble
    cat <<'EOF'
if [[ -n "${SLACK_WEBHOOK_URL:-}" && " $* " == *" ${SLACK_WEBHOOK_URL} "* ]]; then
  body=""
  prev=""
  for arg in "$@"; do
    if [[ "$prev" == "--data" || "$prev" == "-d" ]]; then
      body="$arg"
    fi
    prev="$arg"
  done
  {
    echo "URL=$SLACK_WEBHOOK_URL"
    echo "BODY_START"
    printf '%s' "$body"
    echo
    echo "BODY_END"
  } >"${MOCK_SLACK_REQUEST_LOG}"
  exit 0
fi
exec "$REAL_CURL" "$@"
EOF
  } >"$CURL_WRAPPER_DIR/curl"
  _activate_curl_wrapper
}

restore_slack_curl_stub() {
  [[ -n "${MOCK_SLACK_REQUEST_LOG:-}" && -f "$MOCK_SLACK_REQUEST_LOG" ]] && rm -f "$MOCK_SLACK_REQUEST_LOG"
  unset MOCK_SLACK_REQUEST_LOG
  restore_curl_stub
}

# Intercept GitHub repository_dispatch POST (no real network).
install_dispatch_curl_stub() {
  _init_curl_wrapper_dir
  MOCK_DISPATCH_REQUEST_LOG="${MOCK_DISPATCH_REQUEST_LOG:-$(mktemp)}"
  export MOCK_DISPATCH_REQUEST_LOG
  MOCK_DISPATCH_STATUS="${MOCK_DISPATCH_STATUS:-204}"
  export MOCK_DISPATCH_STATUS
  MOCK_DISPATCH_RESPONSE_BODY="${MOCK_DISPATCH_RESPONSE_BODY:-}"
  export MOCK_DISPATCH_RESPONSE_BODY
  {
    echo '#!/usr/bin/env bash'
    _curl_stub_preamble
    cat <<'EOF'
args=("$@")
url=""
method=""
body_file=""
body_inline=""
out_file=""
write_out=""
i=0
while [[ $i -lt ${#args[@]} ]]; do
  arg="${args[$i]}"
  case "$arg" in
    -X)
      method="${args[$((i + 1))]}"
      i=$((i + 2))
      ;;
    -d)
      next="${args[$((i + 1))]}"
      if [[ -f "$next" ]]; then
        body_file="$next"
      else
        body_inline="$next"
      fi
      i=$((i + 2))
      ;;
    -o)
      out_file="${args[$((i + 1))]}"
      i=$((i + 2))
      ;;
    -w)
      write_out="${args[$((i + 1))]}"
      i=$((i + 2))
      ;;
    http://*|https://*)
      url="$arg"
      i=$((i + 1))
      ;;
    *)
      i=$((i + 1))
      ;;
  esac
done
if [[ "$url" == *"api.github.com/repos/"*/dispatches && "$method" == "POST" ]]; then
  {
    echo "URL=$url"
    echo "METHOD=$method"
    if [[ -n "$body_file" ]]; then
      echo "BODY_START"
      cat "$body_file"
      echo ""
      echo "BODY_END"
    elif [[ -n "$body_inline" ]]; then
      echo "BODY_START"
      printf '%s\n' "$body_inline"
      echo "BODY_END"
    fi
  } >"$MOCK_DISPATCH_REQUEST_LOG"
  if [[ -n "$out_file" ]]; then
    if [[ -n "${MOCK_DISPATCH_RESPONSE_BODY:-}" ]]; then
      printf '%s' "$MOCK_DISPATCH_RESPONSE_BODY" >"$out_file"
    else
      : >"$out_file"
    fi
  fi
  if [[ -n "$write_out" ]]; then
    printf '%s' "$MOCK_DISPATCH_STATUS"
  fi
  exit 0
fi
exec "$REAL_CURL" "$@"
EOF
  } >"$CURL_WRAPPER_DIR/curl"
  _activate_curl_wrapper
}

restore_dispatch_curl_stub() {
  restore_curl_stub
  if [[ -n "${MOCK_DISPATCH_REQUEST_LOG:-}" && -f "$MOCK_DISPATCH_REQUEST_LOG" ]]; then
    rm -f "$MOCK_DISPATCH_REQUEST_LOG"
  fi
  unset MOCK_DISPATCH_REQUEST_LOG MOCK_DISPATCH_STATUS MOCK_DISPATCH_RESPONSE_BODY
}

extract_dispatch_request_body() {
  local log="${1:?}"
  awk '/^BODY_START$/{found=1; next} /^BODY_END$/{found=0} found' "$log"
}
