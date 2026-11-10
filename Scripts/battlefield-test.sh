#!/usr/bin/env bash
# Battlefield check: screenshots the menu, the battlefield selection and a fight
# on every battlefield into ./snapshots/battlefields/, and fails if a map doesn't
# load, its pads can't be built on, enemies don't advance, a summon can't be
# placed, or another map's background stays in memory after switching.
# Build first: Scripts/build.sh
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BIN="$PROJECT_ROOT/build/EvolutionDefense.app/Contents/MacOS/EvolutionDefense"
[[ -x "$APP_BIN" ]] || { echo "Build first: Scripts/build.sh" >&2; exit 1; }
CONTAINER_TMP="$HOME/Library/Containers/local.evolutiondefense.game/Data/tmp/snapshots"
RESULT="$(EVO_BATTLEFIELD_TEST=1 EVO_MUTE=1 "$APP_BIN" 2>&1 | grep BATTLEFIELDTEST || true)"
rm -rf "$PROJECT_ROOT/snapshots/battlefields"; mkdir -p "$PROJECT_ROOT/snapshots/battlefields"
cp "$CONTAINER_TMP"/bf-*.png "$PROJECT_ROOT/snapshots/battlefields/" 2>/dev/null || true
echo "${RESULT:-BATTLEFIELDTEST no result}"
[[ "$RESULT" == *PASS* ]]
