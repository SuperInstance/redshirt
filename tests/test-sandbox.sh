#!/bin/bash
# test-sandbox.sh — exercises sandbox.sh's layers.
# Namespace-dependent assertions self-skip on kernels without userns support.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SB="$SCRIPT_DIR/../sandbox.sh"
chmod +x "$SB" 2>/dev/null || true

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
no()   { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
skip() { SKIP=$((SKIP+1)); echo "SKIP: $1"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

sb() {  # sb <workdir> <net_ok> <allowlist> -- <cmd...>
  local wd="$1" net="$2" allow="$3"; shift 3; shift  # drop the --
  mkdir -p "$wd"
  RS_WORKDIR="$wd" RS_NET_OK="$net" RS_ALLOWLIST="$allow" "$SB" "$@"
}

# 1. allowlisted command runs, output captured
out="$(sb "$T/w1" 0 "" -- sh -c 'echo hello' 2>"$T/e1")"
[ "$out" = "hello" ] && ok "allowlisted sh runs" || no "allowlisted sh runs (got: '$out')"

# 2. rm -rf ~ fails loudly (rm not in allowlist); canary outside survives
CANARY="$T/canary-$$"; echo canary > "$CANARY"
if sb "$T/w2" 0 "" -- sh -c 'rm -rf ~' >"$T/o2" 2>"$T/e2"; then
  no "rm -rf ~ refused (it succeeded!)"
else
  if grep -q "not found" "$T/e2" && [ "$(cat "$CANARY")" = "canary" ]; then
    ok "rm -rf ~ fails loudly, outside canary intact"
  else
    no "rm -rf ~ failure mode (see $T/e2)"
  fi
fi

# 3. curl blocked by stub when NET_OK=0, even if allowlisted
if sb "$T/w3" 0 "curl" -- curl -s --max-time 5 http://127.0.0.1:9/ >"$T/o3" 2>"$T/e3"; then
  no "curl blocked with NET_OK=0 (it succeeded!)"
else
  grep -q "DISABLED" "$T/e3" && ok "curl stub fails loudly with NET_OK=0" \
    || no "curl stub message (see $T/e3)"
fi

# 4. NET_OK=1 + allowlisted curl: real network works (local server, no external dep)
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
SRV=$!
sleep 1
if sb "$T/w4" 1 "curl" -- curl -s --max-time 5 "http://127.0.0.1:$PORT/" >"$T/o4" 2>"$T/e4"; then
  ok "NET_OK=1: allowlisted curl reaches the network"
else
  no "NET_OK=1: curl should work (see $T/e4)"
fi
kill "$SRV" 2>/dev/null || true

# 5. HOME is confined to the workdir (redirection is a shell builtin: no external needed)
sb "$T/w5" 0 "" -- sh -c 'echo "$HOME"; echo hi > ~/homefile' >"$T/o5" 2>"$T/e5"
if [ -f "$T/w5/homefile" ] && [ "$(head -1 "$T/o5")" = "$T/w5" ]; then
  ok "HOME confined to workdir (~ writes land inside)"
else
  no "HOME confinement (see $T/o5 $T/e5)"
fi

# 6. task can write inside its workdir (positive control)
sb "$T/w6" 0 "" -- sh -c 'echo data > out.txt' >"$T/o6" 2>"$T/e6"
[ "$(cat "$T/w6/out.txt" 2>/dev/null)" = "data" ] && ok "workdir is writable" || no "workdir writable"

# 7. namespace-mode assertions (full containment) — self-skip without userns
if unshare -U --map-user="$(id -u)" --map-group="$(id -g)" -m -n true 2>/dev/null; then
  if sb "$T/w7" 1 "" -- sh -c 'echo pwn > /etc/redshirt-test-pwn-$$' >"$T/o7" 2>"$T/e7"; then
    no "ns mode: write to /etc refused (it succeeded!)"
  else
    if grep -qi "read-only" "$T/e7" && ! ls /etc/redshirt-test-pwn-* >/dev/null 2>&1; then
      ok "ns mode: outside workdir is read-only"
    else
      no "ns mode: expected read-only error (see $T/e7)"
    fi
  fi
  # allowlisted python cannot exfiltrate either (netns) in ns mode
  if sb "$T/w8" 0 "python3" -- python3 -c 'import socket; socket.create_connection(("127.0.0.1",9),timeout=3)' >"$T/o8" 2>"$T/e8"; then
    no "ns mode: python socket blocked with NET_OK=0 (it succeeded!)"
  else
    ok "ns mode: NET_OK=0 blocks even python sockets"
  fi
else
  skip "ns-mode read-only + netns assertions (no userns support on this kernel)"
fi

echo "---"
echo "sandbox tests: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
