#!/bin/sh
# Records the site's demo.gif. The site lives on the `landing` branch, so the gif is written into a checkout of
# that branch — `git worktree add ../landing landing` next to this one, then `Tools/demo.sh ../landing/demo.gif`.
# Needs ffmpeg (brew install ffmpeg). Don't touch the keyboard for the few seconds it runs.
set -e
cd "$(dirname "$0")/.."
OUT="${1:?usage: Tools/demo.sh <path to demo.gif in a checkout of the landing branch>}"
FRAMES="$(mktemp -d)"
FRAMES="$FRAMES" Tests/live.sh 'ghbdtn rfr ltkf hello '
ffmpeg -loglevel error -y -framerate 25 -i "$FRAMES/%04d.png" \
    -vf "scale=800:-1:flags=lanczos,tpad=stop_mode=clone:stop_duration=1.5,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse" "$OUT"
rm -r "$FRAMES"
ls -la "$OUT"
