#!/bin/bash
# redshirt poller: pulls tasks from git, executes, pushes results. Dies on timebox.
set -e
source "$HOME/.redshirt/config"
WORKDIR="$WORKDIR"
INBOX="$WORKDIR/tasks/$NAME/inbox"
OUTBOX="$WORKDIR/tasks/$NAME/outbox"
DONE="$WORKDIR/tasks/$NAME/done"
END_TIME=$((STARTED + HOURS * 3600))
CURRENT_TASK="none"

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

heartbeat

while [ "$(date -u +%s)" -lt "$END_TIME" ]; do
  cd "$WORKDIR"
  git pull -q 2>/dev/null || true

  for taskfile in "$INBOX"/*.md; do
    [ -f "$taskfile" ] || continue
    # Skip if already claimed (simple lock via .claimed suffix check)
    [ -f "$taskfile.claimed" ] && continue
    touch "$taskfile.claimed"

    slug=$(basename "$taskfile" .md)
    echo "[redshirt] Claimed task: $slug"
    CURRENT_TASK="$slug"
    heartbeat

    # Parse task: look for "claude:" or "run:" line
    CLAUDE_PROMPT=$(grep -m1 '^claude:' "$taskfile" | sed 's/^claude: *//')
    RUN_CMD=$(grep -m1 '^run:' "$taskfile" | sed 's/^run: *//')

    RESULT_FILE="$OUTBOX/$slug.result.md"
    {
      echo "# Result: $slug"
      echo ""
      echo "node: $NAME"
      echo "at: $(date -u +%FT%TZ)"
      echo ""
      echo "## output"
      echo ""
      echo '```'
      if [ -n "$CLAUDE_PROMPT" ]; then
        if command -v claude >/dev/null 2>&1; then
          timeout 600 claude -p "$CLAUDE_PROMPT" 2>&1 || echo "[redshirt] claude failed or timed out"
        else
          echo "[redshirt] claude not installed"
        fi
      elif [ -n "$RUN_CMD" ]; then
        timeout 600 bash -c "$RUN_CMD" 2>&1 || echo "[redshirt] command failed or timed out"
      else
        echo "[redshirt] no claude: or run: directive found"
      fi
      echo '```'
    } > "$RESULT_FILE"

    mv "$taskfile" "$DONE/"
    rm -f "$taskfile.claimed"
    CURRENT_TASK="none"
    git add -A
    git -c user.name="redshirt-$NAME" -c user.email="redshirt@superinstance.ai" commit -qm "redshirt $NAME: done $slug" 2>/dev/null || true
    git push -q 2>/dev/null || true
    echo "[redshirt] Done: $slug, result pushed."
  done

  # Heartbeat every loop
  heartbeat
  cd "$WORKDIR" && git add "tasks/$NAME/heartbeat.md" && git -c user.name="redshirt-$NAME" -c user.email="redshirt@superinstance.ai" commit -qm "heartbeat $NAME" 2>/dev/null || true
  git push -q 2>/dev/null || true

  sleep 60
done

echo "[redshirt] Timebox expired. Node '$NAME' is dead."
