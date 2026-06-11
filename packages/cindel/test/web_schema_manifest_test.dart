import 'package:cindel/cindel_web.dart';
import 'package:cindel/src/native/wire.dart';
import 'package:test/test.dart';

void main() {
  // Scenario: Dart Web prepares generated schemas for the Worker/Wasm opener.
  // Covers:
  // - Public `package:cindel/cindel_web.dart` schema exports.
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
  });

  // Scenario: Dart Web generated code imports the separate Web entrypoint.
  // Covers:
  // - Public export of the direct SQLite-native document batch encoder.
  // - Decode compatibility with the existing CindelWireV1 native batch shape.
  // Expected: The Web entrypoint exposes an encoder that emits readable native
  // document rows without requiring the internal wire library at call sites.
  test('web entrypoint exports direct native document batch encoder', () {
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
