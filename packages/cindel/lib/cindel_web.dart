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
        WireChangeSet,
        WireDocumentWrite,
        WireIndexedDocumentWrite,
        WireIndexEntry,
        WireIndexValue,
        WireFilter,
        WireFilterOperation,
        WireNativeDocumentBool,
        WireNativeDocumentBytes,
        WireNativeDocumentDouble,
        WireNativeDocumentInt,
        WireNativeDocumentNull,
        WireNativeDocumentValue,
        WireNativeDocumentWrite,
        WireQueryAllSource,
        WireQueryIndexEqualSource,
        WireQueryIndexRangeSource,
        WireQueryPlan,
        WireProjectionRows,
        WireQuerySort,
        WireQuerySource,
        WireScalar,
        WireValue,
        decodeIdList,
        decodeChangeSetList,
        decodeIndexedDocumentWriteBatch,
        decodeNativeDocumentWriteBatch,
        decodeOptionalDocumentBatch,
        decodeProjectionRows,
        decodeScalar,
        encodeDocumentWriteBatch,
        encodeFieldUpdates,
        encodeFilter,
        encodeIdList,
        encodeIndexValue,
        encodeIndexedDocumentWriteBatch,
        encodeNativeDocumentWriteBatch,
        encodeOptionalDocumentBatch,
        encodeQueryPlan;
export 'src/web/schema_manifest.dart';
export 'src/web/worker_bridge.dart';
