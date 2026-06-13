import 'dart:typed_data';

/// Raw bytes encoded with Cindel's generated binary document format.
typedef CindelBinaryDocumentBytes = Uint8List;

/// Field type metadata used by generated binary document codecs.
enum CindelBinaryFieldType {
  /// Boolean field.
  boolValue,

  /// Integer field.
  intValue,

  /// Double field.
  doubleValue,

  /// String field.
  stringValue,

  /// List field.
  listValue,

  /// Object field.
  objectValue,
}

/// Web-safe placeholder for the native binary document reader.
///
/// Generated code imports these symbols through `package:cindel/cindel.dart`.
/// On Web, supported typed storage uses SQLite native rows through the Worker;
/// the native binary-document codec is intentionally unavailable so Web code
/// does not silently drift onto an unsupported MDBX-style hydration path.
final class CindelSchemaBinaryDocumentReader {
  /// Creates a reader placeholder.
  CindelSchemaBinaryDocumentReader(Uint8List bytes, {required int staticSize});

  /// Binary document decoding is not part of the Web SQLite facade.
  int readId(int documentIndex) => _unsupported();

  /// Binary document decoding is not part of the Web SQLite facade.
  bool? readBool(int fieldIndex, int staticOffset) => _unsupported();

  /// Binary document decoding is not part of the Web SQLite facade.
  int? readInt(int fieldIndex, int staticOffset) => _unsupported();

  /// Binary document decoding is not part of the Web SQLite facade.
  double? readDouble(int fieldIndex, int staticOffset) => _unsupported();

  /// Binary document decoding is not part of the Web SQLite facade.
  String? readString(int fieldIndex, int staticOffset) => _unsupported();

  /// Binary document decoding is not part of the Web SQLite facade.
  List<String>? readStringList(int fieldIndex, int staticOffset) =>
      _unsupported();

  /// Binary document decoding is not part of the Web SQLite facade.
  Object? readList(int fieldIndex, int staticOffset) => _unsupported();

  /// Binary document decoding is not part of the Web SQLite facade.
  Object? readObject(int fieldIndex, int staticOffset) => _unsupported();
}

/// Binary document encoding is not part of the Web SQLite facade.
Uint8List cindelEncodeSchemaBinaryDocument(
  List<Object?> values,
  List<CindelBinaryFieldType> fieldTypes,
) {
  throw UnsupportedError(
    'Cindel Web uses SQLite native documents instead of binary documents.',
  );
}

/// Binary document decoding is not part of the Web SQLite facade.
List<Object?> cindelDecodeSchemaBinaryDocument(Uint8List bytes) {
  throw UnsupportedError(
    'Cindel Web uses SQLite native documents instead of binary documents.',
  );
}

/// Binary object encoding is not part of the Web SQLite facade.
Uint8List cindelEncodeBinaryObject(Map<String, Object?> value) {
  throw UnsupportedError(
    'Cindel Web native embedded object binary encoding is not available yet.',
  );
}

/// Binary object decoding is not part of the Web SQLite facade.
Map<String, Object?> cindelDecodeBinaryObject(Uint8List bytes) {
  throw UnsupportedError(
    'Cindel Web native embedded object binary decoding is not available yet.',
  );
}

/// Binary list encoding is not part of the Web SQLite facade.
Uint8List cindelEncodeBinaryList(List<Object?> value) {
  throw UnsupportedError(
    'Cindel Web native embedded list binary encoding is not available yet.',
  );
}

/// Binary list decoding is not part of the Web SQLite facade.
List<Object?> cindelDecodeBinaryList(Uint8List bytes) {
  throw UnsupportedError(
    'Cindel Web native embedded list binary decoding is not available yet.',
  );
}

Never _unsupported() {
  throw UnsupportedError(
    'Cindel Web uses SQLite native documents instead of binary documents.',
  );
}
