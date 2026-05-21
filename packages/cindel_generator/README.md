# cindel_generator

Source generator for Cindel schemas, serializers, typed collections, query
builders, filters, projections, and watcher helpers.

Maintainer: Alain Ramirez <nolbertrg@gmail.com>

Repository: <https://github.com/mainser/Cindel>

## Usage

```yaml
dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^0.1.9
```

Run the generator with:

```sh
dart run build_runner build --delete-conflicting-outputs
```

The generator reads Cindel annotations from model classes and emits:

- Schema manifests for the native runtime.
- JSON-compatible serializers and deserializers.
- Typed collection accessors.
- Indexed query builders.
- Filter builders.
- Sorting, pagination, distinct, and projection helpers.
- Watcher and lazy watcher helpers.

## Publishing Status

This package is still pre-1.0.0 and keeps `publish_to: none` until local path
dependencies can be replaced by hosted Cindel package constraints.
