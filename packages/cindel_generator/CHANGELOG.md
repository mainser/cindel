# Changelog

## 0.5.8

- Generated native typed readers and writers for collection schemas containing
  embedded object fields and embedded object lists.
- Added generated nested filter helpers for fields inside a single embedded
  object.
- Kept embedded object-list nested query helpers unsupported, matching the
  current Isar-aligned scope.

## 0.5.7

- Added support for Freezed primary-factory collection models by discovering
  persisted properties from the unnamed factory constructor when no concrete
  fields are declared.
- Reads Cindel field annotations such as `@Index`, `@Enumerated`, and `@ignore`
  from Freezed factory parameters.
- Updated generated native writers to write stored values for converted field
  types such as enums.
- Keeps Freezed union/sealed multi-constructor models unsupported.

## 0.5.6

- Changed generated collection id detection to require a field named `dbId`
  instead of `id`.
- Allows a normal model field named `id` to be persisted and queried, which
  keeps API identifiers separate from Cindel's internal storage id.
- Updated generated native nullable readers and writers to avoid unnecessary
  casts for nullable primitive values.

## 0.5.5

- Generated typed query plans now include the metadata needed by the SQLite
  native filter path for supported generated collection filters.

## 0.5.4

- Generated `toDocument` maps now omit the collection id field, keeping ids in
  the storage key path instead of duplicating them inside document payloads.
- Generated native list writers now use the model list directly when no value
  conversion is needed, avoiding redundant list copies during typed inserts.

## 0.5.3

- Updated generated compact binary serializers so ids stay in the collection
  key instead of the document payload.

## 0.5.2

- Updated the annotations dependency constraint to `^0.5.2`.
- Generated native typed readers now use the direct native string-list reader
  for non-nullable `List<String>` fields.

## 0.5.1

- Generated native MDBX typed writers now keep collection ids in the native key
  path instead of duplicating them inside compact document payloads.
- Generated native typed readers now hydrate ids from the native document key.

## 0.5.0

- Updated the annotations dependency constraint and package documentation to
  the coordinated `0.5.0` release line.
- Cached native list lengths in generated typed hydration loops.
- Allowed generated schemas to hydrate immutable explicit-id collection models
  through constructor parameters and omit auto-increment setters when `id` is
  final.

## 0.4.0

- Generated schema-specific compact document writers and readers for the
  optimized typed MDBX path.
- Updated the annotations dependency constraint to `^0.4.0`.

## 0.2.5

- Generated schema-specific typed binary document serializers for Cindel's
  `binary-v2` storage format.
- Emitted binary storage type metadata for generated fields.
- Generated direct binary document hydration readers for schema-backed models.

## 0.2.4

- Restored analyzer 9 downgrade compatibility while keeping analyzer 10+
  field-origin handling, so pub.dev downgrade analysis and Riverpod generator
  consumers can resolve the same package line.

## 0.2.3

- Generated collection-level composite index metadata and equality where
  helpers.
- Generated multi-entry list membership where helpers for primitive list
  indexes.

## 0.2.2

- Generated binary document serializers alongside the existing JSON document
  serializers.
- Emitted binary fields in the same sorted order used by the native schema
  manifest, so MDBX can index and read generated objects directly.
- Relaxed the `analyzer` constraint to support both the Riverpod-compatible
  analyzer 9 line and the current analyzer 10+ pub.dev scoring line.

## 0.2.1

- Expanded the `analyzer` dependency constraint to support the current stable
  analyzer release line reported by pub.dev.
- Replaced deprecated analyzer field-origin checks used by the generator.

## 0.2.0

- Prepared the generator package for the coordinated `0.2.0` Cindel release
  line.
- Updated the annotations dependency constraint to `^0.2.0`.
- Updated package usage snippets to reference the `0.2.0` release line.

## 0.1.11

- Moved the package back to normal pub.dev versioning after the development
  preview line.
- Updated the Cindel annotations dependency to the normal `0.1.7` release
  line.

## 0.1.10

- Prepared the first pub.dev development preview.
- Switched the Cindel annotations dependency to the hosted development
  preview constraint.
- Updated the Cindel annotations dependency for the next development preview.
- Removed dates from changelog headings so pub.dev renders version labels cleanly.
- Added a package example page for pub.dev.
- Added a library-level documentation comment for dartdoc/pub.dev analysis.

## 0.1.9

- Added pub.dev-oriented package metadata and documentation.

## 0.1.8

- Added generator support for index variants and the current typed query
  pipeline.
