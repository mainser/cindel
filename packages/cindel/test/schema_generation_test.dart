import 'dart:typed_data';

import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'backend_test_support.dart';

import 'schema_generation_fixture.dart';

void main() {
  group('Cindel schema generation', () {
    // Scenario: A class annotated with @Collection has generated metadata.
    // Covers:
    // - Collection name configured by annotation.
    // - Field discovery, id detection, and index metadata.
    // Expected: The generated schema exposes stable collection metadata.
    test('generates collection and field metadata.', () {
      // Arrange.
      final schema = UserSchema;

      // Act.
      final fields = schema.fields;
      final indexedFields = fields.where((field) => field.isIndexed).toList();
      final username = fields.singleWhere((field) => field.name == 'username');
      final displayName = fields.singleWhere(
        (field) => field.name == 'displayName',
      );
      final accessToken = fields.singleWhere(
        (field) => field.name == 'accessToken',
      );
      final bio = fields.singleWhere((field) => field.name == 'bio');
      final tags = fields.singleWhere((field) => field.name == 'tags');
      final createdAt = fields.singleWhere(
        (field) => field.name == 'createdAt',
      );
      final plan = fields.singleWhere((field) => field.name == 'plan');
      final primaryRecipient = fields.singleWhere(
        (field) => field.name == 'primaryRecipient',
      );
      final recipients = fields.singleWhere(
        (field) => field.name == 'recipients',
      );

      // Assert.
      expect(schema.name, 'users');
      expect(schema.dartName, 'User');
      expect(schema.idField, 'dbId');
      expect(fields.map((field) => field.name), [
        'dbId',
        'name',
        'email',
        'username',
        'displayName',
        'accessToken',
        'bio',
        'active',
        'createdAt',
        'sessionLength',
        'tags',
        'scores',
        'role',
        'status',
        'plan',
        'primaryRecipient',
        'recipients',
      ]);
      expect(indexedFields.map((field) => field.name), [
        'email',
        'username',
        'displayName',
        'accessToken',
        'bio',
        'createdAt',
        'tags',
        'status',
      ]);
      expect(username.isIndexUnique, isTrue);
      expect(displayName.indexCaseSensitive, isFalse);
      expect(accessToken.indexType, CindelIndexType.hash);
      expect(bio.indexType, CindelIndexType.words);
      expect(bio.indexCaseSensitive, isFalse);
      expect(tags.indexType, CindelIndexType.multiEntry);
      expect(tags.indexCaseSensitive, isFalse);
      expect(schema.compositeIndexes, hasLength(1));
      expect(schema.compositeIndexes.single.name, 'email_active');
      expect(schema.compositeIndexes.single.fields, ['email', 'active']);
      expect(schema.writeNativeDocument, isNotNull);
      expect(schema.readNativeDocument, isNotNull);
      expect(createdAt.dartType, 'DateTime');
      expect(plan.dartType, 'UserPlan');
      expect(primaryRecipient.dartType, 'Recipient?');
      expect(recipients.dartType, 'List<Recipient>?');
      expect(fields.any((field) => field.name == 'transientNote'), isFalse);
    });

    // Scenario: A generated serializer is used with a typed object.
    // Covers:
    // - Generated toDocument function.
    // - Generated fromDocument function.
    // Expected: The typed object round-trips through a Cindel document map.
    test('generates serializers for typed objects.', () {
      // Arrange.
      final createdAt = DateTime.utc(2026, 5, 21, 12, 30, 45, 123, 456);
      final recipient = Recipient()
        ..name = 'Ada'
        ..address = 'ada@example.com'
        ..metadata = (RecipientMetadata()..label = 'primary');
      final secondaryRecipient = Recipient()
        ..name = 'Ben'
        ..address = 'ben@example.com';
      final user = User()
        ..dbId = 7
        ..name = 'Jhon'
        ..email = 'demo@example.com'
        ..username = 'jhon'
        ..displayName = 'Jhon Doe'
        ..accessToken = 'secret-token'
        ..bio = 'Builds local databases'
        ..active = true
        ..createdAt = createdAt
        ..sessionLength = const Duration(minutes: 3, microseconds: 45)
        ..tags = ['local', 'database']
        ..scores = [10, 20]
        ..role = UserRole.owner
        ..status = UserStatus.active
        ..plan = UserPlan.pro
        ..primaryRecipient = recipient
        ..recipients = [recipient, secondaryRecipient]
        ..transientNote = 'not persisted';

      // Act.
      final document = UserSchema.toDocument(user);
      final restored = UserSchema.fromDocument({...document, 'dbId': 7});

      // Assert.
      expect(document, {
        'name': 'Jhon',
        'email': 'demo@example.com',
        'username': 'jhon',
        'displayName': 'Jhon Doe',
        'accessToken': 'secret-token',
        'bio': 'Builds local databases',
        'active': true,
        'createdAt': createdAt.microsecondsSinceEpoch,
        'sessionLength': const Duration(
          minutes: 3,
          microseconds: 45,
        ).inMicroseconds,
        'tags': ['local', 'database'],
        'scores': [10, 20],
        'role': 'owner',
        'status': 1,
        'plan': 'pro',
        'primaryRecipient': {
          'name': 'Ada',
          'address': 'ada@example.com',
          'metadata': {'label': 'primary'},
        },
        'recipients': [
          {
            'name': 'Ada',
            'address': 'ada@example.com',
            'metadata': {'label': 'primary'},
          },
          {'name': 'Ben', 'address': 'ben@example.com', 'metadata': null},
        ],
      });
      expect(restored.dbId, 7);
      expect(restored.name, 'Jhon');
      expect(restored.email, 'demo@example.com');
      expect(restored.username, 'jhon');
      expect(restored.displayName, 'Jhon Doe');
      expect(restored.accessToken, 'secret-token');
      expect(restored.bio, 'Builds local databases');
      expect(restored.active, isTrue);
      expect(restored.createdAt, createdAt);
      expect(
        restored.sessionLength,
        const Duration(minutes: 3, microseconds: 45),
      );
      expect(restored.tags, ['local', 'database']);
      expect(restored.scores, [10, 20]);
      expect(restored.role, UserRole.owner);
      expect(restored.status, UserStatus.active);
      expect(restored.plan, UserPlan.pro);
      expect(restored.primaryRecipient?.name, 'Ada');
      expect(restored.primaryRecipient?.address, 'ada@example.com');
      expect(restored.primaryRecipient?.metadata?.label, 'primary');
      expect(restored.recipients?.map((recipient) => recipient.name), [
        'Ada',
        'Ben',
      ]);
      expect(restored.transientNote, '');
    });

    // Scenario: A generated serializer is used with Cindel binary documents.
    // Covers:
    // - Generated binary writer.
    // - Generated binary reader.
    // Expected: Stored field values round-trip without JSON map decoding.
    test('generates binary serializers for typed objects.', () {
      // Arrange.
      final createdAt = DateTime.utc(2026, 5, 21, 12, 30, 45, 123, 456);
      final recipient = Recipient()
        ..name = 'Ada'
        ..address = 'ada@example.com'
        ..metadata = (RecipientMetadata()..label = 'primary');
      final user = User()
        ..dbId = 7
        ..name = 'Jhon'
        ..email = 'demo@example.com'
        ..username = 'jhon'
        ..displayName = 'Jhon Doe'
        ..accessToken = 'secret-token'
        ..bio = 'Builds local databases'
        ..active = true
        ..createdAt = createdAt
        ..sessionLength = const Duration(minutes: 3, microseconds: 45)
        ..tags = ['local', 'database']
        ..scores = [10, 20]
        ..role = UserRole.owner
        ..status = UserStatus.active
        ..plan = UserPlan.pro
        ..primaryRecipient = recipient
        ..recipients = [recipient];

      // Act.
      final bytes = UserSchema.toBinaryDocument!(user);
      final storedValues = cindelDecodeSchemaBinaryDocument(bytes, const [
        CindelBinaryFieldType.stringValue,
        CindelBinaryFieldType.boolValue,
        CindelBinaryFieldType.stringValue,
        CindelBinaryFieldType.intValue,
        CindelBinaryFieldType.stringValue,
        CindelBinaryFieldType.stringValue,
        CindelBinaryFieldType.stringValue,
        CindelBinaryFieldType.stringValue,
        CindelBinaryFieldType.objectValue,
        CindelBinaryFieldType.listValue,
        CindelBinaryFieldType.stringValue,
        CindelBinaryFieldType.listValue,
        CindelBinaryFieldType.intValue,
        CindelBinaryFieldType.intValue,
        CindelBinaryFieldType.listValue,
        CindelBinaryFieldType.stringValue,
      ]);
      final restored = UserSchema.fromBinaryDocument!(bytes);

      // Assert.
      expect(storedValues[3], createdAt.microsecondsSinceEpoch);
      expect(storedValues[13], 1);
      expect(restored.dbId, autoIncrement);
      expect(restored.name, 'Jhon');
      expect(restored.createdAt, createdAt);
      expect(
        restored.sessionLength,
        const Duration(minutes: 3, microseconds: 45),
      );
      expect(restored.tags, ['local', 'database']);
      expect(restored.scores, [10, 20]);
      expect(restored.role, UserRole.owner);
      expect(restored.status, UserStatus.active);
      expect(restored.plan, UserPlan.pro);
      expect(restored.primaryRecipient?.metadata?.label, 'primary');
      expect(restored.recipients?.single.address, 'ada@example.com');
    });

    // Scenario: Native storage returns compact list data for a generated
    // schema field.
    // Covers:
    // - Compact binary list decoding.
    // - Nullable list item preservation.
    // Expected: The decoded field preserves the original string and null items.
    test(
      'decodes native compact string list payloads from binary documents.',
      () {
        // Arrange.
        final bytes = _compactSingleListDocument(['local', null, 'database']);

        // Act.
        final storedValues = cindelDecodeSchemaBinaryDocument(bytes, const [
          CindelBinaryFieldType.listValue,
        ]);

        // Assert.
        expect(storedValues.single, ['local', null, 'database']);
      },
    );

    // Scenario: A generated schema assigns an auto-increment id.
    // Covers:
    // - Generated setId function.
    // - Schema metadata used by typed auto-increment writes.
    // Expected: The generated setter mutates the dbId field on the typed object.
    test('generates an id setter for auto-increment writes.', () {
      // Arrange.
      final user = User()
        ..name = 'Noel'
        ..email = 'demo@example.com';

      // Act.
      UserSchema.setId!(user, 42);

      // Assert.
      expect(user.dbId, 42);
    });

    // Scenario: A generated schema has both Cindel dbId and an API id field.
    // Covers:
    // - dbId detection as the internal Cindel document id.
    // - Normal persistence and query helper generation for a field named id.
    // Expected: dbId is used as the storage key and id remains a normal field.
    test('keeps id free for API models when dbId is the Cindel id.', () {
      // Arrange.
      final product = ApiProduct()
        ..dbId = 9
        ..id = 'api-product-9'
        ..name = 'Notebook';

      // Act.
      final document = ApiProductSchema.toDocument(product);
      final restored = ApiProductSchema.fromDocument({...document, 'dbId': 9});

      // Assert.
      expect(ApiProductSchema.idField, 'dbId');
      expect(ApiProductSchema.fields.map((field) => field.name), [
        'dbId',
        'id',
        'name',
      ]);
      expect(document, {'id': 'api-product-9', 'name': 'Notebook'});
      expect(restored.dbId, 9);
      expect(restored.id, 'api-product-9');
      expect(restored.name, 'Notebook');
    });

    // Scenario: A generated schema hydrates an immutable explicit-id model.
    // Covers:
    // - Constructor-based generated hydration for final persisted fields.
    // - Omission of auto-increment id setter metadata when id is final.
    // Expected: The immutable model round-trips and does not expose setId.
    test('supports immutable explicit-id collection models.', () {
      // Arrange.
      const user = ImmutableUser(
        dbId: 7,
        email: 'immutable@example.com',
        active: true,
      );

      // Act.
      final document = ImmutableUserSchema.toDocument(user);
      final restored = ImmutableUserSchema.fromDocument({
        ...document,
        'dbId': 7,
      });

      // Assert.
      expect(ImmutableUserSchema.setId, isNull);
      expect(document, {'email': 'immutable@example.com', 'active': true});
      expect(restored.dbId, 7);
      expect(restored.email, 'immutable@example.com');
      expect(restored.active, isTrue);
    });

    // Scenario: A generated schema hydrates a Freezed primary-factory model.
    // Covers:
    // - Persisted properties discovered from factory parameters.
    // - Parameter annotations such as @Index, @Enumerated, and @ignore.
    // - Constructor-based JSON and binary hydration through the primary factory.
    // Expected: The Freezed model round-trips and keeps generated value APIs.
    test('supports Freezed primary-factory collection models.', () {
      // Arrange.
      const user = FreezedPrimaryUser(
        dbId: 11,
        email: 'factory@example.com',
        username: 'factory-user',
        status: UserStatus.active,
        transientNote: 'not persisted',
      );

      // Act.
      final copied = user.copyWith(active: false);
      final document = FreezedPrimaryUserSchema.toDocument(copied);
      final restored = FreezedPrimaryUserSchema.fromDocument({
        ...document,
        'dbId': 11,
      });
      final binaryBytes = FreezedPrimaryUserSchema.toBinaryDocument!(copied);
      final binaryRestored = FreezedPrimaryUserSchema.fromBinaryDocument!(
        binaryBytes,
      );

      // Assert.
      expect(FreezedPrimaryUserSchema.setId, isNull);
      expect(FreezedPrimaryUserSchema.fields.map((field) => field.name), [
        'dbId',
        'email',
        'username',
        'status',
        'active',
      ]);
      expect(
        FreezedPrimaryUserSchema.fields.singleWhere(
          (field) => field.name == 'username',
        ),
        isA<CindelFieldSchema>()
            .having((field) => field.isIndexed, 'isIndexed', isTrue)
            .having((field) => field.isIndexUnique, 'isIndexUnique', isTrue),
      );
      expect(document, {
        'email': 'factory@example.com',
        'username': 'factory-user',
        'status': 1,
        'active': false,
      });
      expect(restored.dbId, copied.dbId);
      expect(restored.email, copied.email);
      expect(restored.username, copied.username);
      expect(restored.status, copied.status);
      expect(restored.active, copied.active);
      expect(restored.transientNote, isNull);
      expect(binaryRestored.dbId, autoIncrement);
      expect(binaryRestored.email, copied.email);
      expect(binaryRestored.username, copied.username);
      expect(binaryRestored.status, copied.status);
      expect(binaryRestored.active, copied.active);
      expect(binaryRestored.transientNote, isNull);
    });

    // Scenario: A generated schema persists expanded Dart field shapes.
    // Covers:
    // - Native in-memory persistence of encoded DateTime and Duration values.
    // - Primitive list JSON storage.
    // - Enum persistence by name, ordinal, and custom value.
    // Expected: A typed object round-trips through the native document store.
    test('round-trips expanded schema types through Cindel.', () async {
      // Arrange.
      final db = await openTestDatabaseInMemory(schemas: [UserSchema]);
      final createdAt = DateTime.utc(2026, 5, 21, 13, 20);
      final primaryRecipient = Recipient()
        ..name = 'Grace'
        ..address = 'grace@example.com'
        ..metadata = (RecipientMetadata()..label = 'lead');
      final secondaryRecipient = Recipient()
        ..name = 'Mary'
        ..address = 'mary@example.com';
      final user = User()
        ..name = 'Ada'
        ..email = 'ada@example.com'
        ..username = null
        ..displayName = null
        ..accessToken = null
        ..bio = null
        ..active = null
        ..createdAt = createdAt
        ..sessionLength = null
        ..tags = ['compiler', 'math']
        ..scores = null
        ..role = UserRole.member
        ..status = UserStatus.blocked
        ..plan = UserPlan.enterprise
        ..primaryRecipient = primaryRecipient
        ..recipients = [primaryRecipient, secondaryRecipient];

      addTearDown(db.close);

      // Act.
      await db.users.put(user);
      final restored = await db.users.get(user.dbId);
      final createdAtMatches = await db.users
          .all()
          .filter()
          .createdAtBetween(createdAt, createdAt)
          .findAll();
      final planMatches = await db.users
          .all()
          .filter()
          .planEqualTo(UserPlan.enterprise)
          .findAll();
      final createdAtValues = await db.users
          .all()
          .createdAtProperty()
          .findAll();
      final statusValues = await db.users.all().statusProperty().findAll();
      final planValues = await db.users.all().planProperty().findAll();
      final primaryRecipientValues = await db.users
          .all()
          .primaryRecipientProperty()
          .findAll();
      final recipientValues = await db.users
          .all()
          .recipientsProperty()
          .findAll();
      final primaryRecipientMatches = await db.users
          .all()
          .filter()
          .primaryRecipient((recipient) {
            return recipient.addressEqualTo('grace@example.com');
          })
          .findAll();
      final metadataMatches = await db.users.all().filter().primaryRecipient((
        recipient,
      ) {
        return recipient.metadata((metadata) {
          return metadata.labelEqualTo('lead');
        });
      }).findAll();

      // Assert.
      expect(restored, isNotNull);
      expect(restored!.createdAt, createdAt);
      expect(restored.sessionLength, isNull);
      expect(restored.tags, ['compiler', 'math']);
      expect(restored.scores, isNull);
      expect(restored.role, UserRole.member);
      expect(restored.status, UserStatus.blocked);
      expect(restored.plan, UserPlan.enterprise);
      expect(restored.primaryRecipient?.name, 'Grace');
      expect(restored.primaryRecipient?.metadata?.label, 'lead');
      expect(restored.recipients?.map((recipient) => recipient.address), [
        'grace@example.com',
        'mary@example.com',
      ]);
      expect(createdAtMatches.map((user) => user.email), ['ada@example.com']);
      expect(planMatches.map((user) => user.email), ['ada@example.com']);
      expect(createdAtValues, [createdAt]);
      expect(statusValues, [UserStatus.blocked]);
      expect(planValues, [UserPlan.enterprise]);
      expect(primaryRecipientValues.single?.name, 'Grace');
      expect(recipientValues.single?.map((recipient) => recipient.name), [
        'Grace',
        'Mary',
      ]);
      expect(primaryRecipientMatches.map((user) => user.email), [
        'ada@example.com',
      ]);
      expect(metadataMatches.map((user) => user.email), ['ada@example.com']);
    });

    // Scenario: A generated query update changes a string-list field.
    // Covers:
    // - Native update serialization for compact List<String> fields.
    // - Reading the updated list back through the generated native reader.
    // Expected: Matching objects receive the replacement tags list.
    test(
      'updates generated string-list fields through native queries.',
      () async {
        // Arrange.
        final db = await openTestDatabaseInMemory(schemas: [UserSchema]);
        final first = User()
          ..name = 'Ada'
          ..email = 'ada@example.com'
          ..active = true
          ..tags = ['old'];
        final second = User()
          ..name = 'Ben'
          ..email = 'ben@example.com'
          ..active = false
          ..tags = ['keep'];

        addTearDown(db.close);

        // Act.
        await db.users.putAll([first, second]);
        final updated = await db.users
            .all()
            .filter()
            .activeEqualTo(true)
            .updateAll({
              'tags': ['fresh', 'fast'],
            });
        final users = await db.users.all().sortByEmail().findAll();

        // Assert.
        expect(updated, 1);
        expect(users.map((user) => user.tags), [
          ['fresh', 'fast'],
          ['keep'],
        ]);
      },
    );
  });
}

Uint8List _compactSingleListDocument(List<String?> values) {
  final payload = _compactStringListPayload(values);
  final bytes = Uint8List(3 + 3 + 3 + payload.length);
  _writeUint24(bytes, 0, 3);
  _writeUint24(bytes, 3, 3);
  _writeUint24(bytes, 6, payload.length);
  bytes.setRange(9, bytes.length, payload);
  return bytes;
}

Uint8List _compactStringListPayload(List<String?> values) {
  final staticSize = values.length * 3;
  final bytes = <int>[..._uint24(staticSize), ...List.filled(staticSize, 0)];
  for (var i = 0; i < values.length; i += 1) {
    final value = values[i];
    if (value == null) {
      continue;
    }
    final encoded = value.codeUnits;
    final offset = bytes.length - 3;
    bytes.setRange(3 + i * 3, 6 + i * 3, _uint24(offset));
    bytes
      ..addAll(_uint24(encoded.length))
      ..addAll(encoded);
  }
  return Uint8List.fromList(bytes);
}

List<int> _uint24(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
];

void _writeUint24(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
}
