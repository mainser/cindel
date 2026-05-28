# Cindel Flutter Libs

Flutter plugin package that bundles prebuilt Cindel native runtime libraries.

[Overview](#overview) |
[When To Use It](#when-to-use-it) |
[Setup](#setup) |
[Supported Platforms](#supported-platforms) |
[What It Contains](#what-it-contains) |
[Maintainers](#maintainers)

> This package does not expose a Dart database API. Apps use
> `package:cindel/cindel.dart`; this package only makes Flutter include the
> native Cindel library in the built application.

## Overview

`cindel_flutter_libs` is the native-binary companion package for Flutter apps
that use Cindel.

Cindel's Dart API talks to a Rust native core through FFI. Flutter apps need
that native library to be present in the final app bundle. This package provides
the prebuilt libraries for the platforms currently supported by the package, so
app developers do not need Rust, Cargo, or the Cindel native build scripts just
to run their Flutter app.

The bundled native libraries include both storage backends compiled into the
runtime:

- MDBX, Cindel's default backend.
- SQLite, available only when selected explicitly from the `cindel` API.

## When To Use It

Add this package when a Flutter app depends on `cindel` and should use the
prebuilt native runtime:

```yaml
dependencies:
  cindel: ^0.5.7
  cindel_flutter_libs: ^0.5.7
```

No Dart import is required from this package.

```dart
import 'package:cindel/cindel.dart';
```

The `cindel` package owns the public API. `cindel_flutter_libs` is present so
Flutter's platform build can find and bundle the native library.

## Setup

After adding the dependency, use Cindel normally:

```dart
final db = await Cindel.open(
  directory: directory.path,
  schemas: [UserSchema],
);
```

MDBX is used by default. SQLite can still be selected explicitly:

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
- Windows
- Linux

Current binary locations:

- Android: `android/src/main/jniLibs/<abi>/libcindel_native.so`
- Windows: `windows/cindel_native.dll`
- Linux: `linux/libcindel_native.so`

Android ABIs currently included:

- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`

## Planned Platforms

The package contains plugin scaffolding for Apple platforms, but Apple native
runtime binaries are not part of the current advertised platform set.

Planned binary locations:

- iOS: `ios/cindel.xcframework`
- macOS: `macos/libcindel_native.dylib`

iOS and macOS should be advertised only after those binaries are generated,
bundled, and validated.

## What It Contains

This package contains:

- Flutter plugin registration files for supported platforms.
- Prebuilt Cindel native libraries for supported platforms.
- Minimal Dart library metadata.

It does not contain:

- The Cindel database API.
- The Cindel model annotations.
- The code generator.
- Application-level database code.

Those live in the other Cindel packages:

- `cindel`: runtime API, typed collections, queries, watchers, and FFI loading.
- `cindel_annotations`: public annotations and schema metadata types.
- `cindel_generator`: build-time source generator for annotated models.

## Maintainers

Regenerate native binaries whenever the Rust native core changes and the
Flutter package needs to ship that new ABI.

From the repository root, use the scripts in `tool/prebuilt/` for the supported
platforms. The package should not be released with stale native binaries,
because Flutter consumers would load an older native core than the Dart API
expects.

For local benchmark and development work, the repository often uses the
source-current Windows library from:

```text
packages/cindel/native/target/release/cindel_native.dll
```

That development DLL is not a replacement for regenerating and publishing the
prebuilt Flutter package binaries.

## Status

Cindel is in active pre-1.0 development. Keep the `cindel` and
`cindel_flutter_libs` package versions aligned with the native ABI expected by
the Dart runtime for the release being tested or published.
