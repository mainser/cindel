# Cindel Storage Migration Framework

This document records the internal migration framework added before Cindel
starts writing optimized binary documents or changing the production MDBX
layout.

The framework is currently native/internal. It is not exposed through the public
Dart API or FFI symbols yet.

## Goals

- Persist the current storage layout version.
- Persist the current document format version.
- Plan layout or document-format changes before writing data.
- Fail closed when a requested change would rewrite stored data without an
  explicit migration.
- Rebuild index entries as a first-class native operation.
- Verify migrated storage before treating a migration as complete.

## Current Versions

| Backend | Storage layout | Document format |
| --- | --- | --- |
| SQLite | `sqlite-v1` | `json-v1` |
| MDBX | `mdbx-v1` | `json-v1` |
| MDBX layout prototype | `mdbx-v2` | `json-v1` |

The planned binary document format is `binary-v1`.

## Migration Planning

The native storage layer can compare current metadata with a target:

```text
current: mdbx-v1 + json-v1
target:  mdbx-v2 + binary-v1
```

If either layout or document format differs, the plan requires explicit
migration actions:

- rewrite storage layout,
- rewrite document format.

Until those execution paths exist, applying such a plan returns an error. This
prevents accidental automatic rewrites when the default format changes later.

## Index Rebuild

Index rebuild is now a native storage operation. The caller supplies the
collection and the full document/index entry set that should become the source
of truth. The storage backend clears old index entries for that collection and
inserts the supplied index entries transactionally.

This keeps future migrations from relying on many independent document rewrites
just to refresh indexes.

## Verification

The native verification helper records:

- storage metadata,
- document counts per collection,
- schema versions,
- collection revisions,
- selected equality and range index checks.

The intent is to use these checks after explicit migrations and index rebuilds
before marking a migrated database as valid.

## Safety Rules

- Opening current databases remains backward compatible.
- Adding metadata does not rewrite document bytes.
- Layout or document-format changes are planned but refused until explicit
  migration execution exists.
- Index rebuilds validate document existence before creating index entries.

## Remaining Work

Before optimized storage can ship, Cindel still needs:

- explicit execution for layout/document-format migrations,
- backup and rollback guidance,
- generated binary serializer integration,
- compatibility handling for existing JSON documents,
- public Dart/FFI access once the internal surface is stable.
