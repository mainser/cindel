#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE="${SCRIPT_DIR}/cindel_flutter_libs/CindelNative.xcframework.zip"
BUILD_DIR="${SCRIPT_DIR}/build"
test -f "${ARCHIVE}"
mkdir -p "${BUILD_DIR}"
TEMP_DIR="$(mktemp -d "${BUILD_DIR}/cindel-framework.XXXXXX")"
trap 'rm -rf "${TEMP_DIR}"' EXIT

# CocoaPods path dependencies do not run prepare_command. The podspec invokes
# this script before collecting vendored frameworks, using only the local ZIP.
unzip -q "${ARCHIVE}" -d "${TEMP_DIR}"
FRAMEWORK="${TEMP_DIR}/CindelNative.xcframework/macos-arm64_x86_64/CindelNative.framework"
test -L "${FRAMEWORK}/Versions/Current"
for entry in CindelNative Headers Modules Resources; do
  test -L "${FRAMEWORK}/${entry}"
done
test -f "${FRAMEWORK}/CindelNative"
rm -rf "${BUILD_DIR}/CindelNative.xcframework"
mv "${TEMP_DIR}/CindelNative.xcframework" "${BUILD_DIR}/CindelNative.xcframework"
