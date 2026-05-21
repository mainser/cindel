# cindel_flutter_libs

Prebuilt native libraries for Flutter apps that use Cindel.

This package is intentionally similar in shape to `isar_flutter_libs`: it does
not expose a Dart API. It only makes Flutter bundle the correct Cindel native
library for each platform so application developers do not need Rust or Cargo
installed locally.

Expected binary locations:

- Android: `android/src/main/jniLibs/<abi>/libcindel_native.so`
- iOS: `ios/cindel.xcframework`
- macOS: `macos/libcindel_native.dylib`
- Windows: `windows/cindel_native.dll`
- Linux: `linux/libcindel_native.so`

Maintainers can regenerate these binaries with the scripts in
`tool/prebuilt/` from the repository root.

When Cindel's native Rust code changes, regenerate the affected binaries before
committing so Flutter consumers do not accidentally run an older native core.
