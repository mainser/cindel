import 'package:test/test.dart';

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

      // Assert.
      expect(schema.name, 'users');
      expect(schema.dartName, 'User');
      expect(schema.idField, 'id');
      expect(fields.map((field) => field.name), [
        'id',
        'name',
        'email',
        'active',
      ]);
      expect(indexedFields.map((field) => field.name), ['email']);
    });

    // Scenario: A generated serializer is used with a typed object.
    // Covers:
    // - Generated toDocument function.
    // - Generated fromDocument function.
    // Expected: The typed object round-trips through a Cindel document map.
    test('generates serializers for typed objects.', () {
      // Arrange.
      final user = User()
        ..id = 7
        ..name = 'Noel'
        ..email = 'demo@example.com'
        ..active = true;

      // Act.
      final document = UserSchema.toDocument(user);
      final restored = UserSchema.fromDocument(document);

      // Assert.
      expect(document, {
        'id': 7,
        'name': 'Noel',
        'email': 'demo@example.com',
        'active': true,
      });
      expect(restored.id, 7);
      expect(restored.name, 'Noel');
      expect(restored.email, 'demo@example.com');
      expect(restored.active, isTrue);
    });
  });
}
