#!/usr/bin/env bash
# Regenerates the app icon in the asset catalog.
#   1. Blender renders the floating-island artwork (Tools/bake/blender/render_icon.py),
#      unless Tools/bake/out/icon/island.png already exists (pass --render to force).
#   2. Tools/bake/compose_icon.py adds the macOS icon shape, sky and shadow and writes
#      every size into EvolutionDefense/Assets.xcassets/AppIcon.appiconset.
# Needs the bake sources (Tools/bake/fetch-sources.sh) and Blender for step 1.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BAKE="$PROJECT_ROOT/Tools/bake"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
if [[ "${1:-}" == "--render" || ! -f "$BAKE/out/icon/island.png" ]]; then
    "$BLENDER" -b --factory-startup -P "$BAKE/blender/render_icon.py" | grep -E "ICON_DONE|Error" || true
fi
python3 "$BAKE/compose_icon.py"
