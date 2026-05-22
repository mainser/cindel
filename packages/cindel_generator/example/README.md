# Cindel generator example

Use `cindel_generator` with `build_runner` in the package that contains your
annotated Cindel models.

```yaml
dependencies:
  cindel_annotations: ^0.1.6-dev.3

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^0.1.10-dev.3
```

Given an annotated model:

```dart
import 'package:cindel_annotations/cindel_annotations.dart';

part 'user.g.dart';

@Collection(name: 'users')
class User {
  Id id = autoIncrement;

  @index
  late String email;

  late String name;
}
```

Generate the schema and typed collection APIs:

```console
dart run build_runner build --delete-conflicting-outputs
```
