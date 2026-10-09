#!/bin/bash
# test-reaper.sh — the scavenger requeues only stale claims.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RP="$SCRIPT_DIR/../reaper.sh"
chmod +x "$RP" 2>/dev/null || true

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "PASS: $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export RS_DIR="$T/rs"
mkdir -p "$RS_DIR"

NOW="$(date -u +%s)"
cat > "$RS_DIR/config" << EOF
NAME=testnode
WORKDIR=$T/work
REAP_AFTER=300
EOF

INBOX="$T/work/tasks/testnode/inbox"
OUTBOX="$T/work/tasks/testnode/outbox"
mkdir -p "$INBOX" "$OUTBOX"

# fresh claim: heartbeat now -> must survive
echo "# fresh" > "$INBOX/fresh.md"
printf 'name=testnode\nclaimed_at=%s\nheartbeat=%s\n' "$NOW" "$NOW" > "$INBOX/fresh.md.claimed"
# stale claim: heartbeat 1000s ago -> must be requeued
echo "# stale" > "$INBOX/stale.md"
printf 'name=deadnode\nclaimed_at=%s\nheartbeat=%s\n' "$((NOW-1000))" "$((NOW-1000))" > "$INBOX/stale.md.claimed"
# malformed claim: non-numeric heartbeat -> treated as ancient -> requeued
echo "# malformed" > "$INBOX/malformed.md"
printf 'name=weirdnode\nclaimed_at=bogus\nheartbeat=bogus\n' > "$INBOX/malformed.md.claimed"
# unclaimed task -> untouched
echo "# plain" > "$INBOX/plain.md"

"$RP" > "$T/reaper.out" 2>&1

[ -f "$INBOX/fresh.md.claimed" ] \
  && ok "fresh claim survives" || no "fresh claim survives"
[ ! -f "$INBOX/stale.md.claimed" ] && [ -f "$INBOX/stale.md" ] \
  && ok "stale claim requeued (task file intact)" || no "stale claim requeued"
[ ! -f "$INBOX/malformed.md.claimed" ] \
  && ok "malformed claim treated as stale" || no "malformed claim treated as stale"
[ ! -f "$INBOX/plain.md.claimed" ] \
  && ok "unclaimed task untouched" || no "unclaimed task untouched"
grep -q "stale" "$OUTBOX/reaped.log" && grep -q "malformed" "$OUTBOX/reaped.log" \
  && ok "reaped.log records both requeues" || no "reaped.log records requeues"

echo "---"
echo "reaper tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
