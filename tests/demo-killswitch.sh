#!/bin/bash
# demo-killswitch.sh — proves the external switch kills a shirt that ignores
# its own timebox, then buries it. Runs in a scratch HOME; the real
# ~/.redshirt is untouched.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KS="$SCRIPT_DIR/../killswitch.sh"
chmod +x "$KS" 2>/dev/null || true

T="$(mktemp -d)"
export HOME="$T/home"
mkdir -p "$HOME"
trap 'rm -rf "$T"' EXIT

NOW="$(date -u +%s)"
mkdir -p "$HOME/.redshirt"
# Deadline ~8s away: HOURS=1, STARTED=now-3592.
cat > "$HOME/.redshirt/config" << EOF
NAME=demonode
HOURS=1
STARTED=$((NOW - 3592))
REPO=https://github.com/SuperInstance/redshirt.git
WORKDIR=$HOME/.redshirt/work
ALLOWLIST=
NET_OK=0
REAP_AFTER=300
WAKE=0
KILLSWITCH=1
EOF

# Rogue shirt: ignores SIGTERM *and* its timebox. Never exits on its own.
setsid bash -c 'trap "" TERM; while true; do echo "$(date -u +%FT%TZ) rogue: alive, ignoring timebox" >> "$HOME/.redshirt/rogue.log"; sleep 2; done' \
  < /dev/null > /dev/null 2>&1 &
ROGUE=$!
echo "$ROGUE" > "$HOME/.redshirt/poller.pgid"   # setsid => pgid == pid
echo "rogue shirt running (pid $ROGUE, pgid $ROGUE), deadline in ~8s"

"$KS" > "$T/ks.log" 2>&1
echo "--- killswitch log ---"
cat "$T/ks.log"
echo "--- verdict ---"
if kill -0 "$ROGUE" 2>/dev/null; then
  echo "FAIL: rogue shirt still alive past its deadline"
  exit 1
else
  echo "PASS: rogue shirt is dead (SIGKILL path taken)"
fi
if [ -e "$HOME/.redshirt" ]; then
  echo "FAIL: node directory remains after burial"
  exit 1
else
  echo "PASS: node buried — nothing remains"
fi
