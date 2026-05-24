import 'dart:typed_data';

import 'package:cindel/src/native/wire.dart';
import 'package:test/test.dart';

void main() {
  group('CindelWireV1', () {
    // Scenario: A Dart caller sends a compact list of document ids to Rust.
    // Covers:
    // - IdList little-endian count and u64 element encoding.
    // - IdList fixture compatibility with the Rust codec tests.
    // Expected: Dart encodes the exact fixture bytes and decodes them back.
    test('encodes and decodes id list fixture', () {
      // Arrange.
      final ids = [7, 255, 65536];

      // Act / Assert.
      expect(encodeIdList(ids), idsFixture);
      expect(decodeIdList(bytes(idsFixture)), ids);
    });

    // Scenario: A Dart caller sends a nested tagged index value to Rust.
    // Covers:
    // - IndexValue list, bool, int, and string tags.
    // - Byte-for-byte compatibility with the Rust index-value fixture.
    // Expected: The canonical binary payload round-trips without JSON.
    test('encodes and decodes index value fixture', () {
      // Arrange.
      const value = WireIndexValue.list([
        WireIndexValue.bool(true),
        WireIndexValue.int(-2),
        WireIndexValue.string('hi'),
      ]);

      // Act / Assert.
      expect(encodeIndexValue(value), indexValueFixture);
      expect(decodeIndexValue(bytes(indexValueFixture)), value);
    });

    // Scenario: A Dart caller receives or sends a scalar query result.
    // Covers:
    // - Scalar double tag and little-endian f64 payload.
    // - Byte-for-byte compatibility with the Rust scalar fixture.
    // Expected: The scalar payload round-trips as 1.5.
    test('encodes and decodes scalar fixture', () {
      // Arrange.
      const value = WireScalar.double(1.5);

      // Act / Assert.
      expect(encodeScalar(value), scalarFixture);
      expect(decodeScalar(bytes(scalarFixture)), value);
    });

    // Scenario: Dart sends a native filter AST to Rust.
    // Covers:
    // - Filter all/not/field tags.
    // - Filter operation tags and nested scalar values.
    // - Byte-for-byte compatibility with the Rust filter fixture.
    // Expected: The filter payload round-trips without JSON.
    test('encodes and decodes filter fixture', () {
      // Arrange.
      const filter = WireFilter.all([
        WireFilter.field(
          field: 'active',
          operation: WireFilterOperation.equal,
          value: WireValue.bool(true),
        ),
        WireFilter.not(
          WireFilter.field(
            field: 'name',
            operation: WireFilterOperation.startsWith,
            value: WireValue.string('A'),
          ),
        ),
      ]);

      // Act / Assert.
      expect(encodeFilter(filter), filterFixture);
      expect(decodeFilter(bytes(filterFixture)), filter);
    });

    // Scenario: Dart batches document writes before crossing the FFI boundary.
    // Covers:
    // - DocumentWriteBatch count, id, byte length, and empty-byte handling.
    // - Byte-for-byte compatibility with the Rust document-batch fixture.
    // Expected: The batch round-trips with ids and document bytes preserved.
    test('encodes and decodes document batch fixture', () {
      // Arrange.
      final documents = [
        WireDocumentWrite(id: 9, bytes: bytes([97, 98, 99])),
        WireDocumentWrite(id: 10, bytes: bytes([])),
      ];

      // Act / Assert.
      expect(encodeDocumentWriteBatch(documents), documentBatchFixture);
      expect(decodeDocumentWriteBatch(bytes(documentBatchFixture)), documents);
    });

    // Scenario: Dart batches indexed document writes before crossing FFI.
    // Covers:
    // - Document bytes plus per-document index names and tagged values.
    // - Byte-for-byte compatibility with the Rust indexed-write fixture.
    // Expected: The indexed batch round-trips without a JSON envelope.
    test('encodes and decodes indexed document batch fixture', () {
      // Arrange.
      final documents = [
        WireIndexedDocumentWrite(
          id: 9,
          bytes: bytes([97, 98, 99]),
          indexes: const [
            WireIndexEntry(
              documentId: 9,
              indexName: 'email',
              value: WireIndexValue.string('a'),
            ),
          ],
        ),
      ];

      // Act / Assert.
      expect(
        encodeIndexedDocumentWriteBatch(documents),
        indexedDocumentBatchFixture,
      );
      expect(
        decodeIndexedDocumentWriteBatch(bytes(indexedDocumentBatchFixture)),
        documents,
      );
    });

    // Scenario: Rust returns projected cells without hydrating full documents.
    // Covers:
    // - ProjectionRows row/column counts.
    // - Nullable scalar and list cell encoding.
    // Expected: Projection rows decode with the same cell order and values.
    test('encodes and decodes projection rows fixture', () {
      // Arrange.
      const rows = WireProjectionRows(
        rowCount: 1,
        columnCount: 3,
        cells: [
          WireValue.nullValue(),
          WireValue.string('A'),
          WireValue.list([WireValue.int(5), WireValue.bool(false)]),
        ],
      );

      // Act / Assert.
      expect(encodeProjectionRows(rows), projectionRowsFixture);
      expect(decodeProjectionRows(bytes(projectionRowsFixture)), rows);
    });

    // Scenario: Dart registers schema metadata through a binary manifest.
    // Covers:
    // - Collection, field, and index schema binary encoding.
    // - Boolean option encoding for id/index/unique/nullability/case flags.
    // Expected: The schema manifest fixture matches Rust byte-for-byte.
    test('encodes and decodes schema manifest fixture', () {
      // Arrange.
      const manifest = WireSchemaManifest(
        version: 1,
        collections: [
          WireCollectionSchema(
            name: 'u',
            idField: 'id',
            fields: [
              WireFieldSchema(
                name: 'id',
                typeName: 'int',
                indexType: 'value',
                isId: true,
                isIndexed: false,
                isUnique: false,
                isNullable: false,
                caseSensitive: true,
              ),
            ],
            indexes: [
              WireIndexSchema(
                name: 'by_id',
                fields: ['id'],
                isUnique: true,
                caseSensitive: true,
              ),
            ],
          ),
        ],
      );

      // Act / Assert.
      expect(encodeSchemaManifest(manifest), schemaManifestFixture);
      expect(decodeSchemaManifest(bytes(schemaManifestFixture)), manifest);
    });

    // Scenario: Rust persists reverse index metadata in a binary list.
    // Covers:
    // - IndexEntryList document id, index name, and tagged value encoding.
    // - Byte-for-byte compatibility with the Rust index-entry fixture.
    // Expected: The entry list round-trips without JSON.
    test('encodes and decodes index entry list fixture', () {
      // Arrange.
      const entries = [
        WireIndexEntry(
          documentId: 9,
          indexName: 'email',
          value: WireIndexValue.string('a'),
        ),
      ];

      // Act / Assert.
      expect(encodeIndexEntryList(entries), indexEntryListFixture);
      expect(decodeIndexEntryList(bytes(indexEntryListFixture)), entries);
    });

    // Scenario: Dart receives malformed wire payloads from native code.
    // Covers:
    // - Truncated payloads.
    // - Unknown tags.
    // - Unsafe length counts.
    // - Trailing bytes.
    // Expected: Every malformed payload throws a FormatException.
    test('rejects truncated invalid and trailing payloads', () {
      // Arrange / Act / Assert.
      expect(
        () => decodeIdList(bytes(idsFixture.take(idsFixture.length - 1))),
        throwsFormatException,
      );
      expect(() => decodeIndexValue(bytes([99])), throwsFormatException);
      expect(
        () => decodeIdList(bytes([255, 255, 255, 255])),
        throwsFormatException,
      );
      expect(
        () => decodeIdList(bytes([...idsFixture, 0])),
        throwsFormatException,
      );
      expect(() => decodeFilter(bytes([99])), throwsFormatException);
      expect(
        () => decodeFilter(
          bytes([wireFilterTagField, 1, 0, 0, 0, 97, 99, wireTagNull]),
        ),
        throwsFormatException,
      );
    });

    // Scenario: Dart receives invalid primitive wire encodings.
    // Covers:
    // - Invalid UTF-8 string bytes.
    // - Non 0/1 bool payloads.
    // Expected: Invalid primitive encodings throw FormatException.
    test('rejects invalid UTF-8 and bool values', () {
      // Arrange / Act / Assert.
      expect(
        () => decodeIndexValue(bytes([wireTagString, 1, 0, 0, 0, 0xff])),
        throwsFormatException,
      );
      expect(
        () => decodeScalar(bytes([wireTagBool, 2])),
        throwsFormatException,
      );
    });
  });
}

Uint8List bytes(Iterable<int> values) => Uint8List.fromList(values.toList());

const idsFixture = [
  3,
  0,
  0,
  0,
  7,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  255,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
];

const indexValueFixture = [
  5,
  3,
  0,
  0,
  0,
  1,
  1,
  2,
  254,
  255,
  255,
  255,
  255,
  255,
  255,
  255,
  4,
  2,
  0,
  0,
  0,
  104,
  105,
];

const scalarFixture = [3, 0, 0, 0, 0, 0, 0, 248, 63];

const filterFixture = [
  2,
  2,
  0,
  0,
  0,
  1,
  6,
  0,
  0,
  0,
  97,
  99,
  116,
  105,
  118,
  101,
  1,
  1,
  1,
  4,
  1,
  4,
  0,
  0,
  0,
  110,
  97,
  109,
  101,
  7,
  4,
  1,
  0,
  0,
  0,
  65,
];

const documentBatchFixture = [
  2,
  0,
  0,
  0,
  9,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  3,
  0,
  0,
  0,
  97,
  98,
  99,
  10,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
];

const indexedDocumentBatchFixture = [
  1,
  0,
  0,
  0,
  9,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  3,
  0,
  0,
  0,
  97,
  98,
  99,
  1,
  0,
  0,
  0,
  5,
  0,
  0,
  0,
  101,
  109,
  97,
  105,
  108,
  4,
  1,
  0,
  0,
  0,
  97,
];

const projectionRowsFixture = [
  1,
  0,
  0,
  0,
  3,
  0,
  0,
  0,
  0,
  4,
  1,
  0,
  0,
  0,
  65,
  5,
  2,
  0,
  0,
  0,
  2,
  5,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

const schemaManifestFixture = [
  1,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  117,
  2,
  0,
  0,
  0,
  105,
  100,
  1,
  0,
  0,
  0,
  2,
  0,
  0,
  0,
  105,
  100,
  3,
  0,
  0,
  0,
  105,
  110,
  116,
  5,
  0,
  0,
  0,
  118,
  97,
  108,
  117,
  101,
  1,
  0,
  0,
  0,
  1,
  1,
  0,
  0,
  0,
  5,
  0,
  0,
  0,
  98,
  121,
  95,
  105,
  100,
  1,
  0,
  0,
  0,
  2,
  0,
  0,
  0,
  105,
  100,
  1,
  1,
];

const indexEntryListFixture = [
  1,
  0,
  0,
  0,
  9,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  5,
  0,
  0,
  0,
  101,
  109,
  97,
  105,
  108,
  4,
  1,
  0,
  0,
  0,
  97,
];
