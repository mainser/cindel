# Cindel Flutter libs example

Flutter apps add `cindel_flutter_libs` next to `cindel` so the supported
prebuilt native runtime is bundled with the app.

```yaml
dependencies:
  cindel: ^0.7.0
  cindel_flutter_libs: ^0.7.0
```

No Dart import is required from this package. It is a Flutter plugin that
provides the native runtime for Android, iOS, Linux, macOS, and Windows, plus
the SQLite Worker/Wasm runtime assets for Web.
