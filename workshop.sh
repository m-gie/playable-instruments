#!/usr/bin/env bash
# Stages the Workshop upload folder in ~/Zomboid/Workshop/PlayItInstruments.
# Upload it from the game: main menu -> Workshop -> PlayItInstruments.
set -euo pipefail
cd "$(dirname "$0")"
DEST="$HOME/Zomboid/Workshop/PlayItInstruments"
rm -rf "$DEST"
mkdir -p "$DEST/Contents/mods/PlayItInstruments"
for f in workshop/workshop.txt workshop/preview.png; do if [ -f "$f" ]; then cp "$f" "$DEST/"; fi; done
cp -r 42 common "$DEST/Contents/mods/PlayItInstruments/"
find "$DEST" -type f | sort
