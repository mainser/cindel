# Cindel Flutter Libs

Flutter plugin package that bundles Cindel native libraries and Web runtime
assets.

[Overview](#overview) |
[When To Use It](#when-to-use-it) |
[Setup](#setup) |
[Supported Platforms](#supported-platforms) |
[What It Contains](#what-it-contains) |
[Maintainers](#maintainers)

> This package does not expose a Dart database API. Apps use
> `package:cindel/cindel.dart`; this package makes Flutter include the runtime
> files required by that API.

## Overview

`cindel_flutter_libs` is the native-binary and Web-runtime companion package for
Flutter apps that use Cindel.

Cindel's Dart API talks to a Rust native core through FFI on native platforms
and through Worker/Wasm runtime assets on Web. Flutter apps need those runtime
files to be present in the final app bundle. This package provides the prebuilt
libraries and Web assets for the platforms currently supported by the package,
so app developers do not need Rust, Cargo, or the Cindel native build scripts
just to run their Flutter app.

The bundled native libraries include both storage backends compiled into the
native runtime:

- MDBX, Cindel's default backend.
- SQLite, available only when selected explicitly from the `cindel` API.

The bundled Web runtime is SQLite/OPFS only. MDBX remains the default native
backend and is not a browser backend.

## When To Use It

Add this package when a Flutter app depends on `cindel` and should use the
packaged native or Web runtime:

```yaml
dependencies:
  cindel: ^x.y.z
  cindel_flutter_libs: ^x.y.z
```

No Dart import is required from this package.

```dart
import 'package:cindel/cindel.dart';
```

The `cindel` package owns the public API. `cindel_flutter_libs` is present so
Flutter's platform build can find and bundle the required native libraries or
Web Worker/Wasm assets.

## Setup

After adding the dependency, use Cindel normally:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);
```

MDBX is used by default on native platforms. SQLite can still be selected
explicitly:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
  backend: CindelStorageBackend.sqlite,
);
```

## Supported Platforms

The current package declares Flutter plugin support for:

- Android
- iOS
- Linux
- macOS
- Web runtime assets
- Windows

Current packaged binary locations:

- Android: `android/src/main/jniLibs/<abi>/libcindel_native.so`
- Linux: `linux/libcindel_native.so`
- iOS: `ios/cindel_flutter_libs/cindel.xcframework` (static).
- macOS: `macos/cindel_flutter_libs/CindelNative.xcframework.zip` (dynamic; preserves framework symlinks through Pub). SwiftPM consumes the ZIP directly; CocoaPods extracts it during installation.
- Web: `web/cindel_worker.js`, `web/pkg/cindel_native.js`, and
  `web/pkg/cindel_native_bg.wasm`
- Windows: `windows/cindel_native.dll`

The iOS and macOS podspecs are versioned with this package. Their vendored
Apple binaries must be generated on macOS with Xcode before publishing Apple
runtime support.

iOS and macOS support both Swift Package Manager and CocoaPods with the same
public Cindel API. Flutter selects the integration; no extra Dart imports or
manual linker settings are needed. The plugin targets iOS 13 and macOS 10.15
or later, subject to the minimum required by the application's Flutter SDK.
Prebuilt slices cover iOS ARM64 devices, ARM64/x64 simulators, and ARM64/x64 Macs.

Maintainers build Apple artifacts with `tool/prebuilt/build_apple.sh` on macOS
with Xcode. CI is configured to validate both managers with Flutter 3.41.0 and 3.47.8;
release repeats consumer checks against the binaries being published. These
checks include all FFI symbols, ABI 39, and MDBX/SQLite persistence. iOS device
Release builds are checked without signing; runtime checks use the simulator.
Consumer checks use a locally archived and extracted pub package, including
the macOS framework symlinks, without uploading anything to pub.dev.

Android ABIs currently included:

- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`

## What It Contains

This package contains:

- Flutter plugin registration files for supported platforms.
- Prebuilt Cindel native libraries for supported platforms.
- Web SQLite/OPFS Worker/Wasm runtime assets used by
  `Cindel.open(...)` on Flutter Web.
- Minimal Dart library metadata.

It does not contain:

- The Cindel database API.
- The Cindel model annotations.
- The code generator.
- Application-level database code.

Those live in the other Cindel packages:

- `cindel`: runtime API, typed collections, queries, watchers, and backend
  loading.
- `cindel_annotations`: public annotations and schema metadata types.
- `cindel_generator`: build-time source generator for annotated models.

## Status

Keep the `cindel` and `cindel_flutter_libs` package versions aligned with the
native ABI expected by the Dart runtime for the release being tested or
published.
