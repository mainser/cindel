# Changelog

## 1.1.3

- Fixed nullable list serialization and shared embedded helper generation.
- Removed unnecessary casts from generated list readers and embedded filters.

## 1.0.0

- Released the first stable generator with annotations `^1.0.0`.

## 0.9.1

- Aligned with the Cindel 0.9.1 release and annotations `^0.9.1`.

## 0.8.0

- Generated typed links/backlinks and database-bound relation containers, excluding relations from document fields.

## 0.6.4

- Updated documentation for the generated typed API and coordinated release.

## 0.6.1

- Added `@Name` persistence mappings without changing generated Dart method names.
- Generated unique-replace `putBy...`/`putAllBy...` helpers and validated that replace indexes are unique.
- Updated annotations to `^0.5.4`.

## 0.6.0

- Added typed `optional`, `anyOf`, `allOf`, list-length, and list-empty filters.
- Added nested embedded-list filters and optimized native embedded-object/list serialization.

## 0.5.9

- Optimized generated `List<String>` writes with the direct native batch writer.

## 0.5.8

- Added native embedded-object/list readers and writers, plus nested single-object filters.
- Embedded-list nested queries remained unsupported.

## 0.5.7

- Added Freezed primary-factory models and field annotations; union/sealed multi-constructor models remained unsupported.
- Fixed native serialization of converted field types, including enums.

## 0.5.6

- Required `dbId` as the collection ID, allowing ordinary persisted `id` fields.
- Removed unnecessary casts from nullable native readers and writers.

## 0.5.5

- Added query-plan metadata for supported SQLite native filters.

## 0.5.4

- Omitted collection IDs from document maps and avoided unnecessary list copies during native writes.

## 0.5.3

- Kept compact binary document IDs in collection keys rather than payloads.

## 0.5.2

- Added direct native readers for non-nullable string lists; updated annotations to `^0.5.2`.

## 0.5.1

- Stored and hydrated MDBX typed IDs through native document keys.

## 0.5.0

- Optimized list hydration and supported immutable models with explicit IDs.
- Aligned annotations and documentation with the 0.5.0 release.

## 0.4.0

- Generated compact MDBX readers/writers and updated annotations to `^0.4.0`.

## 0.2.5

- Generated `binary-v2` serializers, field metadata, and direct typed hydration.

## 0.2.4

- Restored analyzer 9 downgrade compatibility while retaining analyzer 10+ support for Riverpod and pub.dev consumers.

## 0.2.3

- Generated composite-index equality and primitive-list multi-entry query helpers.

## 0.2.2

- Added binary serializers alongside JSON, with field ordering matching native schemas.
- Supported analyzer 9 and 10+ for Riverpod and pub.dev compatibility.

## 0.2.1

- Updated analyzer compatibility and replaced deprecated field-origin checks.

## 0.2.0

- Aligned the generator, annotations `^0.2.0`, and usage documentation with the coordinated release.

## 0.1.11

- Returned to normal pub.dev versioning with annotations 0.1.7.

## 0.1.10

- Prepared the pub.dev preview with hosted annotations, documentation, and an example.

## 0.1.9

- Added pub.dev metadata and documentation.

## 0.1.8

- Added index variants and typed query generation.
