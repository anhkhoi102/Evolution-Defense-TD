#!/usr/bin/env bash
# Renders the same scene with the default placeholder pack and with an asset
# pack override, so a replacement pack can be checked visually.
#   Scripts/asset-demo.sh [pack-name]     (default: sample → asset_manifest.sample.json)
# Output: snapshots/asset-pack-default.png and snapshots/asset-pack-<name>.png
set -euo pipefail
PACK="${1:-sample}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BIN="$PROJECT_ROOT/build/EvolutionDefense.app/Contents/MacOS/EvolutionDefense"
[[ -x "$APP_BIN" ]] || { echo "Build first: Scripts/build.sh" >&2; exit 1; }
CONTAINER_TMP="$HOME/Library/Containers/local.evolutiondefense.game/Data/tmp/snapshots"
mkdir -p "$PROJECT_ROOT/snapshots"
EVO_ASSET_DEMO=1 EVO_MUTE=1 "$APP_BIN" 2>&1 | grep -E "ASSETDEMO|Assets:" || true
EVO_ASSET_DEMO=1 EVO_MUTE=1 EVO_ASSET_PACK="$PACK" "$APP_BIN" 2>&1 | grep -E "ASSETDEMO|Assets:" || true
cp "$CONTAINER_TMP"/asset-pack-*.png "$PROJECT_ROOT/snapshots/"
ls -1 "$PROJECT_ROOT"/snapshots/asset-pack-*.png
