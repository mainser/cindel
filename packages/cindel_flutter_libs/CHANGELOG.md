# Changelog

## 0.2.5

- Regenerated native runtime libraries for the Cindel native ABI 5 cleanup.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as
  Cindel's default backend.
- Added Linux as an advertised prebuilt platform alongside Android and
  Windows.

## 0.2.0

- Prepared the Flutter native libraries package for the coordinated `0.2.0`
  Cindel release line.
- Kept Android and Windows as the advertised prebuilt platforms for the current
  pub.dev package.
- Updated package and plugin metadata to the `0.2.0` version.

## 0.1.11

- Updated package documentation to describe MDBX as Cindel's default backend
  while SQLite remains explicitly selectable.

## 0.1.10

- Prepared the first pub.dev development preview.
- Limited published Flutter plugin support to Android and Windows until Apple
  and Linux binaries are generated and validated.
- Removed dates from changelog headings so pub.dev renders version labels cleanly.
- Added a package example page for pub.dev.
- Added a library-level documentation comment for dartdoc/pub.dev analysis.
- Updated the package example dependency constraints for the current Cindel
  development preview.
- Updated the package example to reference the MDBX-04 Cindel development
  preview.
- Bundled Windows and Android native libraries built with MDBX support.
- Updated the Windows and Android prebuilt build scripts to enable the native
  `mdbx` Cargo feature.

## 0.1.9

- Added pub.dev-oriented package metadata and maintainer information.
- Declared current Flutter plugin support for Android, iOS, and Windows while
  Linux and macOS prebuilt binaries remain pending.

## 0.1.8

- Bundled regenerated Android and Windows native libraries for the current
  Cindel native ABI.
