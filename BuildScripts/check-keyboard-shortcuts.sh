#!/bin/bash
set -euo pipefail
shortcut_root="$(cd "$(dirname "$0")/.." && pwd)"
shortcut_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyboard-shortcut-check.XXXXXX")"
trap 'rm -rf "$shortcut_check_dir"' EXIT
xcrun --sdk macosx clang -fobjc-arc -framework Foundation \
    -I "$shortcut_root/Limelight/Input" \
    "$shortcut_root/Tests/KeyboardShortcutCheck.m" \
    "$shortcut_root/Limelight/Input/KeyboardShortcut.m" \
    -o "$shortcut_check_dir/check"
"$shortcut_check_dir/check"
