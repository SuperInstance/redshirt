#!/bin/bash
# wake.sh — outbound-only wake trigger for the redshirt poller.
#
# The poll posture stays pull-only (the cloud gets no path into the box), but
# the shirt stops napping between fetches: this daemon long-polls the repo's
# commit API with ETag conditional requests and touches $WORKDIR/.wake the
# moment the inbox path changes. redshirt.sh watches for that file and cuts
# its 60s sleep short, so a landed task starts within ~5s instead of ~60s.
#
# Why this mechanism: it is pure outbound HTTPS — no inbound port, no webhook
# receiver, no extra infrastructure. GitHub does not offer true long-poll, so
# we poll every 5s; conditional (If-None-Match) requests that return 304 do
# NOT count against the API rate limit, so even unauthenticated polling is
# sustainable. Set GITHUB_TOKEN in the environment for private repos.
#
# Failure mode: if the API becomes unreachable the daemon backs off (5s -> 60s
# between attempts) and keeps trying, while the poller keeps its plain 60s
# cycle. The trigger can die; the shirt degrades to polling, never to silence.
#
# Started by redshirt.sh (same process group, so the killswitch reaps it too).
# Test hook: WAKE_API_URL overrides the commits API endpoint (see tests/).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib.sh"
# shellcheck disable=SC1091
source "$RS_DIR/config"

WAKE_FILE="$WORKDIR/.wake"
ETAG_FILE="$WORKDIR/.wake-etag"
WATCH_PATH="tasks/$NAME/inbox"
API_URL="${WAKE_API_URL:-}"

if [ -z "$API_URL" ]; then
  read -r OWNER REPO_NAME < <(repo_owner_name "$REPO") \
    || { rs_log "wake: cannot parse repo URL '$REPO'; wake trigger disabled"; exit 1; }
  API_URL="https://api.github.com/repos/$OWNER/$REPO_NAME/commits?path=$WATCH_PATH&per_page=1"
fi

ETAG=""
[ -f "$ETAG_FILE" ] && ETAG="$(cat "$ETAG_FILE")"

rs_log "wake: watching $WATCH_PATH via ${API_URL%%\?*} (outbound-only)"

FAIL=0
while true; do
  headers="$(mktemp)"
  # -w emits the http code; curl's own exit code is captured separately.
  code="$(curl -s -o /dev/null -D "$headers" --max-time 10 \
      ${ETAG:+-H "If-None-Match: $ETAG"} \
      ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
      -w "%{http_code}" "$API_URL" 2>/dev/null)"
  curl_rc=$?
  [ "$curl_rc" -ne 0 ] && code="000"
  code="$(echo "$code" | tr -d ' \r\n')"

  case "$code" in
    200)
      # Inbox path changed (or first successful read): wake the poller.
      new_etag="$(grep -i '^etag:' "$headers" | tr -d '\r' | sed 's/^[Ee][Tt][Aa][Gg]: *//' | tr -d ' \r\n')"
      [ -n "$new_etag" ] && { ETAG="$new_etag"; echo "$ETAG" > "$ETAG_FILE"; }
      touch "$WAKE_FILE"
      rs_log "wake: inbox changed (http 200) — poller woken"
      FAIL=0
      rm -f "$headers"
      sleep 5
      ;;
    304)
      FAIL=0
      rm -f "$headers"
      sleep 5
      ;;
    *)
      FAIL=$((FAIL + 1))
      rm -f "$headers"
      if [ "$FAIL" -ge 12 ]; then
        rs_log "wake: channel failing (${FAIL} consecutive, last http=$code) — backing off to 60s checks; poller continues its 60s cycle"
        sleep 60
      else
        [ "$FAIL" -eq 1 ] && rs_log "wake: API request failed (http=$code); retrying"
        sleep 5
      fi
      ;;
  esac
done
