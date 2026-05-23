# cindel_annotations

Public annotations and shared schema types for Cindel, an ultra-fast,
lightweight NoSQL local database for Flutter and Dart apps.

## What It Provides

- `@Collection` for persisted root models.
- `@Embedded` for nested value objects.
- `@Index` and `@index` for indexed fields.
- `CompositeIndex` for collection-level composite indexes.
- `CindelIndexType.multiEntry` for primitive list membership indexes.
- `@Enumerated` for enum persistence strategies.
- `@ignore` for transient fields.
- `Id` and `autoIncrement` for generated native IDs.
- Shared index and enum option types used by `cindel` and
  `cindel_generator`.

Most applications depend on `cindel` directly, which re-exports the public
annotation API. Generator and tooling packages depend on this package to share
schema metadata without pulling in the native runtime.

## Release Status

This package is still pre-1.0.0. The `0.2.0` package line is the first normal
release line after the coordinated Cindel development previews.
