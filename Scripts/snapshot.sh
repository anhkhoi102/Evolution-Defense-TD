#!/usr/bin/env bash
# Runs a scripted match and saves PNGs of the window into ./snapshots, then quits.
# The app is sandboxed, so it writes into its container's tmp folder; this
# script copies the images out afterwards. Build first: Scripts/build.sh
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BIN="$PROJECT_ROOT/build/EvolutionDefense.app/Contents/MacOS/EvolutionDefense"
[[ -x "$APP_BIN" ]] || { echo "Build first: Scripts/build.sh" >&2; exit 1; }
CONTAINER_TMP="$HOME/Library/Containers/local.evolutiondefense.game/Data/tmp/snapshots"
EVO_SNAPSHOT_DIR=1 "$APP_BIN"
rm -rf "$PROJECT_ROOT/snapshots"
mkdir -p "$PROJECT_ROOT/snapshots"
cp "$CONTAINER_TMP"/*.png "$PROJECT_ROOT/snapshots/"
ls -1 "$PROJECT_ROOT/snapshots"
