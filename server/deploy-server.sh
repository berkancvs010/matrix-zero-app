#!/usr/bin/env bash
set -euo pipefail

TARGET="$HOME/zerolog-v2/deploy/app/zerolog_final/server/server.js"
BACKUP="${TARGET}.bak-before-release-$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "$TARGET" ]]; then
  echo "SERVER_JS_NOT_FOUND: $TARGET" >&2
  exit 1
fi

cp "$TARGET" "$BACKUP"
cp "$(dirname "$0")/server.js" "$TARGET"
node --check "$TARGET"

echo "SERVER_JS_UPDATED"
echo "BACKUP=$BACKUP"
