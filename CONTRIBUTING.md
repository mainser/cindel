# Contributing to Cindel

Thank you for taking the time to improve Cindel.

Cindel is an experimental Flutter-first local database library. The project is
in early MVP development, so the best contributions are small, well-tested, and
aligned with `ROADMAP.md`.

## Project Status

Cindel currently has a working vertical slice:

- Dart public API.
- Generated schema metadata and serializers.
- Rust native core behind a narrow FFI bridge.
- SQLite storage backend.
- Simple indexes and equality/range queries.
- Dart streams for document and collection watchers.
- Schema version registration and compatible additive migrations.
- A Rust benchmark baseline for backend evaluation.

The API is still experimental. Breaking changes may happen before a first
public release.

## Repository Layout

```text
Cindel/
  docs/                         Project notes and backend evaluation
  examples/cindel_todo/         Flutter example app
  packages/cindel/              Public Dart API, FFI bridge, native Rust core
  packages/cindel_annotations/  Public annotations and shared types
  packages/cindel_flutter_libs/ Prebuilt native libraries for Flutter apps
  packages/cindel_generator/    Source generator for schemas and serializers
```

## Prerequisites

- Dart SDK compatible with `sdk: ^3.11.0`.
- Flutter SDK when working on Flutter examples.
- Rust toolchain `1.90.0` or newer.
- Windows MSVC C++ toolchain for native builds on Windows.
- Android NDK and `cargo-ndk` when regenerating Android prebuilt binaries.
- Xcode command line tools when regenerating iOS or macOS prebuilt binaries.
- Git.

## Setup

From the repository root:

```powershell
dart pub get
```

For the native package:

```powershell
cargo build --manifest-path packages/cindel/native/Cargo.toml
```

## Development Checks

Run these before opening a pull request:

```powershell
dart format --output=none --set-exit-if-changed .
dart analyze
cargo fmt --manifest-path packages/cindel/native/Cargo.toml --check
cargo test --manifest-path packages/cindel/native/Cargo.toml
dart test packages/cindel/test -r expanded
flutter test examples/cindel_todo
```

Flutter app builds should use `cindel_flutter_libs` by default. If a maintainer
needs to validate Dart native-assets instead of prebuilt binaries, temporarily
set `hooks.user_defines.cindel.build_native_assets` to `true` in the workspace
`pubspec.yaml` and regenerate the affected prebuilt binaries afterward.

Run the backend benchmark baseline with:

```powershell
cargo run --release --manifest-path packages/cindel/native/Cargo.toml --bin cindel_bench -- --documents 10000 --query-repeats 1000
```

## Testing Style

Every Dart test should document intent in the same style used by the current
test suite:

```dart
// Scenario: The state or input being simulated.
// Covers:
// - The branch, rule, or integration point being validated.
// Expected: The exact outcome or side effect.
test('short behavior description.', () {
  // Arrange.
  // Act.
  // Assert.
});
```

Rust tests should follow the same Scenario/Covers/Expected structure and keep
Arrange/Act/Assert comments for readability.

## Code Style

- Keep the Dart API clean and Flutter-friendly.
- Keep SQLite and future storage backend details out of the public Dart API.
- Prefer existing project patterns over new abstractions.
- Keep the FFI boundary small and explicit.
- Use structured serialization formats instead of ad hoc string parsing.
- Add tests for user-visible behavior, storage semantics, FFI boundaries, and
  migration compatibility.
- Do not introduce a new dependency without a clear reason.

## Versioning

Cindel is pre-1.0.0 while the API and package boundaries are still settling.
Use small version steps so every package change stays traceable without rushing
to a stable release.

- Keep changed packages and examples versioned in the same change that modifies
  them.
- Record user-visible package, example, native binary, and migration changes in
  `CHANGELOG.md`.
- Use `0.1.0` as the current development baseline.
- For follow-up changes, bump the patch version: `0.1.1`, `0.1.2`, and so on.
- For Flutter examples that include a build number, bump both the patch version
  and build number when the example changes, for example `0.1.1+2`.
- Do not jump to `1.0.0` until the public API, native binary distribution, and
  publishing workflow are intentionally declared stable.

## Pull Request Guidelines

Before starting a large change, open an issue or draft a short proposal.

Pull requests should include:

- A clear summary of the change.
- Tests for the behavior being added or fixed.
- Documentation updates when public behavior changes.
- Notes about migrations, native build impact, or public API changes.

Small, focused pull requests are preferred.

## Publishing Preparation

Cindel is not published yet. The repository root stays private to pub.dev with
`publish_to: none`; individual packages will be prepared and published in a
controlled order when the API is ready.

Before any package publication:

- Keep `README.md`, `CHANGELOG.md`, `LICENSE`, and `pubspec.yaml` present at
  each package root.
- Replace local path dependencies with hosted version constraints.
- Run `dart pub publish --dry-run` from the package directory and inspect the
  file list.

## Commit Messages

Use concise, imperative commit messages:

```text
Add indexed query support
Fix schema compatibility validation
Document backend benchmark baseline
```

## License

By contributing to Cindel, you agree that your contributions are licensed under
the Apache License, Version 2.0.
