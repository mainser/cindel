# Cindel Binary Document Format

This document records the first Cindel binary object format design. The format
is implemented as an internal Rust prototype and is not yet used by the public
Dart API or by the production storage backends.

## Goals

- Replace JSON in the generated typed hot path.
- Let native code read one field by offset without decoding the whole object.
- Keep the format versioned before any storage migration work begins.
- Support the field shapes Cindel already supports in generated models.

## Scope

The format is intended for generated typed models first. Manual map-style APIs
can keep using JSON until a compatibility path is chosen.

This stage does not change:

- the public Dart API,
- the FFI symbols,
- the production MDBX or SQLite storage format,
- prebuilt native binaries.

## Object Layout

All integers in the document format are little-endian.

```text
header
field slot table
static section
dynamic section
```

Header:

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 4 | Magic bytes: `CDBF` |
| 4 | 2 | Format version: `1` |
| 6 | 2 | Header length |
| 8 | 2 | Field count |
| 10 | 2 | Reserved |
| 12 | 4 | Static section length |
| 16 | 4 | Dynamic section length |
| 20 | 4 | Total document length |

Each field has a fixed 16-byte slot:

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 1 | Field kind |
| 1 | 1 | Flags |
| 2 | 2 | Reserved |
| 4 | 4 | Static section offset |
| 8 | 4 | Dynamic section offset |
| 12 | 4 | Dynamic payload length |

Null values set the null flag and do not reserve static or dynamic payload
space.

## Field Kinds

| Tag | Kind | Storage |
| ---: | --- | --- |
| 0 | null | slot flag only |
| 1 | bool | 1 byte in static section |
| 2 | int | 8 bytes in static section |
| 3 | double | 8 bytes in static section |
| 4 | String | UTF-8 bytes in dynamic section |
| 5 | DateTime | microseconds as 8 bytes in static section |
| 6 | Duration | microseconds as 8 bytes in static section |
| 7 | list | encoded dynamic value records |
| 8 | enum | UTF-8 enum value in dynamic section |
| 9 | embedded object | nested binary document in dynamic section |

Primitive lists, embedded objects, and embedded lists use dynamic value records.
Each record stores the value kind, null flag, payload length, and payload.

## Limits

The initial maximum object size is 64 MiB. This keeps the first format bounded
and gives future migration code a simple validation rule.

Double values must be finite. `NaN` and infinities are rejected by the prototype
because they are not safe for deterministic indexed comparison.

## Validation

The Rust prototype currently proves:

- bool, int, double, String, DateTime, Duration, primitive lists, enums,
  nullable values, embedded objects, and embedded lists can round-trip without
  JSON.
- A fixed field can be read by field-slot offset while an unrelated dynamic
  field contains invalid bytes.
- Invalid headers and non-finite doubles fail closed.

## Adoption Notes

Before this format can become a storage format, Cindel still needs:

- explicit execution for storage/document migrations,
- backup and rollback guidance,
- generated Dart writer/reader integration,
- a compatibility path for existing JSON documents.
