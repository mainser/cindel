# Backend Evaluation

This note records the phase 8 baseline for keeping Cindel's public Dart API
stable while the native storage backend remains interchangeable.

## Current Decision

Cindel now uses MDBX as the default backend for new databases. SQLite remains
available as an explicit secondary backend through
`backend: CindelStorageBackend.sqlite`.

Reasons:

- The public Dart API must not expose SQLite or MDBX concepts.
- MDBX passed the shared Rust storage contracts and the Dart package behavior
  suite.
- Windows and Android prebuilt binaries include MDBX support.
- SQLite remains selectable as a secondary backend for compatibility,
  debugging, and benchmark comparison.

## Anti-JSON Optimization Track

JSON-00 established the measured baseline and exact JSON inventory for the
next performance line. The benchmark output is stored locally as CSV under
`docs/local_benchmarks/` because those runs are machine-specific and intentionally
ignored by git. The refreshed inventory now maps every known runtime JSON path
to its planned removal stage: id lists and basic batches in JSON-02, index
values and write metadata in JSON-03, native filters in JSON-04, manual
documents in JSON-05, schema/reverse-index metadata in JSON-06, and projection
or aggregate rows in JSON-07.

JSON-01 added the internal CindelWireV1 codec foundation in Dart and Rust. It
does not change public Dart APIs, native ABI symbols, storage behavior, or
prebuilt native libraries. The codec gives later stages a shared binary contract
for id lists, index values, scalar results, document write batches,
nullable/list/object cells, projection rows, schema manifests, and reverse
index entry lists. Dart and Rust now share byte-for-byte fixture tests plus
malformed-payload checks for truncation, invalid tags, invalid UTF-8, invalid
bool bytes, trailing bytes, and unsafe native item counts.

JSON-02 moved runtime id-list FFI traffic onto CindelWireV1. Dart now encodes
ids with `encodeIdList`, native code decodes ids with `decode_id_list`, and
native id results return through `encode_id_list`. This covers document id
scans, manual `getMany`, generated `getManyStored`, `deleteMany`, indexed
equality/range id results, native filter candidate/result ids, projection
candidate ids, and aggregate candidate ids. Generated binary document batch
writes also reuse CindelWireV1 `DocumentWriteBatch`, removing the previous
one-off stored-document batch codec. The native ABI is now 10 because existing
FFI id-list symbols changed their payload contract from JSON arrays to binary
buffers. Windows, Android, and Linux prebuilt native libraries were regenerated
for the ABI 10 contract.

The next backend-relevant stage is JSON-03. It should move index values, index
entries, indexed document writes, unique checks, and stable index hashing onto
canonical binary payloads. JSON-02 still leaves manual document JSON, filter
AST JSON, schema/reverse-index metadata JSON, and projection/aggregate result
JSON for later stages.

The JSON-00 large benchmark showed SQLite winning the simple single-get
microbenchmark while MDBX leads the native indexed and batch-oriented routes.
After JSON-02, re-benchmark `get`, `getMany`, indexed queries, and `deleteMany`
against the JSON-00 baseline, with special attention to per-get transaction,
key-buffer, and FFI overhead before assuming storage engine latency is the
cause.

## Candidate: libmdbx

`libmdbx` is a strong candidate for the advanced backend because it is an
embedded transactional key-value store and has Rust bindings available through
the `libmdbx` crate. The crate documentation currently describes it as Rust
bindings for libmdbx and exposes database/cursor/table APIs.

Sources checked on 2026-05-20:

- https://docs.rs/libmdbx
- https://docs.rs/crate/libmdbx/latest

Sources checked on 2026-05-22 for MDBX-01:

- https://docs.rs/crate/libmdbx/latest
- https://docs.rs/crate/mdbx-sys/latest/source/Cargo.toml.orig
- https://rust-lang.github.io/rust-bindgen/requirements.html

Open questions before integration:

- Windows build reliability with the same toolchain used by Flutter native
  assets.
- Best data layout for collections, documents, index entries, schema metadata,
  and revision counters.
- Transaction ergonomics for keeping documents and indexes atomic.
- Whether typed table APIs or raw key-value tables are the cleaner fit for
  generated schemas.
- Binary size and compile-time impact versus SQLite bundled mode.

## MDBX-01 - Dependency and Build Feasibility

Status: passed on Windows after installing LLVM/libclang.

Implemented:

- Added an optional native Cargo feature named `mdbx`.
- Added `libmdbx = 0.6.6` as an optional dependency behind that feature.
- Added a small MDBX build probe that opens an MDBX database directory only
  when the `mdbx` feature is enabled.
- Kept SQLite as the default and only runtime backend.

Validation:

```powershell
cargo test --manifest-path packages/cindel/native/Cargo.toml
```

Result: passed. The default native build remains SQLite-only.

```powershell
cargo test --manifest-path packages/cindel/native/Cargo.toml mdbx
```

Initial result: blocked on Windows because `mdbx-sys` runs `bindgen`, and
`bindgen` requires `libclang`. The local machine did not have `clang.dll` or
`libclang.dll` available, and `LIBCLANG_PATH` was not set.

Final Windows result after installing LLVM:

```powershell
$env:LIBCLANG_PATH = "C:\Program Files\LLVM\bin"
cargo test --manifest-path packages/cindel/native/Cargo.toml mdbx
```

Result: passed. `libmdbx` and `mdbx-sys` compile, and the probe opens an MDBX
database directory.

Next requirement before MDBX-02:

- Keep LLVM/libclang available in every native build environment that enables
  the `mdbx` feature.
- Start MDBX-02 with a storage layout design and a minimal `StorageEngine`
  implementation behind the same feature gate.

## MDBX-03 Key Layout Spike

The MDBX key layout spike is implemented as pure Rust key encoding under the
native storage module. It does not open MDBX and does not change the default
SQLite backend.

Planned MDBX tables:

- `documents`: `(collection, document_id)` -> raw document bytes.
- `indexes`: `(collection, index_name, encoded_index_value, document_id)` ->
  empty bytes.
- `unique_indexes`: `(collection, index_name, encoded_index_value)` ->
  document id bytes.
- `id_counters`: `collection` -> next id.
- `collection_revisions`: `collection` -> revision.
- `schema_collections`: `collection` -> schema metadata JSON.

The key spike proves:

- Signed integers sort lexicographically in numeric order by flipping the sign
  bit before big-endian encoding.
- Finite doubles sort lexicographically in numeric order by using sortable IEEE
  754 bytes. Non-finite doubles remain rejected, matching the current SQLite
  path.
- String segments preserve UTF-8 lexicographic ordering and escape NUL bytes so
  compound key boundaries remain unambiguous.
- Index value kind tags keep bool, int, double, and string values from
  colliding.
- Equality prefixes and inclusive range boundaries can support
  `query_index_equal` and `query_index_range`.

String case-insensitive and word-index normalization remains in the existing
Dart index-entry path, so MDBX will receive the same normalized `IndexValue`
entries SQLite receives today.

## MDBX-04 Minimal Storage Prototype

MDBX-04 added the first feature-gated `MdbxStorage` implementation behind the
native `mdbx` Cargo feature. SQLite was still the default backend at that
stage.

Implemented prototype surface:

- Opens a persistent MDBX directory.
- Uses a test-only temporary directory for the existing `:memory:` sentinel.
- Writes indexed documents.
- Reads documents by collection/id.
- Lists document ids by collection.
- Scans equality and inclusive range index keys.
- Tracks collection revisions.
- Registers schemas with a minimal compatible path.
- Lets the benchmark run `sqlite`, `mdbx`, or `all` from one binary.

Still out of scope for this prototype:

- Public explicit MDBX transactions.
- Public migration tooling.
- Native unique-index enforcement.
- Dart API backend selection.

Validation:

```powershell
cargo test --manifest-path packages/cindel/native/Cargo.toml mdbx
```

Result: passed. MDBX prototype tests can write, read, and query indexed
documents.

```powershell
cargo run --release --manifest-path packages/cindel/native/Cargo.toml --features benchmarks --bin cindel_bench -- --backend all --documents 1000 --query-repeats 100
```

Sample Windows output:

```text
backend,operation,items,total_ms,ops_per_second
sqlite,put_indexed,1000,2813.211,355.47
sqlite,get,1000,7.991,125139.22
sqlite,query_equal,100,14.988,6671.96
sqlite,query_range,100,18.986,5266.93
mdbx,put_indexed,1000,963.885,1037.47
mdbx,get,1000,6.135,162988.56
mdbx,query_equal,100,0.666,150240.38
mdbx,query_range,100,1.227,81506.24
```

These numbers are a smoke-test sample only. MDBX-05 will run the formal
comparison and decide whether the win is meaningful enough for default-backend
adoption.

## MDBX-05 Benchmark Parity and First Decision

MDBX-05 expands the benchmark so both SQLite and MDBX measure the same core
operations:

- Database open.
- Schema registration.
- Indexed single-document writes.
- Point reads.
- Indexed equality queries.
- Indexed range queries.
- Indexed batch writes.
- Batch deletes.

Windows validation command:

```powershell
cargo run --release --manifest-path packages/cindel/native/Cargo.toml --features benchmarks --bin cindel_bench -- --backend all --documents 10000 --query-repeats 1000
```

Windows result:

```text
backend,operation,items,total_ms,ops_per_second
sqlite,open,1,40.916,24.44
sqlite,register_schemas,1,2.354,424.72
sqlite,put_indexed,10000,38624.093,258.91
sqlite,get,10000,92.725,107845.32
sqlite,query_equal,1000,1554.399,643.34
sqlite,query_range,1000,1495.375,668.73
sqlite,put_many_indexed,10000,35423.763,282.30
sqlite,delete_many,10000,36868.461,271.23
mdbx,open,1,8.711,114.79
mdbx,register_schemas,1,1.132,883.16
mdbx,put_indexed,10000,20015.174,499.62
mdbx,get,10000,50.285,198868.04
mdbx,query_equal,1000,5.753,173831.42
mdbx,query_range,1000,53.473,18701.13
mdbx,put_many_indexed,10000,43676.842,228.95
mdbx,delete_many,10000,39023.506,256.26
```

Observed Windows ratios:

- Open: MDBX about 4.7x faster.
- Schema registration: MDBX about 2.1x faster.
- Indexed single writes: MDBX about 1.9x faster.
- Point reads: MDBX about 1.8x faster.
- Equality index queries: MDBX about 270x faster.
- Range index queries: MDBX about 28x faster.
- Batch indexed writes: SQLite about 1.2x faster.
- Batch deletes: SQLite about 1.1x faster.

Linux validation:

- Local WSL validation was attempted with `wsl.exe --status`, but the machine
  returned `Wsl/EnumerateDistros/Service/E_ACCESSDENIED`.
- Linux release-mode benchmark remains a future platform-hardening task because
  Linux binaries are not published in the current Android/Windows package
  line.

First decision:

- Continue to MDBX-06 storage parity. MDBX clearly exceeds the adoption
  threshold on indexed queries and is close to the indexed write threshold on
  Windows.
- Do not switch the default backend yet. Batch writes and deletes are still
  slower in this prototype, Linux numbers are still missing, and parity tests
  need to prove the full `StorageEngine` contract.

## MDBX-06 Storage Parity

MDBX-06 adds a shared native `StorageEngine` contract suite and runs it against
both SQLite and MDBX.

Validated parity surface:

- CRUD by collection/id.
- Ordered `get_many` results with missing ids.
- Per-collection document id scans.
- Per-collection revision bumps.
- Id allocation and manual-id counter advancement.
- Equality and range index queries.
- Index replacement and cleanup during updates/deletes.
- Batch indexed writes and deletes.
- Rollback for failed batch writes.
- Schema registration, additive versioning, incompatible schema rejection, and
  index option metadata.
- Unique index enforcement.
- Case-insensitive, hash, and words index metadata acceptance. Dart still
  normalizes those indexed values before they reach native storage.

Validation command:

```powershell
cargo test --manifest-path packages/cindel/native/Cargo.toml
```

Result:

- `44 passed; 0 failed` on Windows with LLVM/libclang installed.

Remaining validation gates at this point:

- Full Dart parity, prebuilt packaging, and CI matrix validation are still
  required before promoting MDBX in public package docs.

## MDBX-07 Transaction Model Integration

MDBX-07 adds explicit transaction support to `MdbxStorage` without storing
self-referential MDBX transaction handles.

Internal representation:

- Read transactions use an active read marker to reject nested transactions and
  writes.
- Write transactions use an internal write log.
- `commit_transaction` applies the staged operations inside one MDBX write
  transaction.
- `rollback_transaction` discards the staged operations.

Validated transaction surface:

- Explicit write transaction commit.
- Explicit write transaction rollback.
- Writes inside read transactions are rejected.
- Nested transactions are rejected.
- Id allocations inside rolled-back write transactions do not advance persisted
  counters.
- Staged writes, indexes, counters, and revisions are only persisted after a
  successful commit.

Validation command:

```powershell
cargo test --manifest-path packages/cindel/native/Cargo.toml
```

Result:

- `46 passed; 0 failed` on Windows with LLVM/libclang installed.

Next step:

- MDBX-08 exposes backend selection so Dart-level MDBX tests can run through
  the public API.

## MDBX-08 FFI and Dart Backend Option

MDBX-08 exposes backend selection through the public Dart API while keeping
SQLite as the default.

Public API:

- `CindelStorageBackend.sqlite`
- `CindelStorageBackend.mdbx`
- `backend:` on `Cindel.open`
- `backend:` on `Cindel.openInMemory`
- `backend:` on `CindelDatabase.open`
- `backend:` on `CindelDatabase.openInMemory`

FFI:

- Existing `cindel_open` remains the SQLite/default open path.
- Added `cindel_open_with_backend(directory, len, backend)`.
- Backend ids:
  - `0 = sqlite`
  - `1 = mdbx`
- Unsupported or unavailable backends return a null handle and surface as a
  Dart `StateError`.

Validation commands:

```powershell
cargo test --manifest-path packages/cindel/native/Cargo.toml
cargo test --manifest-path packages/cindel/native/Cargo.toml
cargo build --manifest-path packages/cindel/native/Cargo.toml
dart analyze packages/cindel
dart test packages/cindel
```

MDBX-specific Dart validation used a locally built native library:

```powershell
$env:CINDEL_NATIVE_LIBRARY = (Resolve-Path "$env:TEMP\cindel_cargo_target_codex\debug\cindel_native.dll").Path
$env:CINDEL_TEST_MDBX = "1"
dart test packages\cindel\test\native_bindings_test.dart packages\cindel\test\transactions_test.dart -r expanded
```

Results:

- Rust default: `40 passed; 0 failed`.
- Rust with MDBX: `46 passed; 0 failed`.
- Dart analyze: `No issues found`.
- Dart package default: `78 passed; 2 skipped`.
- Dart MDBX targeted: `25 passed; 0 failed`.

Remaining validation gates at this point:

- Full Dart behavior parity across the broader feature matrix belongs to
  MDBX-09.
- Linux release-mode benchmark validation remains a future hardening task for
  the Linux package line.

## MDBX-09 Full Dart Behavior Parity

MDBX-09 parameterizes the Cindel package tests so the same Dart behavior suite
can run against either backend.

Implemented:

- Added a test backend selector driven by `CINDEL_TEST_BACKEND`.
- Reused the existing package tests across SQLite and MDBX for manual CRUD,
  typed CRUD, ids, batch operations, query builders, indexes, watchers,
  transactions, schema versions, and backend behavior.
- Fixed MDBX staged write transactions so reads inside the same Dart write
  transaction see pending puts/deletes before commit.
- Fixed MDBX staged indexed queries so query builders can see pending writes
  inside the same Dart write transaction.
- Shared same-directory MDBX environments inside the process so multiple Dart
  database handles can observe each other through watchers.

Validation commands:

```powershell
dart analyze packages/cindel
dart test packages/cindel -r expanded
```

MDBX validation used a locally built native library:

```powershell
$env:CINDEL_NATIVE_LIBRARY = (Resolve-Path "$env:TEMP\cindel_cargo_target_codex\debug\cindel_native.dll").Path
$env:CINDEL_TEST_BACKEND = "mdbx"
$env:CINDEL_TEST_MDBX = "1"
dart test packages\cindel -r expanded
```

Results:

- Rust with MDBX: `47 passed; 0 failed`.
- Dart package with SQLite/default: `79 passed; 2 skipped`.
- Dart package with MDBX: `81 passed; 0 failed`.

Remaining validation gates at this point:

- Prebuilt binaries must be rebuilt with MDBX support before consumers can use
  the MDBX backend without a local Rust toolchain.
- Linux release-mode benchmark validation remains a future hardening task for
  the Linux package line.

## MDBX-10 Prebuilt Binary and Platform Packaging

MDBX-10 rebuilds the consumer prebuilt binaries for the platforms currently
available in this workspace: Windows and Android.

Implemented:

- Updated the Windows prebuilt script to build `cindel_native.dll` with the
  native `mdbx` Cargo feature enabled.
- Updated the Android prebuilt script to build `arm64-v8a`, `armeabi-v7a`, and
  `x86_64` libraries with the native `mdbx` Cargo feature enabled.
- Switched the Android script to a direct NDK clang/cargo build path so bindgen
  and the linker receive explicit Android target, sysroot, and include paths on
  Windows hosts.
- Added a local `mdbx-sys` patch for Windows-hosted Android cross-compiles:
  Android bindgen value layout is forced to libmdbx's `size_t`-based value
  struct, host Windows system libraries are linked only for Windows targets,
  and Android x86_64 disables builtin CPU detection that references
  unavailable PIC symbols.
- Regenerated the checked-in Windows and Android binaries in
  `packages/cindel_flutter_libs`.

Validation commands:

```powershell
.\tool\prebuilt\build_windows.ps1
.\tool\prebuilt\build_android.ps1
cargo test --manifest-path packages/cindel/native/Cargo.toml
cargo test --manifest-path packages/cindel/native/Cargo.toml
dart analyze packages/cindel
dart test packages/cindel -r expanded
```

MDBX Dart validation used the regenerated Windows prebuilt DLL:

```powershell
$env:CINDEL_NATIVE_LIBRARY = (Resolve-Path "packages\cindel_flutter_libs\windows\cindel_native.dll").Path
$env:CINDEL_TEST_BACKEND = "mdbx"
$env:CINDEL_TEST_MDBX = "1"
dart test packages\cindel -r expanded
```

Consumer packaging validation:

```powershell
cd examples\cindel_todo
flutter build windows --release
flutter build apk --release
```

Results:

- Windows prebuilt generation: succeeded.
- Android prebuilt generation: succeeded for `arm64-v8a`, `armeabi-v7a`, and
  `x86_64`.
- Rust default: `40 passed; 0 failed`.
- Rust with MDBX: `47 passed; 0 failed`.
- Dart analyze: `No issues found`.
- Dart package default: `79 passed; 2 skipped`.
- Dart package with MDBX through the regenerated Windows prebuilt DLL:
  `81 passed; 0 failed`.
- Windows consumer build: produced
  `examples/cindel_todo/build/windows/x64/runner/Release/cindel_todo.exe`.
- Android consumer build: produced
  `examples/cindel_todo/build/app/outputs/flutter-apk/app-release.apk`.
- Linux, iOS, and macOS: not attempted in this stage because those build
  machines are not available.

Binary size deltas compared with the previous SQLite-only checked-in binaries:

- Windows `cindel_native.dll`: `+358,912` bytes.
- Android `arm64-v8a/libcindel_native.so`: `+367,048` bytes.
- Android `armeabi-v7a/libcindel_native.so`: `+310,636` bytes.
- Android `x86_64/libcindel_native.so`: `+398,776` bytes.

## MDBX-11 CI Backend Matrix

MDBX-11 updates GitHub Actions so SQLite and MDBX regressions are caught
without running benchmark workloads on every PR.

Implemented:

- Kept the fast Dart format/analyze job as the first static validation lane.
- Split backend validation into separate Ubuntu jobs:
  - `sqlite-backend` builds and tests the SQLite-capable native core, then runs
    the Dart package suite against explicit SQLite.
  - `mdbx-backend` installs LLVM/libclang, builds and tests the native core
    with MDBX enabled by the default Cargo feature set, then runs the Dart
    package suite with
    `CINDEL_TEST_BACKEND=mdbx` and `CINDEL_TEST_MDBX=1`.
- Added separate Rust cache keys for SQLite, MDBX, and benchmark builds.
- Added a manual-only `Backend Benchmark` workflow with `workflow_dispatch`
  inputs for document count and query repetitions.
- The benchmark workflow runs `cindel_bench --backend all` with MDBX enabled
  and uploads `backend-benchmark.csv` as an artifact.

Validation:

- Local workflow edit check: `git diff --check`.
- Full validation requires pushing to GitHub Actions because the matrix depends
  on Ubuntu CI images and hosted action behavior.

## MDBX-12 Default Backend Switch

MDBX-12 makes MDBX the public default for new Cindel databases while preserving
SQLite as an explicit secondary backend.

Implemented:

- Changed `Cindel.open`, `Cindel.openInMemory`,
  `CindelDatabase.open`, and `CindelDatabase.openInMemory` to default to
  `CindelStorageBackend.mdbx`.
- Added `defaultCindelStorageBackend` so callers and tests can inspect the
  current default without relying on duplicated enum values.
- Kept `backend: CindelStorageBackend.sqlite` available.
- Added Dart coverage proving that opening without a backend uses MDBX when
  the loaded native library includes MDBX support.
- Documented that existing SQLite databases are not migrated automatically.

Preview data decision:

- Cindel will not silently migrate existing SQLite database directories during
  the default switch.
- Existing SQLite users can keep using
  `backend: CindelStorageBackend.sqlite`.
- Public migration/export tooling is deferred until Cindel approaches 1.0 or a
  real public database format needs preservation.

Validation:

- Dart analyze: `No issues found`.
- SQLite-explicit Dart package suite: `79 passed; 3 skipped`.
- MDBX Dart package suite through the regenerated Windows prebuilt DLL:
  `82 passed; 0 failed`.
- Focused default-backend test:
  `opens with MDBX as the default backend` passed.
- Rust and Dart validation should continue to run through the MDBX-11 CI
  backend matrix after pushing.

## MDBX Layout Prototype

A second MDBX layout has been added as an internal benchmark prototype. It is
not the production storage format and is not exposed through Dart or FFI.

Prototype shape:

- One document table per collection.
- Integer document ids as primary document keys.
- One duplicate-sorted table per index.
- Encoded index values as index keys and document ids as duplicate values.
- Dedicated unique-index tables.
- Reverse document-index metadata for replacing and deleting documents without
  scanning every index table.

Why this layout is promising:

- It reduces global-key prefix work in the hottest document and index paths.
- Duplicate-sorted index tables make equality and range scans closer to the
  access pattern MDBX is optimized for.
- Reverse index metadata makes index cleanup deterministic during replace and
  delete operations.

Windows release benchmark sample:

```powershell
cargo run --release --manifest-path packages/cindel/native/Cargo.toml --features benchmarks --bin cindel_bench -- --backend all --documents 1000 --query-repeats 100 --format json --output docs/local_benchmarks/native-perf-layout-v2.json
```

| Backend | put indexed | get | query equal | query range | put many indexed | delete many | size |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| SQLite | 3134.156 ms | 8.045 ms | 14.569 ms | 17.210 ms | 326.454 ms | 297.332 ms | 4,775,560 bytes |
| MDBX current | 702.312 ms | 4.418 ms | 0.840 ms | 2.001 ms | 413.011 ms | 239.942 ms | 16,781,312 bytes |
| MDBX prototype | 610.628 ms | 3.292 ms | 0.419 ms | 0.940 ms | 31.436 ms | 15.007 ms | 16,781,312 bytes |

Decision:

- Continue with the next performance stages. The prototype shows a meaningful
  win for batch writes, deletes, point reads, and indexed queries.
- Do not ship this layout yet. Cindel still needs typed FFI integration,
  native query execution, and release hardening before a layout change is worth
  carrying in production.
- No custom build patches or platform-specific hacks were added for this
  prototype.

## Binary Document Format Prototype

Cindel now has an internal native prototype for a versioned binary document
format. The format is documented in `docs/binary_document_format.md`.

The prototype uses:

- a magic/versioned header,
- fixed-size field slots,
- a static section for bool, int, double, DateTime, and Duration values,
- a dynamic section for strings, lists, enums, and embedded objects,
- explicit null flags,
- a 64 MiB maximum object size.

The prototype is not connected to storage yet. It exists to prove that Cindel
can move generated typed documents away from JSON while preserving one-field
offset reads for future native index extraction, filtering, sorting, and
projection work.

Validated behavior:

- Supported field shapes round-trip without JSON.
- One fixed field can be read by offset without decoding unrelated dynamic
  payloads.
- Invalid headers and non-finite doubles are rejected.

## Storage Metadata and Verification

Cindel now records internal storage metadata for layout and document format
versions. The current production combinations are:

- SQLite: `sqlite-v1` plus `json-v1`.
- MDBX: `mdbx-v1` plus `binary-v1`.

The storage layer has verification helpers for document counts, schema
versions, collection revisions, and selected equality/range index checks. The
public migration and dry-run APIs are intentionally deferred while Cindel is
pre-1.0 and the optimized MDBX format is still moving quickly.

## MDBX Binary Document Storage

MDBX now stores schema-backed documents in Cindel's native binary document
format. This keeps generated typed models on the optimized path.

The native storage layer derives index entries from the stored binary document
bytes, including value indexes, case-insensitive strings, hash indexes, and word
indexes. Dart still sends JSON payloads through the existing FFI functions for
now, and MDBX converts those payloads internally before writing.

Schema-backed MDBX writes reject unknown fields instead of falling back to
JSON, because there are no external production databases to preserve before
1.0. Public reads continue returning JSON bytes so the Dart API remains
unchanged until the typed FFI reader/writer stage removes JSON from the hot
path. SQLite remains the secondary backend and keeps its JSON-oriented storage
path internally.

Validation:

- Rust native tests with MDBX enabled by default: `50 passed; 0 failed`.
- Rust native tests without default features for SQLite-only validation:
  `42 passed; 0 failed`.
- Rust benchmark/prototype build with `--features benchmarks`:
  `51 passed; 0 failed`.
- Dart package suite against a locally built MDBX DLL: `77 passed; 0 failed`.
- Dart package suite against explicit SQLite using the same local DLL:
  `74 passed; 3 skipped`.
- Dart package suite against the regenerated Windows prebuilt DLL:
  `77 passed; 0 failed`.
- Todo example tests: `9 passed`.
- Todo example Windows release build produced `cindel_todo.exe`.

## Benchmark Baseline

The backend comparison benchmark is implemented as an internal Rust binary:

```powershell
cargo run --release --manifest-path packages/cindel/native/Cargo.toml --features benchmarks --bin cindel_bench -- --backend all --documents 10000 --query-repeats 1000
```

The output is CSV:

```text
backend,operation,items,total_ms,ops_per_second
sqlite,open,...
sqlite,register_schemas,...
sqlite,put_indexed,...
sqlite,get,...
mdbx,open,...
mdbx,register_schemas,...
mdbx,put_indexed,...
mdbx,get,...
```

Measured operations:

- Database open.
- Schema registration.
- Indexed document writes.
- Point reads by collection/id.
- Equality query through an index.
- Range query through an index.
- Batch indexed writes.
- Batch deletes.

## PERF-17 Release Hardening Snapshot

The optimized MDBX path was release-hardened after native property aggregates
landed in ABI 9. The validation pass kept MDBX as the default backend, kept
SQLite explicitly selectable, and aligned package metadata with the current
Android, Windows, and Linux prebuilt binaries.

Validation summary:

- Rust format check: clean.
- Rust default/native test suite: `59 passed`.
- Rust SQLite-only test suite with `--no-default-features`: `44 passed`.
- Dart workspace analyzer: no issues.
- Dart package suite with explicit MDBX: `85 passed`.
- Dart package suite with explicit SQLite: `82 passed`, `3 skipped` MDBX-only
  tests.
- Flutter plugin analyzer for `cindel_flutter_libs`: no issues.
- Todo example analyzer: no issues.
- Todo example tests: `9 passed`.
- Windows release build produced `cindel_todo.exe`.
- Android release build produced `app-release.apk`.
- Linux prebuilt generation through WSL produced `linux/libcindel_native.so`.
- Pub dry-runs validated package archives. The only remaining warning during
  this local pass is pub.dev's clean-git warning while release-hardening edits
  are uncommitted; rerun from a clean commit before publishing.

Release benchmark smoke, Windows, release mode, 1000 documents and 100 query
repeats:

| Operation | SQLite total ms | MDBX total ms | MDBX ratio |
| --- | ---: | ---: | ---: |
| `put_indexed` | 3530.370 | 794.596 | 4.44x |
| `query_equal` | 14.876 | 0.717 | 20.75x |
| `query_range` | 17.913 | 1.207 | 14.85x |
| `query_composite_equal` | 17.301 | 0.537 | 32.23x |
| `query_multi_entry` | 45.304 | 3.290 | 13.77x |
| `aggregate_score_average` | 539.585 | 46.149 | 11.69x |
| `aggregate_name_max` | 545.026 | 50.558 | 10.78x |
| `put_many_indexed` | 771.917 | 71.836 | 10.75x |
| `delete_many` | 716.534 | 25.885 | 27.68x |

Point `get` remains faster on SQLite in this small smoke sample, while
`get_many` is faster on MDBX. The current default-backend decision still favors
MDBX because the optimized path wins decisively on indexed writes, indexed
queries, aggregates, batch writes, and deletes, which are the critical paths
for generated Cindel workloads.

## Adoption Gate

MDBX was promoted to the default backend after satisfying these gates:

- Same public Dart API.
- Same `StorageEngine` behavior.
- Same Rust and Dart test suite passes.
- Benchmark harness can compare SQLite and MDBX with the same workload.
- Schema metadata, index entries, and collection revision counters are stored
  atomically with document changes.
- Windows and Android native asset builds remain reproducible.

SQLite remains explicitly selectable for compatibility, debugging, and future
migration work if the project needs it before 1.0.
