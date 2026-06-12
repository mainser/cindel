import 'dart:typed_data';

import '../schema.dart';
import 'wire.dart';

/// Encodes generated Cindel schemas for the Web worker/Wasm runtime.
///
/// The output matches the native `open_with_backend_and_schemas` schema manifest
/// wire format. Web callers should send these bytes to the Worker as an
/// `ArrayBuffer`.
Uint8List cindelEncodeWebSchemaManifest(
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
