# Cindel Todo Example

Flutter example app that uses Cindel like a normal application dependency.

The example demonstrates:

- Opening a local Cindel database.
- Registering schema metadata.
- Persisting documents.
- Reading live collection updates through watchers.
- Updating and deleting documents.
- Querying an indexed field through generated query builder helpers.
- Filtering by exact title and title prefix with typed query results.
- Reading the stored schema version.
- Wiring the feature with Riverpod providers.
- Loading Cindel's prebuilt native libraries through `cindel_flutter_libs`.
- Testing the repository and UI against an in-memory Cindel database.

## Architecture

The app uses one feature, `todos`, with this structure:

```text
lib/features/todos/
  di/
  domain/
    entities/
    failures/
    repositories/
    usecases/
  data/
    datasources/
    models/
    repositories/
  presentation/
    pages/
    providers/
    widgets/
    utils/
```

The UI depends on providers only. Cindel calls are isolated in the data source.

## Run Locally

```powershell
flutter pub get
flutter pub run build_runner build
flutter run -d windows
```

The generated files are committed so the example can be opened and run without
an extra generation step, but `build_runner` can regenerate them at any time.

The app depends on `cindel_flutter_libs`, so normal Flutter builds use bundled
native libraries instead of requiring Rust or Cargo on the app developer's
machine.

## Android

The app has been validated on a physical Android device using a release APK:

```powershell
flutter pub get
flutter build apk --release
flutter install -d <device-id> --release
```

The bundled Cindel Android binaries cover:

```text
armeabi-v7a  -> 32-bit ARM
arm64-v8a    -> ARMv8 64-bit
x86_64       -> x86_64 emulator
```

Maintainers can refresh those binaries from the repository root with:

```powershell
.\tool\prebuilt\build_android.ps1
```

## iOS

iOS builds must be done on macOS with Xcode installed. This repository includes
the Flutter iOS project under `ios/`, and the Cindel native Rust toolchain is
configured with the usual iOS targets:

```text
aarch64-apple-ios      -> physical iPhone/iPad
aarch64-apple-ios-sim  -> Apple Silicon simulator
x86_64-apple-ios       -> Intel simulator
```

Once `packages/cindel_flutter_libs/ios/cindel.xcframework` is generated on a
Mac and committed, app builds should not require Cargo. On a Mac, run:

```zsh
flutter pub get
flutter build ios
```

To install on a physical iPhone, open `ios/Runner.xcworkspace` in Xcode and set
the signing team and bundle identifier as needed before building or running.
