# Cindel

Cindel is an experimental Flutter-first local database library inspired by the architectural pattern that made Isar compelling: a clean Dart API, code generation, a native Rust core, and a narrow FFI bridge.

This repository starts intentionally small. The first milestone is not a complete database, but a working vertical slice:

Dart API -> FFI -> Rust core -> storage backend -> Rust -> FFI -> Dart

## Packages

- `packages/cindel`: public Dart API, FFI bridge, and native Rust core.
- `packages/cindel_annotations`: annotations and shared public types such as `@collection`, `@index`, `Id`, and `autoIncrement`.
- `packages/cindel_generator`: future code generator for schemas, serializers, collection accessors, and query builders.
- `examples/cindel_todo`: placeholder Flutter example app.

## Initial Direction

- Public API: Dart.
- Native core: Rust.
- Bridge: Dart FFI with a small C ABI.
- MVP storage backend: SQLite via Rust, hidden behind an internal storage trait.
- Advanced backend candidate: libmdbx.
- Code generation: `source_gen`, `build_runner`, and `analyzer`.
- Web support: deferred until the native MVP is solid.

## MVP Goal

```dart
final db = await Cindel.open(directory: dir.path);
await db.put('users', 1, {'name': 'Noel'});
final user = await db.get('users', 1);
await db.close();
```

After this vertical slice works, the next step is annotations and generated schemas.
