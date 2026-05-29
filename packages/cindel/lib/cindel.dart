/// Public Dart API for opening Cindel databases, defining schemas, and running
/// generated typed collections and queries.
library cindel;

export 'package:cindel_annotations/cindel_annotations.dart';

export 'src/binary_document.dart'
    show
        CindelSchemaBinaryDocumentReader,
        CindelBinaryFieldType,
        cindelDecodeBinaryList,
        cindelDecodeBinaryObject,
        cindelDecodeSchemaBinaryDocument,
        cindelEncodeBinaryList,
        cindelEncodeBinaryObject,
        cindelEncodeSchemaBinaryDocument;
export 'src/cindel.dart';
export 'src/database.dart';
export 'src/query.dart';
export 'src/schema.dart';
export 'src/text.dart';
export 'src/typed_collection.dart';
