#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/package-app.sh"
APP="$ROOT/dist/Status Board.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
OUT="$ROOT/dist/releases/$VERSION-build$BUILD"
ARCHIVE="StatusBoard-$VERSION-build$BUILD-macOS-universal.zip"
mkdir -p "$OUT"
lipo "$APP/Contents/MacOS/StatusBoard" -verify_arch arm64 x86_64
for document in LICENSE DISCLAIMER.md PRIVACY.md THIRD_PARTY_NOTICES.md SECURITY.md; do
  cmp "$ROOT/$document" "$APP/Contents/Resources/Legal/$document"
done
for retired in joker_right.png crown.png; do
  if [[ -e "$APP/Contents/Resources/$retired" ]]; then
    echo "Retired artwork remains in build output: $retired. Clean the Xcode build before packaging." >&2
    exit 1
  fi
done
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP" "$OUT/$ARCHIVE"
(cd "$OUT" && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
unzip -tq "$OUT/$ARCHIVE"
echo "$OUT/$ARCHIVE"
