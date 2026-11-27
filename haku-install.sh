#!/bin/bash
# Fork: put the build in build/Search.app into /Applications as Haku.
#   SEARCH_DEV=1 SEARCH_FEATURE=tiles SEARCH_IDENT=fi.mangusti.haku SEARCH_SHOWN=Haku ./build.sh && ./haku-install.sh
# Quits Haku (its session comes back), swaps the app, and removes the build
# folder's copy: two bundles with one identifier leave it to macOS which one
# a link opens. Never touches /Applications/Search.app.
set -euo pipefail
cd "$(dirname "$0")"
NEW="build/Search.app" APP="/Applications/Haku.app"
[ -d "$NEW" ] || { echo "no $NEW: build first" >&2; exit 1; }
id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$NEW/Contents/Info.plist")"
[ "$id" = "fi.mangusti.haku" ] || { echo "$NEW is $id, not Haku: build with SEARCH_IDENT=fi.mangusti.haku" >&2; exit 1; }
codesign --verify --strict "$NEW"
pkill -f "$APP/Contents/MacOS/Search" || true
until ! pgrep -f "$APP/Contents/MacOS/Search" >/dev/null; do sleep 1; done
# After the process has gone: a hook for edits to its data files.
[ -n "${HAKU_WHILE_QUIT:-}" ] && "$HAKU_WHILE_QUIT"
rm -rf "$APP.old"
[ -d "$APP" ] && mv "$APP" "$APP.old"
ditto "$NEW" "$APP"
codesign --verify --strict "$APP"
rm -rf "$APP.old" "$NEW"
open "$APP"
echo "installed: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist") build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
