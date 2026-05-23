# cindel_flutter_libs

Prebuilt native libraries for Flutter apps that use Cindel.

This package does not expose a Dart API. It only makes Flutter bundle the
correct Cindel native library for each supported platform so application
developers do not need Rust or Cargo installed locally.

The current Android, Windows, and Linux binaries include the SQLite and MDBX
storage backends. MDBX is Cindel's default backend, and SQLite can still be
selected explicitly from the `cindel` package.

Current binary locations:

- Android: `android/src/main/jniLibs/<abi>/libcindel_native.so`
- Windows: `windows/cindel_native.dll`
- Linux: `linux/libcindel_native.so`

Planned binary locations:

- iOS: `ios/cindel.xcframework`
- macOS: `macos/libcindel_native.dylib`

Android, Windows, and Linux are advertised in the current pub.dev release.
Apple binaries will be added in a later package version after they can be
generated and validated.

Maintainers can regenerate these binaries with the scripts in
`tool/prebuilt/` from the repository root.

When Cindel's native Rust code changes, regenerate the affected binaries before
committing so Flutter consumers do not accidentally run an older native core.
