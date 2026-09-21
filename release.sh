#!/bin/sh
# ./release.sh 1.0.0 — universal ad-hoc-signed build zipped into dist/, ready to attach to a GitHub release.
# Ad-hoc because a self-signed local identity means nothing on another Mac, and there is no Apple Developer ID:
# Gatekeeper will ask for right click > Open on first launch either way.
set -e
cd "$(dirname "$0")"
VERSION="${1:?usage: ./release.sh <version>}"
OUT=dist UNIVERSAL=1 IDENTITY=- VERSION="$VERSION" ./build.sh
dist/LayoutSwitcher.app/Contents/MacOS/LayoutSwitcher --selftest
ditto -c -k --keepParent dist/LayoutSwitcher.app "dist/LayoutSwitcher-$VERSION.zip"
echo "dist/LayoutSwitcher-$VERSION.zip"
