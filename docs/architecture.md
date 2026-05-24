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
fit the registered schema. Manual `CindelDocument` values use GenericDocumentV1,
and the hot FFI paths now use CindelWireV1 for ids, indexed writes, filters,
schema metadata, native query plans, scalar/projection results, and watcher
change sets. SQLite remains the compatibility backend, but it stores the current
manual and schema metadata formats instead of the early JSON preview records.

## Watcher and async boundaries

Committed native write operations produce compact CindelWireV1 change sets with
the collection name, post-commit collection revision, and affected document ids.
Dart watchers use those change sets to wake local subscriptions and skip
unrelated document refreshes. Periodic polling through `pollInterval` remains the
compatibility fallback for changes made by other database handles or future
process/isolate owners that do not share a direct notification channel yet.

The isolate-pool design should keep ownership explicit:

- A native engine handle is owned by one Dart isolate at a time.
- Write requests are serialized through the owning isolate or a future native
  worker queue; handles are not shared concurrently across isolates.
- Read requests can be moved to worker isolates only when each worker owns its
  own native handle or when the Rust side exposes a thread-safe request queue.
- Async request and response buffers should stay CindelWireV1 byte buffers so
  isolates pass transferable binary data instead of JSON maps.
- Watcher notifications should cross isolate boundaries as change-set buffers,
  with Dart hydration left to the subscribed isolate.

Storage format migration tooling is intentionally deferred until the optimized
MDBX path settles.
