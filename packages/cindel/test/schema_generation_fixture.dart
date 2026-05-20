import 'package:cindel/cindel.dart';

part 'schema_generation_fixture.g.dart';

@Collection(name: 'users')
class User {
  Id id = autoIncrement;

  late String name;

  @index
  late String email;

  bool? active;
}
