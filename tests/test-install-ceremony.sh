#!/bin/bash
# test-install-ceremony.sh — the install ceremony never says yes blind.
#
# 1. No terminal + no REDSHIRT_ASSUME_YES  -> refuses, exit 1, nothing installed.
# 2. No terminal + REDSHIRT_ASSUME_YES=1    -> proceeds, prints the one-page
#    summary, writes the grant receipt (HOURS=0 so the killswitch buries the
#    node immediately after; test runs against a throwaway HOME).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$HERE/../install.sh"

pass=0; fail=0
ok()   { pass=$((pass+1)); echo "ok   - $1"; }
bad()  { fail=$((fail+1)); echo "FAIL - $1"; }

export HOME_TEST="$(mktemp -d)"
trap 'rm -rf "$HOME_TEST"' EXIT

# --- 1. refuses without the escape hatch -----------------------------------
out="$(echo | HOME="$HOME_TEST" bash "$INSTALLER" ceremony-test 1 2>&1)"
code=$?
[ "$code" -eq 1 ] || bad "refusal exit code is $code, expected 1"
echo "$out" | grep -q 'The install ceremony requires a witnessed yes' \
  && ok "refuses without a witnessed yes" \
  || bad "refusal message missing"
[ -e "$HOME_TEST/.redshirt" ] && bad "wrote ~/.redshirt before the grant" \
  || ok "nothing installed before the grant"

# --- 2. escape hatch proceeds, summary is real ------------------------------
out="$(REDSHIRT_ASSUME_YES=1 HOME="$HOME_TEST" bash "$INSTALLER" ceremony-test 0 2>&1)"
code=$?
[ "$code" -eq 0 ] || bad "assume-yes install exit code is $code, expected 0"
echo "$out" | grep -q 'INSTALL CEREMONY' \
  && ok "prints the one-page summary" \
  || bad "ceremony page missing"
echo "$out" | grep -q 'open internet' \
  && ok "summary names open-internet reachability" \
  || bad "open-internet line missing"
echo "$out" | grep -q 'cloud metadata' \
  && ok "summary names cloud metadata" \
  || bad "cloud-metadata line missing"
echo "$out" | grep -q 'names only, values never shown' \
  && ok "credentials shown as names only" \
  || bad "credentials caveat missing"
echo "$out" | grep -q 'REDSHIRT_ASSUME_YES=1 with no terminal — proceeding as the recorded grant' \
  && ok "records the assume-yes grant in the transcript" \
  || bad "grant recording missing"

# the 0-hour node is buried by its own killswitch; give it a few seconds
sleep 20
[ -e "$HOME_TEST/.redshirt" ] && bad "0-hour node not buried" \
  || ok "0-hour node self-buries via killswitch"

echo "--- ceremony: $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
