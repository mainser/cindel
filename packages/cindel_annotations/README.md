# cindel_annotations

Public annotations and shared schema types for Cindel, an ultra-fast,
lightweight NoSQL local database for Flutter and Dart apps.

Maintainer: Alain Ramirez <nolbertrg@gmail.com>

Repository: <https://github.com/mainser/Cindel>

## What It Provides

- `@Collection` for persisted root models.
- `@Embedded` for nested value objects.
- `@Index` and `@index` for indexed fields.
- `@Enumerated` for enum persistence strategies.
- `@ignore` for transient fields.
- `Id` and `autoIncrement` for generated native IDs.
- Shared index and enum option types used by `cindel` and
  `cindel_generator`.

Most applications depend on `cindel` directly, which re-exports the public
annotation API. Generator and tooling packages depend on this package to share
schema metadata without pulling in the native runtime.

## Publishing Status

This package is still pre-1.0.0 and keeps `publish_to: none` until the first
coordinated Cindel pub.dev release.
