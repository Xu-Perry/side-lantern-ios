#!/bin/bash
set -euo pipefail
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 /path/to/Debug-iphonesimulator/Moonlight.app simulator-udid" >&2
    exit 2
fi
touch_check_root="$(cd "$(dirname "$0")/.." && pwd)"
touch_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/touch-mode-check.XXXXXX")"
trap 'rm -rf "$touch_check_dir"' EXIT
touch_check_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
touch_check_bundle="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$1/Info.plist")"
xcrun --sdk iphonesimulator clang -fobjc-arc -dynamiclib -arch arm64 -isysroot "$touch_check_sdk" \
    -mios-simulator-version-min=15.0 -framework Foundation -framework UIKit -framework CoreGraphics \
    "$touch_check_root/Tests/TouchModeRuntimeCheck.m" -o "$touch_check_dir/check.dylib"
xcrun simctl install "$2" "$1"
SIMCTL_CHILD_DYLD_INSERT_LIBRARIES="$touch_check_dir/check.dylib" \
    xcrun simctl launch --console --terminate-running-process "$2" "$touch_check_bundle" --sidelantern-stream-preview \
    | tee "$touch_check_dir/output.log"
rg -q 'Touch mode runtime checks passed:' "$touch_check_dir/output.log"
