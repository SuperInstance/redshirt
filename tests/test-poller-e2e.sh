#!/bin/bash
# test-poller-e2e.sh — full loop against a LOCAL bare repo (no network):
# pull -> claim -> sandbox-run (good + hostile tasks) -> outbox -> push ->
# timebox expiry -> self-burial. Runs in a scratch HOME.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/.."

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "PASS: $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME"
export RS_DIR="$HOME/.redshirt"

# --- bare repo with seeded inbox -------------------------------------------
git init -q --bare "$T/remote.git"
git init -q "$T/seed"
git -C "$T/seed" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$T/seed/tasks/e2enode/inbox"
printf '# t-good\nrun: echo task-output-123\n'              > "$T/seed/tasks/e2enode/inbox/t-good.md"
printf '# t-evil-rm\nrun: rm -rf ~\n'                       > "$T/seed/tasks/e2enode/inbox/t-evil-rm.md"
printf '# t-evil-curl\nrun: curl --max-time 5 http://127.0.0.1:9/\n' > "$T/seed/tasks/e2enode/inbox/t-evil-curl.md"
git -C "$T/seed" add -A
git -C "$T/seed" -c user.email=t@t -c user.name=t commit -q -m "seed tasks"
git -C "$T/seed" push -q "$T/remote.git" HEAD:main
BRANCH="main"
git --git-dir="$T/remote.git" symbolic-ref HEAD "refs/heads/main"

# --- node config: 30s of life ------------------------------------------------
NOW="$(date -u +%s)"
mkdir -p "$RS_DIR"
git clone -q "$T/remote.git" "$RS_DIR/work"
cat > "$RS_DIR/config" << EOF
NAME=e2enode
HOURS=1
STARTED=$((NOW - 3570))
REPO=$T/remote.git
WORKDIR=$RS_DIR/work
ALLOWLIST=
NET_OK=0
REAP_AFTER=300
WAKE=0
KILLSWITCH=0
POLL_INTERVAL=5
EOF
echo canary > "$HOME/canary.txt"

# --- run the poller ----------------------------------------------------------
timeout 120 "$SRC/redshirt.sh" > "$T/poller.out" 2>&1
echo "poller rc=$?"

# --- verdicts ----------------------------------------------------------------
LOG="$(git --git-dir="$T/remote.git" log --oneline | head -5)"
echo "$LOG" | grep -q "redshirt e2enode: done t-good" \
  && ok "good task committed+pushed" || no "good task committed+pushed"
git --git-dir="$T/remote.git" show "$BRANCH:tasks/e2enode/outbox/t-good.result.md" 2>/dev/null | grep -q "task-output-123" \
  && ok "good task output captured in outbox" || no "good task output in outbox"
git --git-dir="$T/remote.git" show "$BRANCH:tasks/e2enode/outbox/t-evil-rm.result.md" 2>/dev/null | grep -qi "not found" \
  && ok "rm -rf ~ blocked, failure in outbox" || no "rm -rf ~ blocked in outbox"
git --git-dir="$T/remote.git" show "$BRANCH:tasks/e2enode/outbox/t-evil-curl.result.md" 2>/dev/null | grep -q "DISABLED" \
  && ok "curl blocked, failure in outbox" || no "curl blocked in outbox"
[ "$(cat "$HOME/canary.txt")" = "canary" ] \
  && ok "home canary intact after hostile tasks" || no "home canary intact"
[ ! -e "$RS_DIR" ] \
  && ok "self-burial: ~/.redshirt is gone" || no "self-burial"
grep -q "burying node" "$T/poller.out" \
  && ok "burial logged" || no "burial logged"

echo "---"
echo "e2e tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
