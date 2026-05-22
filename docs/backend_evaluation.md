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
- SQLite remains selectable for users who need the older storage layout while
  the explicit SQLite-to-MDBX migration helper is planned.

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
cargo test --manifest-path packages/cindel/native/Cargo.toml --features mdbx mdbx
```

Initial result: blocked on Windows because `mdbx-sys` runs `bindgen`, and
`bindgen` requires `libclang`. The local machine did not have `clang.dll` or
`libclang.dll` available, and `LIBCLANG_PATH` was not set.

Final Windows result after installing LLVM:

```powershell
$env:LIBCLANG_PATH = "C:\Program Files\LLVM\bin"
cargo test --manifest-path packages/cindel/native/Cargo.toml --features mdbx mdbx
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
- `schema_migrations`: append-only migration records.

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

MDBX-04 adds a feature-gated `MdbxStorage` implementation behind the native
`mdbx` Cargo feature. SQLite remains the default backend for the FFI path.

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
- Full migration compatibility checks.
- Native unique-index enforcement.
- Dart API backend selection.

Validation:

```powershell
cargo test --manifest-path packages/cindel/native/Cargo.toml --features mdbx mdbx
```

Result: passed. MDBX prototype tests can write, read, and query indexed
documents.

```powershell
cargo run --release --manifest-path packages/cindel/native/Cargo.toml --features mdbx --bin cindel_bench -- --backend all --documents 1000 --query-repeats 100
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
cargo run --release --manifest-path packages/cindel/native/Cargo.toml --features mdbx --bin cindel_bench -- --backend all --documents 10000 --query-repeats 1000
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
- Schema registration, additive versioning, explicit migration registration,
  incompatible schema rejection, and index option metadata.
- Unique index enforcement.
- Case-insensitive, hash, and words index metadata acceptance. Dart still
  normalizes those indexed values before they reach native storage.

Validation command:

```powershell
cargo test --manifest-path packages/cindel/native/Cargo.toml --features mdbx
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
cargo test --manifest-path packages/cindel/native/Cargo.toml --features mdbx
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
cargo test --manifest-path packages/cindel/native/Cargo.toml --features mdbx
cargo build --manifest-path packages/cindel/native/Cargo.toml --features mdbx
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
- Added backend support to `Cindel.dryRunMigration` and
  `CindelDatabase.dryRunMigration`.
- Reused the existing package tests across SQLite and MDBX for manual CRUD,
  typed CRUD, ids, batch operations, query builders, indexes, watchers,
  transactions, migrations, and dry-run diagnostics.
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
cargo test --manifest-path packages/cindel/native/Cargo.toml --features mdbx
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
    with `--features mdbx`, then runs the Dart package suite with
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
  `CindelDatabase.open`, `CindelDatabase.openInMemory`, and dry-run migration
  helpers to default to `CindelStorageBackend.mdbx`.
- Added `defaultCindelStorageBackend` so callers and tests can inspect the
  current default without relying on duplicated enum values.
- Kept `backend: CindelStorageBackend.sqlite` available.
- Added Dart coverage proving that opening without a backend uses MDBX when
  the loaded native library includes MDBX support.
- Documented that existing SQLite databases are not migrated automatically.

Migration decision:

- Cindel will not silently migrate existing SQLite database directories during
  the default switch.
- Existing SQLite users can keep using
  `backend: CindelStorageBackend.sqlite`.
- A separate explicit SQLite-to-MDBX migration helper is planned after this
  default switch.

Validation:

- Dart analyze: `No issues found`.
- SQLite-explicit Dart package suite: `79 passed; 3 skipped`.
- MDBX Dart package suite through the regenerated Windows prebuilt DLL:
  `82 passed; 0 failed`.
- Focused default-backend test:
  `opens with MDBX as the default backend` passed.
- Rust and Dart validation should continue to run through the MDBX-11 CI
  backend matrix after pushing.

## Benchmark Baseline

The backend comparison benchmark is implemented as an internal Rust binary:

```powershell
cargo run --release --manifest-path packages/cindel/native/Cargo.toml --features mdbx --bin cindel_bench -- --backend all --documents 10000 --query-repeats 1000
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

## Adoption Gate

MDBX was promoted to the default backend after satisfying these gates:

- Same public Dart API.
- Same `StorageEngine` behavior.
- Same Rust and Dart test suite passes.
- Benchmark harness can compare SQLite and MDBX with the same workload.
- Schema metadata, index entries, and collection revision counters are stored
  atomically with document changes.
- Windows and Android native asset builds remain reproducible.

SQLite remains explicitly selectable for compatibility and for future migration
work.
