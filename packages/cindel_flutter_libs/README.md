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
  cindel: ^0.7.0
  cindel_flutter_libs: ^0.7.0
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
- Web: `web/cindel_worker.js`, `web/pkg/cindel_native.js`, and
  `web/pkg/cindel_native_bg.wasm`
- Windows: `windows/cindel_native.dll`

The iOS and macOS podspecs are versioned with this package. Their vendored
Apple binaries must be generated on macOS with Xcode before publishing Apple
runtime support.

Android ABIs currently included:

- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`

## What It Contains

This package contains:

- Flutter plugin registration files for supported platforms.
- Prebuilt Cindel native libraries for supported platforms.
- Experimental Web SQLite/OPFS Worker/Wasm runtime assets used by
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

Cindel is in active pre-1.0 development. Keep the `cindel` and
`cindel_flutter_libs` package versions aligned with the native ABI expected by
the Dart runtime for the release being tested or published.
