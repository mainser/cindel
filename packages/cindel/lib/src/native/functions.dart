part of 'bindings.dart';

// Contract shared by every way Cindel can call the native library.
//
// `CindelNativeBindings` depends on this interface instead of binding directly
// to one loading strategy. Dynamic libraries and native assets expose the same
// Dart function signatures here, so higher layers can use one facade regardless
// of how the Rust library was loaded.
abstract interface class _CindelNativeFunctions {
  // Prefer an explicitly opened/bundled dynamic library when one is available.
  // Otherwise use Dart native assets, which resolve the generated symbols at
  // compile/build time.
  factory _CindelNativeFunctions.resolve() {
    final library = _openBundledLibrary();
    if (library != null) {
      return _DynamicCindelNativeFunctions(library);
    }
    return const _NativeAssetCindelNativeFunctions();
  }

  // ABI/version and database open symbols.
  int Function() get abiVersion;

  Pointer<Void> Function(Pointer<Uint8>, int) get open;

  Pointer<Void> openWithBackend(
    Pointer<Uint8> directory,
    int length,
    int backend,
  );

  Pointer<Void> openWithBackendAndSchemas(
    Pointer<Uint8> directory,
    int length,
    int backend,
    Pointer<Uint8> schemas,
    int schemasLength,
  );

  // Database lifecycle and transaction symbols.
  void Function(Pointer<Void>) get close;

  int Function(Pointer<Void>) get beginReadTransaction;

  int Function(Pointer<Void>) get beginWriteTransaction;

  int Function(Pointer<Void>) get commitTransaction;

  int Function(Pointer<Void>) get rollbackTransaction;

  // Document write symbols. Indexed variants send both stored bytes and index
  // payloads; stored variants send only persisted document bytes.
  int Function(Pointer<Void>, Pointer<Uint8>, int, int, Pointer<Uint8>, int)
  get put;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  get allocateId;

  int Function(Pointer<Void>, Pointer<Uint8>, int) get registerSchemas;

  int Function(Pointer<Void>, Pointer<Uint8>, int) get registerMigratedSchemas;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
  )
  get putIndexed;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  get putManyIndexed;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  get putManyStored;

  // Native writer symbols used by generated collection code to serialize
  // documents directly into Rust-owned batch builders.
  Pointer<Void> Function(Pointer<Uint8>, int, int, int)
  get nativeBatchWriterNew;

  void Function(Pointer<Void>, int) get nativeBatchWriterBeginDocument;

  void Function(Pointer<Void>, int) get nativeBatchWriterWriteNull;

  void Function(Pointer<Void>, int, bool) get nativeBatchWriterWriteBool;

  void Function(Pointer<Void>, int, int) get nativeBatchWriterWriteInt;

  void Function(Pointer<Void>, int, double) get nativeBatchWriterWriteDouble;

  void Function(Pointer<Void>, int, Pointer<Uint8>, int)
  get nativeBatchWriterWriteBytes;

  Pointer<Void> Function(Pointer<Void>, int, int)
  get nativeBatchWriterBeginList;

  void Function(Pointer<Void>, Pointer<Void>) get nativeBatchWriterEndList;

  Pointer<Void> Function(Pointer<Void>, int, Pointer<Uint8>, int)
  get nativeBatchWriterBeginObject;

  void Function(Pointer<Void>, Pointer<Void>) get nativeBatchWriterEndObject;

  void Function(Pointer<Void>, int) get nativeBatchWriterSaveDocument;

  void Function(Pointer<Void>) get nativeBatchWriterEndDocument;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>)
  get nativeBatchWriterFinish;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>, int)
  get nativeBatchWriterFinishWithOptions;

  void Function(Pointer<Void>) get nativeBatchWriterAbort;

  // Native reader symbols used by generated collection code to hydrate typed
  // objects from native result buffers or streaming query-plan readers.
  Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
  )
  get nativeDocumentReaderNew;

  Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
  )
  get nativeDocumentReaderNewFromQueryPlan;

  int Function(Pointer<Void>) get nativeDocumentReaderLen;

  bool Function(Pointer<Void>) get nativeDocumentReaderIsStreaming;

  bool Function(Pointer<Void>) get nativeDocumentReaderNext;

  bool Function(Pointer<Void>, int) get nativeDocumentReaderIsPresent;

  bool Function(Pointer<Void>, int, Pointer<Uint64>)
  get nativeDocumentReaderReadId;

  int Function(Pointer<Void>, int) get nativeDocumentReaderReadIdValue;

  int Function(Pointer<Void>) get nativeDocumentReaderReadCurrentIdValue;

  bool Function(Pointer<Void>, int, int, Pointer<Bool>)
  get nativeDocumentReaderReadBool;

  int Function(Pointer<Void>, int, int) get nativeDocumentReaderReadBoolValue;

  int Function(Pointer<Void>, int) get nativeDocumentReaderReadCurrentBoolValue;

  bool Function(Pointer<Void>, int, int, Pointer<Int64>)
  get nativeDocumentReaderReadInt;

  int Function(Pointer<Void>, int, int) get nativeDocumentReaderReadIntValue;

  int Function(Pointer<Void>, int) get nativeDocumentReaderReadCurrentIntValue;

  bool Function(Pointer<Void>, int, int, Pointer<Double>)
  get nativeDocumentReaderReadDouble;

  double Function(Pointer<Void>, int, int)
  get nativeDocumentReaderReadDoubleValue;

  double Function(Pointer<Void>, int)
  get nativeDocumentReaderReadCurrentDoubleValue;

  bool Function(Pointer<Void>, int, int, Pointer<Pointer<Uint8>>, Pointer<Size>)
  get nativeDocumentReaderReadBytes;

  bool Function(Pointer<Void>, int, Pointer<Pointer<Uint8>>, Pointer<Size>)
  get nativeDocumentReaderReadCurrentBytes;

  bool Function(
    Pointer<Void>,
    int,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
    Pointer<Bool>,
    Pointer<Uint64>,
  )
  get nativeDocumentReaderReadString;

  int Function(Pointer<Void>, int, int, Pointer<Pointer<Uint8>>, Pointer<Bool>)
  get nativeDocumentReaderReadStringValue;

  int Function(Pointer<Void>, int, Pointer<Pointer<Uint8>>, Pointer<Bool>)
  get nativeDocumentReaderReadCurrentStringValue;

  bool Function(Pointer<Void>, int, int, Pointer<Pointer<Uint8>>, Pointer<Size>)
  get nativeDocumentReaderReadListBytes;

  bool Function(Pointer<Void>, int, Pointer<Pointer<Uint8>>, Pointer<Size>)
  get nativeDocumentReaderReadCurrentListBytes;

  Pointer<Void> Function(Pointer<Void>, int, int)
  get nativeDocumentReaderReadList;

  Pointer<Void> Function(Pointer<Void>, int)
  get nativeDocumentReaderReadCurrentList;

  Pointer<Void> Function(Pointer<Void>, int, int, Pointer<Uint8>, int)
  get nativeDocumentReaderReadObject;

  Pointer<Void> Function(Pointer<Void>, int, Pointer<Uint8>, int)
  get nativeDocumentReaderReadCurrentObject;

  void Function(Pointer<Void>) get nativeDocumentReaderFree;

  // Document read symbols. Methods returning pointer/length pairs transfer a
  // native-owned result buffer that must later be released with `freeBuffer`.
  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get get;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get getStored;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get getMany;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get getManyStored;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get documentIds;

  // Delete, revision, change-tracking, and schema metadata symbols.
  int Function(Pointer<Void>, Pointer<Uint8>, int, int) get delete;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  get deleteMany;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  get deleteManyNativeDocuments;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  get collectionRevision;

  int Function(Pointer<Void>, Pointer<Pointer<Uint8>>, Pointer<Size>)
  get takeChanges;

  int Function(Pointer<Void>) get discardChanges;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  get schemaVersion;

  int Function(Pointer<Void>, Pointer<Uint64>) get migrationVersion;

  int Function(Pointer<Void>, int) get setMigrationVersion;

  int Function(Pointer<Void>) get compact;

  // Legacy query symbols that execute one native operation at a time.
  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryIndexEqual;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryIndexRange;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryFilter;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryProject;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryAggregate;

  // Query-plan symbols. Dart builds a compact plan once, then native executes
  // it for ids, documents, counts, projections, aggregates, deletes, or updates.
  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryPlanIds;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryPlanDocuments;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryPlanCount;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryPlanProject;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryPlanAggregate;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryPlanDelete;

  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    bool,
    Pointer<Uint64>,
  )
  get queryPlanUpdate;

  // Releases native-owned buffers returned through pointer/length out params.
  void Function(Pointer<Uint8>, int) get freeBuffer;
}
