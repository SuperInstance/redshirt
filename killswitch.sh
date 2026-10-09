#!/bin/bash
# killswitch.sh — the external dead-man's switch for a redshirt node.
#
# The timebox used to be a promise the redshirt kept. This moves the clock
# outside the redshirt: at install time the installer computes the deadline
# and starts this supervisor. At the deadline it SIGTERMs the poller's whole
# process group, SIGKILLs it 10s later if anything is still alive, then buries
# the node (rm -rf ~/.redshirt) in case the shirt never ran its own EXIT trap.
# Revocation does not depend on the cooperation of the thing being revoked.
#
# Started by install.sh in its OWN process group (so it never kills itself).
# Costs one sleeping process per node. See docs/killswitch.md for the
# residual risks, stated honestly.

set -u
# shellcheck disable=SC1091
source "$HOME/.redshirt/config"
RS_DIR="$HOME/.redshirt"

DEADLINE=$((STARTED + HOURS * 3600))
PGID_FILE="$RS_DIR/poller.pgid"

echo "[killswitch] Armed for node '$NAME': deadline $(date -u -d "@$DEADLINE" +%FT%TZ 2>/dev/null || date -u -r "$DEADLINE" +%FT%TZ)"

now="$(date -u +%s)"
wait_for=$((DEADLINE - now))
if [ "$wait_for" -gt 0 ]; then
  sleep "$wait_for"
fi

echo "[killswitch] Deadline reached for node '$NAME' — terminating."

if [ -f "$PGID_FILE" ]; then
  PGID="$(cat "$PGID_FILE")"
  case "$PGID" in
    ''|*[!0-9]*) echo "[killswitch] bad pgid file; skipping signal step" ;;
    *)
      # Polite first: lets the shirt run its EXIT trap (self-burial).
      kill -TERM -"$PGID" 2>/dev/null || true
      sleep 10
      # Then the guarantee: SIGKILL cannot be caught or ignored.
      if kill -0 -"$PGID" 2>/dev/null; then
        echo "[killswitch] process group $PGID still alive after SIGTERM — SIGKILL"
        kill -KILL -"$PGID" 2>/dev/null || true
        sleep 2
      else
        echo "[killswitch] process group $PGID exited on SIGTERM"
      fi
      ;;
  esac
else
  echo "[killswitch] no pgid file ($PGID_FILE); nothing to signal"
fi

# Burial: the shirt's own EXIT trap may never have run (SIGKILL).
# Idempotent — safe if the shirt already buried itself.
rm -rf "$RS_DIR"
echo "[killswitch] Node '$NAME' terminated and buried. Switch disarming."
