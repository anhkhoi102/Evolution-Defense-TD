#!/usr/bin/env bash
#
# Builds Evolution Defense from the Xcode project and copies the app to
# build/EvolutionDefense.app (stable path used by snapshot.sh).
#
# Usage:
#   Scripts/build.sh                 # Release (optimised)
#   Scripts/build.sh debug           # Debug
#   Scripts/build.sh release --open  # build, then launch
#
# Packaging (Info.plist, asset catalog, resource bundles, signing, hardened
# runtime) is done by Xcode from EvolutionDefense.xcodeproj — not by this script.

set -euo pipefail

CONFIG_ARG="${1:-release}"
OPEN_AFTER="${2:-}"
case "$CONFIG_ARG" in
    release) CONFIG="Release" ;;
    debug)   CONFIG="Debug" ;;
    *) echo "Usage: $0 [release|debug] [--open]" >&2; exit 1 ;;
esac

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
BUILD_DIR="$PROJECT_ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
APP_OUT="$BUILD_DIR/EvolutionDefense.app"

echo "==> xcodebuild ($CONFIG)…"
xcodebuild -project EvolutionDefense.xcodeproj -scheme EvolutionDefense \
           -configuration "$CONFIG" -derivedDataPath "$DERIVED" \
           -destination 'platform=macOS,arch=arm64' build -quiet \
           2> >(grep -v "failed with exit code 0 but produced no further output" >&2)
# ^ With -quiet, Xcode reports the App Intents metadata step (which has nothing
#   to do for this app) as a bogus "error" even though the build succeeds.

PRODUCT="$DERIVED/Build/Products/$CONFIG/EvolutionDefense.app"
[[ -d "$PRODUCT" ]] || { echo "error: $PRODUCT not found" >&2; exit 1; }

# When only data files changed, Xcode can copy them into the app without signing it again.
# A stale signature means: throw the built app away and build once more.
if ! codesign --verify --strict "$PRODUCT" 2>/dev/null; then
    echo "==> stale signature after a data-only change: rebuilding the app bundle"
    rm -rf "$PRODUCT"
    exec "$0" "$@"
fi

if [[ -d "$APP_OUT" && "$APP_OUT" == "$BUILD_DIR/"*.app ]]; then rm -r "$APP_OUT"; fi
ditto "$PRODUCT" "$APP_OUT"
codesign --verify --strict "$APP_OUT"

echo "==> Done: $APP_OUT ($(du -sh "$APP_OUT" | cut -f1))"
[[ "$OPEN_AFTER" == "--open" ]] && open "$APP_OUT"
exit 0
