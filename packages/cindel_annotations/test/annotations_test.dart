import 'package:cindel_annotations/cindel_annotations.dart';
import 'package:test/test.dart';

void main() {
  group('cindel annotations', () {
    // Scenario: Application models use collection-level annotations.
    // Covers:
    // - Default `Collection` values and the `collection` constant.
    // - Named collections with composite index metadata.
    // Expected: Public annotation values remain stable for generator reads.
    test('exposes collection annotations and defaults.', () {
      const defaultCollection = Collection();
      const namedCollection = Collection(
        name: 'users',
        indexes: [
          CompositeIndex(['email', 'active'], unique: true, replace: true),
        ],
      );

      expect(collection.name, isNull);
      expect(collection.indexes, isEmpty);
      expect(defaultCollection.name, isNull);
      expect(defaultCollection.indexes, isEmpty);
      expect(namedCollection.name, 'users');
      expect(namedCollection.indexes.single.fields, ['email', 'active']);
      expect(namedCollection.indexes.single.unique, isTrue);
      expect(namedCollection.indexes.single.replace, isTrue);
      expect(namedCollection.indexes.single.caseSensitive, isTrue);
    });

    // Scenario: Application model fields use persisted names and index
    // annotations.
    // Covers:
    // - `Name` persisted-value storage.
    // - Default `index` constant options.
    // - Explicit `Index` option overrides.
    // - Public `CindelIndexType` ordering.
    // Expected: Generator-facing index metadata remains stable.
    test('exposes field annotations and index options.', () {
      const renamed = Name('user_name');
      const hashedIndex = Index(
        unique: true,
        replace: true,
        caseSensitive: false,
        type: CindelIndexType.hash,
      );

      expect(renamed.value, 'user_name');
      expect(index.unique, isFalse);
      expect(index.replace, isFalse);
      expect(index.caseSensitive, isTrue);
      expect(index.type, CindelIndexType.value);
      expect(hashedIndex.unique, isTrue);
      expect(hashedIndex.replace, isTrue);
      expect(hashedIndex.caseSensitive, isFalse);
      expect(hashedIndex.type, CindelIndexType.hash);
      expect(CindelIndexType.values, [
        CindelIndexType.value,
        CindelIndexType.hash,
        CindelIndexType.words,
        CindelIndexType.multiEntry,
      ]);
    });

    // Scenario: Application models use the remaining public annotation helpers.
    // Covers:
    // - `embedded` and `ignore` constants.
    // - `Enumerated` strategies and value-field metadata.
    // - Public `CindelEnumType` ordering.
    // - `Id` and `autoIncrement` public id helpers.
    // Expected: Annotation-only consumers can rely on the public constants and
    // enum values without importing runtime packages.
    test('exposes embedded, ignore, enum, and id helpers.', () {
      const byName = Enumerated(CindelEnumType.name);
      const byValue = Enumerated(CindelEnumType.value, valueField: 'code');
      final backlink = Backlink(to: 'songs');

      expect(embedded, isA<Embedded>());
      expect(ignore, isA<Ignore>());
      expect(backlink.to, 'songs');
      expect(byName.type, CindelEnumType.name);
      expect(byName.valueField, isNull);
      expect(byValue.type, CindelEnumType.value);
      expect(byValue.valueField, 'code');
      expect(CindelEnumType.values, [
        CindelEnumType.name,
        CindelEnumType.ordinal,
        CindelEnumType.value,
      ]);
      expect(autoIncrement, -1);
      const Id explicitId = 42;
      expect(explicitId, 42);
    });
  });
}
