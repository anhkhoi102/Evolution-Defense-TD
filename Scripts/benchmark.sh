#!/usr/bin/env bash
# Frame-rate benchmark: 16 level-5 towers, all tech, 300 Futuristic enemies + the
# final boss, measured on the live SKView (normal and performance mode).
# Use a Release build: Scripts/build.sh release
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BIN="$PROJECT_ROOT/build/EvolutionDefense.app/Contents/MacOS/EvolutionDefense"
[[ -x "$APP_BIN" ]] || { echo "Build first: Scripts/build.sh release" >&2; exit 1; }
EVO_BENCHMARK=1 EVO_MUTE=1 "$APP_BIN" 2>&1 | grep BENCHMARK
