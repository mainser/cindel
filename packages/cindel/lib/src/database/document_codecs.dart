part of '../database.dart';

// Encoding and validation helpers shared by generated binary documents, schema
// registration, and index query planning.

// Query helpers can receive the same id more than once from multi-entry or word
// indexes. Preserve first-seen order while removing duplicates.
List<int> _dedupeIds(List<int> ids) {
  final seen = <int>{};
  return [
    for (final id in ids)
      if (seen.add(id)) id,
  ];
}

// Convert wire values returned from native projections and aggregates into the
// Map-shaped values exposed by the Dart runtime.
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

// Schema validation.

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

// Wire encoders used by native write paths.

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
          isReplace: field.isIndexReplace,
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
          isReplace: index.isReplace,
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

final class _EncodedIndexValue {
  const _EncodedIndexValue({required this.kind, required this.bytes});

  final String kind;
  final Uint8List bytes;
}
