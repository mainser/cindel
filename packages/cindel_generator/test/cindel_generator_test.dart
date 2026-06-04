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

    test(
      'supports positional constructors and default collection names.',
      () async {
        final generated = await _generate(_positionalConstructorSource);

        _expectAll(generated, [
          'final PositionalUserSchema = CindelCollectionSchema<PositionalUser>(',
          'name: "positionalUser"',
          'CindelTypedCollection<PositionalUser> get positionalUser',
          'return PositionalUser(',
          'document["dbId"] as int',
          'document["name"] as String',
          'document["active"] as bool',
        ]);
      },
    );

    test(
      'falls back to lower-camel accessors for non-identifier names.',
      () async {
        final generated = await _generate(_nonIdentifierCollectionNameSource);

        _expectAll(generated, [
          'name: "event-log"',
          'CindelTypedCollection<EventLog> get eventLog',
        ]);
      },
    );

    test(
      'generates native paths for non-null embedded and scalar lists.',
      () async {
        final generated = await _generate(_nativeBranchSource);

        _expectAll(generated, [
          'object.requiredFlag);',
          'object.requiredCount);',
          'object.requiredRatio);',
          'object.requiredName);',
          'object.requiredAt.microsecondsSinceEpoch);',
          'object.requiredDuration.inMicroseconds);',
          'final listWriter = writer.beginList(',
          'listWriter.writeInt(i, list[i]);',
          'listWriter.writeDouble(i, list[i]);',
          'listWriter.writeBool(i, list[i]);',
          'listWriter.writeString(i, value);',
          'cindelWriteNativeObject<NativeEmbedded>(',
          'cindelWriteNativeObjectList<NativeEmbedded>(',
          '(cindelReadNativeObject<NativeEmbedded>(',
          'const <NativeEmbedded?>[]',
          'cindelReadNativeObjectList<NativeEmbedded>(',
          'reader.readDouble(documentIndex,',
          'reader.readList(documentIndex,',
        ]);
      },
    );

    test(
      'generates enum strategies for default and nullable values.',
      () async {
        final generated = await _generate(_enumStrategySource);

        _expectAll(generated, [
          '"plain": object.plain?.name',
          'PlainStatus.values.byName(document["plain"] as String)',
          '"ordinal": object.ordinal?.index',
          'OrdinalStatus.values[document["ordinal"] as int]',
          '"toggle": object.toggle?.isEnabled',
          'ToggleStatus.values.firstWhere(',
          '"priority": object.priority.rank',
          '"rating": object.rating.score',
          '"code": object.code.code',
          'CindelBinaryFieldType.boolValue',
          'CindelBinaryFieldType.doubleValue',
        ]);
      },
    );

    test('rejects abstract non-Freezed collections.', () async {
      await _expectBuildError(
        _abstractCollectionSource,
        '@collection classes must be concrete.',
      );
    });

    test('rejects @collection on non-class elements.', () async {
      await _expectBuildError(
        _nonClassCollectionSource,
        '@collection can only be used on classes.',
      );
    });

    test('rejects collections without persisted fields.', () async {
      await _expectBuildError(
        _emptyPersistedFieldsSource,
        '@collection classes must declare at least one persisted field.',
      );
    });

    test('rejects collections without exactly one dbId field.', () async {
      await _expectBuildError(
        _missingIdSource,
        '@collection classes must declare exactly one field named `dbId`.',
      );
    });

    test('rejects collections without a usable unnamed constructor.', () async {
      await _expectBuildError(
        _noUsableConstructorSource,
        '@collection classes need an unnamed constructor with no parameters',
      );
    });

    test(
      'rejects final persisted fields without constructor hydration.',
      () async {
        await _expectBuildError(
          _finalFieldsWithoutConstructorSource,
          '@collection classes with final persisted fields need an unnamed '
          'constructor parameter for every persisted field.',
        );
      },
    );

    test('rejects invalid constructor hydration signatures.', () async {
      await _expectBuildError(
        _constructorUnknownParameterSource,
        'Constructor parameter `unknown` does not match a persisted field.',
      );
      await _expectBuildError(
        _constructorTypeMismatchSource,
        'Constructor parameter `name` must have type `String`.',
      );
      await _expectBuildError(
        _constructorMissingFieldSource,
        'Constructor is missing persisted fields: name.',
      );
    });

    test('rejects list indexes that are not multi-entry.', () async {
      await _expectBuildError(
        _invalidListIndexSource,
        'list fields require CindelIndexType.multiEntry',
      );
    });

    test('rejects invalid index options.', () async {
      await _expectBuildError(
        _invalidMultiEntryIndexSource,
        'multi-entry indexes require primitive list fields.',
      );
      await _expectBuildError(
        _invalidCaseInsensitiveIndexSource,
        'only String indexes support case-insensitive lookup.',
      );
      await _expectBuildError(
        _invalidWordsIndexSource,
        'word indexes require String fields.',
      );
    });

    test('rejects embedded indexes.', () async {
      await _expectBuildError(
        _invalidEmbeddedIndexSource,
        'embedded indexes are not supported yet',
      );
    });

    test('rejects nested lists.', () async {
      await _expectBuildError(
        _nestedListSource,
        'unsupported type `List<List<String>>`',
      );
    });

    test('rejects invalid composite indexes.', () async {
      await _expectBuildError(
        _shortCompositeIndexSource,
        'Composite indexes require at least two fields.',
      );
      await _expectBuildError(
        _unknownCompositeIndexFieldSource,
        'Composite index references unknown field `missing`.',
      );
      await _expectBuildError(
        _listCompositeIndexFieldSource,
        'Composite index field `tags` cannot be a list.',
      );
      await _expectBuildError(
        _duplicateCompositeIndexSource,
        'Composite index `email_active` is duplicated.',
      );
    });

    test('rejects invalid embedded class shapes.', () async {
      await _expectBuildError(
        _abstractEmbeddedSource,
        '@Embedded classes must be concrete.',
      );
      await _expectBuildError(
        _embeddedWithoutDefaultConstructorSource,
        '@Embedded classes need an unnamed constructor with no parameters.',
      );
    });

    test('rejects invalid enum annotations.', () async {
      await _expectBuildError(
        _enumeratedNonEnumSource,
        '@Enumerated can only be used on enum fields.',
      );
      await _expectBuildError(
        _enumValueWithoutValueFieldSource,
        'uses CindelEnumType.value but does not declare valueField.',
      );
      await _expectBuildError(
        _enumValueUnknownFieldSource,
        'does not declare a `missing` field.',
      );
      await _expectBuildError(
        _enumValueNonPrimitiveFieldSource,
        'must be int, double, String, or bool.',
      );
    });

    test('rejects ignored required Freezed factory parameters.', () async {
      await _expectBuildError(
        _freezedIgnoredRequiredParameterSource,
        '@ignore cannot be used on required Freezed factory parameter `name`.',
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

Future<void> _expectBuildError(String source, String message) async {
  final result = await _build(source);

  expect(result.succeeded, isFalse);
  expect(result.errors.join('\n'), contains(message));
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

const _positionalConstructorSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class PositionalUser {
  const PositionalUser(this.dbId, this.name, this.active);

  final Id dbId;
  final String name;
  final bool active;
}
''';

const _nonIdentifierCollectionNameSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@Collection(name: 'event-log')
class EventLog {
  Id dbId = autoIncrement;
  String message = '';
}
''';

const _nativeBranchSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class NativeBranch {
  Id dbId = autoIncrement;

  bool requiredFlag = false;
  bool? optionalFlag;

  int requiredCount = 0;
  int? optionalCount;

  double requiredRatio = 0.0;
  double? optionalRatio;

  String requiredName = '';
  String? optionalName;

  DateTime requiredAt = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);
  DateTime? optionalAt;

  @index
  Duration requiredDuration = Duration.zero;
  Duration? optionalDuration;

  List<int> counts = const [];
  List<double> ratios = const [];
  List<bool> flags = const [];
  List<String?> aliases = const [];

  @Index(type: CindelIndexType.multiEntry)
  List<DateTime> timestamps = const [];

  @Index(type: CindelIndexType.multiEntry)
  List<Duration> durations = const [];

  NativeEmbedded requiredChild = NativeEmbedded();
  NativeEmbedded? optionalChild;

  List<NativeEmbedded> children = const [];
  List<NativeEmbedded?> maybeChildren = const [];
  List<NativeEmbedded>? optionalChildren;
}

@embedded
class NativeEmbedded {
  int count = 0;
  double ratio = 0.0;
  DateTime createdAt = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);
  Duration span = Duration.zero;
  NativeLeaf leaf = NativeLeaf();
  List<NativeLeaf> leaves = const [];
}

@embedded
class NativeLeaf {
  String? label;
}
''';

const _enumStrategySource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class EnumStrategies {
  Id dbId = autoIncrement;

  PlainStatus? plain;

  @Enumerated(CindelEnumType.ordinal)
  OrdinalStatus? ordinal;

  @Enumerated(CindelEnumType.value, valueField: 'isEnabled')
  ToggleStatus? toggle;

  @Enumerated(CindelEnumType.value, valueField: 'rank')
  PriorityStatus priority = PriorityStatus.low;

  @Enumerated(CindelEnumType.value, valueField: 'score')
  RatingStatus rating = RatingStatus.one;

  @Enumerated(CindelEnumType.value, valueField: 'code')
  CodeStatus code = CodeStatus.free;

  @Index(type: CindelIndexType.multiEntry)
  List<PlainStatus> plainValues = const [];
}

enum PlainStatus { one, two }

enum OrdinalStatus { one, two }

enum ToggleStatus {
  enabled(true),
  disabled(false);

  const ToggleStatus(this.isEnabled);

  final bool isEnabled;
}

enum PriorityStatus {
  low(1),
  high(2);

  const PriorityStatus(this.rank);

  final int rank;
}

enum RatingStatus {
  one(1.0),
  two(2.0);

  const RatingStatus(this.score);

  final double score;
}

enum CodeStatus {
  free('free'),
  pro('pro');

  const CodeStatus(this.code);

  final String code;
}
''';

const _abstractCollectionSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
abstract class BadModel {
  Id dbId = autoIncrement;
}
''';

const _nonClassCollectionSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
enum BadModel { one }
''';

const _emptyPersistedFieldsSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  @ignore
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

const _noUsableConstructorSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  BadModel.named();

  Id dbId = autoIncrement;
  String name = '';
}
''';

const _finalFieldsWithoutConstructorSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  final Id dbId = autoIncrement;
  final String name = '';
}
''';

const _constructorUnknownParameterSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  BadModel(this.dbId, this.name, String unknown);

  final Id dbId;
  final String name;
}
''';

const _constructorTypeMismatchSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  BadModel(this.dbId, Object name) : name = name as String;

  final Id dbId;
  final String name;
}
''';

const _constructorMissingFieldSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  BadModel(this.dbId);

  final Id dbId;
  final String name = '';
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

const _invalidMultiEntryIndexSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  Id dbId = autoIncrement;

  @Index(type: CindelIndexType.multiEntry)
  int value = 0;
}
''';

const _invalidCaseInsensitiveIndexSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  Id dbId = autoIncrement;

  @Index(caseSensitive: false)
  int value = 0;
}
''';

const _invalidWordsIndexSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  Id dbId = autoIncrement;

  @Index(type: CindelIndexType.words)
  int value = 0;
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

const _shortCompositeIndexSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@Collection(indexes: [CompositeIndex(['email'])])
class BadModel {
  Id dbId = autoIncrement;
  String email = '';
}
''';

const _unknownCompositeIndexFieldSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@Collection(indexes: [CompositeIndex(['email', 'missing'])])
class BadModel {
  Id dbId = autoIncrement;
  String email = '';
}
''';

const _listCompositeIndexFieldSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@Collection(indexes: [CompositeIndex(['email', 'tags'])])
class BadModel {
  Id dbId = autoIncrement;
  String email = '';
  List<String> tags = const [];
}
''';

const _duplicateCompositeIndexSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@Collection(
  indexes: [
    CompositeIndex(['email', 'active']),
    CompositeIndex(['email', 'active']),
  ],
)
class BadModel {
  Id dbId = autoIncrement;
  String email = '';
  bool active = false;
}
''';

const _abstractEmbeddedSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  Id dbId = autoIncrement;
  BadEmbedded? child;
}

@embedded
abstract class BadEmbedded {
  String? name;
}
''';

const _embeddedWithoutDefaultConstructorSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  Id dbId = autoIncrement;
  BadEmbedded? child;
}

@embedded
class BadEmbedded {
  BadEmbedded(this.name);

  String name;
}
''';

const _enumeratedNonEnumSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  Id dbId = autoIncrement;

  @Enumerated(CindelEnumType.ordinal)
  String status = '';
}
''';

const _enumValueWithoutValueFieldSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  Id dbId = autoIncrement;

  @Enumerated(CindelEnumType.value)
  BadStatus status = BadStatus.one;
}

enum BadStatus { one, two }
''';

const _enumValueUnknownFieldSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  Id dbId = autoIncrement;

  @Enumerated(CindelEnumType.value, valueField: 'missing')
  BadStatus status = BadStatus.one;
}

enum BadStatus {
  one('one');

  const BadStatus(this.code);

  final String code;
}
''';

const _enumValueNonPrimitiveFieldSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class BadModel {
  Id dbId = autoIncrement;

  @Enumerated(CindelEnumType.value, valueField: 'codes')
  BadStatus status = BadStatus.one;
}

enum BadStatus {
  one(['one']);

  const BadStatus(this.codes);

  final List<String> codes;
}
''';

const _freezedIgnoredRequiredParameterSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

class Freezed {
  const Freezed();
}

const freezed = Freezed();

@freezed
@collection
abstract class BadModel {
  external factory BadModel({
    required Id dbId,
    @ignore required String name,
  });
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
