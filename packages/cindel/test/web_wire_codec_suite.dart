import 'dart:convert';
import 'dart:typed_data';

import 'package:cindel/src/binary_document.dart' as binary_document;
import 'package:cindel/src/web/binary_document.dart' as web_binary_document;
import 'package:cindel/src/web/native_document_reader.dart';
import 'package:cindel/src/web/wire.dart' as web_wire;
import 'package:test/test.dart';

void main() {
  group('Cindel Web wire codec', () {
    // Scenario: Web encodes and decodes id lists for Worker requests.
    // Covers:
    // - [web_wire.encodeIdList].
    // - [web_wire.decodeIdList].
    // - Web-safe u64 decoding guard.
    // Expected: Id order is preserved and unsafe Web integers are rejected.
    test('round-trips web id lists and rejects unsafe u64 values.', () {
      // Act / Assert.
      expect(web_wire.decodeIdList(web_wire.encodeIdList([1, 3, 5])), [
        1,
        3,
        5,
      ]);

      final unsafe = web_wire.CindelWireWriter()
        ..writeLength(1)
        ..writeUint32(0)
        ..writeUint32(0x00200000);
      expect(
        () => web_wire.decodeIdList(unsafe.finish()),
        throwsFormatException,
      );
    });

    // Scenario: Web index values represent all query source key variants.
    // Covers:
    // - Index null, bool, int, double, string, and list values.
    // - Equality for nested index lists.
    // Expected: Every index value variant round-trips through the Web codec.
    test('round-trips web index value variants.', () {
      // Arrange.
      const values = <web_wire.WireIndexValue>[
        web_wire.WireIndexValue.nullValue(),
        web_wire.WireIndexValue.bool(true),
        web_wire.WireIndexValue.int(-7),
        web_wire.WireIndexValue.double(3.5),
        web_wire.WireIndexValue.string('Ana'),
        web_wire.WireIndexValue.list([
          web_wire.WireIndexValue.string('email'),
          web_wire.WireIndexValue.int(42),
        ]),
      ];

      // Act / Assert.
      for (final value in values) {
        expect(
          web_wire.decodeIndexValue(web_wire.encodeIndexValue(value)),
          value,
        );
      }
    });

    // Scenario: Web scalar and projection values carry native query results.
    // Covers:
    // - All scalar variants.
    // - Nested [web_wire.WireValue] list/object values through projection rows.
    // Expected: Scalars and row-major projection cells round-trip.
    test('round-trips web scalars and projection rows.', () {
      // Arrange.
      const scalars = <web_wire.WireScalar>[
        web_wire.WireScalar.nullValue(),
        web_wire.WireScalar.bool(false),
        web_wire.WireScalar.int(-9),
        web_wire.WireScalar.double(2.25),
        web_wire.WireScalar.string('total'),
      ];
      const rows = web_wire.WireProjectionRows(
        rowCount: 1,
        columnCount: 3,
        cells: [
          web_wire.WireValue.int(1),
          web_wire.WireValue.list([
            web_wire.WireValue.string('vip'),
            web_wire.WireValue.bool(true),
          ]),
          web_wire.WireValue.object([
            web_wire.WireObjectEntry('nested', web_wire.WireValue.double(4.5)),
          ]),
        ],
      );

      // Act / Assert.
      for (final scalar in scalars) {
        expect(web_wire.decodeScalar(web_wire.encodeScalar(scalar)), scalar);
      }
      expect(
        web_wire.decodeProjectionRows(web_wire.encodeProjectionRows(rows)),
        rows,
      );
      expect(
        () => web_wire.encodeProjectionRows(
          const web_wire.WireProjectionRows(
            rowCount: 2,
            columnCount: 2,
            cells: [web_wire.WireValue.int(1)],
          ),
        ),
        throwsFormatException,
      );
    });

    // Scenario: Generated Web code imports the native binary-document symbols.
    // Covers:
    // - Web schema-binary document placeholder construction.
    // - Unsupported schema-binary reader methods.
    // - Unsupported schema-binary top-level encode/decode helpers.
    // Expected: Web keeps the symbols analyzable while routing generated
    // storage through SQLite native rows instead.
    test('keeps schema-binary document APIs unsupported on web.', () {
      // Arrange.
      final reader = web_binary_document.CindelSchemaBinaryDocumentReader(
        _bytes([]),
        staticSize: 0,
      );

      // Act / Assert.
      expect(() => reader.readId(0), throwsUnsupportedError);
      expect(() => reader.readBool(0, 0), throwsUnsupportedError);
      expect(() => reader.readInt(0, 0), throwsUnsupportedError);
      expect(() => reader.readDouble(0, 0), throwsUnsupportedError);
      expect(() => reader.readString(0, 0), throwsUnsupportedError);
      expect(() => reader.readStringList(0, 0), throwsUnsupportedError);
      expect(() => reader.readList(0, 0), throwsUnsupportedError);
      expect(() => reader.readObject(0, 0), throwsUnsupportedError);
      expect(
        () => web_binary_document.cindelEncodeSchemaBinaryDocument(
          const [],
          const [],
        ),
        throwsUnsupportedError,
      );
      expect(
        () => web_binary_document.cindelDecodeSchemaBinaryDocument(_bytes([])),
        throwsUnsupportedError,
      );
    });

    // Scenario: Web native embedded payloads use the shared binary value shape.
    // Covers:
    // - Web embedded object/list binary encode and decode helpers.
    // - Primitive, temporal, nested, null, and invalid embedded values.
    // Expected: Embedded payloads round-trip before being handed to generated
    // native Web readers.
    test('round-trips web embedded binary values.', () {
      // Arrange.
      final timestamp = DateTime.fromMicrosecondsSinceEpoch(123456);
      const duration = Duration(microseconds: 9876);
      final object = <String, Object?>{
        'active': false,
        'createdAt': timestamp,
        'duration': duration,
        'score': 4.5,
        'items': [
          'vip',
          null,
          {'nested': true},
        ],
      };
      final list = <Object?>[
        null,
        true,
        -7,
        2.25,
        'Ana',
        object,
      ];

      // Act / Assert.
      expect(
        web_binary_document.cindelDecodeBinaryObject(
          web_binary_document.cindelEncodeBinaryObject(object),
        ),
        {
          'active': false,
          'createdAt': timestamp.microsecondsSinceEpoch,
          'duration': duration.inMicroseconds,
          'score': 4.5,
          'items': [
            'vip',
            null,
            {'nested': true},
          ],
        },
      );
      expect(
        web_binary_document.cindelDecodeBinaryList(
          web_binary_document.cindelEncodeBinaryList(list),
        ),
        [
          null,
          true,
          -7,
          2.25,
          'Ana',
          {
            'active': false,
            'createdAt': timestamp.microsecondsSinceEpoch,
            'duration': duration.inMicroseconds,
            'score': 4.5,
            'items': [
              'vip',
              null,
              {'nested': true},
            ],
          },
        ],
      );
      expect(
        () => web_binary_document.cindelEncodeBinaryList([Object()]),
        throwsArgumentError,
      );
      expect(
        () => web_binary_document.cindelEncodeBinaryList(
          const [0x20000000000000],
        ),
        throwsUnsupportedError,
      );
    });

    // Scenario: Web filters send query predicate ASTs to the Worker.
    // Covers:
    // - Field filter operation tags.
    // - all/any/not filter groups.
    // Expected: Every filter operation and group shape round-trips.
    test('round-trips web filter operations and groups.', () {
      // Arrange.
      final operations = web_wire.WireFilterOperation.values.map(
        (operation) => web_wire.WireFilter.field(
          field: operation.name,
          operation: operation,
          value: const web_wire.WireValue.string('value'),
        ),
      );
      final filter = web_wire.WireFilter.all([
        ...operations,
        web_wire.WireFilter.any([
          const web_wire.WireFilter.field(
            field: 'active',
            operation: web_wire.WireFilterOperation.equal,
            value: web_wire.WireValue.bool(true),
          ),
        ]),
        web_wire.WireFilter.not(
          const web_wire.WireFilter.field(
            field: 'deleted',
            operation: web_wire.WireFilterOperation.isNull,
            value: web_wire.WireValue.nullValue(),
          ),
        ),
      ]);

      // Act / Assert.
      expect(web_wire.decodeFilter(web_wire.encodeFilter(filter)), filter);
    });

    // Scenario: Web batch payloads carry generated document writes.
    // Covers:
    // - Raw document write batches.
    // - Indexed document write batches.
    // - Optional document batches.
    // - Index entry lists.
    // Expected: Ordered document and index metadata round-trips.
    test('round-trips web document and index batches.', () {
      // Arrange.
      final documents = [
        web_wire.WireDocumentWrite(id: 1, bytes: _bytes([10, 11])),
      ];
      final indexedDocuments = [
        web_wire.WireIndexedDocumentWrite(
          id: 2,
          bytes: _bytes([12]),
          indexes: const [
            web_wire.WireIndexEntry(
              documentId: 2,
              indexName: 'email',
              value: web_wire.WireIndexValue.string('a@example.com'),
            ),
          ],
        ),
      ];
      final optional = <Uint8List?>[
        _bytes([1]),
        null,
        _bytes([2, 3]),
      ];
      const indexEntries = [
        web_wire.WireIndexEntry(
          documentId: 7,
          indexName: 'status',
          value: web_wire.WireIndexValue.int(1),
        ),
      ];

      // Act / Assert.
      expect(
        web_wire.decodeDocumentWriteBatch(
          web_wire.encodeDocumentWriteBatch(documents),
        ),
        documents,
      );
      expect(
        web_wire.decodeIndexedDocumentWriteBatch(
          web_wire.encodeIndexedDocumentWriteBatch(indexedDocuments),
        ),
        indexedDocuments,
      );
      expect(
        web_wire.decodeOptionalDocumentBatch(
          web_wire.encodeOptionalDocumentBatch(optional),
        ),
        optional,
      );
      expect(
        web_wire.decodeIndexEntryList(
          web_wire.encodeIndexEntryList(indexEntries),
        ),
        indexEntries,
      );
    });

    // Scenario: Web SQLite-native generated document rows can use object and
    // direct writer paths.
    // Covers:
    // - [web_wire.encodeNativeDocumentWriteBatch].
    // - [web_wire.encodeNativeDocumentWriteBatchDirect].
    // - Direct writer null/bool/int/double/string/bytes/string-list paths.
    // - Direct writer validation branches.
    // Expected: Direct writes emit the same observable native row values and
    // invalid generated writer behavior fails early.
    test(
      'round-trips web native document batches and direct writer paths.',
      () {
        // Arrange.
        final documents = [
          web_wire.WireNativeDocumentWrite(
            id: 1,
            values: [
              const web_wire.WireNativeDocumentValue.nullValue(),
              const web_wire.WireNativeDocumentValue.bool(true),
              const web_wire.WireNativeDocumentValue.int(-3),
              const web_wire.WireNativeDocumentValue.double(1.5),
              web_wire.WireNativeDocumentValue.bytes(_utf8('Ana')),
            ],
          ),
        ];

        // Act.
        final decoded = web_wire.decodeNativeDocumentWriteBatch(
          web_wire.encodeNativeDocumentWriteBatch(documents),
        );
        final direct = web_wire.decodeNativeDocumentWriteBatch(
          web_wire.encodeNativeDocumentWriteBatchDirect<String>(
            ids: const [2],
            objects: const ['Ana'],
            fieldCount: 9,
            writeDocument: (writer, object) {
              writer.writeNull(0);
              writer.writeBool(1, true);
              writer.writeInt(2, -3);
              writer.writeDouble(3, 1.5);
              writer.writeString(4, object);
              writer.writeBytes(5, _bytes([1, 2]));
              writer.writeStringListJson(6, [
                '"',
                '\\',
                '\b',
                '\f',
                '\n',
                '\r',
                '\t',
                '\u0001',
                'ñ',
                '東京',
                '😀',
              ]);
              writer.writeObject(7, const {
                'label': 'primary',
                'metadata': {
                  'priority': 3,
                  'tags': ['vip', 'web'],
                },
              });
              writer.writeObjectList(8, const [
                {'line': 'first'},
                null,
                {'line': 'second'},
              ]);
            },
          ),
        );

        // Assert.
        expect(decoded, documents);
        expect(direct.single.id, 2);
        expect(direct.single.values.take(6), [
          const web_wire.WireNativeDocumentValue.nullValue(),
          const web_wire.WireNativeDocumentValue.bool(true),
          const web_wire.WireNativeDocumentValue.int(-3),
          const web_wire.WireNativeDocumentValue.double(1.5),
          web_wire.WireNativeDocumentValue.bytes(_utf8('Ana')),
          web_wire.WireNativeDocumentValue.bytes(_bytes([1, 2])),
        ]);
        final jsonListValue =
            direct.single.values[6] as web_wire.WireNativeDocumentBytes;
        expect(json.decode(utf8.decode(jsonListValue.value)), [
          '"',
          '\\',
          '\b',
          '\f',
          '\n',
          '\r',
          '\t',
          '\u0001',
          'ñ',
          '東京',
          '😀',
        ]);
        final objectValue =
            direct.single.values[7] as web_wire.WireNativeDocumentBytes;
        final objectListValue =
            direct.single.values[8] as web_wire.WireNativeDocumentBytes;
        expect(
          web_binary_document.cindelDecodeBinaryObject(objectValue.value),
          {
            'label': 'primary',
            'metadata': {
              'priority': 3,
              'tags': ['vip', 'web'],
            },
          },
        );
        expect(
          web_binary_document.cindelDecodeBinaryList(objectListValue.value),
          [
            {'line': 'first'},
            null,
            {'line': 'second'},
          ],
        );

        expect(
          () => web_wire.encodeNativeDocumentWriteBatchDirect<String>(
            ids: const [1],
            objects: const ['a', 'b'],
            fieldCount: 1,
            writeDocument: (writer, object) => writer.writeString(0, object),
          ),
          throwsArgumentError,
        );
        expect(
          () => web_wire.encodeNativeDocumentWriteBatchDirect<String>(
            ids: const [1],
            objects: const ['a'],
            fieldCount: -1,
            writeDocument: (writer, object) => writer.writeString(0, object),
          ),
          throwsRangeError,
        );
        expect(
          () => web_wire.encodeNativeDocumentWriteBatchDirect<String>(
            ids: const [1],
            objects: const ['a'],
            fieldCount: 2,
            writeDocument: (writer, object) => writer.writeString(0, object),
          ),
          throwsStateError,
        );
        expect(
          () => web_wire.encodeNativeDocumentWriteBatchDirect<String>(
            ids: const [1],
            objects: const ['a'],
            fieldCount: 1,
            writeDocument: (writer, object) => writer.writeString(1, object),
          ),
          throwsStateError,
        );
        expect(
          () => web_wire.encodeNativeDocumentWriteBatchDirect<String>(
            ids: const [1],
            objects: const ['a'],
            fieldCount: 1,
            writeDocument: (writer, object) =>
                writer.writeDouble(0, double.nan),
          ),
          throwsFormatException,
        );
      },
    );

    // Scenario: Web native readers hydrate generated primitive fields.
    // Covers:
    // - [CindelWebNativeDocumentReader.length].
    // - [CindelWebNativeDocumentReader.isPresent].
    // - [CindelWebNativeDocumentReader.readId].
    // - Primitive bool, int, double, string, and string-list reads.
    // Expected: Generated Web readers consume compact native rows with the
    // same primitive field metadata sent through the Worker boundary.
    test('reads web native primitive payloads.', () {
      // Arrange.
      final document = binary_document.cindelEncodeSchemaBinaryDocument(
        [true, -42, 2.5, 'Ana'],
        [
          binary_document.CindelBinaryFieldType.boolValue,
          binary_document.CindelBinaryFieldType.intValue,
          binary_document.CindelBinaryFieldType.doubleValue,
          binary_document.CindelBinaryFieldType.stringValue,
        ],
      );
      final nullDocument = binary_document.cindelEncodeSchemaBinaryDocument(
        [null, null, null, null],
        [
          binary_document.CindelBinaryFieldType.boolValue,
          binary_document.CindelBinaryFieldType.intValue,
          binary_document.CindelBinaryFieldType.doubleValue,
          binary_document.CindelBinaryFieldType.stringValue,
        ],
      );
      final stringListDocument =
          binary_document.cindelEncodeSchemaBinaryDocument(
            [jsonEncode(['vip', 'web'])],
            [binary_document.CindelBinaryFieldType.stringValue],
          );
      final nullStringListDocument =
          binary_document.cindelEncodeSchemaBinaryDocument(
            [null],
            [binary_document.CindelBinaryFieldType.stringValue],
          );
      final reader = CindelWebNativeDocumentReader(
        ids: const [7, 8, 9],
        documents: [document, nullDocument, null],
        fieldTypes: _bytes([0, 1, 2, 3]),
      );
      final listReader = CindelWebNativeDocumentReader(
        ids: const [10, 11],
        documents: [stringListDocument, nullStringListDocument],
        fieldTypes: _bytes([4]),
      );

      // Act / Assert.
      expect(reader.length, 3);
      expect(reader.isPresent(0), isTrue);
      expect(reader.isPresent(2), isFalse);
      expect(reader.readId(0), 7);
      expect(reader.readBool(0, 0), isTrue);
      expect(reader.readInt(0, 1), -42);
      expect(reader.readDouble(0, 2), 2.5);
      expect(reader.readString(0, 3), 'Ana');
      expect(reader.readBool(1, 0), isNull);
      expect(reader.readInt(1, 1), isNull);
      expect(reader.readDouble(1, 2), isNull);
      expect(reader.readString(1, 3), isNull);
      expect(listReader.readStringList(0, 0), ['vip', 'web']);
      expect(listReader.readStringList(1, 0), isNull);
      expect(() => reader.readList(0, 0), throwsUnsupportedError);
      reader.release();
    });

    // Scenario: Web native readers hydrate embedded binary payloads.
    // Covers:
    // - [CindelWebNativeDocumentReader.readObject].
    // - [CindelWebNativeDocumentReader.readObjectList].
    // Expected: Embedded object and object-list fields decode from stored
    // binary payloads using the same public generated-reader contract.
    test('reads web native embedded object payloads.', () {
      // Arrange.
      final document = binary_document.cindelEncodeSchemaBinaryDocument(
        [
          {
            'name': 'Ana',
            'flags': ['vip'],
          },
          [
            {'line': 'one'},
            null,
            {'line': 'two'},
          ],
        ],
        [
          binary_document.CindelBinaryFieldType.objectValue,
          binary_document.CindelBinaryFieldType.listValue,
        ],
      );
      final reader = CindelWebNativeDocumentReader(
        ids: const [7],
        documents: [document],
        fieldTypes: _bytes([5, 4]),
      );

      // Act / Assert.
      expect(reader.readObject(0, 0), {
        'name': 'Ana',
        'flags': ['vip'],
      });
      expect(reader.readObjectList(0, 1), [
        {'line': 'one'},
        null,
        {'line': 'two'},
      ]);
    });

    // Scenario: Web query plans and change sets cross the Worker boundary.
    // Covers:
    // - All query source variants.
    // - Optional filter bytes.
    // - Sort, distinct, offset, and limit fields.
    // - Watcher change-set lists.
    // Expected: Query plans and changes round-trip with exact metadata.
    test('round-trips web query plans and change sets.', () {
      // Arrange.
      final filter = web_wire.encodeFilter(
        const web_wire.WireFilter.field(
          field: 'active',
          operation: web_wire.WireFilterOperation.equal,
          value: web_wire.WireValue.bool(true),
        ),
      );
      final plans = [
        const web_wire.WireQueryPlan(
          source: web_wire.WireQuerySource.all(dedupe: true),
          filter: null,
          sorts: [],
          distinctFields: [],
          offset: 0,
          limit: null,
        ),
        web_wire.WireQueryPlan(
          source: const web_wire.WireQuerySource.indexEqual(
            indexName: 'email',
            value: web_wire.WireIndexValue.string('a@example.com'),
            dedupe: true,
          ),
          filter: filter,
          sorts: const [
            web_wire.WireQuerySort(field: 'name', ascending: false),
          ],
          distinctFields: const ['email'],
          offset: 3,
          limit: 10,
        ),
        const web_wire.WireQueryPlan(
          source: web_wire.WireQuerySource.indexRange(
            indexName: 'createdAt',
            lower: web_wire.WireIndexValue.int(1),
            upper: null,
            dedupe: false,
          ),
          filter: null,
          sorts: [],
          distinctFields: [],
          offset: 0,
          limit: null,
        ),
      ];
      const changes = [
        web_wire.WireChangeSet(
          collection: 'users',
          revision: 3,
          documentIds: [7, 9],
        ),
      ];

      // Act / Assert.
      for (final plan in plans) {
        expect(web_wire.decodeQueryPlan(web_wire.encodeQueryPlan(plan)), plan);
      }
      expect(
        web_wire.decodeChangeSetList(web_wire.encodeChangeSetList(changes)),
        changes,
      );
    });

    // Scenario: Web schema manifests use the same compact wire shape as Worker
    // schema registration.
    // Covers:
    // - [web_wire.encodeSchemaManifest].
    // - [web_wire.decodeSchemaManifest].
    // - Collection, field, and index schema equality.
    // Expected: Schema metadata round-trips without relying on native wire.
    test('round-trips web schema manifests.', () {
      // Arrange.
      const manifest = web_wire.WireSchemaManifest(
        version: 1,
        collections: [
          web_wire.WireCollectionSchema(
            name: 'users',
            idField: 'id',
            fields: [
              web_wire.WireFieldSchema(
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
              web_wire.WireIndexSchema(
                name: 'email_active',
                fields: ['email', 'active'],
                isUnique: true,
                isReplace: true,
                caseSensitive: false,
              ),
            ],
          ),
        ],
      );

      // Act / Assert.
      expect(
        web_wire.decodeSchemaManifest(web_wire.encodeSchemaManifest(manifest)),
        manifest,
      );
    });

    // Scenario: Field updates are sorted deterministically before reaching the
    // Worker.
    // Covers:
    // - [web_wire.encodeFieldUpdates].
    // - [web_wire.CindelWireReader.readValue].
    // Expected: Update keys are encoded in lexical order.
    test('encodes web field updates in stable field order.', () {
      // Act.
      final reader = web_wire.CindelWireReader(
        web_wire.encodeFieldUpdates({
          'z': const web_wire.WireValue.int(2),
          'a': const web_wire.WireValue.string('first'),
        }),
      );

      // Assert.
      expect(reader.readLength(), 2);
      expect(reader.readString(), 'a');
      expect(reader.readValue(), const web_wire.WireValue.string('first'));
      expect(reader.readString(), 'z');
      expect(reader.readValue(), const web_wire.WireValue.int(2));
      reader.finish();
    });

    // Scenario: Web wire reader and writer reject malformed payloads.
    // Covers:
    // - Trailing payload detection.
    // - Truncated payload detection.
    // - Invalid bool, UTF-8, and unknown tag errors.
    // - Writer integer range guards.
    // Expected: Invalid Web wire payloads fail with explicit exceptions.
    test('rejects malformed web wire payloads.', () {
      // Act / Assert.
      expect(() => web_wire.decodeIdList(_bytes([0])), throwsFormatException);
      expect(
        () => web_wire.decodeIdList(_bytes([0, 0, 0, 0, 1])),
        throwsFormatException,
      );
      expect(
        () => web_wire.CindelWireReader(_bytes([2])).readBool(),
        throwsFormatException,
      );
      expect(
        () =>
            web_wire.CindelWireReader(_bytes([1, 0, 0, 0, 0xff])).readString(),
        throwsFormatException,
      );
      expect(
        () => web_wire.decodeIndexValue(_bytes([99])),
        throwsFormatException,
      );
      expect(() => web_wire.decodeScalar(_bytes([99])), throwsFormatException);
      expect(() => _readValueTag(99), throwsFormatException);
      expect(
        () => web_wire.decodeNativeDocumentWriteBatch(
          _bytes([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 99]),
        ),
        throwsFormatException,
      );
      expect(() => web_wire.decodeFilter(_bytes([99])), throwsFormatException);
      expect(() => _readQuerySourceTag(99), throwsFormatException);
      expect(
        () => web_wire.CindelWireWriter().writeUint32(-1),
        throwsRangeError,
      );
      expect(
        () => web_wire.CindelWireWriter().writeUint64(-1),
        throwsRangeError,
      );
    });

    // Scenario: Web wire model objects participate in hash collections.
    // Covers:
    // - `hashCode` implementations across Web wire model families.
    // - [web_wire.listEquals] identity, length, mismatch, and equality paths.
    // Expected: Hashing and list equality are stable for Web wire metadata.
    test('computes web wire hash codes and list equality.', () {
      // Arrange.
      final objects = <Object>[
        const web_wire.WireIndexValue.nullValue(),
        const web_wire.WireIndexValue.bool(true),
        const web_wire.WireIndexValue.int(1),
        const web_wire.WireIndexValue.double(1),
        const web_wire.WireIndexValue.string('x'),
        const web_wire.WireIndexValue.list([web_wire.WireIndexValue.int(1)]),
        const web_wire.WireScalar.nullValue(),
        const web_wire.WireScalar.bool(true),
        const web_wire.WireScalar.int(1),
        const web_wire.WireScalar.double(1),
        const web_wire.WireScalar.string('x'),
        const web_wire.WireValue.nullValue(),
        const web_wire.WireValue.bool(true),
        const web_wire.WireValue.int(1),
        const web_wire.WireValue.double(1),
        const web_wire.WireValue.string('x'),
        const web_wire.WireValue.list([web_wire.WireValue.int(1)]),
        const web_wire.WireValue.object([
          web_wire.WireObjectEntry('x', web_wire.WireValue.int(1)),
        ]),
        const web_wire.WireFilter.field(
          field: 'x',
          operation: web_wire.WireFilterOperation.equal,
          value: web_wire.WireValue.int(1),
        ),
        const web_wire.WireFilter.all([]),
        const web_wire.WireFilter.any([]),
        const web_wire.WireFilter.not(web_wire.WireFilter.all([])),
        web_wire.WireDocumentWrite(id: 1, bytes: _bytes([1])),
        web_wire.WireIndexedDocumentWrite(
          id: 1,
          bytes: _bytes([1]),
          indexes: const [],
        ),
        const web_wire.WireNativeDocumentValue.nullValue(),
        const web_wire.WireNativeDocumentValue.bool(true),
        const web_wire.WireNativeDocumentValue.int(1),
        const web_wire.WireNativeDocumentValue.double(1),
        web_wire.WireNativeDocumentValue.bytes(_bytes([1])),
        web_wire.WireNativeDocumentWrite(
          id: 1,
          values: [
            web_wire.WireNativeDocumentValue.bytes(_bytes([1])),
          ],
        ),
        const web_wire.WireProjectionRows(
          rowCount: 0,
          columnCount: 0,
          cells: [],
        ),
        const web_wire.WireSchemaManifest(version: 1, collections: []),
        const web_wire.WireCollectionSchema(
          name: 'c',
          idField: 'id',
          fields: [],
          indexes: [],
        ),
        const web_wire.WireFieldSchema(
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
        const web_wire.WireIndexSchema(
          name: 'idx',
          fields: ['a'],
          isUnique: false,
          isReplace: false,
          caseSensitive: true,
        ),
        const web_wire.WireIndexEntry(
          documentId: 1,
          indexName: 'idx',
          value: web_wire.WireIndexValue.int(1),
        ),
        const web_wire.WireQuerySource.all(dedupe: true),
        const web_wire.WireQuerySource.indexEqual(
          indexName: 'idx',
          value: web_wire.WireIndexValue.int(1),
        ),
        const web_wire.WireQuerySource.indexRange(
          indexName: 'idx',
          lower: web_wire.WireIndexValue.int(1),
          upper: web_wire.WireIndexValue.int(2),
        ),
        const web_wire.WireQuerySort(field: 'name', ascending: true),
        web_wire.WireQueryPlan(
          source: const web_wire.WireQuerySource.all(),
          filter: _bytes([1, 2]),
          sorts: const [],
          distinctFields: const [],
          offset: 0,
          limit: null,
        ),
        const web_wire.WireChangeSet(
          collection: 'users',
          revision: 1,
          documentIds: [1],
        ),
      ];
      final sameList = [1, 2];

      // Act / Assert.
      for (final object in objects) {
        expect(object.hashCode, isA<int>());
      }
      expect(web_wire.listEquals(sameList, sameList), isTrue);
      expect(web_wire.listEquals([1], [1, 2]), isFalse);
      expect(web_wire.listEquals([1, 2], [1, 3]), isFalse);
      expect(web_wire.listEquals([1, 2], [1, 2]), isTrue);
    });
  });
}

Uint8List _bytes(List<int> bytes) => Uint8List.fromList(bytes);

Uint8List _utf8(String value) => Uint8List.fromList(utf8.encode(value));

void _readValueTag(int tag) {
  web_wire.CindelWireReader(_bytes([tag])).readValue();
}

void _readQuerySourceTag(int tag) {
  web_wire.CindelWireReader(_bytes([tag, 0])).readQuerySource();
}
