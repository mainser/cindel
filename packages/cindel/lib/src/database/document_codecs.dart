part of '../database.dart';

// Encoding and validation helpers shared by manual documents, generated binary
// documents, schema registration, and index query planning.

// Query helpers can receive the same id more than once from multi-entry or word
// indexes. Preserve first-seen order while removing duplicates.
List<int> _dedupeIds(List<int> ids) {
  final seen = <int>{};
  return [
    for (final id in ids)
      if (seen.add(id)) id,
  ];
}

// Manual API documents use the generic document envelope. Generated typed
// payloads use schema-backed binary documents and are decoded below.
Uint8List _encodeDocument(CindelDocument value) {
  return cindelEncodeGenericDocument(value);
}

// Decode either a manual generic document or a generated binary document.
//
// When native storage returns a generated payload, the schema serializer is used
// to reconstruct an object and convert it back to CindelDocument form. The id is
// reattached when the stored payload did not include it.
CindelDocument _decodeDocument(
  String collection,
  Uint8List bytes,
  CindelCollectionSchema<dynamic>? schema, {
  int? id,
}) {
  if (cindelIsGenericDocument(bytes)) {
    return _documentWithExternalId(
      cindelDecodeGenericDocument(bytes),
      schema,
      id,
    );
  }

  if (schema != null) {
    final dynamic dynamicSchema = schema;
    final fromBinaryDocument = dynamicSchema.fromBinaryDocument;
    if (fromBinaryDocument != null) {
      try {
        final object = fromBinaryDocument(bytes);
        if (id != null) {
          final setId = dynamicSchema.setId;
          if (setId != null) {
            setId(object, id);
          }
        }
        final document = dynamicSchema.toDocument(object);
        if (document is Map) {
          return _documentWithExternalId(
            document.cast<String, Object?>(),
            schema,
            id,
          );
        }
      } on Object {
        // Fall through to the unsupported payload error below.
      }
    }
  }

  throw CindelNativeError(
    'Native Cindel returned an unsupported document payload for `$collection`.',
  );
}

// Ensure documents returned through manual APIs include the external id field
// when the schema stores the id outside the payload.
CindelDocument _documentWithExternalId(
  CindelDocument document,
  CindelCollectionSchema<dynamic>? schema,
  int? id,
) {
  if (schema == null || id == null || document[schema.idField] is int) {
    return document;
  }
  return <String, Object?>{...document, schema.idField: id};
}

// Convert wire values returned from native projections and aggregates into the
// JSON-like shapes exposed by the Dart runtime.
Object? _wireScalarToObject(WireScalar scalar) {
  return switch (scalar) {
    WireScalarNull() => null,
    WireScalarBool(:final value) => value,
    WireScalarInt(:final value) => value,
    WireScalarDouble(:final value) => value,
    WireScalarString(:final value) => value,
  };
}

Object? _wireValueToObject(WireValue value) {
  return switch (value) {
    WireNullValue() => null,
    WireBoolValue(:final value) => value,
    WireIntValue(:final value) => value,
    WireDoubleValue(:final value) => value,
    WireStringValue(:final value) => value,
    WireListValue(:final values) => [
      for (final value in values) _wireValueToObject(value),
    ],
    WireObjectValue(:final fields) => {
      for (final field in fields) field.name: _wireValueToObject(field.value),
    },
  };
}

// Encode/decode id and binary-document batches exchanged with the native layer.

Uint8List _encodeIds(Iterable<int> ids) {
  return encodeIdList(ids.toList(growable: false));
}

List<Uint8List?> _decodeBinaryDocumentBatch(Uint8List bytes) {
  final data = bytes.buffer.asByteData(
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  var offset = 0;
  int readUint8() {
    if (offset + 1 > bytes.length) {
      throw CindelNativeError(
        'Native Cindel returned a truncated binary batch.',
      );
    }
    return bytes[offset++];
  }

  int readUint32() {
    if (offset + 4 > bytes.length) {
      throw CindelNativeError(
        'Native Cindel returned a truncated binary batch.',
      );
    }
    final value = data.getUint32(offset, Endian.little);
    offset += 4;
    return value;
  }

  final count = readUint32();
  final documents = <Uint8List?>[];
  for (var index = 0; index < count; index += 1) {
    final present = readUint8();
    final length = readUint32();
    if (present == 0) {
      if (length != 0) {
        throw CindelNativeError(
          'Native Cindel returned an invalid binary batch.',
        );
      }
      documents.add(null);
      continue;
    }
    if (present != 1 || offset + length > bytes.length) {
      throw CindelNativeError(
        'Native Cindel returned an invalid binary batch.',
      );
    }
    documents.add(Uint8List.sublistView(bytes, offset, offset + length));
    offset += length;
  }
  if (offset != bytes.length) {
    throw CindelNativeError(
      'Native Cindel returned trailing binary batch bytes.',
    );
  }
  return documents;
}

// Public API argument validation.
//
// These helpers intentionally throw Dart core ArgumentError values because they
// validate caller input rather than internal Cindel state.

void _checkDirectory(String directory) {
  if (directory.trim().isEmpty) {
    throw ArgumentError.value(directory, 'directory', 'Must not be empty.');
  }
}

void _checkCollection(String collection) {
  if (collection.trim().isEmpty) {
    throw ArgumentError.value(collection, 'collection', 'Must not be empty.');
  }
}

void _checkIndexName(String field) {
  if (field.trim().isEmpty) {
    throw ArgumentError.value(field, 'field', 'Must not be empty.');
  }
}

void _checkPollInterval(Duration pollInterval) {
  if (pollInterval <= Duration.zero) {
    throw ArgumentError.value(
      pollInterval,
      'pollInterval',
      'Must be greater than zero.',
    );
  }
}

void _checkId(int id) {
  if (id < 0) {
    throw ArgumentError.value(id, 'id', 'Must be greater than or equal to 0.');
  }
  if (id > _maximumSqliteId) {
    throw ArgumentError.value(
      id,
      'id',
      'Must be less than or equal to $_maximumSqliteId.',
    );
  }
}

// Schema and document validation.

Map<String, CindelCollectionSchema<dynamic>> _schemasByCollection(
  Iterable<CindelCollectionSchema<dynamic>> schemas,
) {
  final schemasByCollection = <String, CindelCollectionSchema<dynamic>>{};
  for (final schema in schemas) {
    if (schemasByCollection.containsKey(schema.name)) {
      throw ArgumentError.value(
        schema.name,
        'schemas',
        'Collection schemas must be unique by name.',
      );
    }
    schemasByCollection[schema.name] = schema;
  }
  return Map.unmodifiable(schemasByCollection);
}

void _checkDocument(CindelDocument value) {
  for (final entry in value.entries) {
    _checkJsonValue(entry.value, 'value.${entry.key}');
  }
}

void _checkJsonValue(Object? value, String path) {
  switch (value) {
    case null || String() || bool():
      return;
    case int():
      return;
    case double() when value.isFinite:
      return;
    case List<Object?>():
      for (var index = 0; index < value.length; index += 1) {
        _checkJsonValue(value[index], '$path[$index]');
      }
      return;
    case Map<String, Object?>():
      for (final entry in value.entries) {
        _checkJsonValue(entry.value, '$path.${entry.key}');
      }
      return;
    default:
      throw ArgumentError.value(
        value,
        path,
        'Must be a JSON-compatible value.',
      );
  }
}

// Wire encoders used by native write paths.

Uint8List _encodeIndexEntries(List<_IndexEntry> entries) {
  return encodeIndexEntryList([
    for (final entry in entries)
      WireIndexEntry(documentId: 0, indexName: entry.name, value: entry.value),
  ]);
}

Uint8List _encodeBatchPutEntries(List<_BatchPutEntry> entries) {
  return encodeIndexedDocumentWriteBatch([
    for (final entry in entries)
      WireIndexedDocumentWrite(
        id: entry.id,
        bytes: _encodeDocument(entry.document),
        indexes: [
          for (final index in entry.indexes)
            WireIndexEntry(
              documentId: entry.id,
              indexName: index.name,
              value: index.value,
            ),
        ],
      ),
  ]);
}

Uint8List _encodeBinaryBatchPutEntries(Map<int, Uint8List> entries) {
  return encodeDocumentWriteBatch([
    for (final entry in entries.entries)
      WireDocumentWrite(id: entry.key, bytes: entry.value),
  ]);
}

// Schema manifest encoding.
//
// The native side persists these names for compatibility checks, so this path
// must stay aligned with the generated CindelCollectionSchema values.

Uint8List _encodeSchemaManifest(
  Iterable<CindelCollectionSchema<dynamic>> schemas,
) {
  final collections = schemas.toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
  return encodeSchemaManifest(
    WireSchemaManifest(
      version: 1,
      collections: [for (final schema in collections) _schemaWire(schema)],
    ),
  );
}

WireCollectionSchema _schemaWire(CindelCollectionSchema<dynamic> schema) {
  final fields = schema.fields.toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
  return WireCollectionSchema(
    name: schema.name,
    idField: schema.idField,
    fields: [
      for (final field in fields)
        WireFieldSchema(
          name: field.name,
          typeName: field.dartType,
          binaryType: field.binaryType ?? field.dartType,
          indexType: field.indexType.name,
          isId: field.isId,
          isIndexed: field.isIndexed,
          isUnique: field.isIndexUnique,
          isNullable: field.dartType.endsWith('?'),
          caseSensitive: field.indexCaseSensitive,
        ),
    ],
    indexes: [
      for (final index in schema.compositeIndexes)
        WireIndexSchema(
          name: index.name,
          fields: index.fields,
          isUnique: index.isUnique,
          caseSensitive: index.caseSensitive,
        ),
    ],
  );
}

// Native compact field metadata.
//
// Returns null when a schema contains a field shape that the native typed
// document writer/reader cannot represent directly.
Uint8List? _nativeFieldTypes(CindelCollectionSchema<dynamic> schema) {
  final fields = schema.fields.toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
  final binaryFields = fields
      .where((field) => !field.isId)
      .toList(growable: false);
  final bytes = Uint8List(binaryFields.length);
  for (var i = 0; i < binaryFields.length; i += 1) {
    final type = binaryFields[i].binaryType;
    final value = switch (type) {
      'bool' => 0,
      'int' => 1,
      'double' => 2,
      'string' => 3,
      'list' => 4,
      'object' => 5,
      _ => null,
    };
    if (value == null) {
      return null;
    }
    bytes[i] = value;
  }
  return bytes;
}

// Index value encoding.
//
// Values are normalized here before both SQLite-compatible generic indexes and
// native query plans see them. Hash indexes hash the stable encoded value rather
// than the original Dart object.
Uint8List _encodeIndexValue(Object value, CindelFieldSchema field) {
  return _encodedIndexValue(value, field, 'value').bytes;
}

_EncodedIndexValue _encodeRangeIndexValue(
  Object value,
  CindelFieldSchema field,
  String argumentName,
) {
  final encoded = _encodedIndexValue(value, field, argumentName);
  if (encoded.kind == 'bool') {
    throw ArgumentError.value(
      value,
      argumentName,
      'Range queries support int, double, and String values.',
    );
  }
  return encoded;
}

_EncodedIndexValue _encodedIndexValue(
  Object value,
  CindelFieldSchema field,
  String argumentName,
) {
  final wire = _indexValueWire(value, field, argumentName);
  return _EncodedIndexValue(
    kind: _wireIndexValueKind(wire),
    bytes: encodeIndexValue(wire),
  );
}

WireIndexValue _indexValueWire(
  Object value,
  CindelFieldSchema field, [
  String argumentName = 'value',
]) {
  final normalizedType = _nonNullableDartType(field.dartType);

  final wireValue = switch ((normalizedType, value)) {
    ('bool', final bool value) => WireIndexValue.bool(value),
    ('int', final int value) => WireIndexValue.int(
      _checkSqliteInteger(value, argumentName),
    ),
    ('double', final double value) when value.isFinite => WireIndexValue.double(
      value,
    ),
    ('String', final String value) => _stringIndexValueWire(value, field),
    ('DateTime', final DateTime value) => WireIndexValue.int(
      _checkSqliteInteger(value.microsecondsSinceEpoch, argumentName),
    ),
    ('DateTime', final int value) => WireIndexValue.int(
      _checkSqliteInteger(value, argumentName),
    ),
    ('Duration', final Duration value) => WireIndexValue.int(
      _checkSqliteInteger(value.inMicroseconds, argumentName),
    ),
    ('Duration', final int value) => WireIndexValue.int(
      _checkSqliteInteger(value, argumentName),
    ),
    ('double', final double value) => throw ArgumentError.value(
      value,
      argumentName,
      'Must be finite.',
    ),
    (_, final bool value) => WireIndexValue.bool(value),
    (_, final int value) => WireIndexValue.int(
      _checkSqliteInteger(value, argumentName),
    ),
    (_, final double value) when value.isFinite => WireIndexValue.double(value),
    (_, final String value) =>
      field.indexType == CindelIndexType.multiEntry
          ? _stringIndexValueWire(value, field)
          : WireIndexValue.string(value),
    (_, final double value) => throw ArgumentError.value(
      value,
      argumentName,
      'Must be finite.',
    ),
    _ => throw ArgumentError.value(
      value,
      argumentName,
      'Must match indexed field type `${field.dartType}`.',
    ),
  };
  if (field.indexType == CindelIndexType.hash) {
    return WireIndexValue.int(_stableHashBytes(encodeIndexValue(wireValue)));
  }
  return wireValue;
}

String _nonNullableDartType(String dartType) {
  return dartType.endsWith('?')
      ? dartType.substring(0, dartType.length - 1)
      : dartType;
}

WireIndexValue _stringIndexValueWire(String value, CindelFieldSchema field) {
  final indexedValue = field.indexCaseSensitive ? value : value.toLowerCase();
  return WireIndexValue.string(indexedValue);
}

String _wireIndexValueKind(WireIndexValue value) {
  return switch (value) {
    WireIndexNull() => 'null',
    WireIndexBool() => 'bool',
    WireIndexInt() => 'int',
    WireIndexDouble() => 'double',
    WireIndexString() => 'string',
    WireIndexList() => 'list',
  };
}

// Equality and range helpers for index fallback verification.

bool _indexedValuesEqual(
  Object? actual,
  Object expected,
  CindelFieldSchema field,
) {
  if (_nonNullableDartType(field.dartType) == 'String' &&
      !field.indexCaseSensitive) {
    return actual is String &&
        expected is String &&
        actual.toLowerCase() == expected.toLowerCase();
  }
  if (_nonNullableDartType(field.dartType) == 'DateTime') {
    return _dateTimeMicros(actual) == _dateTimeMicros(expected);
  }
  if (_nonNullableDartType(field.dartType) == 'Duration') {
    return _durationMicros(actual) == _durationMicros(expected);
  }
  return actual == expected;
}

int? _dateTimeMicros(Object? value) {
  return switch (value) {
    DateTime() => value.microsecondsSinceEpoch,
    int() => value,
    _ => null,
  };
}

int? _durationMicros(Object? value) {
  return switch (value) {
    Duration() => value.inMicroseconds,
    int() => value,
    _ => null,
  };
}

bool _jsonLikeEquals(Object? left, Object? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key)) {
        return false;
      }
      if (!_jsonLikeEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_jsonLikeEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

// Stable FNV-1a hash used by hash indexes. The mask keeps the value in the
// positive SQLite INTEGER range.
int _stableHashBytes(Uint8List value) {
  const offsetBasis = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0x7fffffffffffffff;
  var hash = offsetBasis;
  for (final byte in value) {
    hash ^= byte;
    hash = (hash * prime) & mask;
  }
  return hash;
}

int _checkSqliteInteger(int value, String argumentName) {
  if (value < -0x8000000000000000 || value > _maximumSqliteId) {
    throw ArgumentError.value(
      value,
      argumentName,
      'Must fit in SQLite INTEGER range.',
    );
  }
  return value;
}

// Range bounds must encode to the same wire value kind so native and fallback
// comparisons agree.
void _checkMatchingRangeBounds(
  _EncodedIndexValue? lower,
  _EncodedIndexValue? upper,
) {
  if (lower != null && upper != null && lower.kind != upper.kind) {
    throw ArgumentError.value(
      upper.kind,
      'upper',
      'Range bounds must have matching types.',
    );
  }
}

// Small write-planning records used while batching documents and indexes.

final class _IndexEntry {
  const _IndexEntry({required this.name, required this.value});

  final String name;
  final WireIndexValue value;
}

final class _BatchPutEntry {
  const _BatchPutEntry({
    required this.id,
    required this.document,
    required this.indexes,
  });

  final int id;
  final CindelDocument document;
  final List<_IndexEntry> indexes;
}

final class _UniqueIndexEntry {
  const _UniqueIndexEntry({
    required this.id,
    required this.field,
    required this.originalValue,
    required this.encodedValue,
  });

  final int id;
  final CindelFieldSchema field;
  final Object? originalValue;
  final WireIndexValue encodedValue;
}

final class _EncodedIndexValue {
  const _EncodedIndexValue({required this.kind, required this.bytes});

  final String kind;
  final Uint8List bytes;
}
