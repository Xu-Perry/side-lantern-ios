#!/bin/bash
set -euo pipefail
manual_video_root="$(cd "$(dirname "$0")/.." && pwd)"
manual_video_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/manual-video-check.XXXXXX")"
trap 'rm -rf "$manual_video_check_dir"' EXIT
manual_video_sdk="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx clang -fobjc-arc -framework Foundation -lxml2 '-DLog(...)=((void)0)' \
  -I "$manual_video_sdk/usr/include/libxml2" \
  -I "$manual_video_root/Limelight/Network" -I "$manual_video_root/Limelight/Stream" -I "$manual_video_root/Limelight/Database" \
  "$manual_video_root/Tests/ManualVideoProtocolCheck.m" \
  "$manual_video_root/Limelight/Network/ManualVideoSettings.m" \
  "$manual_video_root/Limelight/Stream/ManualVideoController.m" \
  "$manual_video_root/Limelight/Network/StreamModesResponse.m" \
  "$manual_video_root/Limelight/Database/StreamTargetPreferences.m" \
  "$manual_video_root/Limelight/Network/HttpResponse.m" -o "$manual_video_check_dir/check"
"$manual_video_check_dir/check"
