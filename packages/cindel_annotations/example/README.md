# Cindel annotations example

Define your persistent models with annotations from `cindel_annotations`, then
generate the Cindel schema and typed accessors with `cindel_generator`.

```dart
import 'package:cindel_annotations/cindel_annotations.dart';

part 'todo.g.dart';

@Collection(name: 'todos')
class Todo {
  Id dbId = autoIncrement;

  @index
  late String title;

  @Index(type: CindelIndexType.value)
  late bool completed;
}
```

Run the generator from the package that owns the model:

```console
dart run build_runner build --delete-conflicting-outputs
```
