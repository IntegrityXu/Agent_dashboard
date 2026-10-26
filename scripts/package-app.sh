#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-app.sh" Release
SOURCE="$ROOT/.build/xcode/Build/Products/Release/StatusBoard.app"
DEST="$ROOT/dist/Status Board.app"
mkdir -p "$ROOT/dist"
# Stage a fresh bundle so previous build resources cannot leak into the package.
STAGING="$(mktemp -d "$ROOT/dist/.package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$SOURCE" "$STAGING/Status Board.app"
LEGAL="$STAGING/Status Board.app/Contents/Resources/Legal"
mkdir -p "$LEGAL"
for document in LICENSE DISCLAIMER.md PRIVACY.md THIRD_PARTY_NOTICES.md SECURITY.md; do
  cp "$ROOT/$document" "$LEGAL/$document"
done
codesign --force --deep --sign - "$STAGING/Status Board.app"
codesign --verify --deep --strict "$STAGING/Status Board.app"
if [[ -d "$DEST" ]]; then rm -rf "$DEST"; fi
mv "$STAGING/Status Board.app" "$DEST"
echo "$DEST"
