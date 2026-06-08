# Changelog

## 0.5.4

- Added the `@Name` annotation for persisted collection and field names.
- Added `replace` metadata to `@Index` and `CompositeIndex` for unique
  replace-index upserts.

## 0.5.3

- Updated annotation documentation and examples to use `dbId` as the Cindel
  collection id field, leaving `id` available for API/domain identifiers.

## 0.5.2

- Expanded package documentation with clearer usage guidance for annotations,
  indexes, ids, enum persistence, and package roles.

## 0.5.0

- Updated the annotations package to the coordinated Cindel `0.5.0` release
  line.

## 0.4.0

- Aligned the annotations package with the coordinated Cindel `0.4.0` release
  line.

## 0.2.1

- Added `CompositeIndex` metadata for collection-level composite indexes.
- Added `CindelIndexType.multiEntry` for primitive list membership indexes.

## 0.2.0

- Prepared the annotations package for the coordinated `0.2.0` Cindel release
  line.
- Updated release documentation to remove development-preview wording.

## 0.1.7

- Moved the package back to normal pub.dev versioning after the development
  preview line.

## 0.1.6

- Prepared the first pub.dev development preview.
- Removed dates from changelog headings so pub.dev renders version labels cleanly.
- Added a package example page for pub.dev.
- Added a library-level documentation comment for dartdoc/pub.dev analysis.

## 0.1.5

- Added pub.dev-oriented package metadata and documentation.

## 0.1.4

- Added public annotation support for expanded schema, index, and embedded
  object features.
