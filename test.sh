#!/bin/sh
# Everything that can be checked without touching the keyboard. Run before and after changing the switching rules.
set -e
cd "$(dirname "$0")"
xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1 || export DEVELOPER_DIR=/Library/Developer/CommandLineTools
swift build -c release 2>&1 | tail -1
BIN=.build/release/LayoutSwitcher
$BIN --selftest
# Everyday chat, work talk and a bit of code: not one false switch is allowed (exits 1 otherwise).
# Baseline 2026-09-21: 0 false; 10 + 10 missed, all of them 2-3 letter words. Decisions are sub-millisecond
# apart from the odd one where the system speller takes its time, so the printed maximum swings between runs.
$BIN --eval Tests/chat-ru.txt Tests/chat-en.txt
# Rare words and names, the hard case: every 15th word past rank 5000 of github.com/hermitdave/FrequencyWords
# (OpenSubtitles 2018, CC-BY-SA). Baseline: 3 false (нэша, смс-ку, chen), 94 + 90 missed.
$BIN --eval Tests/stress-ru.txt Tests/stress-en.txt || true
