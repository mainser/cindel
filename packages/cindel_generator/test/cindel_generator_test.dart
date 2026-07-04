import 'package:build_test/build_test.dart';
import 'package:cindel_generator/cindel_generator.dart';
import 'package:test/test.dart';

void main() {
  group('CindelGenerator', () {
    // Scenario: A rich mutable collection model uses ids, indexes, composite
    // indexes, ignored fields, binary documents, and native document hooks.
    // Covers:
    // - Generated schema metadata and field/index descriptors.
    // - Generated document/binary/native serializers.
    // - Generated typed collection extension access.
    // Expected: The generated schema exposes the typed API surface and omits
    // ignored fields from persisted metadata.
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

    // Scenario: Models declare forward links and backlinks.
    // Covers:
    // - Generated link metadata for to-one and to-many relations.
    // - Generated backlink metadata using the forward link Dart field name.
    // - Generated runtime link binding hooks.
    // Expected: Link fields are excluded from persisted fields and bound by
    //   generated schema callbacks after hydration.
    test('generates link and backlink metadata and binders.', () async {
      final generated = await _generate(_linkModelSource);

      _expectAll(generated, [
        'final AuthorSchema = CindelCollectionSchema<Author>(',
        'links: <CindelLinkSchema>[',
        'name: "books"',
        'dartName: "books"',
        'targetCollection: "books"',
        'isToMany: true',
        'isBacklink: true',
        'backlinkTo: "contributors"',
        'bindLinks: _\$AuthorBindCindelLinks',
        'void _\$AuthorBindCindelLinks(',
        'object.books.bind(',
        'final BookSchema = CindelCollectionSchema<Book>(',
        'name: "contributors"',
        'dartName: "contributors"',
        'targetCollection: "authors"',
        'isToMany: true',
        'isBacklink: false',
        'name: "primaryAuthor"',
        'dartName: "primaryAuthor"',
        'isToMany: false',
        'bindLinks: _\$BookBindCindelLinks',
        'object.contributors.bind(',
        'object.primaryAuthor.bind(',
        'targetCollection: "editors"',
        'object.editors.bind(',
      ]);
      expect(generated, isNot(contains('dartType: "CindelLinks')));
      expect(generated, isNot(contains('dartType: "CindelLink')));
    });

    // Scenario: Generated query helpers are emitted for every supported indexed
    // and filtered field shape in the rich model.
    // Covers:
    // - `where()` helpers for value, word, multi-entry, and composite indexes.
    // - `filter()` helpers for scalar, list, and embedded object fields.
    // - Optional, anyOf, and allOf query combinators.
    // Expected: Generated query helpers expose the complete typed query API for
    // the model without requiring manual document predicates.
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
          'Future<void> putByEmail(RichUser object)',
          'Future<void> putAllByEmail(Iterable<RichUser> objects)',
          'indexName: "email"',
          'isComposite: false',
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

    // Scenario: A collection has no indexed or composite-indexed fields.
    // Covers:
    // - Avoiding empty generated `where()` helpers.
    // - Keeping the filter API available for non-indexed collections.
    // Expected: The generated API exposes `filter()` but does not emit an empty
    // `QueryWhere` class or a `where()` method with no valid methods.
    test('does not generate empty where helpers without indexes.', () async {
      final generated = await _generate(_noIndexModelSource);

      _expectAll(generated, [
        'final NoIndexModelSchema = CindelCollectionSchema<NoIndexModel>(',
        'NoIndexModelQueryFilter filter() => NoIndexModelQueryFilter(',
        'final class NoIndexModelQueryFilter',
      ]);

      expect(generated, isNot(contains('NoIndexModelQueryWhere')));
      expect(generated, isNot(contains('where() =>')));
    });

    // Scenario: Persisted values need conversions between Dart types and
    // Cindel's stored representation.
    // Covers:
    // - DateTime and Duration microsecond storage.
    // - Enum ordinal/name/value strategies.
    // - Embedded object and embedded list mapping.
    // Expected: Generated conversion code is explicit and deterministic for
    // every supported persisted value shape.
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

    // Scenario: The generator emits native document readers and writers for
    // values that can use Cindel's typed native row path.
    // Covers:
    // - String-list native writer helpers.
    // - Embedded object native writer/reader helpers.
    // - Embedded object-list native writer/reader helpers.
    // Expected: Native fast-path hooks are present in generated schemas so MDBX,
    // SQLite native, and SQLite Web can use typed storage.
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

    // Scenario: A class is immutable and must be hydrated through its
    // constructor instead of field assignment.
    // Covers:
    // - Explicit `dbId` constructor hydration.
    // - Required constructor parameters for final persisted fields.
    // - Omitting setters when generated code cannot mutate ids.
    // Expected: Generated `fromDocument` calls the constructor and does not emit
    // an unavailable id setter.
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

    // Scenario: A Freezed model exposes its persisted fields through the
    // primary factory constructor.
    // Covers:
    // - Freezed factory parameter discovery.
    // - Generated id getter and constructor hydration.
    // - Ignored Freezed parameters.
    // Expected: Generated code hydrates through the Freezed factory and omits
    // ignored values from storage.
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

    // Scenario: A collection model uses positional constructor parameters and
    // does not specify an explicit collection name.
    // Covers:
    // - Positional constructor hydration.
    // - Default collection naming.
    // - Generated extension getter naming.
    // Expected: Generated code calls the positional constructor and derives the
    // default collection accessor from the class name.
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

    // Scenario: A persisted collection name cannot be used directly as a Dart
    // getter identifier.
    // Covers:
    // - Stable Dart accessor generation for non-identifier collection names.
    // - Preserving the exact persisted collection name in schema metadata.
    // Expected: The generated getter uses a valid lower-camel Dart name while
    // the stored collection name remains unchanged.
    test(
      'normalizes lower-camel accessors for non-identifier names.',
      () async {
        final generated = await _generate(_nonIdentifierCollectionNameSource);

        _expectAll(generated, [
          'name: "event-log"',
          'CindelTypedCollection<EventLog> get eventLog',
        ]);
      },
    );

    // Scenario: Non-null scalar lists and embedded values are generated for the
    // native document branch.
    // Covers:
    // - Required scalar writer calls.
    // - Native nested list writer calls.
    // - Native embedded object and object-list reader/writer calls.
    // Expected: Generated native code covers required scalar/list/embedded
    // fields without dropping to manual document storage.
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

    // Scenario: Enum fields use a mix of default, ordinal, and custom value
    // persistence strategies.
    // Covers:
    // - Name-based enum persistence.
    // - Ordinal enum persistence.
    // - Custom int, double, String, and bool value fields.
    // Expected: Generated code emits matching read/write branches and binary
    // field metadata for every enum strategy.
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

    // Scenario: An abstract class is annotated as a collection without being a
    // supported Freezed model.
    // Covers: Generator validation for constructible collection shapes.
    // Expected: The build fails with a concrete-class diagnostic.
    test('rejects abstract non-Freezed collections.', () async {
      await _expectBuildError(
        _abstractCollectionSource,
        '@collection classes must be concrete.',
      );
    });

    // Scenario: `@collection` is applied to a non-class element.
    // Covers: Generator target validation before schema analysis.
    // Expected: The build fails with a class-only diagnostic.
    test('rejects @collection on non-class elements.', () async {
      await _expectBuildError(
        _nonClassCollectionSource,
        '@collection can only be used on classes.',
      );
    });

    // Scenario: A collection has no persisted fields after ignoring fields.
    // Covers: Minimum persisted-field validation.
    // Expected: The build fails before generating an unusable schema.
    test('rejects collections without persisted fields.', () async {
      await _expectBuildError(
        _emptyPersistedFieldsSource,
        '@collection classes must declare at least one persisted field.',
      );
    });

    // Scenario: A collection does not expose exactly one `dbId` field.
    // Covers: Typed public id convention enforcement.
    // Expected: The build fails and points at the `dbId` requirement.
    test('rejects collections without exactly one dbId field.', () async {
      await _expectBuildError(
        _missingIdSource,
        '@collection classes must declare exactly one field named `dbId`.',
      );
    });

    // Scenario: A collection cannot be hydrated through a usable unnamed
    // constructor.
    // Covers: Constructor discovery for generated object hydration.
    // Expected: The build fails with a usable-constructor diagnostic.
    test('rejects collections without a usable unnamed constructor.', () async {
      await _expectBuildError(
        _noUsableConstructorSource,
        '@collection classes need an unnamed constructor with no parameters',
      );
    });

    // Scenario: Final persisted fields exist but the constructor cannot hydrate
    // all of them.
    // Covers: Immutable model validation before generating assignment code.
    // Expected: The build fails instead of generating code that cannot write
    // final fields.
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

    // Scenario: Constructor parameters drift away from persisted field metadata.
    // Covers:
    // - Unknown constructor parameters.
    // - Constructor type mismatches.
    // - Missing persisted constructor parameters.
    // Expected: Each invalid constructor shape fails with a targeted diagnostic.
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

    // Scenario: A list field is indexed without declaring a multi-entry index.
    // Covers: List index validation.
    // Expected: The build fails before generating an unusable list index.
    test('rejects list indexes that are not multi-entry.', () async {
      await _expectBuildError(
        _invalidListIndexSource,
        'list fields require CindelIndexType.multiEntry',
      );
    });

    // Scenario: Index annotations combine options that cannot be represented by
    // the typed query/index contract.
    // Covers:
    // - Invalid multi-entry targets.
    // - Invalid case-insensitive targets.
    // - Invalid word-index targets.
    // Expected: The generator reports precise diagnostics for each bad option.
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

    // Scenario: An embedded field is annotated as indexed.
    // Covers: Rejection of unsupported embedded indexes.
    // Expected: The build fails instead of generating partial embedded index
    // support.
    test('rejects embedded indexes.', () async {
      await _expectBuildError(
        _invalidEmbeddedIndexSource,
        'embedded indexes are not supported yet',
      );
    });

    // Scenario: A persisted field is a nested list.
    // Covers: Persisted type validation for unsupported nested lists.
    // Expected: The build fails with the unsupported type name.
    test('rejects nested lists.', () async {
      await _expectBuildError(
        _nestedListSource,
        'unsupported type `List<List<String>>`',
      );
    });

    // Scenario: Composite index declarations are malformed.
    // Covers:
    // - Too few fields.
    // - Unknown fields.
    // - List fields in composite indexes.
    // - Duplicate composite index names.
    // Expected: Each invalid composite declaration fails with a specific
    // diagnostic before code generation.
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

    // Scenario: Embedded classes cannot be safely instantiated by generated
    // code.
    // Covers:
    // - Abstract embedded classes.
    // - Embedded classes without a default constructor.
    // Expected: The build fails before generating embedded hydration helpers.
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

    // Scenario: Link fields declare targets the runtime cannot bind safely.
    // Covers:
    // - Link fields must be final relation containers.
    // - Link targets must be collection classes.
    // - Embedded and unannotated classes cannot be link targets.
    // - Persisted link names cannot collide with persisted field names.
    // Expected: The build fails before emitting unusable relation metadata.
    test('rejects invalid link declarations.', () async {
      await _expectBuildError(
        _nonFinalLinkSource,
        'Link field `authors` must be final.',
      );
      await _expectBuildError(
        _voidLinkTargetSource,
        'Link field `authors` must target a collection type.',
      );
      await _expectBuildError(
        _enumLinkTargetSource,
        'Link field `status` must target a class.',
      );
      await _expectBuildError(
        _embeddedLinkTargetSource,
        'Link field `embedded` cannot target an embedded object.',
      );
      await _expectBuildError(
        _plainClassLinkTargetSource,
        'Link field `plain` must target a @collection class.',
      );
      await _expectBuildError(
        _linkNameConflictSource,
        'Persisted link name `author` conflicts with another field.',
      );
    });

    // Scenario: Enum annotations refer to unsupported targets or value fields.
    // Covers:
    // - `@Enumerated` on non-enum fields.
    // - Missing value-field configuration.
    // - Unknown enum value fields.
    // - Non-primitive enum value fields.
    // Expected: The build fails with diagnostics that identify the invalid enum
    // configuration.
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

    // Scenario: A required Freezed factory parameter is marked ignored.
    // Covers: Freezed-specific validation for values required by construction.
    // Expected: The build fails instead of generating a constructor call that
    // cannot supply a required value.
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

  @Index(unique: true, replace: true)
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

const _linkModelSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@Collection(name: 'authors')
class Author {
  Id dbId = autoIncrement;

  late String name;

  @Backlink(to: 'contributors')
  final books = CindelLinks<Book>();
}

@Collection(name: 'books')
class Book {
  Id dbId = autoIncrement;

  late String title;

  final contributors = CindelLinks<Author>();

  final primaryAuthor = CindelLink<Author>();

  final editors = CindelLinks<Editor>();
}

@Name('editors')
@collection
class Editor {
  Id dbId = autoIncrement;

  late String name;
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

const _noIndexModelSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class NoIndexModel {
  Id dbId = autoIncrement;

  String title = '';
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

const _nonFinalLinkSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class Book {
  Id dbId = autoIncrement;

  CindelLinks<Author> authors = CindelLinks<Author>();
}

@collection
class Author {
  Id dbId = autoIncrement;
}
''';

const _voidLinkTargetSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class Book {
  Id dbId = autoIncrement;

  final authors = CindelLinks<void>();
}
''';

const _enumLinkTargetSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class Book {
  Id dbId = autoIncrement;

  final status = CindelLink<BookStatus>();
}

enum BookStatus { draft }
''';

const _embeddedLinkTargetSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class Book {
  Id dbId = autoIncrement;

  final embedded = CindelLink<EmbeddedAuthor>();
}

@embedded
class EmbeddedAuthor {
  String name = '';
}
''';

const _plainClassLinkTargetSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class Book {
  Id dbId = autoIncrement;

  final plain = CindelLink<PlainAuthor>();
}

class PlainAuthor {
  Id dbId = autoIncrement;
}
''';

const _linkNameConflictSource = r'''
import 'package:cindel/cindel.dart';

part 'model.g.dart';

@collection
class Book {
  Id dbId = autoIncrement;

  late String author;

  @Name('author')
  final contributor = CindelLink<Author>();
}

@collection
class Author {
  Id dbId = autoIncrement;
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
