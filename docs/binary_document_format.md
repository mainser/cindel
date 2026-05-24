# Cindel Binary Document Format

This document records the first Cindel binary object format. MDBX uses this
format internally for schema-backed documents that match the registered
collection schema. Manual documents use GenericDocumentV1, and the current hot
FFI paths use CindelWireV1 binary payloads instead of the early JSON envelopes.
After the anti-JSON cleanup, the default native runtime path no longer depends
on `serde_json`; JSON output is limited to optional benchmark reporting.

## Goals

- Replace JSON in the generated typed hot path.
- Let native code read one field by offset without decoding the whole object.
- Keep the format versioned so later 1.0 migration tooling has a stable
  validation point.
- Support the field shapes Cindel already supports in generated models.

## Scope

The format is intended for generated typed models first. Manual map-style APIs
now use GenericDocumentV1 for document bytes, while schema-backed MDBX writes use
the generated binary document format directly.

This stage does not change:

- the public Dart API,
- the public shape of the FFI-backed Dart APIs.

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
| 10 | object/map | sorted named value records in dynamic section |

Primitive lists, embedded objects, and embedded lists use dynamic value records.
Each record stores the value kind, null flag, payload length, and payload.

## Limits

The initial maximum object size is 64 MiB. This keeps the first format bounded
and gives future migration tooling a simple validation rule.

Double values must be finite. `NaN` and infinities are rejected by the prototype
because they are not safe for deterministic indexed comparison.

## Validation

The Rust implementation currently proves:

- bool, int, double, String, DateTime, Duration, primitive lists, enums,
  nullable values, embedded objects, and embedded lists can round-trip without
  JSON.
- A fixed field can be read by field-slot offset while an unrelated dynamic
  field contains invalid bytes.
- Invalid headers and non-finite doubles fail closed.

## Adoption Notes

MDBX stores binary documents for registered schema collections. Unknown fields
are rejected instead of being stored through a JSON compatibility fallback,
because Cindel is still pre-1.0 and no external database migration promise has
been made yet.

Manual writes without a registered schema are stored as GenericDocumentV1 raw
payloads. SQLite remains the compatibility backend and stores the same current
manual and schema metadata formats.

The generated FFI hot path now writes and reads typed fields through binary
native handles where MDBX planning supports the query shape.

Before this format is the only native path, Cindel still needs:

- a final decision on how much of the manual map API should remain optimized
  after generated typed FFI becomes the hot path,
- public migration tooling once the optimized storage format is close enough to
  1.0.
