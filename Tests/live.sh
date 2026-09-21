#!/bin/sh
# Live check of the running app: opens a small window and types into it by key code for a few seconds.
# Don't touch the keyboard or click elsewhere meanwhile — the pad stops by itself if it loses focus.
# Pass your own cases as arguments, in single quotes, as typed on an English keyboard.
set -e
cd "$(dirname "$0")"
xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1 || export DEVELOPER_DIR=/Library/Developer/CommandLineTools
OUT="${TMPDIR:-/tmp}/layoutswitcher-pad"
swiftc -O -sdk "$(xcrun --sdk macosx --show-sdk-path)" pad.swift -o "$OUT"
pgrep -f "LayoutSwitcher.app/Contents/MacOS/LayoutSwitcher" >/dev/null || { echo "LayoutSwitcher is not running"; exit 1; }
if [ $# -eq 0 ]; then
  # Expected: ну ты привет | press the привет | hello. ну ты привет | я ну привет | to привет | всё привет | девопсов | kubectl nginx
  set -- 'ye ns ghbdtn ' 'press the ghbdtn ' 'hello. ye ns ghbdtn ' 'z ye ghbdtn ' 'to ghbdtn ' 'dc` ghbdtn ' 'ltdjgcjd ' 'kubectl nginx '
fi
"$OUT" "$@"
