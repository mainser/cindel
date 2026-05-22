# Cindel example

Add Cindel, the Flutter native libraries package, and the generator to your app:

```yaml
dependencies:
  cindel: ^0.1.17-dev.10
  cindel_flutter_libs: ^0.1.10-dev.5

dev_dependencies:
  build_runner: ^2.15.0
  cindel_generator: ^0.1.10-dev.3
```

Define a model and generate its schema:

```dart
import 'package:cindel/cindel.dart';

part 'user.g.dart';

@Collection(name: 'users')
class User {
  Id id = autoIncrement;

  @index
  late String email;

  late String name;
}
```

Use the generated schema and typed collection API:

```dart
import 'package:cindel/cindel.dart';

import 'user.dart';

Future<void> main() async {
  final db = await Cindel.open(
    directory: 'app_data',
    schemas: [UserSchema],
  );

  final user = User()
    ..email = 'ana@example.com'
    ..name = 'Ana';

  await db.users.put(user);

  final matches = await db.users
      .where()
      .emailEqualTo('ana@example.com')
      .findAll();

  print('Found ${matches.length} user(s).');

  await db.close();
}
```

Generate the code before running the app:

```console
dart run build_runner build --delete-conflicting-outputs
```
