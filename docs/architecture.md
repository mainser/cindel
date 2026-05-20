# Cindel Architecture Notes

See `ROADMAP.md` for the detailed starting guide.

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
Storage backend: SQLite first, libmdbx later
```

Phase 8 benchmark and backend adoption notes live in
`docs/backend_evaluation.md`.
