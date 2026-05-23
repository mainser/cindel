# Cindel Architecture Notes

See `ROADMAP.md` for the current project direction.

Short version:

```text
Flutter App
   |
   v
Dart API
   |
   v
Generated schemas / serializers / queries
   |
   v
Dart FFI
   |
   v
Rust Core
   |
   v
Storage backend: MDBX by default, SQLite as explicit fallback
```

Backend decision notes, benchmark evidence, and platform limits live in
`docs/backend_evaluation.md`.

The planned generated binary document format is documented in
`docs/binary_document_format.md`. It is not a shipped storage format yet; it is
the design target for the native MDBX performance work.

The internal storage migration metadata and verification framework is
documented in `docs/storage_migration_framework.md`.
