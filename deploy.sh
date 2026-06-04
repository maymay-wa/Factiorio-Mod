#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFO_JSON="$SCRIPT_DIR/info.json"
MODS_DIR="$HOME/Library/Application Support/factorio/mods"

if [[ ! -f "$INFO_JSON" ]]; then
  echo "Error: info.json not found at $INFO_JSON" >&2
  exit 1
fi

MOD_NAME=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['name'])" "$INFO_JSON")
MOD_VERSION=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['version'])" "$INFO_JSON")
DEST="$MODS_DIR/${MOD_NAME}_${MOD_VERSION}"

echo "Deploying $MOD_NAME v$MOD_VERSION -> $DEST"

rm -rf "$DEST"
mkdir -p "$DEST"

rsync -a --exclude='.git' --exclude='deploy.sh' --exclude='downloadportal.png' \
  --exclude='.DS_Store' \
  "$SCRIPT_DIR/" "$DEST/"

echo "Done. Mod installed at: $DEST"
