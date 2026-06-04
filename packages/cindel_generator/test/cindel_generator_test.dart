import 'package:build_test/build_test.dart';
import 'package:cindel_generator/cindel_generator.dart';
import 'package:test/test.dart';

void main() {
  group('CindelGenerator', () {
    test(
      'generates schema metadata, serializers, and collection access.',
      () async {
        final generated = await _generate(_richModelSource);

        _expectAll(generated, [
          'final RichUserSchema = CindelCollectionSchema<RichUser>(',
          'name: "richUsers"',
          'dartName: "RichUser"',
          'idField: "dbId"',
          'CindelFieldSchema(',
          'name: "email"',
          'isIndexed: true',
          'isIndexUnique: true',
          'indexType: CindelIndexType.value',
          'name: "tags"',
          'indexCaseSensitive: false',
          'indexType: CindelIndexType.multiEntry',
          'name: "bio"',
          'indexType: CindelIndexType.words',
          'CindelCompositeIndexSchema(',
          'fields: <String>[',
          '"email", "active"',
          'isUnique: true',
          'toDocument: _\$RichUserToCindelDocument',
          'fromDocument: _\$RichUserFromCindelDocument',
          'toBinaryDocument: _\$RichUserToCindelBinaryDocument',
          'fromBinaryDocument: _\$RichUserFromCindelBinaryDocument',
          'writeNativeDocument: _\$RichUserWriteCindelNativeDocument',
          'readNativeDocument: _\$RichUserReadCindelNativeDocument',
          'getId: _\$RichUserGetCindelId',
          'setId: _\$RichUserSetCindelId',
          'extension RichUserCindelCollectionAccess on CindelDatabase',
          'CindelTypedCollection<RichUser> get richUsers',
        ]);

        expect(generated, isNot(contains('transientNote')));
      },
    );

    test(
      'generates query helpers for indexes, filters, lists, and embedded objects.',
      () async {
        final generated = await _generate(_richModelSource);

        _expectAll(generated, [
          'final class RichUserQueryWhere',
          'CindelQuery<RichUser> emailEqualTo(String value)',
          'CindelQuery<RichUser> emailStartsWith(String value)',
          'CindelQuery<RichUser> emailBetween(String? lower, String? upper)',
          'CindelQuery<RichUser> emailActiveEqualTo(',
          'CindelQuery<RichUser> tagsContains(String value)',
          'CindelQuery<RichUser> bioWordEqualTo(String word)',
          'CindelQuery<RichUser> bioWordStartsWith(String prefix)',
          'CindelQuery<RichUser> bioWordsContain(String word)',
          'final class RichUserQueryFilter',
          'CindelQuery<RichUser> optional(',
          'CindelQuery<RichUser> anyOf<E>(',
          'CindelQuery<RichUser> allOf<E>(',
          'CindelQuery<RichUser> tagsElementEqualTo(String value)',
          'CindelQuery<RichUser> tagsIsEmpty()',
          'CindelQuery<RichUser> tagsIsNotEmpty()',
          'CindelQuery<RichUser> tagsLengthEqualTo(int length)',
          'CindelQuery<RichUser> tagsLengthLessThan(int length, {bool include = false})',
          'CindelQuery<RichUser> tagsLengthGreaterThan(',
          'CindelQuery<RichUser> tagsLengthBetween(',
          'CindelQuery<RichUser> recipient(',
          'CindelQuery<RichUser> recipientsElement(',
          'final class RichUserRecipientCindelEmbeddedFilter',
          'CindelFilterPredicate addressEqualTo(String? value)',
          'CindelFilterPredicate metadata(',
          'final class RichUserRecipientMetadataCindelEmbeddedFilter',
          'CindelFilterPredicate labelsLengthBetween(',
        ]);
      },
    );

    test(
      'generates conversion code for enums, date/time, duration, and embedded lists.',
      () async {
        final generated = await _generate(_richModelSource);

        _expectAll(generated, [
          '"createdAt": object.createdAt.microsecondsSinceEpoch',
          'object.createdAt = DateTime.fromMicrosecondsSinceEpoch(',
          '"sessionLength": object.sessionLength?.inMicroseconds',
          'object.sessionLength = document["sessionLength"] == null',
          '"status": object.status.index',
          'UserStatus.values[document["status"] as int]',
          '"plan": object.plan.code',
          'UserPlan.values.firstWhere(',
          '(enumValue) => enumValue.code == document["plan"],',
          '_\$RecipientToCindelEmbedded(',
          'object.recipient as Recipient',
          ': _\$RecipientFromCindelEmbedded(',
          '(document["recipient"] as Map).cast<String, Object?>(),',
          '_\$RecipientToCindelEmbedded(value)',
          '(value as Map).cast<String, Object?>(),',
        ]);
      },
    );

    test(
      'generates native fast paths for string lists and embedded objects.',
      () async {
        final generated = await _generate(_richModelSource);

        _expectAll(generated, [
          'void _\$RichUserWriteCindelNativeDocument(',
          'RichUser _\$RichUserReadCindelNativeDocument(',
          'cindelWriteNativeStringList(writer,',
          'cindelWriteNativeObject<Recipient>(',
          'cindelWriteNativeObjectList<Recipient>(',
          'void _\$RecipientWriteCindelNativeEmbedded(',
          'Recipient _\$RecipientReadCindelNativeEmbedded(',
          'void _\$RecipientMetadataWriteCindelNativeEmbedded(',
          'RecipientMetadata _\$RecipientMetadataReadCindelNativeEmbedded(',
        ]);
      },
    );

    test(
      'supports immutable explicit-id classes with constructor hydration.',
      () async {
        final generated = await _generate(_immutableSource);

        _expectAll(generated, [
          'final ImmutableUserSchema = CindelCollectionSchema<ImmutableUser>(',
          'fromDocument: _\$ImmutableUserFromCindelDocument',
          'ImmutableUser _\$ImmutableUserFromCindelDocument(',
          'return ImmutableUser(',
          'dbId: document["dbId"] as int',
          'email: document["email"] as String',
          'active: document["active"] as bool',
        ]);

        expect(
          generated,
          isNot(contains('setId: _\$ImmutableUserSetCindelId')),
        );
      },
    );

    test('supports Freezed primary-factory collection models.', () async {
      final generated = await _generate(_freezedPrimaryFactorySource);

      _expectAll(generated, [
        'final FreezedUserSchema = CindelCollectionSchema<FreezedUser>(',
        'int _\$FreezedUserGetCindelId(FreezedUser object)',
        'FreezedUser _\$FreezedUserFromCindelDocument(',
        'return FreezedUser(',
        'dbId: document["dbId"] as int',
        'username: document["username"] as String',
        'status: UserStatus.values[document["status"] as int]',
        'active: document["active"] as bool',
      ]);

      expect(generated, isNot(contains('transientNote')));
    });

    test('rejects abstract non-Freezed collections.', () async {
      final result = await _build(_abstractCollectionSource);

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        contains('@collection classes must be concrete.'),
      );
    });

    test('rejects collections without exactly one dbId field.', () async {
      final result = await _build(_missingIdSource);

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        contains(
          '@collection classes must declare exactly one field named `dbId`.',
        ),
      );
    });

    test('rejects list indexes that are not multi-entry.', () async {
      final result = await _build(_invalidListIndexSource);

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        contains('list fields require CindelIndexType.multiEntry'),
      );
    });

    test('rejects embedded indexes.', () async {
      final result = await _build(_invalidEmbeddedIndexSource);

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        contains('embedded indexes are not supported yet'),
      );
    });

    test('rejects nested lists.', () async {
      final result = await _build(_nestedListSource);

      expect(result.succeeded, isFalse);
      expect(
        result.errors.join('\n'),
        contains('unsupported type `List<List<String>>`'),
      );
    });
  });
}

Future<String> _generate(String source) async {
  final result = await _build(source);
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  final outputs = result.outputs
      .where((asset) => asset.path.endsWith('.cindel.g.part'))
      .toList(growable: false);
  expect(outputs, hasLength(1));
  return result.readerWriter.testing.readString(outputs.single);
}

Future<TestBuilderResult> _build(String source) async {
  final readerWriter = TestReaderWriter(rootPackage: 'fixture');
  await readerWriter.testing.loadIsolateSources();
  return testBuilderFactories(
    [cindelBuilder],
    {'fixture|lib/model.dart': source},
    rootPackage: 'fixture',
    generateFor: {'fixture|lib/model.dart'},
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

void _expectAll(String value, Iterable<String> fragments) {
  for (final fragment in fragments) {
    expect(
      value,
      contains(fragment),
      reason: 'Missing generated fragment: $fragment',
    );
  }
}

const _richModelSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@Collection(
  name: 'richUsers',
  indexes: [
    CompositeIndex(['email', 'active'], unique: true, caseSensitive: false),
  ],
)
class RichUser {
  Id dbId = autoIncrement;

  @Index(unique: true)
  late String email;

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

  @Enumerated(CindelEnumType.ordinal)
  UserStatus status = UserStatus.invited;

  @Enumerated(CindelEnumType.value, valueField: 'code')
  UserPlan plan = UserPlan.free;

  Recipient? recipient;

  List<Recipient>? recipients;

  @ignore
  String transientNote = '';
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
  List<String>? labels;
}

enum UserStatus { invited, active, blocked }

enum UserPlan {
  free('free'),
  pro('pro');

  const UserPlan(this.code);

  final String code;
}
''';

const _immutableSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

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
''';

const _freezedPrimaryFactorySource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

class Freezed {
  const Freezed();
}

const freezed = Freezed();

@freezed
@Collection(name: 'freezedUsers')
abstract class FreezedUser {
  external factory FreezedUser({
    required Id dbId,
    @Index(unique: true) required String username,
    @Enumerated(CindelEnumType.ordinal) required UserStatus status,
    bool active,
    @ignore String? transientNote,
  });
}

enum UserStatus { invited, active, blocked }
''';

const _abstractCollectionSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
abstract class BadModel {
  Id dbId = autoIncrement;
}
''';

const _missingIdSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  late String name;
}
''';

const _invalidListIndexSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  Id dbId = autoIncrement;

  @index
  List<String> tags = const [];
}
''';

const _invalidEmbeddedIndexSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  Id dbId = autoIncrement;

  BadEmbedded? child;
}

@embedded
class BadEmbedded {
  @index
  String? name;
}
''';

const _nestedListSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  Id dbId = autoIncrement;

  List<List<String>> values = const [];
}
''';
