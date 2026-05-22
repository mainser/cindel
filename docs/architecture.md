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
