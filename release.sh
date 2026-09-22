#!/bin/sh
# ./release.sh 2.0.0 — universal build zipped into dist/, ready to attach to a GitHub release.
# Ad-hoc-signed by default (a self-signed local identity means nothing on another Mac); with IDENTITY set to a
# "Developer ID Application" certificate the build is ready for notarization — see .github/workflows/release.yml.
set -e
cd "$(dirname "$0")"
VERSION="${1:?usage: ./release.sh <version>}"
# IDENTITY from the environment wins: the release workflow passes a Developer ID when the secrets are there.
OUT=dist UNIVERSAL=1 IDENTITY="${IDENTITY:--}" VERSION="$VERSION" ./build.sh
"dist/ghbdtn vbh.app/Contents/MacOS/ghbdtnvbh" --selftest
ditto -c -k --keepParent "dist/ghbdtn vbh.app" "dist/ghbdtn-vbh-$VERSION.zip"
echo "dist/ghbdtn-vbh-$VERSION.zip"
