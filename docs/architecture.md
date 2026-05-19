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
