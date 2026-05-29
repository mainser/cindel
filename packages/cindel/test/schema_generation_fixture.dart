import 'package:cindel/cindel.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'schema_generation_fixture.freezed.dart';
part 'schema_generation_fixture.g.dart';

@Collection(
  name: 'users',
  indexes: [
    CompositeIndex(['email', 'active']),
  ],
)
class User {
  Id dbId = autoIncrement;

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

  @Index(type: CindelIndexType.multiEntry, caseSensitive: false)
  List<String> tags = const [];

  List<int>? scores;

  UserRole role = UserRole.member;

  @Index(type: CindelIndexType.value)
  @Enumerated(CindelEnumType.ordinal)
  UserStatus status = UserStatus.invited;

  @Enumerated(CindelEnumType.value, valueField: 'code')
  UserPlan plan = UserPlan.free;

  Recipient? primaryRecipient;

  List<Recipient>? recipients;

  @ignore
  String transientNote = '';
}

@Collection(name: 'immutableUsers')
class ImmutableUser {
  const ImmutableUser({
    required this.dbId,
    required this.email,
    required this.active,
  });

  final Id dbId;

  @index
  final String email;

  final bool active;
}

@Collection(name: 'apiProducts')
class ApiProduct {
  Id dbId = autoIncrement;

  @index
  String? id;

  late String name;
}

@freezed
@Collection(name: 'freezedPrimaryUsers')
abstract class FreezedPrimaryUser with _$FreezedPrimaryUser {
  const factory FreezedPrimaryUser({
    required Id dbId,
    required String email,
    @Index(unique: true) required String username,
    @Enumerated(CindelEnumType.ordinal) required UserStatus status,
    @Default(true) bool active,
    @ignore String? transientNote,
  }) = _FreezedPrimaryUser;
}

@embedded
class Recipient {
  String? name;

  String? address;

  RecipientMetadata? metadata;
}

@embedded
class RecipientMetadata {
  String? label;
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
