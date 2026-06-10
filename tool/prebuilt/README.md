# Cindel prebuilt native binaries

These scripts build Cindel's Rust native library and copy the output into
`packages/cindel_flutter_libs`, the Flutter plugin package that bundles native
libraries for app consumers.

The native platform scripts build the native library with the `mdbx` Cargo
feature enabled so Flutter consumers can select either SQLite or MDBX without a
local Rust toolchain. The Web script is different: it builds the SQLite-only
Wasm runtime with `--no-default-features --features web` because MDBX is not a
browser backend.

Maintainer requirements by platform:

- Windows: Rust MSVC toolchain and LLVM/libclang for MDBX bindgen.
- Android: Rust Android targets and Android NDK. The script can auto-detect
  common SDK paths or use `ANDROID_NDK_HOME`. LLVM/libclang is also required
  for MDBX bindgen.
- iOS/macOS: macOS, Xcode command line tools, Rust Apple targets, and
  LLVM/libclang for MDBX bindgen.
- Linux: Rust GNU toolchain for the host or WSL, plus LLVM/libclang for MDBX
  bindgen.
- Web: Rust `wasm32-unknown-unknown` target, LLVM/clang for sqlite-wasm-rs, and
  `wasm-bindgen-cli` available on `PATH`.

Consumers should not need Rust or Cargo once the generated binaries are checked
into `packages/cindel_flutter_libs`.

Common commands from the repository root:

```powershell
.\tool\prebuilt\build_windows.ps1
.\tool\prebuilt\build_android.ps1
.\tool\prebuilt\build_web.ps1
```

```sh
./tool/prebuilt/build_apple.sh
./tool/prebuilt/build_linux.sh
```

After changing `packages/cindel/native`, regenerate every advertised prebuilt
binary that can be produced before publishing. On Windows that means
`build_windows.ps1`, `build_android.ps1` when the Android NDK is installed, and
`build_web.ps1`. Run `build_linux.sh` through WSL or a Linux host.

Apple binaries should be generated and validated on Apple platforms before they
are advertised in pub.dev metadata.

The Web script writes `packages/cindel_flutter_libs/web/pkg/cindel_native.js`,
`packages/cindel_flutter_libs/web/pkg/cindel_native_bg.wasm`, and the companion
`packages/cindel_flutter_libs/web/cindel_worker.js`. These are the SQLite-only
runtime assets for Web; MDBX remains native-only.
