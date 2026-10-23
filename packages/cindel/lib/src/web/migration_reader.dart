import 'dart:typed_data';
import '../schema.dart';
import 'native_document_reader.dart';

final _types = Expando<Uint8List>('migration field types');

T cindelReadMigrationObject<T>(
  CindelCollectionSchema<T> schema,
  int id,
  Uint8List bytes, {
  required bool sqlite,
}) {
  final decode = schema.readNativeDocument;
  if (decode == null)
    throw StateError('Migration requires a generated native reader.');
  final types = _types[schema] ??= () {
    final fields = schema.fields.where((f) => !f.isId).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return Uint8List.fromList([
      for (final field in fields)
        switch (field.binaryType) {
          'bool' => 0,
          'int' => 1,
          'double' => 2,
          'string' => 3,
          'list' => 4,
          'object' => 5,
          _ => throw StateError('Unsupported migration field type.'),
        },
    ]);
  }();
  final reader = CindelWebNativeDocumentReader(
    ids: [id],
    documents: [bytes],
    fieldTypes: types,
  );
  try {
    return decode(reader, 0);
  } finally {
    reader.release();
  }
}
