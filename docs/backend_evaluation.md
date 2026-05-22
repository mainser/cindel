# Backend Evaluation

This note records the phase 8 baseline for keeping Cindel's public Dart API
stable while the native storage backend remains interchangeable.

## Current Decision

Cindel keeps SQLite as the MVP backend and evaluates `libmdbx` behind the Rust
`StorageEngine` boundary before exposing any backend choice to Dart.

Reasons:

- The public Dart API must not expose SQLite or MDBX concepts.
- SQLite already validates the vertical slice: documents, indexes, watchers,
  and schema versions.
- The next backend needs to prove the same behavior with the same benchmark
  harness before becoming selectable.

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
- Linux release-mode benchmark remains required before making MDBX the default
  backend.

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

Remaining MDBX adoption gates:

- Explicit read/write transaction integration belongs to MDBX-07.
- Linux release-mode benchmark validation is still required before making MDBX
  the default backend.

## Benchmark Baseline

The phase 8 baseline benchmark is implemented as an internal Rust binary:

```powershell
cargo run --release --manifest-path packages/cindel/native/Cargo.toml --bin cindel_bench -- --documents 10000 --query-repeats 1000
```

The output is CSV:

```text
backend,operation,items,total_ms,ops_per_second
sqlite,put_indexed,...
sqlite,get,...
sqlite,query_equal,...
sqlite,query_range,...
```

Measured operations:

- Indexed document writes.
- Point reads by collection/id.
- Equality query through an index.
- Range query through an index.

## Adoption Gate

MDBX should only be added when it can satisfy all of these:

- Same public Dart API.
- Same `StorageEngine` behavior.
- Same Rust and Dart test suite passes.
- Benchmark harness can compare SQLite and MDBX with the same workload.
- Schema metadata, index entries, and collection revision counters are stored
  atomically with document changes.
- Windows native asset build remains reproducible.

Until then, SQLite remains the default and only compiled backend.
