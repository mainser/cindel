# Cindel generator example

Use `cindel_generator` with `build_runner` in the package that contains your
annotated Cindel models.

```yaml
dependencies:
  cindel: ^0.5.8

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^0.5.6
```

Given an annotated model:

```dart
import 'package:cindel/cindel.dart';

part 'user.g.dart';

@Collection(name: 'users')
class User {
  Id dbId = autoIncrement;

  @index
  late String email;

  late String name;
}
```

Generate the schema and typed collection APIs:

```console
dart run build_runner build --delete-conflicting-outputs
```
