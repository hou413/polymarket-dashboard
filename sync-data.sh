#!/bin/bash
# Sync Smart v2 trader data to GitHub Pages
set -e

REPO_DIR="/tmp/polymarket-dashboard"
SMART_DIR="/Users/openbren/.openclaw/workspace-smart/polymarket-smart-money"
DATA_FILE="$SMART_DIR/data/dashboard-data.json"

# Check if data exists
if [ ! -f "$DATA_FILE" ]; then
  echo "[$(date)] No data file found, skipping sync"
  exit 0
fi

# Copy files to repo
cp "$DATA_FILE" "$REPO_DIR/dashboard-data.json"
cp "$SMART_DIR/dashboard.html" "$REPO_DIR/index.html"

# Commit and push
cd "$REPO_DIR"
git add dashboard-data.json index.html
if git diff --cached --quiet; then
  echo "[$(date)] No changes to sync"
else
  git commit -m "Update data: $(date '+%Y-%m-%d %H:%M:%S')"
  git push origin main
  echo "[$(date)] Synced to GitHub Pages"
fi
