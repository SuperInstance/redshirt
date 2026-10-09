#!/bin/bash
# redshirt.sh — the redshirt poller, hardened.
#
# Pulls tasks from git, executes each inside sandbox.sh (allowlisted commands,
# one writable dir, no network unless flagged), pushes results. Claims carry
# heartbeats; reaper.sh scavenges claims that go silent. wake.sh (child)
# cuts the poll sleep short when the inbox changes. At end of timebox — or on
# any exit — the EXIT trap buries the node: workdir, config, logs, gone.
# killswitch.sh (external supervisor) guarantees death even if this loop is
# ever patched to never exit.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RS_DIR="$HOME/.redshirt"
export RS_DIR
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
# shellcheck disable=SC1091
source "$RS_DIR/config"

WORKDIR="$WORKDIR"   # from config; kept explicit for clarity
INBOX="$WORKDIR/tasks/$NAME/inbox"
OUTBOX="$WORKDIR/tasks/$NAME/outbox"
DONE="$WORKDIR/tasks/$NAME/done"
END_TIME=$((STARTED + HOURS * 3600))
POLL_INTERVAL="${POLL_INTERVAL:-60}"
CURRENT_TASK="none"
export RS_LOG="$RS_DIR/poller.log"

mkdir -p "$INBOX" "$OUTBOX" "$DONE"

# Heartbeat format: machine-readable frontmatter the captain's board reads.
# last: ISO-8601 UTC of this beat; started/hours define the timebox.
heartbeat() {
  cat > "$WORKDIR/tasks/$NAME/heartbeat.md" << EOF
---
node: $NAME
last: $(date -u +%FT%TZ)
started: $STARTED
hours: $HOURS
task: $CURRENT_TASK
---
alive
EOF
}

# --- self-burial: a real redshirt does not even leave a corpse --------------
bury() {
  rs_log "burying node '$NAME' (workdir, config, logs)"
  # Reap our own children first (wake.sh, heartbeat updaters). Grandchildren
  # already spawned (a sleeping `sleep`, an in-flight curl) finish and exit
  # on their own once their parent is gone.
  pkill -P $$ 2>/dev/null || true
  sleep 1
  rm -rf "$RS_DIR"
}
trap bury EXIT

# --- wake trigger (child; dies with our process group) ----------------------
if [ "${WAKE:-1}" = "1" ]; then
  "$SCRIPT_DIR/wake.sh" >> "$RS_LOG" 2>&1 &
  echo $! > "$RS_DIR/wake.pid"
  rs_log "wake trigger started (pid $(cat "$RS_DIR/wake.pid"))"
fi

# --- claim helpers -----------------------------------------------------------
# Atomic claim via noclobber: exactly one shirt wins the race.
claim_task() {
  local taskfile="$1" now
  now="$(rs_now)"
  if ( set -o noclobber
       printf 'name=%s\nclaimed_at=%s\nheartbeat=%s\n' "$NAME" "$now" "$now" \
         > "$taskfile.claimed" ) 2>/dev/null; then
    return 0
  fi
  return 1
}

touch_claim() {
  local claim="$1"
  [ -f "$claim" ] || return 0
  local tmp="$claim.tmp.$$"
  sed "s/^heartbeat=.*/heartbeat=$(rs_now)/" "$claim" > "$tmp" && mv "$tmp" "$claim"
}

# --- task execution ----------------------------------------------------------
run_task() {
  local taskfile="$1" slug="$2" claim="$3"
  local claude_prompt run_cmd rc=0

  claude_prompt="$(grep -m1 '^claude:' "$taskfile" | sed 's/^claude: *//')"
  run_cmd="$(grep -m1 '^run:' "$taskfile" | sed 's/^run: *//')"

  local result_tmp
  result_tmp="$(mktemp)"
  {
    echo "# Result: $slug"
    echo ""
    echo "node: $NAME"
    echo "at: $(date -u +%FT%TZ)"
    echo ""
    echo "## output"
    echo ""
    echo '```'
    if [ -n "$claude_prompt" ]; then
      if printf '%s' "$ALLOWLIST" | grep -qw claude; then
        RS_WORKDIR="$OUTBOX/.task-$slug" RS_NET_OK="$NET_OK" RS_ALLOWLIST="$ALLOWLIST" \
          RS_STRICT="${STRICT:-0}" \
          timeout 600 "$SCRIPT_DIR/sandbox.sh" claude -p "$claude_prompt" 2>&1 \
          || { rc=$?; echo "[redshirt] claude failed (rc=$rc)"; }
      else
        echo "[redshirt] 'claude' is not in this node's command allowlist; task refused"
        rc=126
      fi
    elif [ -n "$run_cmd" ]; then
      mkdir -p "$OUTBOX/.task-$slug"
      RS_WORKDIR="$OUTBOX/.task-$slug" RS_NET_OK="$NET_OK" RS_ALLOWLIST="$ALLOWLIST" \
        RS_STRICT="${STRICT:-0}" \
        timeout 600 "$SCRIPT_DIR/sandbox.sh" sh -c "$run_cmd" 2>&1 \
        || { rc=$?; echo "[redshirt] command failed (rc=$rc)"; }
      rm -rf "$OUTBOX/.task-$slug"
    else
      echo "[redshirt] no claude: or run: directive found"
      rc=2
    fi
    echo '```'
    echo ""
    echo "exit: $rc"
  } > "$result_tmp" &
  local taskpid=$!

  # Heartbeat pumper: keeps our claim fresh while the task runs, so the
  # reaper never mistakes a long task for a dead shirt.
  while kill -0 "$taskpid" 2>/dev/null; do
    touch_claim "$claim"
    sleep 30
  done
  wait "$taskpid" || true

  mv "$result_tmp" "$OUTBOX/$slug.result.md"
  return 0
}

# --- wake-interruptible sleep --------------------------------------------------
wait_with_wake() {
  local budget="$1" waited=0 wakefile="$WORKDIR/.wake"
  rm -f "$wakefile"  # consume any stale wake
  while [ "$waited" -lt "$budget" ]; do
    sleep 2
    waited=$((waited + 2))
    if [ -f "$wakefile" ]; then
      rm -f "$wakefile"
      rs_log "wake: trigger fired after ~${waited}s — polling now"
      return 0
    fi
  done
  return 0
}

# --- main loop -----------------------------------------------------------------
rs_log "node '$NAME' live; timebox ends $(date -u -d "@$END_TIME" +%FT%TZ 2>/dev/null || date -u -r "$END_TIME" +%FT%TZ)"
heartbeat

while [ "$(rs_now)" -lt "$END_TIME" ]; do
  cd "$WORKDIR" || break
  git pull -q 2>/dev/null || true

  # Scavenge: requeue tasks whose claimant went silent.
  "$SCRIPT_DIR/reaper.sh" 2>/dev/null || rs_log "reaper failed (continuing)"

  for taskfile in "$INBOX"/*.md; do
    [ -f "$taskfile" ] || continue
    [ -f "$taskfile.claimed" ] && continue
    claim_task "$taskfile" || continue

    slug="$(basename "$taskfile" .md)"
    rs_log "claimed task: $slug"
    CURRENT_TASK="$slug"
    heartbeat

    run_task "$taskfile" "$slug" "$taskfile.claimed"

    mv "$taskfile" "$DONE/"
    rm -f "$taskfile.claimed"
    CURRENT_TASK="none"
    git add -A
    git -c user.name="redshirt-$NAME" -c user.email="redshirt@superinstance.ai" \
      commit -qm "redshirt $NAME: done $slug" 2>/dev/null || true
    git push -q 2>/dev/null || true
    rs_log "done: $slug, result pushed"
  done

  heartbeat
  ( cd "$WORKDIR" && git add "tasks/$NAME/heartbeat.md" \
    && git -c user.name="redshirt-$NAME" -c user.email="redshirt@superinstance.ai" \
       commit -qm "heartbeat $NAME" 2>/dev/null || true; git push -q 2>/dev/null || true )

  wait_with_wake "$POLL_INTERVAL"
done

rs_log "timebox expired. Node '$NAME' is dead."
# bury() runs via the EXIT trap.
