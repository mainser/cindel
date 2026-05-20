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

Open questions before integration:

- Windows build reliability with the same toolchain used by Flutter native
  assets.
- Best data layout for collections, documents, index entries, schema metadata,
  and revision counters.
- Transaction ergonomics for keeping documents and indexes atomic.
- Whether typed table APIs or raw key-value tables are the cleaner fit for
  generated schemas.
- Binary size and compile-time impact versus SQLite bundled mode.

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
