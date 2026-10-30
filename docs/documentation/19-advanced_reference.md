# Advanced Reference

This guide covers runtime setup for Dart tools, troubleshooting incompatible
libraries, and choosing public APIs for reusable application code.

Use the public package import:

```dart
import 'package:cindel/cindel.dart';
```

Avoid imports from `package:cindel/src/...`; they are not the application API.

## Runtime Compatibility

For Flutter applications, include compatible versions of `cindel` and
`cindel_flutter_libs`, with `cindel_generator` in development dependencies.
After upgrading the generator, regenerate all models:

```sh
dart run build_runner build --delete-conflicting-outputs
```

If opening reports a native ABI mismatch, the app loaded a library that does
not match its Dart package. Cindel 1.1.6 requires ABI 40. To resolve it:

1. Check that the Cindel packages use compatible versions.
2. Remove an old `CINDEL_NATIVE_LIBRARY` override if you want to use the
   packaged Flutter runtime.
3. Rebuild the application so it includes the matching runtime.
4. If you supply your own binary, rebuild it from the matching Cindel source.

An ABI mismatch does not require deleting user data or changing the migration
plan. The generated models and database calls remain the same on all backends.

## Native Build Hooks

Flutter apps normally receive the runtime from `cindel_flutter_libs`. A pure
Dart application or tool can use a prebuilt native library by setting
`CINDEL_NATIVE_LIBRARY` to its absolute path before starting the program.

For example, in PowerShell, replacing the path with your matching Windows DLL:

```powershell
$env:CINDEL_NATIVE_LIBRARY = 'C:\path\to\cindel_native.dll'
dart run bin/main.dart
```

For a source build, enable the optional build hook in the consuming project's
`pubspec.yaml`:

```yaml
hooks:
  user_defines:
    cindel:
      build_native_assets: true
```

The hook is disabled by default. Enabling it requires Rust and the native
compiler toolchain for the target platform. Your models and collection calls
stay the same whichever way the library is supplied.

The native override and build hook do not configure Web. Flutter Web uses the
browser runtime bundled by `cindel_flutter_libs`; follow the [Web setup](13-web.md).

## Reusing Code With Generated Schemas

Use `typedCollection` when a helper receives a schema instead of referring to
one specific generated collection getter:

```dart
Future<List<T?>> loadByIds<T>(
  CindelDatabase db,
  CindelCollectionSchema<T> schema,
  Iterable<int> ids,
) {
  return db.typedCollection(schema).getAll(ids);
}

final users = await loadByIds(db, UserSchema, selectedIds);
```

The schema must be registered when opening the database. Where the model is
known, a generated getter such as `db.users.getAll(selectedIds)` is simpler.

## Choosing An API For Maintenance And Dynamic Features

| Task | Public API and guide |
| --- | --- |
| Build a search from user-selected fields | [`CindelFilter` and persisted field names](07-filters.md#dynamic-filters). |
| Return selected fields for a table | [Property projections](08-projections_and_aggregates.md). |
| Inspect model fields and indexes | [Generated schema metadata](15-schema_metadata.md). |
| Process a large collection by ID | [`documentIdsPage` and typed `getAll`](14-backup_and_advanced_helpers.md#documentidspage). |
| Export or restore a database | [`CindelBackup`](14-backup_and_advanced_helpers.md#cindelbackup). |
| Upgrade existing stored data | [`CindelMigrationPlan`](11-migrations.md). |

For dynamic field names, use the persisted names specified by `@Name` when
present. For normal model reads and writes, keep using generated typed helpers.
