#!/bin/bash
set -euo pipefail

stream_target_root="$(cd "$(dirname "$0")/.." && pwd)"
stream_target_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/stream-target-check.XXXXXX")"
trap 'rm -rf "$stream_target_check_dir"' EXIT
stream_target_sdk="$(xcrun --sdk macosx --show-sdk-path)"

xcrun --sdk macosx clang -fobjc-arc -framework Foundation -lxml2 \
    '-DLog(...)=((void)0)' \
    -I "$stream_target_sdk/usr/include/libxml2" \
    -I "$stream_target_root/Limelight/Network" \
    -I "$stream_target_root/Limelight/Database" \
    "$stream_target_root/Tests/StreamTargetProtocolCheck.m" \
    "$stream_target_root/Limelight/Database/StreamTargetPreferences.m" \
    "$stream_target_root/Limelight/Network/StreamModesResponse.m" \
    "$stream_target_root/Limelight/Network/HttpResponse.m" \
    -o "$stream_target_check_dir/check"

"$stream_target_check_dir/check"
