import 'dart:typed_data';
import 'schema.dart';
import 'web/migration_reader.dart' as sqlite_reader;

T cindelReadMigrationObject<T>(
  CindelCollectionSchema<T> schema,
  int id,
  Uint8List bytes, {
  required bool sqlite,
}) {
  if (sqlite)
    return sqlite_reader.cindelReadMigrationObject(
      schema,
      id,
      bytes,
      sqlite: true,
    );
  final decode = schema.fromBinaryDocument;
  if (decode == null)
    throw StateError('Migration requires a generated binary reader.');
  var object = decode(bytes);
  if (schema.setId != null) {
    schema.setId!(object, id);
  } else if (schema.getId?.call(object) != id) {
    object = schema.fromDocument({
      ...schema.toDocument(object),
      schema.idField: id,
    });
  }
  if (schema.getId?.call(object) != id)
    throw StateError('Migration reader did not preserve the document ID.');
  return object;
}
