#!/bin/sh
# Everything that can be checked without touching the keyboard. Run before and after changing the switching rules.
set -e
cd "$(dirname "$0")"
xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1 || export DEVELOPER_DIR=/Library/Developer/CommandLineTools
swift build -c release 2>&1 | tail -1
BIN=.build/release/ghbdtnvbh
$BIN --selftest
# Everyday chat, work talk and a bit of code: not one false switch is allowed (exits 1 otherwise).
# Baseline 2026-09-21: 0 false; 10 + 10 missed, all of them 2-3 letter words. Decisions are sub-millisecond
# apart from the odd one where the system speller takes its time, so the printed maximum swings between runs.
$BIN --eval Tests/chat-ru.txt Tests/chat-en.txt
# Rare words and names, the hard case: every 15th word past rank 5000 of github.com/hermitdave/FrequencyWords
# (OpenSubtitles 2018, CC-BY-SA). Baseline: 3 false (нэша, смс-ку, chen), 94 + 90 missed.
$BIN --eval Tests/stress-ru.txt Tests/stress-en.txt || true
# Languages without a system speller, where the tables decide alone. Common words (top 2000 of the lists) and the
# English chat typed against that layout: 0 false. Rare words, for the log: English words that sit inside the
# foreign lists count as false there. Baseline 2026-09-23: 2-14 false per language.
# Which languages land here depends on the macOS version: --selftest prints the spellers it found, and a
# language missing from that line belongs in this loop. These fourteen are what macOS 26 leaves without one.
for pair in fi:Finnish is:Icelandic nb:Norwegian pl:Polish lt:Lithuanian he:Hebrew hr:Croatian sk:Slovak et:Estonian mk:Macedonian sq:Albanian sr:Serbian-Latin fa:Persian ka:Georgian-QWERTY; do
    $BIN --eval --layouts "US,${pair#*:}" "Tests/common-${pair%%:*}.txt" Tests/chat-en.txt
    $BIN --eval --layouts "US,${pair#*:}" "Tests/stress-${pair%%:*}.txt" || true
done
