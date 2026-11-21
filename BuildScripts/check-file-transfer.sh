#!/bin/bash
set -euo pipefail
file_transfer_root="$(cd "$(dirname "$0")/.." && pwd)"
file_transfer_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/file-transfer-check.XXXXXX")"
trap 'rm -rf "$file_transfer_check_dir"' EXIT
xcrun --sdk macosx clang -fobjc-arc -framework Foundation \
    -I "$file_transfer_root/Limelight/Files" \
    "$file_transfer_root/Tests/FileTransferProtocolCheck.m" \
    "$file_transfer_root/Limelight/Files/FileTransferProtocol.m" \
    "$file_transfer_root/Limelight/Files/FileTransferManager.m" \
    -o "$file_transfer_check_dir/check"
"$file_transfer_check_dir/check"
