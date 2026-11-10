#!/usr/bin/env bash
# Summon check: both abilities on the Dragon wave. Captures the deployment
# preview (valid / invalid), the fight and the aftermath into ./snapshots/summon/,
# and fails if a summon lands on an invalid spot, isn't drawn, outlives its
# duration, leaks sprites, or any effect sprite is mis-sized.
# Build first: Scripts/build.sh
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BIN="$PROJECT_ROOT/build/EvolutionDefense.app/Contents/MacOS/EvolutionDefense"
[[ -x "$APP_BIN" ]] || { echo "Build first: Scripts/build.sh" >&2; exit 1; }
CONTAINER_TMP="$HOME/Library/Containers/local.evolutiondefense.game/Data/tmp/snapshots"
RESULT="$(EVO_SUMMON_TEST=1 EVO_MUTE=1 "$APP_BIN" 2>&1 | grep SUMMONTEST || true)"
mkdir -p "$PROJECT_ROOT/snapshots/summon"
cp "$CONTAINER_TMP"/summon-*.png "$PROJECT_ROOT/snapshots/summon/" 2>/dev/null || true
echo "${RESULT:-SUMMONTEST no result}"
[[ "$RESULT" == *PASS* ]]
