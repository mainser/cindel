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
  examples/cindel_todo/         Placeholder Flutter example app
  packages/cindel/              Public Dart API, FFI bridge, native Rust core
  packages/cindel_annotations/  Public annotations and shared types
  packages/cindel_generator/    Source generator for schemas and serializers
```

## Prerequisites

- Dart SDK compatible with `sdk: ^3.11.0`.
- Flutter SDK when working on Flutter examples.
- Rust toolchain `1.90.0` or newer.
- Cargo available on `PATH`; after a new `rustup` install, restart the shell or
  run `. "$HOME/.cargo/env"`.
- CocoaPods when running iOS or macOS Flutter targets.
- Windows MSVC C++ toolchain for native builds on Windows.
- Git.

## Setup

From the repository root:

```powershell
dart pub get
cd examples/cindel_todo
flutter pub get
cd ../..
```

For the native package:

```powershell
cargo build --manifest-path packages/cindel/native/Cargo.toml
```

For iOS and macOS Flutter targets, install pods with a Ruby-clean environment:

```powershell
cd examples/cindel_todo/ios
env -u GEM_HOME -u GEM_PATH PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH" pod install
cd ../macos
env -u GEM_HOME -u GEM_PATH PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH" pod install
cd ../../..
```

## Running the Example App

Start from `examples/cindel_todo` and list devices:

```powershell
cd examples/cindel_todo
flutter devices
```

Run on Android:

```powershell
PATH="$HOME/.cargo/bin:$PATH" flutter run -d <android-device-id>
```

Run on an iOS simulator:

```powershell
xcrun simctl list devices available
xcrun simctl boot <simulator-udid>
xcrun simctl bootstatus <simulator-udid> -b
env -u GEM_HOME -u GEM_PATH PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH" flutter run -d <simulator-udid>
```

Run on a physical iPhone or iPad:

```powershell
env -u GEM_HOME -u GEM_PATH PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH" flutter run -d <ios-device-id>
```

Physical iOS devices require a valid Development Team and provisioning profile.
If Xcode reports missing profiles, open `ios/Runner.xcworkspace`, select the
`Runner` target, and set Signing & Capabilities before retrying.

Run on macOS:

```powershell
env -u GEM_HOME -u GEM_PATH PATH="/opt/homebrew/bin:$HOME/.cargo/bin:$PATH" flutter run -d macos
```

## Development Checks

Run these before opening a pull request:

```powershell
dart format --output=none --set-exit-if-changed .
dart analyze packages/cindel packages/cindel_annotations packages/cindel_generator
flutter analyze examples/cindel_todo
cargo fmt --manifest-path packages/cindel/native/Cargo.toml --check
cargo test --manifest-path packages/cindel/native/Cargo.toml
cd packages/cindel
dart test -r expanded
cd ../..
cd examples/cindel_todo
flutter test
cd ../..
```

With Melos installed, the same checks can be run from the scripts in the root
`pubspec.yaml`:

```powershell
dart run melos run format-check
dart run melos run analyze
dart run melos run test
```

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

## Pull Request Guidelines

Before starting a large change, open an issue or draft a short proposal.

Pull requests should include:

- A clear summary of the change.
- Tests for the behavior being added or fixed.
- Documentation updates when public behavior changes.
- Notes about migrations, native build impact, or public API changes.

Small, focused pull requests are preferred.

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
