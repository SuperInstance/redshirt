#!/bin/bash
# lib.sh — shared helpers for the redshirt suite.
# Sourced by redshirt.sh, wake.sh, reaper.sh, killswitch.sh. Not run directly.
#
# Expects: RS_DIR ($HOME/.redshirt) and RS_LOG to be set by the caller,
# or falls back to deriving them from $HOME.

RS_DIR="${RS_DIR:-$HOME/.redshirt}"
RS_LOG="${RS_LOG:-$RS_DIR/redshirt.log}"

# rs_log <msg...> — timestamped line to the node log and stdout.
rs_log() {
  local line
  line="$(date -u +%FT%TZ) $*"
  mkdir -p "$(dirname "$RS_LOG")" 2>/dev/null || true
  echo "$line" >> "$RS_LOG" 2>/dev/null || true
  echo "[redshirt] $*"
}

# rs_now — epoch seconds (UTC).
rs_now() { date -u +%s; }

# rs_stat_mtime <file> — portable mtime (GNU then BSD stat).
rs_stat_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# repo_owner_name <repo-url> — "owner repo" from https or ssh GitHub URLs.
# Prints "owner reponame" on one line, or returns 1 if unparseable.
repo_owner_name() {
  local url="$1" owner repo
  url="${url%.git}"
  case "$url" in
    https://github.com/*) url="${url#https://github.com/}" ;;
    http://github.com/*)  url="${url#http://github.com/}" ;;
    git@github.com:*)     url="${url#git@github.com:}" ;;
    *) return 1 ;;
  esac
  owner="${url%%/*}"
  repo="${url#*/}"
  [ -n "$owner" ] && [ -n "$repo" ] && [ "$repo" != "$url" ] || return 1
  echo "$owner $repo"
}
