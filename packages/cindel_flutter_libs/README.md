# cindel_flutter_libs

Prebuilt native libraries for Flutter apps that use Cindel.

This package does not expose a Dart API. It only makes Flutter bundle the
correct Cindel native library for each supported platform so application
developers do not need Rust or Cargo installed locally.

Maintainer: Alain Ramirez <nolbertrg@gmail.com>

Repository: <https://github.com/mainser/Cindel>

Current binary locations:

- Android: `android/src/main/jniLibs/<abi>/libcindel_native.so`
- iOS: `ios/cindel.xcframework`
- Windows: `windows/cindel_native.dll`

Planned binary locations:

- macOS: `macos/libcindel_native.dylib`
- Linux: `linux/libcindel_native.so`

Maintainers can regenerate these binaries with the scripts in
`tool/prebuilt/` from the repository root.

When Cindel's native Rust code changes, regenerate the affected binaries before
committing so Flutter consumers do not accidentally run an older native core.
