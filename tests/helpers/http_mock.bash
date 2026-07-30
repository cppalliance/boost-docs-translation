# shellcheck shell=bash
# Local HTTP mock for Weblate POST tests (no real network).

MOCK_WEBLATE_PID=""
MOCK_WEBLATE_PORT=""
MOCK_WEBLATE_PORT_FILE=""
MOCK_WEBLATE_BASE_URL=""
MOCK_WEBLATE_REQUEST_LOG=""
MOCK_WEBLATE_SERVER_SCRIPT=""
_CURL_ORIG_PATH=""

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

  local i=0 port=""
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
    sleep 0.05
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

install_curl_timeout_stub() {
  install_curl_stub
}

install_curl_stub() {
  _CURL_ORIG_PATH="$PATH"
  local wrapper_dir
  wrapper_dir="$(mktemp -d)"
  REAL_CURL="$(command -v curl)"
  export REAL_CURL
  cat >"$wrapper_dir/curl" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${MOCK_CURL_EXIT:-}" ]]; then
  echo "mock curl: simulated exit ${MOCK_CURL_EXIT}" >&2
  exit "$MOCK_CURL_EXIT"
fi
if [[ "${MOCK_CURL_TIMEOUT:-}" == "1" ]]; then
  echo "mock curl: simulated timeout" >&2
  exit 28
fi
exec "$REAL_CURL" "$@"
EOF
  chmod +x "$wrapper_dir/curl"
  CURL_WRAPPER_DIR="$wrapper_dir"
  export PATH="$wrapper_dir:$PATH"
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

# Intercept GitHub repository_dispatch POST (no real network).
install_dispatch_curl_stub() {
  _CURL_ORIG_PATH="$PATH"
  local wrapper_dir
  wrapper_dir="$(mktemp -d)"
  REAL_CURL="$(command -v curl)"
  export REAL_CURL
  MOCK_DISPATCH_REQUEST_LOG="${MOCK_DISPATCH_REQUEST_LOG:-$(mktemp)}"
  export MOCK_DISPATCH_REQUEST_LOG
  MOCK_DISPATCH_STATUS="${MOCK_DISPATCH_STATUS:-204}"
  export MOCK_DISPATCH_STATUS
  MOCK_DISPATCH_RESPONSE_BODY="${MOCK_DISPATCH_RESPONSE_BODY:-}"
  export MOCK_DISPATCH_RESPONSE_BODY
  cat >"$wrapper_dir/curl" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${MOCK_CURL_EXIT:-}" ]]; then
  echo "mock curl: simulated exit ${MOCK_CURL_EXIT}" >&2
  exit "$MOCK_CURL_EXIT"
fi
if [[ "${MOCK_CURL_TIMEOUT:-}" == "1" ]]; then
  echo "mock curl: simulated timeout" >&2
  exit 28
fi
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
    printf '%s' "${MOCK_DISPATCH_STATUS:-204}"
  fi
  exit 0
fi
exec "$REAL_CURL" "$@"
EOF
  chmod +x "$wrapper_dir/curl"
  CURL_WRAPPER_DIR="$wrapper_dir"
  export PATH="$wrapper_dir:$PATH"
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
