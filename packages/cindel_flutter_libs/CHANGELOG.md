# Changelog

## 0.6.4

- Updated the bundled Web SQLite Wasm runtime assets with cached native
  document insert chunks for the typed Web batch-write path.
- Updated the bundled Web SQLite Wasm runtime assets with query-plan reads,
  query-plan mutations, collection revision/change-set operations, and
  transaction worker operations.
- Declared Web plugin support and packaged the Web Worker, JavaScript glue, and
  Wasm runtime assets as Flutter package assets.

## 0.6.1

- Added experimental Web SQLite Wasm runtime assets under `web/pkg`.

## 0.6.0

- Prepared regenerated Flutter native runtime libraries for the Cindel `0.6.0`
  native reader ABI.
- Includes the new current-document dynamic field reader symbols required by
  the Cindel `0.6.0` MDBX typed hydration path.
- Keeps MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend and SQLite selectable explicitly.

## 0.5.13

- Added iOS and macOS to the advertised Flutter plugin platform set.
- Prepared release automation to generate Android, iOS, Linux, macOS, and
  Windows native runtime binaries in GitHub Actions before pub.dev publishing.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend and SQLite selectable explicitly.

## 0.5.12

- Regenerated Windows, Android, and Linux native runtime libraries for the
  Cindel `0.5.12` native runtime line.
- Includes the MDBX query-plan count, aggregate, and projection streaming
  optimizations.
- Keeps MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend and SQLite selectable explicitly.

## 0.5.11

- Regenerated Windows, Android, and Linux native runtime libraries for the
  Cindel `0.5.11` native runtime line.
- Includes the latest MDBX native read/query optimizations, SQLite string-list
  hydration improvements, and SQLite schema-aware open behavior.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend and SQLite selectable explicitly.

## 0.5.8

- Regenerated Windows, Android, and Linux native runtime libraries for the
  Cindel `0.5.8` backend format and `dbId` release line.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend and SQLite selectable explicitly.

## 0.5.7

- Regenerated the Windows native runtime library for the Cindel `0.5.7`
  SQLite generated typed backend completion line.
- Kept MDBX and SQLite compiled into the shipped binary, with MDBX as the
  default backend and SQLite selectable explicitly.

## 0.5.6

- Regenerated the Windows native runtime library for the Cindel `0.5.6`
  SQLite generated `getAll` cursor/reader ABI.
- Kept MDBX and SQLite compiled into the shipped binary, with MDBX as the
  default backend.

## 0.5.4

- Regenerated Windows, Android, and Linux native runtime libraries for the
  Cindel `0.5.4` native ABI 29 release line.
- Includes the MDBX unindexed typed batch insert fast path, native query-plan
  update optimization, native filter scan optimization, and filtered sort query
  optimization used by the app-style benchmark path.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.5.3

- Regenerated Windows, Android, and Linux native runtime libraries for the
  Cindel `0.5.3` native fix line.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.5.2

- Regenerated Windows, Android, and Linux native runtime libraries for the
  current Cindel native ABI used by the `cindel` 0.5.2 line.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.5.1

- Regenerated Windows, Android, and Linux native runtime libraries so the
  shipped binaries match the `cindel` 0.5.0 native FFI surface, including the
  native batch list writer symbols required by typed `List<String>` writes.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.5.0

- Updated the Flutter native libraries package to the coordinated `0.5.0`
  release line.
- Regenerated the Windows native runtime library with schema-prepared native
  filter evaluation and typed reader string hydration cleanup.
- Regenerated the Windows native runtime library with the tighter compact
  native `List<String>` payload layout.
- Regenerated the Windows native runtime library for faster typed MDBX inserts
  with compact native string-list payloads.
- Regenerated the Windows native runtime library for Cindel native ABI 25 with
  MDBX schema registration during native open.
- Kept MDBX and SQLite compiled into the Windows binary, with MDBX as the
  default backend.

## 0.4.0

- Regenerated Windows, Android, and Linux native runtime libraries for Cindel
  native ABI 23.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.3.4

- Regenerated Windows, Android, and Linux native runtime libraries for Cindel
  native ABI 17 after removing default-runtime JSON result paths.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.3.3

- Regenerated Windows, Android, and Linux native runtime libraries for Cindel
  native ABI 16 with CindelWireV1 binary watcher change-set support.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.3.2

- Regenerated Windows, Android, and Linux native runtime libraries for Cindel
  native ABI 15 with CindelWireV1 binary native query plan execution support.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.3.1

- Regenerated Windows, Android, and Linux native runtime libraries for Cindel
  native ABI 14 with binary schema and metadata payload support.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.3.0

- Regenerated Windows, Android, and Linux native runtime libraries for Cindel
  native ABI 13 with GenericDocumentV1 manual document payload support.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.2.18

- Regenerated Windows, Android, and Linux native runtime libraries for Cindel
  native ABI 12 with CindelWireV1 binary native filter AST payloads.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.2.17

- Regenerated Windows, Android, and Linux native runtime libraries for Cindel
  native ABI 11 with CindelWireV1 binary index values, index entries, and
  indexed document write batches.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.2.16

- Regenerated Windows, Android, and Linux native runtime libraries with the
  GET-01 MDBX read-path optimization that caches schema manifests for
  get-family reads.
- Kept the native ABI at 10 and kept MDBX and SQLite compiled into the shipped
  binaries.

## 0.2.15

- Regenerated Windows, Android, and Linux native runtime libraries for Cindel
  native ABI 10 with CindelWireV1 binary id-list FFI payloads.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.2.13

- Regenerated Windows, Android, and Linux native runtime libraries for Cindel
  native ABI 9 with native aggregate query support.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.
- Declared Linux in Flutter plugin metadata and included `linux/` in pub.dev
  publication archives.
- Completed Windows, Android, and Linux prebuilt validation for the optimized
  MDBX storage release.

## 0.2.12

- Regenerated Windows, Android, and Linux native runtime libraries with the
  converged MDBX v2 table layout in the real default backend.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.2.11

- Regenerated Windows, Android, and Linux native runtime libraries with the
  MDBX allocation and key-buffer reuse optimizations.

## 0.2.10

- Regenerated Windows, Android, and Linux native runtime libraries with the
  MDBX auto-increment counter optimization.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.2.9

- Regenerated Windows, Android, and Linux native runtime libraries with
  composite and multi-entry index support.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.2.8

- Regenerated Windows, Android, and Linux native runtime libraries for Cindel
  native ABI 8.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.2.7

- Regenerated Windows, Android, and Linux native runtime libraries for Cindel
  native ABI 7.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

## 0.2.6

- Regenerated Windows, Android, and Linux native runtime libraries for Cindel
  native ABI 6.
- Kept MDBX and SQLite compiled into the shipped binaries, with MDBX as the
  default backend.

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
