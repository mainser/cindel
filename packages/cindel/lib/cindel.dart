/// Public Dart API for opening Cindel databases, defining schemas, and running
/// generated typed collections and queries.
///
/// This is the only application entrypoint. Native platforms export the FFI
/// implementation; Dart Web exports the Worker/Wasm SQLite facade behind the
/// same `Cindel.open(...)` API.
library cindel;

export 'package:cindel_annotations/cindel_annotations.dart';

export 'src/backup.dart';
export 'src/binary_document.dart'
    if (dart.library.js_interop) 'src/web/binary_document.dart'
    show
        CindelSchemaBinaryDocumentReader,
        CindelBinaryFieldType,
        cindelDecodeBinaryList,
        cindelDecodeBinaryObject,
        cindelDecodeSchemaBinaryDocument,
        cindelEncodeBinaryList,
        cindelEncodeBinaryObject,
        cindelEncodeSchemaBinaryDocument;
export 'src/cindel.dart' if (dart.library.js_interop) 'src/web/cindel.dart';
export 'src/cindel_error.dart';
export 'src/database.dart' if (dart.library.js_interop) 'src/web/database.dart';
export 'src/migration.dart';
export 'src/query.dart' if (dart.library.js_interop) 'src/web/query.dart';
export 'src/schema.dart';
export 'src/text.dart';
export 'src/typed_collection.dart'
    if (dart.library.js_interop) 'src/web/typed_collection.dart';
