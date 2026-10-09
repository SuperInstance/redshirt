#!/bin/bash
# reaper.sh — the scavenger. Requeues tasks whose claimant went silent.
#
# Claims live next to the task file: inbox/<task>.md.claimed, containing
#   name=<node>
#   claimed_at=<epoch>
#   heartbeat=<epoch>
# The owning shirt refreshes `heartbeat` while it works the task. If
# now - heartbeat > REAP_AFTER (default 300s), the claimant is presumed dead:
# the claim is removed, the task becomes claimable again, and the event is
# appended to outbox/reaped.log.
#
# Run automatically by redshirt.sh at the top of every poll cycle, and
# standalone by the zero agent (or any other shirt): it only needs $RS_DIR/config.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
# shellcheck disable=SC1091
source "$RS_DIR/config"

REAP_AFTER="${REAP_AFTER:-300}"
INBOX="$WORKDIR/tasks/$NAME/inbox"
OUTBOX="$WORKDIR/tasks/$NAME/outbox"
mkdir -p "$OUTBOX" 2>/dev/null || true

now="$(rs_now)"
reaped=0
checked=0

for taskfile in "$INBOX"/*.md; do
  [ -f "$taskfile" ] || continue
  claim="$taskfile.claimed"
  [ -f "$claim" ] || continue
  checked=$((checked + 1))

  cname="$(grep -m1 '^name=' "$claim" 2>/dev/null | cut -d= -f2-)"
  hb="$(grep -m1 '^heartbeat=' "$claim" 2>/dev/null | cut -d= -f2-)"
  # Malformed or non-numeric heartbeat: treat as ancient (reap it).
  case "$hb" in ''|*[!0-9]*) hb=0 ;; esac
  age=$((now - hb))
  [ "$age" -lt 0 ] && age=0

  if [ "$age" -gt "$REAP_AFTER" ]; then
    slug="$(basename "$taskfile" .md)"
    rs_log "reaper: '$slug' claimed by '${cname:-unknown}', silent ${age}s > ${REAP_AFTER}s — requeueing"
    rm -f "$claim"
    echo "$(date -u +%FT%TZ) reaped $slug (was claimed by ${cname:-unknown}, silent ${age}s)" \
      >> "$OUTBOX/reaped.log"
    reaped=$((reaped + 1))
  fi
done

[ "$reaped" -gt 0 ] && rs_log "reaper: requeued $reaped stale task(s) ($checked claim(s) checked)"
exit 0
