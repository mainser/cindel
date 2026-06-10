/// Web entrypoint for Cindel worker transport APIs.
///
/// The main `package:cindel/cindel.dart` entrypoint remains the native FFI API.
/// Import this library from Dart Web code that needs to communicate with the
/// Cindel Web worker runtime.
library cindel_web;

export 'package:cindel_annotations/cindel_annotations.dart'
    show CindelIndexType;

export 'src/schema.dart'
    show CindelCollectionSchema, CindelCompositeIndexSchema, CindelFieldSchema;
export 'src/native/wire.dart'
    show
        WireDocumentWrite,
        WireIndexedDocumentWrite,
        WireIndexEntry,
        WireIndexValue,
        WireNativeDocumentBool,
        WireNativeDocumentBytes,
        WireNativeDocumentDouble,
        WireNativeDocumentInt,
        WireNativeDocumentNull,
        WireNativeDocumentValue,
        WireNativeDocumentWrite,
        decodeIdList,
        decodeIndexedDocumentWriteBatch,
        decodeNativeDocumentWriteBatch,
        decodeOptionalDocumentBatch,
        encodeDocumentWriteBatch,
        encodeIdList,
        encodeIndexedDocumentWriteBatch,
        encodeNativeDocumentWriteBatch,
        encodeOptionalDocumentBatch;
export 'src/web/schema_manifest.dart';
export 'src/web/worker_bridge.dart';
