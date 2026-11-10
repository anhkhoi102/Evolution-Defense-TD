#!/usr/bin/env bash
# Compiles and links the whole game for the iOS Simulator SDK, without changing the
# Xcode project (the Mac target is built with iOS settings passed on the command line).
# This proves the code is free of Mac-only dependencies; it does not produce a shippable
# iOS app (no iOS icon, layout or signing yet: see Docs/IOS_READINESS.md).
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/evo-ios-check"
cd "$PROJECT_ROOT"
LOG="$(xcodebuild -project EvolutionDefense.xcodeproj -target EvolutionDefense -configuration Debug \
    -sdk iphonesimulator SUPPORTED_PLATFORMS="iphonesimulator iphoneos" IPHONEOS_DEPLOYMENT_TARGET=17.0 \
    TARGETED_DEVICE_FAMILY="1,2" CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    ASSETCATALOG_COMPILER_APPICON_NAME="" SYMROOT="$OUT/sym" OBJROOT="$OUT/obj" build 2>&1 || true)"
grep -E "error:" <<<"$LOG" | sed "s|$PROJECT_ROOT/||" | sort -u | head -40 || true
if grep -q "BUILD SUCCEEDED" <<<"$LOG"; then echo "IOSCHECK PASS (compiles and links for iOS Simulator)"; else echo "IOSCHECK FAIL"; exit 1; fi
