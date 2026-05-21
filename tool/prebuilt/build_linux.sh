#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NATIVE_DIR="${REPO_ROOT}/packages/cindel/native"
OUT_DIR="${REPO_ROOT}/packages/cindel_flutter_libs/linux"
TARGET="${CINDEL_LINUX_TARGET:-x86_64-unknown-linux-gnu}"
TARGET_DIR="${CARGO_TARGET_DIR:-${NATIVE_DIR}/target}"

cd "${REPO_ROOT}"

cargo build --release --manifest-path "${NATIVE_DIR}/Cargo.toml" --target "${TARGET}"

mkdir -p "${OUT_DIR}"
cp "${TARGET_DIR}/${TARGET}/release/libcindel_native.so" \
  "${OUT_DIR}/libcindel_native.so"

echo "Wrote packages/cindel_flutter_libs/linux/libcindel_native.so"
