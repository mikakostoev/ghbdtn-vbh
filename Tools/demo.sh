#!/bin/sh
# Records docs/demo.gif: types a phrase into the test pad while the app is running, one frame every 40 ms.
# Needs ffmpeg (brew install ffmpeg). Don't touch the keyboard for the few seconds it runs.
set -e
cd "$(dirname "$0")/.."
FRAMES="$(mktemp -d)"
FRAMES="$FRAMES" Tests/live.sh 'ghbdtn rfr ltkf hello '
ffmpeg -loglevel error -y -framerate 25 -i "$FRAMES/%04d.png" \
    -vf "scale=800:-1:flags=lanczos,tpad=stop_mode=clone:stop_duration=1.5,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse" docs/demo.gif
rm -r "$FRAMES"
ls -la docs/demo.gif
