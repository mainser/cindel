// ignore_for_file: undefined_class, undefined_function
// ignore_for_file: undefined_identifier, uri_does_not_exist

import 'dart:mirrors';
import 'dart:typed_data';

import 'package:cindel/cindel.dart';
import 'package:cindel/src/database.dart' as database;
import 'package:cindel/src/native/wire.dart';
import 'package:test/test.dart';

void main() {
  group('Cindel database document codecs', () {
    // Scenario: Query sources return duplicated ids from multi-entry indexes.
    // Covers:
    // - `_dedupeIds` preserving first-seen order.
    // Expected: Repeated ids are removed without sorting.
    test('deduplicates ids while preserving query order.', () {
      // Act.
      final ids = _invokePrivate<List<int>>('_dedupeIds', [
        [3, 1, 3, 2, 1],
      ]);

      // Assert.
      expect(ids, [3, 1, 2]);
    });

    // Scenario: Native returns malformed binary document batches.
    // Covers:
    // - `_decodeBinaryDocumentBatch` truncated u8/u32 guards.
    // - Invalid absent-document length.
    // - Invalid present flag and trailing payload guards.
    // Expected: Malformed native payloads fail with [CindelNativeError].
    test('rejects malformed native binary document batches.', () {
      // Act / Assert.
      expect(() => _decodeBinaryBatch(_bytes([1, 0, 0])), _throwsNativeError);
      expect(
        () => _decodeBinaryBatch(_bytes([1, 0, 0, 0])),
        _throwsNativeError,
      );
      expect(
        () => _decodeBinaryBatch(_bytes([1, 0, 0, 0, 0, 1, 0, 0, 0])),
        _throwsNativeError,
      );
      expect(
        () => _decodeBinaryBatch(_bytes([1, 0, 0, 0, 2, 0, 0, 0, 0])),
        _throwsNativeError,
      );
      expect(
        () => _decodeBinaryBatch(_bytes([0, 0, 0, 0, 9])),
        _throwsNativeError,
      );
    });

    // Scenario: Public database arguments are validated before native calls.
    // Covers:
    // - `_checkDirectory`, `_checkCollection`, `_checkIndexName`,
    //   `_checkPollInterval`, and `_checkId` error branches.
    // Expected: Invalid caller input fails with [ArgumentError].
    test('rejects invalid public API arguments.', () {
      // Act / Assert.
      expect(() => _invokePrivateRaw('_checkDirectory', ['  ']), _throwsArg);
      expect(() => _invokePrivateRaw('_checkCollection', ['']), _throwsArg);
      expect(() => _invokePrivateRaw('_checkIndexName', [' ']), _throwsArg);
      expect(
        () => _invokePrivateRaw('_checkPollInterval', [Duration.zero]),
        _throwsArg,
      );
      expect(() => _invokePrivateRaw('_checkId', [-1]), _throwsArg);
      expect(
        () => _invokePrivateRaw('_checkId', [0x8000000000000000]),
        _throwsArg,
      );
    });

    // Scenario: Schema registration receives duplicated collection names.
    // Covers:
    // - `_schemasByCollection` duplicate-name validation.
    // Expected: Duplicate collection schemas are rejected before open.
    test('rejects duplicate schema names.', () {
      // Arrange.
      final first = _schema('users');
      final second = _schema('users');

      // Act / Assert.
      expect(
        () => _invokePrivateRaw('_schemasByCollection', [
          [first, second],
        ]),
        _throwsArg,
      );
    });

    // Scenario: Native typed document metadata supports direct field kinds.
    // Covers:
    // - `_nativeFieldTypes` list and object branches.
    // - `_nativeFieldTypes` unsupported-field fallback.
    // Expected: Supported field kinds encode to byte tags and unsupported kinds
    // disable the native direct path.
    test(
      'encodes supported native field types and rejects unsupported ones.',
      () {
        // Arrange.
        final supported = _schema(
          'supported',
          fields: const [
            CindelFieldSchema(
              name: 'id',
              dartType: 'int',
              binaryType: 'int',
              isId: true,
              isIndexed: false,
            ),
            CindelFieldSchema(
              name: 'items',
              dartType: 'List<String>',
              binaryType: 'list',
              isId: false,
              isIndexed: false,
            ),
            CindelFieldSchema(
              name: 'metadata',
              dartType: 'Metadata',
              binaryType: 'object',
              isId: false,
              isIndexed: false,
            ),
          ],
        );
        final unsupported = _schema(
          'unsupported',
          fields: const [
            CindelFieldSchema(
              name: 'id',
              dartType: 'int',
              binaryType: 'int',
              isId: true,
              isIndexed: false,
            ),
            CindelFieldSchema(
              name: 'raw',
              dartType: 'Object',
              binaryType: 'unsupported',
              isId: false,
              isIndexed: false,
            ),
          ],
        );

        // Act.
        final bytes = _invokePrivate<Uint8List>('_nativeFieldTypes', [
          supported,
        ]);
        final missing = _invokePrivate<Uint8List?>('_nativeFieldTypes', [
          unsupported,
        ]);

        // Assert.
        expect(bytes, [4, 5]);
        expect(missing, isNull);
      },
    );

    // Scenario: Index values normalize typed values before reaching native.
    // Covers:
    // - DateTime and Duration integer conversion branches.
    // - Nullable type normalization.
    // - Case-insensitive string normalization.
    // - Multi-entry string normalization.
    // Expected: Encoded wire index values match the normalized representation.
    test('normalizes index values for typed fields.', () {
      // Arrange.
      const dateField = CindelFieldSchema(
        name: 'createdAt',
        dartType: 'DateTime?',
        isId: false,
        isIndexed: true,
      );
      const durationField = CindelFieldSchema(
        name: 'sessionLength',
        dartType: 'Duration',
        isId: false,
        isIndexed: true,
      );
      const displayNameField = CindelFieldSchema(
        name: 'displayName',
        dartType: 'String?',
        isId: false,
        isIndexed: true,
        indexCaseSensitive: false,
      );
      const tagsField = CindelFieldSchema(
        name: 'tags',
        dartType: 'List<String>',
        isId: false,
        isIndexed: true,
        indexType: CindelIndexType.multiEntry,
        indexCaseSensitive: false,
      );

      // Act / Assert.
      expect(
        _indexWire(DateTime.utc(2026, 1, 2), dateField),
        WireIndexValue.int(DateTime.utc(2026, 1, 2).microsecondsSinceEpoch),
      );
      expect(
        _indexWire(const Duration(milliseconds: 3), durationField),
        const WireIndexValue.int(3000),
      );
      expect(
        _indexWire('Ana', displayNameField),
        const WireIndexValue.string('ana'),
      );
      expect(_indexWire('VIP', tagsField), const WireIndexValue.string('vip'));
    });

    // Scenario: Hash indexes store the stable hash of the encoded index value.
    // Covers:
    // - `_stableHashBytes` via `_indexValueWire`.
    // - Hash-index replacement with integer wire values.
    // Expected: Hash indexes produce deterministic integer values.
    test('hashes hash-index values deterministically.', () {
      // Arrange.
      const field = CindelFieldSchema(
        name: 'accessToken',
        dartType: 'String?',
        isId: false,
        isIndexed: true,
        indexType: CindelIndexType.hash,
      );

      // Act.
      final first = _indexWire('secret', field);
      final second = _indexWire('secret', field);
      final other = _indexWire('other', field);

      // Assert.
      expect(first, isA<WireIndexInt>());
      expect(first, second);
      expect(first, isNot(other));
    });

    // Scenario: Invalid index and range values are rejected before native calls.
    // Covers:
    // - Non-finite double validation.
    // - Type mismatch validation.
    // - SQLite integer bounds validation.
    // - Boolean range rejection.
    // - Mismatched range bound kinds.
    // Expected: Invalid query values fail with [ArgumentError].
    test('rejects invalid index and range values.', () {
      // Arrange.
      const intField = CindelFieldSchema(
        name: 'count',
        dartType: 'int',
        isId: false,
        isIndexed: true,
      );
      const boolField = CindelFieldSchema(
        name: 'active',
        dartType: 'bool',
        isId: false,
        isIndexed: true,
      );
      const stringField = CindelFieldSchema(
        name: 'name',
        dartType: 'String',
        isId: false,
        isIndexed: true,
      );

      // Act / Assert.
      expect(() => _indexWire(double.nan, intField), _throwsArg);
      expect(() => _indexWire(Object(), intField), _throwsArg);
      expect(
        () => _invokePrivateRaw('_encodeRangeIndexValue', [
          true,
          boolField,
          'lower',
        ]),
        _throwsArg,
      );

      final lower = _invokePrivateRaw('_encodeRangeIndexValue', [
        1,
        intField,
        'lower',
      ]);
      final upper = _invokePrivateRaw('_encodeRangeIndexValue', [
        'z',
        stringField,
        'upper',
      ]);
      expect(
        () => _invokePrivateRaw('_checkMatchingRangeBounds', [lower, upper]),
        _throwsArg,
      );
    });

    // Scenario: Wire index value kind names are derived from every wire variant.
    // Covers:
    // - `_wireIndexValueKind` list branch.
    // Expected: Composite/list index values report the `list` kind.
    test('reports list wire index value kind.', () {
      // Act.
      final kind = _invokePrivate<String>('_wireIndexValueKind', [
        const WireIndexValue.list([WireIndexValue.int(1)]),
      ]);

      // Assert.
      expect(kind, 'list');
    });
  });
}

Matcher get _throwsArg => throwsA(isA<ArgumentError>());

Matcher get _throwsNativeError => throwsA(isA<CindelNativeError>());

List<Uint8List?> _decodeBinaryBatch(Uint8List bytes) {
  return _invokePrivate<List<Uint8List?>>('_decodeBinaryDocumentBatch', [
    bytes,
  ]);
}

WireIndexValue _indexWire(Object value, CindelFieldSchema field) {
  return _invokePrivate<WireIndexValue>('_indexValueWire', [value, field]);
}

CindelCollectionSchema<Object> _schema(
  String name, {
  List<CindelFieldSchema> fields = const [],
}) {
  return CindelCollectionSchema<Object>(
    name: name,
    dartName: 'Object',
    idField: 'id',
    fields: fields,
    toDocument: (_) => const {},
    fromDocument: (_) => Object(),
  );
}

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

T _invokePrivate<T>(String name, List<Object?> positionalArguments) {
  return _invokePrivateRaw(name, positionalArguments) as T;
}

Object? _invokePrivateRaw(String name, List<Object?> positionalArguments) {
  return _databaseLibrary()
      .invoke(_privateSymbol(name), positionalArguments)
      .reflectee;
}

LibraryMirror _databaseLibrary() {
  expect(database.CindelDatabase, isNotNull);
  final library = currentMirrorSystem()
      .libraries[Uri.parse('package:cindel/src/database.dart')];
  if (library == null) {
    fail('Could not find package:cindel/src/database.dart.');
  }
  return library;
}

Symbol _privateSymbol(String name) =>
    MirrorSystem.getSymbol(name, _databaseLibrary());
