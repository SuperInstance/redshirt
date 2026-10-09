#!/bin/bash
# test-wake.sh — wake.sh against a mock commits API (ETag semantics).
# Asserts: quiet on 304s, fires .wake within ~7s of an inbox change,
# and survives the API dying (degrades, never silences).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WK="$SCRIPT_DIR/../wake.sh"
chmod +x "$WK" 2>/dev/null || true

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "PASS: $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"; kill "$SRV" "$WAKEPID" 2>/dev/null || true' EXIT
export RS_DIR="$T/rs"
mkdir -p "$RS_DIR"
WORK="$T/work"; mkdir -p "$WORK"

cat > "$RS_DIR/config" << EOF
NAME=wakenode
WORKDIR=$WORK
REPO=https://github.com/example-org/example-repo.git
EOF

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
cat > "$T/mock.py" << EOF
import http.server
etag = ['"v1"']
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/trigger':
            etag[0] = '"v2"'
            self.send_response(200); self.end_headers()
            self.wfile.write(b'ok'); return
        if self.headers.get('If-None-Match') == etag[0]:
            self.send_response(304); self.end_headers(); return
        self.send_response(200)
        self.send_header('ETag', etag[0]); self.end_headers()
        self.wfile.write(b'[]')
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', $PORT), H).serve_forever()
EOF
python3 "$T/mock.py" & SRV=$!
sleep 1

export WAKE_API_URL="http://127.0.0.1:$PORT/commits"
"$WK" > "$T/wake.log" 2>&1 & WAKEPID=$!
sleep 3

# Initial read is a 200 -> one wake at startup is expected; consume it.
[ -f "$WORK/.wake" ] && ok "initial read wakes once" || no "initial read wakes once"
rm -f "$WORK/.wake"

# Steady state: 304s -> no wake.
sleep 8
[ ! -f "$WORK/.wake" ] && ok "quiet on 304s (no spurious wake)" || no "quiet on 304s"

# Simulate a landed task.
curl -s "http://127.0.0.1:$PORT/trigger" > /dev/null
fired=0
for _ in $(seq 1 8); do
  sleep 1
  if [ -f "$WORK/.wake" ]; then fired=1; break; fi
done
[ "$fired" = 1 ] && ok "wake fires within ~7s of inbox change" || no "wake fires on change"
kill "$WAKEPID" 2>/dev/null || true
wait "$WAKEPID" 2>/dev/null || true

# Degradation: API dies -> daemon must stay alive and keep polling.
"$WK" > "$T/wake2.log" 2>&1 & WAKEPID=$!
sleep 3
kill "$SRV" 2>/dev/null || true   # murder the API mid-run
sleep 12
if kill -0 "$WAKEPID" 2>/dev/null; then
  ok "wake daemon survives API death (degrades, never silences)"
else
  no "wake daemon survives API death"
fi
grep -qi "fail" "$T/wake2.log" \
  && ok "daemon logs the channel failure" || no "daemon logs the channel failure"

echo "---"
echo "wake tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
