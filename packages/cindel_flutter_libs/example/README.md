# Cindel Flutter libs example

Flutter apps add `cindel_flutter_libs` next to `cindel` so the supported
prebuilt native runtime is bundled with the app.

```yaml
dependencies:
  cindel: ^0.3.4
  cindel_flutter_libs: ^0.3.4
```

No Dart import is required from this package. It is a Flutter plugin that
currently provides the native runtime for Android and Windows.
