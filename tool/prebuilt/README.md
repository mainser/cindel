# Cindel prebuilt native binaries

These scripts build Cindel's Rust native library and copy the output into
`packages/cindel_flutter_libs`, the Flutter plugin package that bundles native
libraries for app consumers.

The platform scripts build the native library with the `mdbx` Cargo feature
enabled so Flutter consumers can select either SQLite or MDBX without a local
Rust toolchain.

Maintainer requirements by platform:

- Windows: Rust MSVC toolchain and LLVM/libclang for MDBX bindgen.
- Android: Rust Android targets and Android NDK. The script can auto-detect
  common SDK paths or use `ANDROID_NDK_HOME`. LLVM/libclang is also required
  for MDBX bindgen.
- iOS/macOS: macOS, Xcode command line tools, Rust Apple targets, and
  LLVM/libclang for MDBX bindgen.
- Linux: Rust GNU toolchain for the host or configured cross toolchains, plus
  LLVM/libclang for MDBX bindgen.

Consumers should not need Rust or Cargo once the generated binaries are checked
into `packages/cindel_flutter_libs`.

Common commands from the repository root:

```powershell
.\tool\prebuilt\build_windows.ps1
.\tool\prebuilt\build_android.ps1
```

```sh
./tool/prebuilt/build_apple.sh
./tool/prebuilt/build_linux.sh
```

After changing `packages/cindel/native`, regenerate every prebuilt binary that
can be produced on the current machine before committing. On Windows that means
at least `build_windows.ps1` and, when the Android NDK is installed,
`build_android.ps1`.

Apple and Linux binaries should be generated and validated on their native
platforms before they are advertised in pub.dev metadata.
