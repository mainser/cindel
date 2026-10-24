#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NATIVE_DIR="${REPO_ROOT}/packages/cindel/native"
LIBS_DIR="${REPO_ROOT}/packages/cindel_flutter_libs"
TARGET_DIR="${CARGO_TARGET_DIR:-${NATIVE_DIR}/target}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 was not found. Install the required Apple build tools first." >&2
    exit 1
  fi
}

build_target() {
  local target="$1"
  local sdk="$2"
  local RUSTFLAGS="${RUSTFLAGS:-}"
  if [[ "${target}" == *-apple-darwin ]]; then
    RUSTFLAGS="${RUSTFLAGS} -C link-arg=-Wl,-headerpad_max_install_names"
  fi
  export RUSTFLAGS
  export SDKROOT
  SDKROOT="$(xcrun --sdk "${sdk}" --show-sdk-path)"
  cargo build \
    --locked \
    --release \
    --manifest-path "${NATIVE_DIR}/Cargo.toml" \
    --target "${target}"
}

require_command cargo
require_command lipo
require_command xcodebuild
require_command xcrun
require_command python3

python3 "${SCRIPT_DIR}/apple_symbols.py" --check

if [ -z "${LIBCLANG_PATH:-}" ]; then
  if XCODE_DEVELOPER_DIR="$(xcode-select -p 2>/dev/null)"; then
    XCODE_LIBCLANG_DIR="${XCODE_DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/lib"
    if [ -f "${XCODE_LIBCLANG_DIR}/libclang.dylib" ]; then
      export LIBCLANG_PATH="${XCODE_LIBCLANG_DIR}"
    fi
  fi
fi

export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-13.0}"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"

cd "${REPO_ROOT}"

build_target aarch64-apple-ios iphoneos
build_target aarch64-apple-ios-sim iphonesimulator
build_target x86_64-apple-ios iphonesimulator
build_target aarch64-apple-darwin macosx
build_target x86_64-apple-darwin macosx

mkdir -p "${LIBS_DIR}/ios/build/ios-arm64"
mkdir -p "${LIBS_DIR}/ios/build/ios-simulator"
mkdir -p "${LIBS_DIR}/macos"
IOS_PACKAGE="${LIBS_DIR}/ios/cindel_flutter_libs"
MACOS_PACKAGE="${LIBS_DIR}/macos/cindel_flutter_libs"
HEADERS="${LIBS_DIR}/ios/build/headers"
mkdir -p "${HEADERS}"
cp "${SCRIPT_DIR}/apple/CindelNative.h" "${HEADERS}/CindelNative.h"
cat > "${HEADERS}/module.modulemap" <<'MODULE'
module CindelNative {
  header "CindelNative.h"
  export *
}
MODULE

cp "${TARGET_DIR}/aarch64-apple-ios/release/libcindel_native.a" \
  "${LIBS_DIR}/ios/build/ios-arm64/libcindel_native.a"

lipo -create \
  "${TARGET_DIR}/aarch64-apple-ios-sim/release/libcindel_native.a" \
  "${TARGET_DIR}/x86_64-apple-ios/release/libcindel_native.a" \
  -output "${LIBS_DIR}/ios/build/ios-simulator/libcindel_native.a"

rm -rf "${IOS_PACKAGE}/cindel.xcframework"
xcodebuild -create-xcframework \
  -library "${LIBS_DIR}/ios/build/ios-arm64/libcindel_native.a" \
  -headers "${HEADERS}" \
  -library "${LIBS_DIR}/ios/build/ios-simulator/libcindel_native.a" \
  -headers "${HEADERS}" \
  -output "${IOS_PACKAGE}/cindel.xcframework"

lipo -create \
  "${TARGET_DIR}/aarch64-apple-darwin/release/libcindel_native.dylib" \
  "${TARGET_DIR}/x86_64-apple-darwin/release/libcindel_native.dylib" \
  -output "${LIBS_DIR}/macos/libcindel_native.dylib"

# Keep the standalone dylib for direct downloads and existing local tools.
# Flutter embeds one versioned dynamic framework, shared by SwiftPM/CocoaPods.
FRAMEWORK="${LIBS_DIR}/macos/build/CindelNative.framework"
rm -rf "${FRAMEWORK}"
mkdir -p "${FRAMEWORK}/Versions/A/Headers" "${FRAMEWORK}/Versions/A/Modules" \
  "${FRAMEWORK}/Versions/A/Resources"
cp "${LIBS_DIR}/macos/libcindel_native.dylib" "${FRAMEWORK}/Versions/A/CindelNative"
install_name_tool -id '@rpath/CindelNative.framework/Versions/A/CindelNative' \
  "${FRAMEWORK}/Versions/A/CindelNative"
cp "${SCRIPT_DIR}/apple/CindelNative.h" "${FRAMEWORK}/Versions/A/Headers/"
cat > "${FRAMEWORK}/Versions/A/Modules/module.modulemap" <<'MODULE'
framework module CindelNative {
  umbrella header "CindelNative.h"
  export *
  module * { export * }
}
MODULE
PACKAGE_VERSION="$(sed -n 's/^version: //p' "${LIBS_DIR}/pubspec.yaml" | tr -d '\r')"
cat > "${FRAMEWORK}/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>CFBundleExecutable</key><string>CindelNative</string>
  <key>CFBundleIdentifier</key><string>dev.cindel.native</string>
  <key>CFBundleName</key><string>CindelNative</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>${PACKAGE_VERSION}</string>
  <key>CFBundleVersion</key><string>${PACKAGE_VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>${MACOSX_DEPLOYMENT_TARGET}</string>
</dict></plist>
PLIST
ln -s A "${FRAMEWORK}/Versions/Current"
for entry in CindelNative Headers Modules Resources; do
  ln -s "Versions/Current/${entry}" "${FRAMEWORK}/${entry}"
done
# install_name_tool changes the Mach-O bytes; replace the stale ad-hoc signature.
codesign --force --sign - "${FRAMEWORK}"
rm -rf "${MACOS_PACKAGE}/CindelNative.xcframework"
xcodebuild -create-xcframework -framework "${FRAMEWORK}" \
  -output "${MACOS_PACKAGE}/CindelNative.xcframework"

echo "Wrote iOS/macOS XCFrameworks and standalone macOS dylib (ABI 39, MDBX and SQLite)"
