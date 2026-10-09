#!/bin/bash
# redshirt installer: curl -sSL https://raw.githubusercontent.com/SuperInstance/redshirt/main/install.sh | bash -s <name> <hours>
set -e
NAME="${1:?Usage: bash -s <name> <hours>}"
HOURS="${2:?Usage: bash -s <name> <hours>}"
REPO="https://github.com/SuperInstance/redshirt.git"
DIR="$HOME/.redshirt"

echo "[redshirt] Installing node '$NAME' for ${HOURS}h..."

# Config
mkdir -p "$DIR"
cat > "$DIR/config" << EOF
NAME=$NAME
HOURS=$HOURS
STARTED=$(date -u +%s)
REPO=$REPO
WORKDIR=$DIR/work
EOF
chmod 600 "$DIR/config"

# Clone or pull the repo
if [ -d "$DIR/work/.git" ]; then
  git -C "$DIR/work" pull -q
else
  git clone -q "$REPO" "$DIR/work"
fi

chmod +x "$DIR/work/redshirt.sh"

# Start the poller in background
nohup "$DIR/work/redshirt.sh" > "$DIR/poller.log" 2>&1 &
echo "[redshirt] Node '$NAME' is live for ${HOURS}h. Polling tasks."
echo "[redshirt] Log: $DIR/poller.log"
