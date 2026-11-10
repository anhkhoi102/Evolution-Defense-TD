#!/usr/bin/env bash
# Mass-death check: wave-7 packs of Giant Wolves, Armored Beasts and Trolls die
# together under maxed splash fire while towers keep evolving. Fails if any
# effect sprite (death animations, corpses, explosions…) is drawn at the wrong
# size. Frames go to ./snapshots/death/. Build first: Scripts/build.sh
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BIN="$PROJECT_ROOT/build/EvolutionDefense.app/Contents/MacOS/EvolutionDefense"
[[ -x "$APP_BIN" ]] || { echo "Build first: Scripts/build.sh" >&2; exit 1; }
CONTAINER_TMP="$HOME/Library/Containers/local.evolutiondefense.game/Data/tmp/snapshots"
RESULT="$(EVO_DEATH_TEST=1 EVO_MUTE=1 "$APP_BIN" 2>&1 | grep DEATHTEST || true)"
mkdir -p "$PROJECT_ROOT/snapshots/death"
cp "$CONTAINER_TMP"/death-*.png "$PROJECT_ROOT/snapshots/death/" 2>/dev/null || true
echo "${RESULT:-DEATHTEST no result}"
[[ "$RESULT" == *PASS* ]]
