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
}
