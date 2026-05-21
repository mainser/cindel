#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NATIVE_DIR="${REPO_ROOT}/packages/cindel/native"
LIBS_DIR="${REPO_ROOT}/packages/cindel_flutter_libs"
TARGET_DIR="${CARGO_TARGET_DIR:-${NATIVE_DIR}/target}"

cd "${REPO_ROOT}"

cargo build --release --manifest-path "${NATIVE_DIR}/Cargo.toml" --target aarch64-apple-ios
cargo build --release --manifest-path "${NATIVE_DIR}/Cargo.toml" --target aarch64-apple-ios-sim
cargo build --release --manifest-path "${NATIVE_DIR}/Cargo.toml" --target x86_64-apple-ios
cargo build --release --manifest-path "${NATIVE_DIR}/Cargo.toml" --target aarch64-apple-darwin
cargo build --release --manifest-path "${NATIVE_DIR}/Cargo.toml" --target x86_64-apple-darwin

mkdir -p "${LIBS_DIR}/ios/build/ios-arm64"
mkdir -p "${LIBS_DIR}/ios/build/ios-simulator"
mkdir -p "${LIBS_DIR}/macos"

cp "${TARGET_DIR}/aarch64-apple-ios/release/libcindel_native.a" \
  "${LIBS_DIR}/ios/build/ios-arm64/libcindel_native.a"

lipo -create \
  "${TARGET_DIR}/aarch64-apple-ios-sim/release/libcindel_native.a" \
  "${TARGET_DIR}/x86_64-apple-ios/release/libcindel_native.a" \
  -output "${LIBS_DIR}/ios/build/ios-simulator/libcindel_native.a"

rm -rf "${LIBS_DIR}/ios/cindel.xcframework"
xcodebuild -create-xcframework \
  -library "${LIBS_DIR}/ios/build/ios-arm64/libcindel_native.a" \
  -library "${LIBS_DIR}/ios/build/ios-simulator/libcindel_native.a" \
  -output "${LIBS_DIR}/ios/cindel.xcframework"

lipo -create \
  "${TARGET_DIR}/aarch64-apple-darwin/release/libcindel_native.dylib" \
  "${TARGET_DIR}/x86_64-apple-darwin/release/libcindel_native.dylib" \
  -output "${LIBS_DIR}/macos/libcindel_native.dylib"

echo "Wrote iOS xcframework and macOS dylib under packages/cindel_flutter_libs"
