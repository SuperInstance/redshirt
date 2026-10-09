#!/bin/bash
# sandbox.sh — layered execution sandbox for redshirt task commands.
#
# Usage: RS_WORKDIR=<taskdir> RS_NET_OK=0|1 RS_ALLOWLIST="git curl python3" \
#          sandbox.sh <command> [args...]
#
# Layers (applied best-effort, strongest first):
#   1. mount namespace (if unshare+userns available): everything remounted
#      read-only except the task workdir (bound read-write).
#   2. net namespace (if available and RS_NET_OK=0): no network at all,
#      loopback only.
#   3. shim PATH (always): only allowlisted commands resolvable. When
#      RS_NET_OK=0, curl/wget/ssh/scp/nc/telnet resolve to loud-failure stubs.
#   4. scrubbed environment (always): env -i, HOME/TMPDIR pointed at the
#      workdir so `~` never means the installer's home.
#
# Exit codes: the command's own, or 126 (blocked by policy), 127 (not
# allowlisted / not found), 2 (sandbox misuse).

set -u

WORKDIR="${RS_WORKDIR:?sandbox: RS_WORKDIR is not set}"
NET_OK="${RS_NET_OK:-0}"
ALLOWLIST="${RS_ALLOWLIST-git curl python3 claude}"
LAYERS="shim+env"

[ $# -ge 1 ] || { echo "sandbox: no command given" >&2; exit 2; }
[ -d "$WORKDIR" ] || { echo "sandbox: workdir '$WORKDIR' does not exist" >&2; exit 2; }

SHIM="$WORKDIR/.shim"
rm -rf "$SHIM"
mkdir -p "$SHIM" || { echo "sandbox: cannot create shim dir" >&2; exit 2; }

# --- Layer 3: network stubs when network is off ---------------------------
# Installed BEFORE the allowlist so an allowlisted `curl` can never silently
# bypass the no-network policy; the stub fails loudly instead.
if [ "$NET_OK" = "0" ]; then
  for netcmd in curl wget ssh scp sftp nc netcat telnet ftp; do
    cat > "$SHIM/$netcmd" << EOF
#!/bin/sh
echo "sandbox: network access is DISABLED for this redshirt (RS_NET_OK=0)" >&2
echo "sandbox: blocked command '$netcmd'; reinstall with --net to allow it" >&2
exit 126
EOF
    chmod +x "$SHIM/$netcmd"
  done
fi

# --- Layer 3 (cont.): allowlist -------------------------------------------
# `sh` is always available: the harness itself runs `run:` directives via
# `sh -c`, and blocking the shell would make every task fail. Everything
# the shell can *reach* is still limited to this shim PATH.
for cmd in sh $ALLOWLIST; do
  [ -e "$SHIM/$cmd" ] && continue  # never override a network stub
  real="$(command -v "$cmd" 2>/dev/null || true)"
  # command -v may return a shell builtin/function/alias name; only link real files
  case "$real" in
    /*) [ -x "$real" ] && ln -s "$real" "$SHIM/$cmd" \
          || echo "sandbox: allowlisted '$cmd' is not executable ($real)" >&2 ;;
    *)  echo "sandbox: allowlisted command '$cmd' not found on this machine" >&2 ;;
  esac
done

# --- Layer 1+2: namespaces, when the kernel permits ------------------------
can_ns() {
  unshare -U --map-user="$(id -u)" --map-group="$(id -g)" -m -n true 2>/dev/null
}

if can_ns; then
  NS_ARGS="-U --map-user=$(id -u) --map-group=$(id -g) -m"
  if [ "$NET_OK" = "0" ]; then
    NS_ARGS="$NS_ARGS -n"
    LAYERS="$LAYERS+netns"
  fi
  LAYERS="$LAYERS+mountns"
  echo "sandbox: layers active: $LAYERS (workdir: $WORKDIR)" >&2
  # shellcheck disable=SC2086
  exec unshare $NS_ARGS bash -s "$WORKDIR" "$SHIM" "$LAYERS" "$@" <<'NS_EOF'
set -u
WORKDIR="$1"; SHIM="$2"; LAYERS="$3"; shift 3

# Detach our mounts from the host, then remount everything read-only
# except the task workdir. Deepest mounts first.
mount --make-rprivate / 2>/dev/null || true
tac /proc/self/mounts | while read -r _dev target _rest; do
  # /proc/self/mounts escapes spaces as \040; unescape for the case match
  target="$(printf '%b' "${target//\\040/ }")"
  case "$target" in
    "$WORKDIR"|"$WORKDIR"/*) continue ;;  # keep workdir writable (bound below)
    /dev|/dev/*)             continue ;;  # keep /dev usable (/dev/null etc.)
  esac
  mount -o remount,ro,bind "$target" 2>/dev/null || true
done < /proc/self/mounts

# Re-bind the workdir read-write over itself (it sits under a now-ro tree).
mount --bind "$WORKDIR" "$WORKDIR"
mount -o remount,rw,bind "$WORKDIR"

cd "$WORKDIR" || exit 2
exec env -i PATH="$SHIM" HOME="$WORKDIR" TMPDIR="$WORKDIR" RS_SANDBOX=1 "$@"
NS_EOF
fi

# --- Fallback: shim + scrubbed env only ------------------------------------
echo "sandbox: WARNING: kernel namespaces unavailable — running DEGRADED (shim+env only)." >&2
echo "sandbox: degraded mode still enforces the command allowlist and the network" >&2
echo "sandbox: stubs, but CANNOT stop writes to world-writable dirs (e.g. /tmp)" >&2
echo "sandbox: via allowlisted interpreters. Run on a userns-capable kernel for" >&2
echo "sandbox: full containment. layers active: $LAYERS (workdir: $WORKDIR)" >&2
cd "$WORKDIR" || exit 2
# shellcheck disable=SC2093
exec env -i PATH="$SHIM" HOME="$WORKDIR" TMPDIR="$WORKDIR" RS_SANDBOX=degraded "$@"
