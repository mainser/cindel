import 'package:cindel/cindel.dart';

part 'schema_generation_fixture.g.dart';

@Collection(name: 'users')
class User {
  Id id = autoIncrement;

  late String name;

  @index
  late String email;

  @Index(unique: true)
  String? username;

  @Index(caseSensitive: false)
  String? displayName;

  @Index(type: CindelIndexType.hash)
  String? accessToken;

  @Index(type: CindelIndexType.words, caseSensitive: false)
  String? bio;

  bool? active;

  @index
  DateTime createdAt = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);

  Duration? sessionLength;

  List<String> tags = const [];

  List<int>? scores;

  UserRole role = UserRole.member;

  @Index(type: CindelIndexType.value)
  @Enumerated(CindelEnumType.ordinal)
  UserStatus status = UserStatus.invited;

  @Enumerated(CindelEnumType.value, valueField: 'code')
  UserPlan plan = UserPlan.free;

  @ignore
  String transientNote = '';
}

enum UserRole { owner, member }

enum UserStatus { invited, active, blocked }

enum UserPlan {
  free('free'),
  pro('pro'),
  enterprise('enterprise');

  const UserPlan(this.code);

  final String code;
}
