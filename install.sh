#!/bin/bash
# redshirt installer — with the install ceremony.
#
# Installation IS the permission grant. Before anything is written or
# started, this script probes what the new node will inherit from this
# machine — network reach, filesystem scope, visible credentials, spend
# authority — prints it in plain words on one page, and pauses for an
# explicit witnessed yes. SSH shows you the fingerprint before the yes;
# this is the one-page equivalent.
#
# Usage: curl -sSL https://raw.githubusercontent.com/SuperInstance/redshirt/main/install.sh | bash -s <name> <hours>
#
# Non-interactive escape hatch: REDSHIRT_ASSUME_YES=1 skips the witnessed
# yes ONLY when stdin is not a terminal. Setting it is itself the grant —
# you are on record in your shell history.
set -e

NAME="${1:?Usage: bash -s <name> <hours>}"
HOURS="${2:?Usage: bash -s <name> <hours>}"
REPO="https://github.com/SuperInstance/redshirt.git"
DIR="$HOME/.redshirt"

# ---------------------------------------------------------------- network
HOSTNAME_FQDN="$(hostname 2>/dev/null || echo unknown)"
OS_PRETTY="$(uname -srmo 2>/dev/null || uname -a)"
USER_WHO="$(id -un 2>/dev/null || whoami 2>/dev/null || echo unknown)"
IPV4_LOCAL="$(hostname -I 2>/dev/null | awk '{print $1}')"

net_github_https="no"
if timeout 8 bash -c 'echo > /dev/tcp/github.com/443' 2>/dev/null; then
  net_github_https="yes — this machine can reach github.com:443"
fi
net_raw_source="no"
if timeout 8 curl -sSIL -o /dev/null -w '%{http_code}' https://raw.githubusercontent.com/SuperInstance/redshirt/main/install.sh 2>/dev/null | grep -q '^2'; then
  net_raw_source="yes — the installer source itself is fetchable"
fi
net_dns="no"
if getent hosts github.com >/dev/null 2>&1 || nslookup github.com >/dev/null 2>&1; then
  net_dns="yes — github.com resolves"
fi
PROXY_VARS="$(env | grep -iE '^(https?|all)_proxy=' | cut -d= -f1 | tr '\n' ' ')"
[ -z "$PROXY_VARS" ] && PROXY_VARS="none set"
PUBLIC_IP="$(timeout 8 curl -s https://api.ipify.org 2>/dev/null || echo unknown)"

# ------------------------------------------------------------- filesystem
FS_HOME="$HOME"
FS_HOME_WRITABLE="no"
[ -w "$HOME" ] && FS_HOME_WRITABLE="yes"
FS_HOME_FREE="$(df -h "$HOME" 2>/dev/null | awk 'NR==2{print $4}' || echo unknown)"
FS_ROOT_YOU="no"
[ "$(id -u 2>/dev/null)" = "0" ] && FS_ROOT_YOU="yes — you are root"

# ------------------------------------------------------------ credentials
# Names only. Values are never printed, logged, or transmitted.
SSH_KEYS="none found"
if [ -d "$HOME/.ssh" ]; then
  SSH_KEYS="$(ls "$HOME"/.ssh 2>/dev/null | grep -vE '\.(pub|known_hosts|config)$' | tr '\n' ' ')"
  [ -z "$SSH_KEYS" ] && SSH_KEYS="directory exists, no private keys visible"
fi
ENV_SECRET_NAMES="$(env | cut -d= -f1 | grep -iE 'TOKEN|SECRET|PASSWORD|PRIVATE|BEARER|SESSION|COOKIE|ACCOUNT_ID|CLIENT_ID|WALLET' | tr '\n' ' ')"
[ -z "$ENV_SECRET_NAMES" ] && ENV_SECRET_NAMES="none in environment"
GITCONFIG_USER="$(git config --global user.name 2>/dev/null || echo none)"
GH_AUTH="not installed or not logged in"
if command -v gh >/dev/null 2>&1; then
  GH_LINE="$(gh auth status 2>/dev/null | grep -m1 'Logged in to' || true)"
  if [ -n "$GH_LINE" ]; then
    GH_AUTH="$(printf '%s' "$GH_LINE" | sed 's/^[[:space:]]*//')"
  else
    GH_AUTH="gh present, not logged in (or status unreadable)"
  fi
fi
CLAUDE_CLI="not found"
command -v claude >/dev/null 2>&1 && CLAUDE_CLI="installed"

# ------------------------------------------------------------------ spend
# Only what can be detected. Absence here is not proof of no spend.
SPEND_LINES=""
spend_add() { SPEND_LINES="${SPEND_LINES}  - $1
"; }
if command -v aws >/dev/null 2>&1; then
  AWS_ACCT="$(timeout 10 aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'no working credentials')"
  spend_add "AWS CLI present; account: ${AWS_ACCT} (spend possible if credentials work)"
fi
if command -v gcloud >/dev/null 2>&1; then
  GCLOUD_ACCT="$(timeout 10 gcloud auth list --format='value(account)' 2>/dev/null | head -1 || true)"
  [ -n "$GCLOUD_ACCT" ] && spend_add "gcloud signed in as: ${GCLOUD_ACCT}"
fi
if command -v az >/dev/null 2>&1; then
  AZ_SUB="$(timeout 10 az account show --query name -o tsv 2>/dev/null || true)"
  [ -n "$AZ_SUB" ] && spend_add "Azure CLI signed in; subscription: ${AZ_SUB}"
fi
for v in ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY DEEPSEEK_API_KEY; do
  if [ -n "${!v:-}" ]; then
    spend_add "${v} is set in the environment (paid API spend possible)"
  fi
done
if [ -z "$SPEND_LINES" ]; then
  SPEND_LINES="  - none detected by these probes
    (anything you add to this machine later is inherited too)
"
fi

# ============================================================ the page
cat <<PAGE
================================================================
  REDSHIRT INSTALL CEREMONY — what you are about to grant
================================================================
Node name:  $NAME
Runs as:    $USER_WHO on $HOSTNAME_FQDN ($OS_PRETTY)
Timebox:    $HOURS hours, then it dies. No residue except this repo.

NETWORK — what the node can reach
  github.com:443 : $net_github_https
  installer source: $net_raw_source
  DNS             : $net_dns
  proxy variables : $PROXY_VARS
  local address   : ${IPV4_LOCAL:-unknown}
  public address  : $PUBLIC_IP

FILESYSTEM — where the node can write
  home directory: $FS_HOME (writable: $FS_HOME_WRITABLE, free: $FS_HOME_FREE)
  root privileges: $FS_ROOT_YOU
  scope of install: ~/.redshirt/ only — it will not touch the rest

CREDENTIALS — what the node can see (names only, values never shown)
  ssh keys (~/.ssh): $SSH_KEYS
  secret-like env vars: $ENV_SECRET_NAMES
  git identity: $GITCONFIG_USER
  github cli: $GH_AUTH
  claude cli: $CLAUDE_CLI

SPEND AUTHORITY — what the node could cost you
$SPEND_LINES
The node pulls tasks from the redshirt repo and runs them. A task that
says "run:" can run any shell command with the above reach. A task that
says "claude:" spends on whatever the claude CLI is logged into.

Probes are read-only and best-effort. They show what this script could
detect in a few seconds — not a full audit. If in doubt, assume more,
not less.
================================================================
PAGE

# ===================================================== the witnessed yes
witness_grant() {
  if [ -t 0 ]; then
    printf 'This is the permission. There is no second prompt.\n'
    printf 'Type the node name to witness the grant [%s]: ' "$NAME"
    local answer
    IFS= read -r answer || { echo; echo "[redshirt] No answer. Nothing installed."; exit 1; }
    if [ "$answer" != "$NAME" ]; then
      echo "[redshirt] Name did not match. Nothing installed."
      exit 1
    fi
  elif [ "${REDSHIRT_ASSUME_YES:-}" = "1" ]; then
    echo "[redshirt] REDSHIRT_ASSUME_YES=1 with no terminal — proceeding as the recorded grant."
  else
    echo "[redshirt] stdin is not a terminal and REDSHIRT_ASSUME_YES is not set."
    echo "[redshirt] The install ceremony requires a witnessed yes. Refusing."
    echo "[redshirt] Re-run in a terminal, or set REDSHIRT_ASSUME_YES=1 to own the grant explicitly."
    exit 1
  fi
}

witness_grant

# ------------------------------------------------------------- the receipt
mkdir -p "$DIR"
RECEIPT="$DIR/grant-receipt.md"
{
  echo "# Grant receipt: $NAME"
  echo ""
  echo "- granted_at: $(date -u +%FT%TZ)"
  echo "- granted_by: $USER_WHO on $HOSTNAME_FQDN"
  echo "- timebox_hours: $HOURS"
  echo "- public_ip: $PUBLIC_IP"
  echo "- repo: $REPO"
  echo ""
  echo "The installer printed a one-page capability summary and the"
  echo "installer typed the node name to witness the grant."
} > "$RECEIPT"
chmod 600 "$RECEIPT"
echo "[redshirt] Grant witnessed. Receipt: $RECEIPT"

# ============================================================ the install
echo "[redshirt] Installing node '$NAME' for ${HOURS}h..."

cat > "$DIR/config" << EOF
NAME=$NAME
HOURS=$HOURS
STARTED=$(date -u +%s)
REPO=$REPO
WORKDIR=$DIR/work
EOF
chmod 600 "$DIR/config"

if [ -d "$DIR/work/.git" ]; then
  git -C "$DIR/work" pull -q
else
  git clone -q "$REPO" "$DIR/work"
fi

chmod +x "$DIR/work/redshirt.sh"

nohup "$DIR/work/redshirt.sh" > "$DIR/poller.log" 2>&1 &
echo "[redshirt] Node '$NAME' is live for ${HOURS}h. Polling tasks."
echo "[redshirt] Log: $DIR/poller.log"
