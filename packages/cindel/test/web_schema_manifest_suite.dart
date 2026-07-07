import 'package:cindel/src/native/wire.dart';
import 'package:cindel/src/schema.dart';
import 'package:cindel/src/web/schema_manifest.dart';
import 'package:test/test.dart';

void main() {
  // Scenario: Dart Web prepares generated schemas for the Worker/Wasm opener.
  // Covers:
  // - Internal Web schema manifest encoding.
  // - Web schema manifest encoding using the native wire format.
  // - Stable field ordering before the manifest crosses the Worker boundary.
  // Expected: The encoded manifest decodes through the native wire decoder with
  // the same collection, id field, field order, and binary field metadata.
  test('web schema manifest encoder uses native wire shape', () {
    // Arrange / Act.
    final bytes = cindelEncodeWebSchemaManifest([
      CindelCollectionSchema<Map<String, Object?>>(
        name: 'users',
        dartName: 'User',
        idField: 'id',
        fields: const [
          CindelFieldSchema(
            name: 'id',
            dartType: 'int',
            binaryType: 'int',
            isId: true,
            isIndexed: false,
          ),
          CindelFieldSchema(
            name: 'email',
            dartType: 'String',
            binaryType: 'string',
            isId: false,
            isIndexed: true,
          ),
        ],
        compositeIndexes: [
          CindelCompositeIndexSchema(
            name: 'email_id',
            fields: const ['email', 'id'],
            isUnique: true,
            isReplace: true,
            caseSensitive: false,
          ),
        ],
        toDocument: (object) => object,
        fromDocument: (document) => document,
      ),
    ]);

    final manifest = decodeSchemaManifest(bytes);

    // Assert.
    expect(manifest.version, 1);
    expect(manifest.collections, hasLength(1));
    expect(manifest.collections.single.name, 'users');
    expect(manifest.collections.single.idField, 'id');
    expect(manifest.collections.single.fields.map((field) => field.name), [
      'email',
      'id',
    ]);
    expect(manifest.collections.single.fields.first.binaryType, 'string');
    expect(manifest.collections.single.indexes, hasLength(1));
    expect(manifest.collections.single.indexes.single.name, 'email_id');
    expect(manifest.collections.single.indexes.single.fields, ['email', 'id']);
    expect(manifest.collections.single.indexes.single.isUnique, isTrue);
    expect(manifest.collections.single.indexes.single.isReplace, isTrue);
    expect(manifest.collections.single.indexes.single.caseSensitive, isFalse);
  });

  // Scenario: Dart Web generated code uses the direct native row encoder.
  // Covers:
  // - Direct SQLite-native document batch encoder.
  // - Decode compatibility with the existing CindelWireV1 native batch shape.
  // Expected: The encoder emits readable native document rows.
  test('direct native document batch encoder uses the CindelWire shape', () {
    // Arrange / Act.
    final bytes = encodeNativeDocumentWriteBatchDirect<String>(
      ids: const [1],
      objects: const ['web'],
      fieldCount: 1,
      writeDocument: (writer, object) {
        writer.writeString(0, object);
      },
    );
    final documents = decodeNativeDocumentWriteBatch(bytes);

    // Assert.
    expect(documents, hasLength(1));
    expect(documents.single.id, 1);
    final value = documents.single.values.single;
    expect(value, isA<WireNativeDocumentBytes>());
    expect((value as WireNativeDocumentBytes).value, [119, 101, 98]);
  });
}
