#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NATIVE_DIR="${REPO_ROOT}/packages/cindel/native"
OUT_DIR="${REPO_ROOT}/packages/cindel_flutter_libs/linux"
TARGET="${CINDEL_LINUX_TARGET:-x86_64-unknown-linux-gnu}"
TARGET_DIR="${CARGO_TARGET_DIR:-${NATIVE_DIR}/target}"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo was not found. Install Rust from https://rustup.rs/." >&2
  exit 1
fi

if ! command -v clang >/dev/null 2>&1 && [ -z "${LIBCLANG_PATH:-}" ]; then
  echo "clang/libclang was not found. Install LLVM/libclang or set LIBCLANG_PATH." >&2
  exit 1
fi

cd "${REPO_ROOT}"

cargo build \
  --release \
  --manifest-path "${NATIVE_DIR}/Cargo.toml" \
  --target "${TARGET}"

mkdir -p "${OUT_DIR}"
cp "${TARGET_DIR}/${TARGET}/release/libcindel_native.so" \
  "${OUT_DIR}/libcindel_native.so"

echo "Wrote packages/cindel_flutter_libs/linux/libcindel_native.so with MDBX support"
