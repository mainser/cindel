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

The generated binary document format is documented in
`docs/binary_document_format.md`. MDBX uses it for schema-backed documents that
fit the registered schema, while SQLite remains on JSON and the public FFI path
still returns JSON during the transition.

Storage format migration tooling is intentionally deferred until the optimized
MDBX path settles.
