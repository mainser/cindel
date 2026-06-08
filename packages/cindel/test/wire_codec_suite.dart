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

    // Scenario: Dart sends every index value tag to Rust.
    // Covers:
    // - Null, bool, int, double, string, and list index value tags.
    // Expected: Every index value variant round-trips through the wire codec.
    test('encodes and decodes all index value variants', () {
      // Arrange.
      const values = [
        WireIndexValue.nullValue(),
        WireIndexValue.bool(false),
        WireIndexValue.int(-7),
        WireIndexValue.double(2.5),
        WireIndexValue.string('A'),
        WireIndexValue.list([WireIndexValue.nullValue()]),
      ];

      // Act / Assert.
      for (final value in values) {
        expect(decodeIndexValue(encodeIndexValue(value)), value);
      }
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

    // Scenario: Dart receives every scalar tag from Rust.
    // Covers:
    // - Null, bool, int, double, and string scalar tags.
    // Expected: Every scalar variant round-trips through the wire codec.
    test('encodes and decodes all scalar variants', () {
      // Arrange.
      const values = [
        WireScalar.nullValue(),
        WireScalar.bool(false),
        WireScalar.int(-7),
        WireScalar.double(-0.0),
        WireScalar.string('A'),
      ];

      // Act / Assert.
      for (final value in values) {
        expect(decodeScalar(encodeScalar(value)), value);
      }
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

    // Scenario: Dart sends every native filter operation to Rust.
    // Covers:
    // - All WireFilterOperation tag mappings.
    // - Any-filter encoding.
    // Expected: Every filter operation and the any combinator round-trip.
    test('encodes and decodes all filter operations', () {
      // Arrange.
      const filters = WireFilter.any([
        WireFilter.field(
          field: 'age',
          operation: WireFilterOperation.lessThan,
          value: WireValue.int(30),
        ),
        WireFilter.field(
          field: 'age',
          operation: WireFilterOperation.lessThanOrEqual,
          value: WireValue.int(30),
        ),
        WireFilter.field(
          field: 'age',
          operation: WireFilterOperation.greaterThan,
          value: WireValue.int(30),
        ),
        WireFilter.field(
          field: 'age',
          operation: WireFilterOperation.greaterThanOrEqual,
          value: WireValue.int(30),
        ),
        WireFilter.field(
          field: 'tags',
          operation: WireFilterOperation.contains,
          value: WireValue.string('admin'),
        ),
        WireFilter.field(
          field: 'email',
          operation: WireFilterOperation.endsWith,
          value: WireValue.string('.dev'),
        ),
        WireFilter.field(
          field: 'deletedAt',
          operation: WireFilterOperation.isNull,
          value: WireValue.nullValue(),
        ),
      ]);

      // Act / Assert.
      expect(decodeFilter(encodeFilter(filters)), filters);
    });

    // Scenario: Dart sends a native query plan to Rust.
    // Covers:
    // - Query source, sort, distinct, offset, and limit encoding.
    // - Byte-for-byte compatibility with the Rust query-plan fixture.
    // Expected: The full plan payload round-trips without JSON.
    test('encodes and decodes query plan fixture', () {
      // Arrange.
      const plan = WireQueryPlan(
        source: WireQuerySource.indexRange(
          indexName: 'name',
          lower: WireIndexValue.string('A'),
          upper: WireIndexValue.string('B'),
          dedupe: true,
        ),
        filter: null,
        sorts: [WireQuerySort(field: 'id', ascending: true)],
        distinctFields: ['name'],
        offset: 2,
        limit: 5,
      );

      // Act / Assert.
      expect(encodeQueryPlan(plan), queryPlanFixture);
      expect(decodeQueryPlan(bytes(queryPlanFixture)), plan);
    });

    // Scenario: Dart sends all query source variants.
    // Covers:
    // - All source, index-equal, and open index-range query source tags.
    // - Null filter and null limit query-plan flags.
    // Expected: Query source variants round-trip without losing flags.
    test('encodes and decodes query plan source variants', () {
      // Arrange.
      const plans = [
        WireQueryPlan(
          source: WireQuerySource.all(dedupe: true),
          filter: null,
          sorts: [],
          distinctFields: [],
          offset: 0,
          limit: null,
        ),
        WireQueryPlan(
          source: WireQuerySource.indexEqual(
            indexName: 'email',
            value: WireIndexValue.nullValue(),
            dedupe: false,
          ),
          filter: null,
          sorts: [],
          distinctFields: [],
          offset: 1,
          limit: null,
        ),
        WireQueryPlan(
          source: WireQuerySource.indexRange(
            indexName: 'email',
            lower: null,
            upper: null,
            dedupe: true,
          ),
          filter: null,
          sorts: [],
          distinctFields: [],
          offset: 2,
          limit: null,
        ),
      ];

      // Act / Assert.
      for (final plan in plans) {
        expect(decodeQueryPlan(encodeQueryPlan(plan)), plan);
      }
    });

    // Scenario: Rust returns compact post-commit watcher change sets.
    // Covers:
    // - Collection name, revision, and changed document ids.
    // - Byte-for-byte compatibility with the Rust change-set fixture.
    // Expected: Watcher metadata round-trips without JSON.
    test('encodes and decodes change set fixture', () {
      // Arrange.
      const changes = [
        WireChangeSet(collection: 'users', revision: 3, documentIds: [7, 9]),
      ];

      // Act / Assert.
      expect(encodeChangeSetList(changes), changeSetFixture);
      expect(decodeChangeSetList(bytes(changeSetFixture)), changes);
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

    // Scenario: Rust returns projected object cells.
    // Covers:
    // - WireValue double and object tags.
    // Expected: Nested projected values round-trip.
    test('encodes and decodes object projection cells', () {
      // Arrange.
      const rows = WireProjectionRows(
        rowCount: 1,
        columnCount: 2,
        cells: [
          WireValue.double(2.5),
          WireValue.object([
            WireObjectEntry('name', WireValue.string('Ana')),
            WireObjectEntry('active', WireValue.bool(true)),
          ]),
        ],
      );

      // Act / Assert.
      expect(decodeProjectionRows(encodeProjectionRows(rows)), rows);
    });

    // Scenario: Dart attempts to encode an invalid projection matrix.
    // Covers:
    // - Projection cell count validation before writing bytes.
    // Expected: Invalid dimensions throw FormatException.
    test('rejects projection rows with mismatched cell count', () {
      // Arrange.
      const rows = WireProjectionRows(
        rowCount: 2,
        columnCount: 2,
        cells: [WireValue.nullValue()],
      );

      // Act / Assert.
      expect(() => encodeProjectionRows(rows), throwsFormatException);
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
                binaryType: 'int',
                indexType: 'value',
                isId: true,
                isIndexed: false,
                isUnique: false,
                isReplace: false,
                isNullable: false,
                caseSensitive: true,
              ),
            ],
            indexes: [
              WireIndexSchema(
                name: 'by_id',
                fields: ['id'],
                isUnique: true,
                isReplace: false,
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

    // Scenario: Dart callers attempt to write integers outside wire bounds.
    // Covers:
    // - Unsigned 32-bit and 64-bit writer range checks.
    // Expected: Invalid integer bounds throw RangeError before bytes are built.
    test('rejects out-of-range writer integers', () {
      // Arrange.
      final writer = CindelWireWriter();

      // Act / Assert.
      expect(() => writer.writeUint32(-1), throwsRangeError);
      expect(() => writer.writeUint32(0x100000000), throwsRangeError);
      expect(() => writer.writeUint64(-1), throwsRangeError);
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

const queryPlanFixture = [
  3,
  1,
  4,
  0,
  0,
  0,
  110,
  97,
  109,
  101,
  1,
  4,
  1,
  0,
  0,
  0,
  65,
  1,
  4,
  1,
  0,
  0,
  0,
  66,
  0,
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
  0,
  0,
  0,
  4,
  0,
  0,
  0,
  110,
  97,
  109,
  101,
  2,
  0,
  0,
  0,
  1,
  5,
  0,
  0,
  0,
];

const changeSetFixture = [
  1,
  0,
  0,
  0,
  5,
  0,
  0,
  0,
  117,
  115,
  101,
  114,
  115,
  3,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  2,
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
  9,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
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
  0,
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
