part of 'bindings.dart';

// `_CindelNativeFunctions` implementation backed by Dart native assets.
//
// Unlike `_DynamicCindelNativeFunctions`, this class does not perform manual
// symbol lookup. Each getter returns the tear-off generated from an `@Native`
// declaration below, using `_assetId` to bind to Cindel's bundled native asset.
// Keep this adapter aligned with `_CindelNativeFunctions` and
// `_DynamicCindelNativeFunctions` whenever the Rust ABI changes.
final class _NativeAssetCindelNativeFunctions
    implements _CindelNativeFunctions {
  const _NativeAssetCindelNativeFunctions();

  // ABI/version and database open symbols.
  @override
  int Function() get abiVersion => _cindelAbiVersion;

  @override
  Pointer<Void> Function(Pointer<Uint8>, int) get open => _cindelOpen;

  @override
  Pointer<Void> openWithBackend(
    Pointer<Uint8> directory,
    int length,
    int backend,
  ) {
    return _cindelOpenWithBackend(directory, length, backend);
  }

  @override
  Pointer<Void> openWithBackendAndSchemas(
    Pointer<Uint8> directory,
    int length,
    int backend,
    Pointer<Uint8> schemas,
    int schemasLength,
  ) {
    return _cindelOpenWithBackendAndSchemas(
      directory,
      length,
      backend,
      schemas,
      schemasLength,
    );
  }

  // Database lifecycle and transaction symbols.
  @override
  void Function(Pointer<Void>) get close => _cindelClose;

  @override
  int Function(Pointer<Void>) get beginReadTransaction =>
      _cindelBeginReadTransaction;

  @override
  int Function(Pointer<Void>) get beginWriteTransaction =>
      _cindelBeginWriteTransaction;

  @override
  int Function(Pointer<Void>) get commitTransaction => _cindelCommitTransaction;

  @override
  int Function(Pointer<Void>) get rollbackTransaction =>
      _cindelRollbackTransaction;

  // Document write symbols.
  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, int, Pointer<Uint8>, int)
  get put => _cindelPut;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  get allocateId => _cindelAllocateId;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int) get registerSchemas =>
      _cindelRegisterSchemas;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int)
  get registerMigratedSchemas => _cindelRegisterMigratedSchemas;

  @override
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
  get putIndexed => _cindelPutIndexed;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  get putManyIndexed => _cindelPutManyIndexed;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  get putManyStored => _cindelPutManyStored;

  // Native generated-document writer symbols.
  @override
  Pointer<Void> Function(Pointer<Uint8>, int, int, int)
  get nativeBatchWriterNew => _cindelNativeBatchWriterNew;

  @override
  void Function(Pointer<Void>, int) get nativeBatchWriterBeginDocument =>
      _cindelNativeBatchWriterBeginDocument;

  @override
  void Function(Pointer<Void>, int) get nativeBatchWriterWriteNull =>
      _cindelNativeBatchWriterWriteNull;

  @override
  void Function(Pointer<Void>, int, bool) get nativeBatchWriterWriteBool =>
      _cindelNativeBatchWriterWriteBool;

  @override
  void Function(Pointer<Void>, int, int) get nativeBatchWriterWriteInt =>
      _cindelNativeBatchWriterWriteInt;

  @override
  void Function(Pointer<Void>, int, double) get nativeBatchWriterWriteDouble =>
      _cindelNativeBatchWriterWriteDouble;

  @override
  void Function(Pointer<Void>, int, Pointer<Uint8>, int)
  get nativeBatchWriterWriteBytes => _cindelNativeBatchWriterWriteBytes;

  @override
  Pointer<Void> Function(Pointer<Void>, int, int)
  get nativeBatchWriterBeginList => _cindelNativeBatchWriterBeginList;

  @override
  void Function(Pointer<Void>, Pointer<Void>) get nativeBatchWriterEndList =>
      _cindelNativeBatchWriterEndList;

  @override
  Pointer<Void> Function(Pointer<Void>, int, Pointer<Uint8>, int)
  get nativeBatchWriterBeginObject => _cindelNativeBatchWriterBeginObject;

  @override
  void Function(Pointer<Void>, Pointer<Void>) get nativeBatchWriterEndObject =>
      _cindelNativeBatchWriterEndObject;

  @override
  void Function(Pointer<Void>, int) get nativeBatchWriterSaveDocument =>
      _cindelNativeBatchWriterSaveDocument;

  @override
  void Function(Pointer<Void>) get nativeBatchWriterEndDocument =>
      _cindelNativeBatchWriterEndDocument;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>)
  get nativeBatchWriterFinish => _cindelNativeBatchWriterFinish;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>, int)
  get nativeBatchWriterFinishWithOptions =>
      _cindelNativeBatchWriterFinishWithOptions;

  @override
  void Function(Pointer<Void>) get nativeBatchWriterAbort =>
      _cindelNativeBatchWriterAbort;

  // Native generated-document reader symbols.
  @override
  Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
  )
  get nativeDocumentReaderNew => _cindelNativeDocumentReaderNew;

  @override
  Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
  )
  get nativeDocumentReaderNewFromQueryPlan =>
      _cindelNativeDocumentReaderNewFromQueryPlan;

  @override
  int Function(Pointer<Void>) get nativeDocumentReaderLen =>
      _cindelNativeDocumentReaderLen;

  @override
  bool Function(Pointer<Void>) get nativeDocumentReaderIsStreaming =>
      _cindelNativeDocumentReaderIsStreaming;

  @override
  bool Function(Pointer<Void>) get nativeDocumentReaderNext =>
      _cindelNativeDocumentReaderNext;

  @override
  bool Function(Pointer<Void>, int) get nativeDocumentReaderIsPresent =>
      _cindelNativeDocumentReaderIsPresent;

  @override
  bool Function(Pointer<Void>, int, Pointer<Uint64>)
  get nativeDocumentReaderReadId => _cindelNativeDocumentReaderReadId;

  @override
  int Function(Pointer<Void>, int) get nativeDocumentReaderReadIdValue =>
      _cindelNativeDocumentReaderReadIdValue;

  @override
  int Function(Pointer<Void>) get nativeDocumentReaderReadCurrentIdValue =>
      _cindelNativeDocumentReaderReadCurrentIdValue;

  @override
  bool Function(Pointer<Void>, int, int, Pointer<Bool>)
  get nativeDocumentReaderReadBool => _cindelNativeDocumentReaderReadBool;

  @override
  int Function(Pointer<Void>, int, int) get nativeDocumentReaderReadBoolValue =>
      _cindelNativeDocumentReaderReadBoolValue;

  @override
  int Function(Pointer<Void>, int)
  get nativeDocumentReaderReadCurrentBoolValue =>
      _cindelNativeDocumentReaderReadCurrentBoolValue;

  @override
  bool Function(Pointer<Void>, int, int, Pointer<Int64>)
  get nativeDocumentReaderReadInt => _cindelNativeDocumentReaderReadInt;

  @override
  int Function(Pointer<Void>, int, int) get nativeDocumentReaderReadIntValue =>
      _cindelNativeDocumentReaderReadIntValue;

  @override
  int Function(Pointer<Void>, int)
  get nativeDocumentReaderReadCurrentIntValue =>
      _cindelNativeDocumentReaderReadCurrentIntValue;

  @override
  bool Function(Pointer<Void>, int, int, Pointer<Double>)
  get nativeDocumentReaderReadDouble => _cindelNativeDocumentReaderReadDouble;

  @override
  double Function(Pointer<Void>, int, int)
  get nativeDocumentReaderReadDoubleValue =>
      _cindelNativeDocumentReaderReadDoubleValue;

  @override
  double Function(Pointer<Void>, int)
  get nativeDocumentReaderReadCurrentDoubleValue =>
      _cindelNativeDocumentReaderReadCurrentDoubleValue;

  @override
  bool Function(Pointer<Void>, int, int, Pointer<Pointer<Uint8>>, Pointer<Size>)
  get nativeDocumentReaderReadBytes => _cindelNativeDocumentReaderReadBytes;

  @override
  bool Function(Pointer<Void>, int, Pointer<Pointer<Uint8>>, Pointer<Size>)
  get nativeDocumentReaderReadCurrentBytes =>
      _cindelNativeDocumentReaderReadCurrentBytes;

  @override
  bool Function(
    Pointer<Void>,
    int,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
    Pointer<Bool>,
    Pointer<Uint64>,
  )
  get nativeDocumentReaderReadString => _cindelNativeDocumentReaderReadString;

  @override
  int Function(Pointer<Void>, int, int, Pointer<Pointer<Uint8>>, Pointer<Bool>)
  get nativeDocumentReaderReadStringValue =>
      _cindelNativeDocumentReaderReadStringValue;

  @override
  int Function(Pointer<Void>, int, Pointer<Pointer<Uint8>>, Pointer<Bool>)
  get nativeDocumentReaderReadCurrentStringValue =>
      _cindelNativeDocumentReaderReadCurrentStringValue;

  @override
  bool Function(Pointer<Void>, int, int, Pointer<Pointer<Uint8>>, Pointer<Size>)
  get nativeDocumentReaderReadListBytes =>
      _cindelNativeDocumentReaderReadListBytes;

  @override
  bool Function(Pointer<Void>, int, Pointer<Pointer<Uint8>>, Pointer<Size>)
  get nativeDocumentReaderReadCurrentListBytes =>
      _cindelNativeDocumentReaderReadCurrentListBytes;

  @override
  Pointer<Void> Function(Pointer<Void>, int, int)
  get nativeDocumentReaderReadList => _cindelNativeDocumentReaderReadList;

  @override
  Pointer<Void> Function(Pointer<Void>, int)
  get nativeDocumentReaderReadCurrentList =>
      _cindelNativeDocumentReaderReadCurrentList;

  @override
  Pointer<Void> Function(Pointer<Void>, int, int, Pointer<Uint8>, int)
  get nativeDocumentReaderReadObject => _cindelNativeDocumentReaderReadObject;

  @override
  Pointer<Void> Function(Pointer<Void>, int, Pointer<Uint8>, int)
  get nativeDocumentReaderReadCurrentObject =>
      _cindelNativeDocumentReaderReadCurrentObject;

  @override
  void Function(Pointer<Void>) get nativeDocumentReaderFree =>
      _cindelNativeDocumentReaderFree;

  // Document read symbols.
  @override
  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get get => _cindelGet;

  @override
  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get getStored => _cindelGetStored;

  @override
  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get getMany => _cindelGetMany;

  @override
  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get getManyStored => _cindelGetManyStored;

  @override
  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get documentIds => _cindelDocumentIds;

  @override
  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    int,
    int,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get documentIdsPage => _cindelDocumentIdsPage;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, int) get delete =>
      _cindelDelete;

  // Delete, revision, change-tracking, and schema metadata symbols.
  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  get deleteMany => _cindelDeleteMany;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  get deleteManyNativeDocuments => _cindelDeleteManyNativeDocuments;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  get collectionRevision => _cindelCollectionRevision;

  @override
  int Function(Pointer<Void>, Pointer<Pointer<Uint8>>, Pointer<Size>)
  get takeChanges => _cindelTakeChanges;

  @override
  int Function(Pointer<Void>) get discardChanges => _cindelDiscardChanges;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  get schemaVersion => _cindelSchemaVersion;

  @override
  int Function(Pointer<Void>, Pointer<Uint64>) get migrationVersion =>
      _cindelMigrationVersion;

  @override
  int Function(Pointer<Void>, int) get setMigrationVersion =>
      _cindelSetMigrationVersion;

  @override
  int Function(Pointer<Void>) get compact => _cindelCompact;

  // Legacy query symbols that execute one native operation at a time.
  @override
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
  get queryIndexEqual => _cindelQueryIndexEqual;

  @override
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
  get queryIndexRange => _cindelQueryIndexRange;

  @override
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
  get queryFilter => _cindelQueryFilter;

  @override
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
  get queryProject => _cindelQueryProject;

  @override
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
  get queryAggregate => _cindelQueryAggregate;

  // Query-plan symbols.
  @override
  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryPlanIds => _cindelQueryPlanIds;

  @override
  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryPlanDocuments => _cindelQueryPlanDocuments;

  @override
  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryPlanCount => _cindelQueryPlanCount;

  @override
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
  get queryPlanProject => _cindelQueryPlanProject;

  @override
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
  get queryPlanAggregate => _cindelQueryPlanAggregate;

  @override
  int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get queryPlanDelete => _cindelQueryPlanDelete;

  @override
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
  get queryPlanUpdate => _cindelQueryPlanUpdate;

  // Buffer release symbol.
  @override
  void Function(Pointer<Uint8>, int) get freeBuffer => _cindelFreeBuffer;
}

// Attempts to open a dynamic library before falling back to native assets.
//
// The environment override is mainly for tests and local builds where the
// package-level prebuilt DLL/so/dylib can be stale. On iOS the symbols are
// expected to live in the current process.
DynamicLibrary? _openBundledLibrary() {
  final overridePath = Platform.environment['CINDEL_NATIVE_LIBRARY'];
  if (overridePath != null && overridePath.trim().isNotEmpty) {
    return DynamicLibrary.open(overridePath);
  }

  if (Platform.isIOS) {
    return DynamicLibrary.process();
  }

  final names = _candidateLibraryNames();

  for (final name in names) {
    try {
      return DynamicLibrary.open(name);
    } on ArgumentError {
      continue;
    } on OSError {
      continue;
    }
  }
  return null;
}

// Returns platform-specific dynamic library candidates used by local tests,
// examples, and desktop/package layouts.
List<String> _candidateLibraryNames() {
  final platformName = switch (Abi.current()) {
    Abi.androidArm ||
    Abi.androidArm64 ||
    Abi.androidIA32 ||
    Abi.androidX64 => 'libcindel_native.so',
    Abi.linuxX64 || Abi.linuxArm64 => 'libcindel_native.so',
    Abi.macosX64 || Abi.macosArm64 => 'libcindel_native.dylib',
    Abi.windowsX64 || Abi.windowsArm64 => 'cindel_native.dll',
    _ => null,
  };

  if (platformName == null) {
    return const <String>[];
  }

  final packagePath = switch (Abi.current()) {
    Abi.linuxX64 || Abi.linuxArm64 => 'linux/$platformName',
    Abi.macosX64 || Abi.macosArm64 => 'macos/$platformName',
    Abi.windowsX64 || Abi.windowsArm64 => 'windows/$platformName',
    _ => null,
  };

  if (packagePath == null) {
    return [platformName];
  }

  final current = Directory.current.path;
  return [
    _joinPath(current, 'packages/cindel_flutter_libs/$packagePath'),
    _joinPath(current, '../cindel_flutter_libs/$packagePath'),
    _joinPath(current, '../../packages/cindel_flutter_libs/$packagePath'),
    platformName,
  ];
}

// Minimal join helper to avoid adding a package dependency in this private FFI
// layer.
String _joinPath(String base, String relativePath) {
  final separator = Platform.pathSeparator;
  final normalizedRelativePath = relativePath.replaceAll('/', separator);
  return '$base$separator$normalizedRelativePath';
}

// Native asset declarations. The Dart signatures here must match both
// `_CindelNativeFunctions` and the exported Rust ABI exactly.
//
// Use `isLeaf: true` only for calls that cannot re-enter Dart, allocate through
// Dart callbacks, or block in a way that would violate FFI leaf-call rules.
@Native<Uint32 Function()>(
  symbol: 'cindel_abi_version',
  assetId: _assetId,
  isLeaf: true,
)
external int _cindelAbiVersion();

@Native<Pointer<Void> Function(Pointer<Uint8>, Size)>(
  symbol: 'cindel_open',
  assetId: _assetId,
)
external Pointer<Void> _cindelOpen(Pointer<Uint8> directory, int directoryLen);

@Native<Pointer<Void> Function(Pointer<Uint8>, Size, Uint32)>(
  symbol: 'cindel_open_with_backend',
  assetId: _assetId,
)
external Pointer<Void> _cindelOpenWithBackend(
  Pointer<Uint8> directory,
  int directoryLen,
  int backend,
);

@Native<
  Pointer<Void> Function(Pointer<Uint8>, Size, Uint32, Pointer<Uint8>, Size)
>(symbol: 'cindel_open_with_backend_and_schemas', assetId: _assetId)
external Pointer<Void> _cindelOpenWithBackendAndSchemas(
  Pointer<Uint8> directory,
  int directoryLen,
  int backend,
  Pointer<Uint8> schemas,
  int schemasLen,
);

// Lifecycle and transaction exports.
@Native<Void Function(Pointer<Void>)>(
  symbol: 'cindel_close',
  assetId: _assetId,
  isLeaf: true,
)
external void _cindelClose(Pointer<Void> handle);

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'cindel_begin_read_txn',
  assetId: _assetId,
)
external int _cindelBeginReadTransaction(Pointer<Void> handle);

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'cindel_begin_write_txn',
  assetId: _assetId,
)
external int _cindelBeginWriteTransaction(Pointer<Void> handle);

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'cindel_commit_txn',
  assetId: _assetId,
)
external int _cindelCommitTransaction(Pointer<Void> handle);

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'cindel_rollback_txn',
  assetId: _assetId,
)
external int _cindelRollbackTransaction(Pointer<Void> handle);

// Document write exports.
@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<Uint8>,
    Size,
  )
>(symbol: 'cindel_put', assetId: _assetId)
external int _cindelPut(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  int id,
  Pointer<Uint8> bytes,
  int bytesLen,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Uint64>)>(
  symbol: 'cindel_allocate_id',
  assetId: _assetId,
)
external int _cindelAllocateId(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint64> outId,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>, Size)>(
  symbol: 'cindel_register_schemas',
  assetId: _assetId,
)
external int _cindelRegisterSchemas(
  Pointer<Void> handle,
  Pointer<Uint8> schemas,
  int schemasLen,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>, Size)>(
  symbol: 'cindel_register_migrated_schemas',
  assetId: _assetId,
)
external int _cindelRegisterMigratedSchemas(
  Pointer<Void> handle,
  Pointer<Uint8> schemas,
  int schemasLen,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
  )
>(symbol: 'cindel_put_indexed', assetId: _assetId)
external int _cindelPutIndexed(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  int id,
  Pointer<Uint8> bytes,
  int bytesLen,
  Pointer<Uint8> indexes,
  int indexesLen,
);

@Native<
  Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Uint8>, Size)
>(symbol: 'cindel_put_many_indexed', assetId: _assetId)
external int _cindelPutManyIndexed(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> documents,
  int documentsLen,
);

@Native<
  Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Uint8>, Size)
>(symbol: 'cindel_put_many_stored', assetId: _assetId)
external int _cindelPutManyStored(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> documents,
  int documentsLen,
);

// Native generated-document writer exports.
@Native<Pointer<Void> Function(Pointer<Uint8>, Size, Size, Int32)>(
  symbol: 'cindel_native_batch_writer_new',
  assetId: _assetId,
)
external Pointer<Void> _cindelNativeBatchWriterNew(
  Pointer<Uint8> fieldTypes,
  int fieldTypesLen,
  int capacity,
  int collectNativeValues,
);

@Native<Void Function(Pointer<Void>, Uint64)>(
  symbol: 'cindel_native_batch_writer_begin_document',
  assetId: _assetId,
)
external void _cindelNativeBatchWriterBeginDocument(
  Pointer<Void> writer,
  int id,
);

@Native<Void Function(Pointer<Void>, Uint32)>(
  symbol: 'cindel_native_batch_writer_write_null',
  assetId: _assetId,
)
external void _cindelNativeBatchWriterWriteNull(
  Pointer<Void> writer,
  int fieldIndex,
);

@Native<Void Function(Pointer<Void>, Uint32, Bool)>(
  symbol: 'cindel_native_batch_writer_write_bool',
  assetId: _assetId,
)
external void _cindelNativeBatchWriterWriteBool(
  Pointer<Void> writer,
  int fieldIndex,
  bool value,
);

@Native<Void Function(Pointer<Void>, Uint32, Int64)>(
  symbol: 'cindel_native_batch_writer_write_int',
  assetId: _assetId,
)
external void _cindelNativeBatchWriterWriteInt(
  Pointer<Void> writer,
  int fieldIndex,
  int value,
);

@Native<Void Function(Pointer<Void>, Uint32, Double)>(
  symbol: 'cindel_native_batch_writer_write_double',
  assetId: _assetId,
)
external void _cindelNativeBatchWriterWriteDouble(
  Pointer<Void> writer,
  int fieldIndex,
  double value,
);

@Native<Void Function(Pointer<Void>, Uint32, Pointer<Uint8>, Size)>(
  symbol: 'cindel_native_batch_writer_write_bytes',
  assetId: _assetId,
)
external void _cindelNativeBatchWriterWriteBytes(
  Pointer<Void> writer,
  int fieldIndex,
  Pointer<Uint8> bytes,
  int bytesLen,
);

@Native<Pointer<Void> Function(Pointer<Void>, Uint32, Size)>(
  symbol: 'cindel_native_batch_writer_begin_list',
  assetId: _assetId,
)
external Pointer<Void> _cindelNativeBatchWriterBeginList(
  Pointer<Void> writer,
  int fieldIndex,
  int length,
);

@Native<Void Function(Pointer<Void>, Pointer<Void>)>(
  symbol: 'cindel_native_batch_writer_end_list',
  assetId: _assetId,
)
external void _cindelNativeBatchWriterEndList(
  Pointer<Void> writer,
  Pointer<Void> listWriter,
);

@Native<Pointer<Void> Function(Pointer<Void>, Uint32, Pointer<Uint8>, Size)>(
  symbol: 'cindel_native_batch_writer_begin_object',
  assetId: _assetId,
)
external Pointer<Void> _cindelNativeBatchWriterBeginObject(
  Pointer<Void> writer,
  int fieldIndex,
  Pointer<Uint8> fieldNames,
  int fieldNamesLength,
);

@Native<Void Function(Pointer<Void>, Pointer<Void>)>(
  symbol: 'cindel_native_batch_writer_end_object',
  assetId: _assetId,
)
external void _cindelNativeBatchWriterEndObject(
  Pointer<Void> writer,
  Pointer<Void> objectWriter,
);

@Native<Void Function(Pointer<Void>, Uint64)>(
  symbol: 'cindel_native_batch_writer_save_document',
  assetId: _assetId,
)
external void _cindelNativeBatchWriterSaveDocument(
  Pointer<Void> writer,
  int id,
);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'cindel_native_batch_writer_end_document',
  assetId: _assetId,
)
external void _cindelNativeBatchWriterEndDocument(Pointer<Void> writer);

@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Void>)>(
  symbol: 'cindel_native_batch_writer_finish',
  assetId: _assetId,
)
external int _cindelNativeBatchWriterFinish(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Void> writer,
);

@Native<
  Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Void>, Int32)
>(symbol: 'cindel_native_batch_writer_finish_with_options', assetId: _assetId)
external int _cindelNativeBatchWriterFinishWithOptions(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Void> writer,
  int trackChanges,
);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'cindel_native_batch_writer_abort',
  assetId: _assetId,
)
external void _cindelNativeBatchWriterAbort(Pointer<Void> writer);

// Native generated-document reader exports.
@Native<
  Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
  )
>(symbol: 'cindel_native_document_reader_new', assetId: _assetId)
external Pointer<Void> _cindelNativeDocumentReaderNew(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> ids,
  int idsLen,
  Pointer<Uint8> fieldTypes,
  int fieldTypesLen,
);

@Native<
  Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
  )
>(
  symbol: 'cindel_native_document_reader_new_from_query_plan',
  assetId: _assetId,
)
external Pointer<Void> _cindelNativeDocumentReaderNewFromQueryPlan(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> plan,
  int planLen,
  Pointer<Uint8> fieldTypes,
  int fieldTypesLen,
);

@Native<Size Function(Pointer<Void>)>(
  symbol: 'cindel_native_document_reader_len',
  assetId: _assetId,
  isLeaf: true,
)
external int _cindelNativeDocumentReaderLen(Pointer<Void> reader);

@Native<Bool Function(Pointer<Void>)>(
  symbol: 'cindel_native_document_reader_is_streaming',
  assetId: _assetId,
  isLeaf: true,
)
external bool _cindelNativeDocumentReaderIsStreaming(Pointer<Void> reader);

@Native<Bool Function(Pointer<Void>)>(
  symbol: 'cindel_native_document_reader_next',
  assetId: _assetId,
)
external bool _cindelNativeDocumentReaderNext(Pointer<Void> reader);

@Native<Bool Function(Pointer<Void>, Size)>(
  symbol: 'cindel_native_document_reader_is_present',
  assetId: _assetId,
  isLeaf: true,
)
external bool _cindelNativeDocumentReaderIsPresent(
  Pointer<Void> reader,
  int documentIndex,
);

@Native<Bool Function(Pointer<Void>, Size, Pointer<Uint64>)>(
  symbol: 'cindel_native_document_reader_read_id',
  assetId: _assetId,
  isLeaf: true,
)
external bool _cindelNativeDocumentReaderReadId(
  Pointer<Void> reader,
  int documentIndex,
  Pointer<Uint64> outValue,
);

@Native<Uint64 Function(Pointer<Void>, Size)>(
  symbol: 'cindel_native_document_reader_read_id_value',
  assetId: _assetId,
  isLeaf: true,
)
external int _cindelNativeDocumentReaderReadIdValue(
  Pointer<Void> reader,
  int documentIndex,
);

@Native<Uint64 Function(Pointer<Void>)>(
  symbol: 'cindel_native_document_reader_read_current_id_value',
  assetId: _assetId,
  isLeaf: true,
)
external int _cindelNativeDocumentReaderReadCurrentIdValue(
  Pointer<Void> reader,
);

@Native<Bool Function(Pointer<Void>, Size, Uint32, Pointer<Bool>)>(
  symbol: 'cindel_native_document_reader_read_bool',
  assetId: _assetId,
  isLeaf: true,
)
external bool _cindelNativeDocumentReaderReadBool(
  Pointer<Void> reader,
  int documentIndex,
  int fieldIndex,
  Pointer<Bool> outValue,
);

@Native<Uint8 Function(Pointer<Void>, Size, Uint32)>(
  symbol: 'cindel_native_document_reader_read_bool_value',
  assetId: _assetId,
  isLeaf: true,
)
external int _cindelNativeDocumentReaderReadBoolValue(
  Pointer<Void> reader,
  int documentIndex,
  int fieldIndex,
);

@Native<Uint8 Function(Pointer<Void>, Uint32)>(
  symbol: 'cindel_native_document_reader_read_current_bool_value',
  assetId: _assetId,
  isLeaf: true,
)
external int _cindelNativeDocumentReaderReadCurrentBoolValue(
  Pointer<Void> reader,
  int fieldIndex,
);

@Native<Bool Function(Pointer<Void>, Size, Uint32, Pointer<Int64>)>(
  symbol: 'cindel_native_document_reader_read_int',
  assetId: _assetId,
  isLeaf: true,
)
external bool _cindelNativeDocumentReaderReadInt(
  Pointer<Void> reader,
  int documentIndex,
  int fieldIndex,
  Pointer<Int64> outValue,
);

@Native<Int64 Function(Pointer<Void>, Size, Uint32)>(
  symbol: 'cindel_native_document_reader_read_int_value',
  assetId: _assetId,
  isLeaf: true,
)
external int _cindelNativeDocumentReaderReadIntValue(
  Pointer<Void> reader,
  int documentIndex,
  int fieldIndex,
);

@Native<Int64 Function(Pointer<Void>, Uint32)>(
  symbol: 'cindel_native_document_reader_read_current_int_value',
  assetId: _assetId,
  isLeaf: true,
)
external int _cindelNativeDocumentReaderReadCurrentIntValue(
  Pointer<Void> reader,
  int fieldIndex,
);

@Native<Bool Function(Pointer<Void>, Size, Uint32, Pointer<Double>)>(
  symbol: 'cindel_native_document_reader_read_double',
  assetId: _assetId,
  isLeaf: true,
)
external bool _cindelNativeDocumentReaderReadDouble(
  Pointer<Void> reader,
  int documentIndex,
  int fieldIndex,
  Pointer<Double> outValue,
);

@Native<Double Function(Pointer<Void>, Size, Uint32)>(
  symbol: 'cindel_native_document_reader_read_double_value',
  assetId: _assetId,
  isLeaf: true,
)
external double _cindelNativeDocumentReaderReadDoubleValue(
  Pointer<Void> reader,
  int documentIndex,
  int fieldIndex,
);

@Native<Double Function(Pointer<Void>, Uint32)>(
  symbol: 'cindel_native_document_reader_read_current_double_value',
  assetId: _assetId,
  isLeaf: true,
)
external double _cindelNativeDocumentReaderReadCurrentDoubleValue(
  Pointer<Void> reader,
  int fieldIndex,
);

@Native<
  Bool Function(
    Pointer<Void>,
    Size,
    Uint32,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(
  symbol: 'cindel_native_document_reader_read_bytes',
  assetId: _assetId,
  isLeaf: true,
)
external bool _cindelNativeDocumentReaderReadBytes(
  Pointer<Void> reader,
  int documentIndex,
  int fieldIndex,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Bool Function(
    Pointer<Void>,
    Size,
    Uint32,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
    Pointer<Bool>,
    Pointer<Uint64>,
  )
>(
  symbol: 'cindel_native_document_reader_read_string',
  assetId: _assetId,
  isLeaf: true,
)
external bool _cindelNativeDocumentReaderReadString(
  Pointer<Void> reader,
  int documentIndex,
  int fieldIndex,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
  Pointer<Bool> outIsAscii,
  Pointer<Uint64> outInternId,
);

@Native<
  Size Function(
    Pointer<Void>,
    Size,
    Uint32,
    Pointer<Pointer<Uint8>>,
    Pointer<Bool>,
  )
>(
  symbol: 'cindel_native_document_reader_read_string_value',
  assetId: _assetId,
  isLeaf: true,
)
external int _cindelNativeDocumentReaderReadStringValue(
  Pointer<Void> reader,
  int documentIndex,
  int fieldIndex,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Bool> outIsAscii,
);

@Native<
  Bool Function(Pointer<Void>, Uint32, Pointer<Pointer<Uint8>>, Pointer<Size>)
>(
  symbol: 'cindel_native_document_reader_read_current_bytes',
  assetId: _assetId,
  isLeaf: true,
)
external bool _cindelNativeDocumentReaderReadCurrentBytes(
  Pointer<Void> reader,
  int fieldIndex,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Size Function(Pointer<Void>, Uint32, Pointer<Pointer<Uint8>>, Pointer<Bool>)
>(
  symbol: 'cindel_native_document_reader_read_current_string_value',
  assetId: _assetId,
  isLeaf: true,
)
external int _cindelNativeDocumentReaderReadCurrentStringValue(
  Pointer<Void> reader,
  int fieldIndex,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Bool> outIsAscii,
);

@Native<
  Bool Function(
    Pointer<Void>,
    Size,
    Uint32,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(
  symbol: 'cindel_native_document_reader_read_list_bytes',
  assetId: _assetId,
  isLeaf: true,
)
external bool _cindelNativeDocumentReaderReadListBytes(
  Pointer<Void> reader,
  int documentIndex,
  int fieldIndex,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Bool Function(Pointer<Void>, Uint32, Pointer<Pointer<Uint8>>, Pointer<Size>)
>(
  symbol: 'cindel_native_document_reader_read_current_list_bytes',
  assetId: _assetId,
  isLeaf: true,
)
external bool _cindelNativeDocumentReaderReadCurrentListBytes(
  Pointer<Void> reader,
  int fieldIndex,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<Pointer<Void> Function(Pointer<Void>, Size, Uint32)>(
  symbol: 'cindel_native_document_reader_read_list',
  assetId: _assetId,
)
external Pointer<Void> _cindelNativeDocumentReaderReadList(
  Pointer<Void> reader,
  int documentIndex,
  int fieldIndex,
);

@Native<Pointer<Void> Function(Pointer<Void>, Uint32)>(
  symbol: 'cindel_native_document_reader_read_current_list',
  assetId: _assetId,
)
external Pointer<Void> _cindelNativeDocumentReaderReadCurrentList(
  Pointer<Void> reader,
  int fieldIndex,
);

@Native<
  Pointer<Void> Function(Pointer<Void>, Size, Uint32, Pointer<Uint8>, Size)
>(symbol: 'cindel_native_document_reader_read_object', assetId: _assetId)
external Pointer<Void> _cindelNativeDocumentReaderReadObject(
  Pointer<Void> reader,
  int documentIndex,
  int fieldIndex,
  Pointer<Uint8> fieldNames,
  int fieldNamesLength,
);

@Native<Pointer<Void> Function(Pointer<Void>, Uint32, Pointer<Uint8>, Size)>(
  symbol: 'cindel_native_document_reader_read_current_object',
  assetId: _assetId,
)
external Pointer<Void> _cindelNativeDocumentReaderReadCurrentObject(
  Pointer<Void> reader,
  int fieldIndex,
  Pointer<Uint8> fieldNames,
  int fieldNamesLength,
);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'cindel_native_document_reader_free',
  assetId: _assetId,
)
external void _cindelNativeDocumentReaderFree(Pointer<Void> reader);

// Document read exports. Pointer/length results are native-owned until released
// through `_cindelFreeBuffer`.
@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_get', assetId: _assetId)
external int _cindelGet(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  int id,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_get_stored', assetId: _assetId)
external int _cindelGetStored(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  int id,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_get_many', assetId: _assetId)
external int _cindelGetMany(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> ids,
  int idsLen,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_get_many_stored', assetId: _assetId)
external int _cindelGetManyStored(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> ids,
  int idsLen,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_document_ids', assetId: _assetId)
external int _cindelDocumentIds(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Uint64,
    Int32,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_document_ids_page', assetId: _assetId)
external int _cindelDocumentIdsPage(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  int afterId,
  int hasAfterId,
  int limit,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

// Delete, revision, change-tracking, and schema metadata exports.
@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Uint64)>(
  symbol: 'cindel_delete',
  assetId: _assetId,
)
external int _cindelDelete(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  int id,
);

@Native<
  Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Uint8>, Size)
>(symbol: 'cindel_delete_many', assetId: _assetId)
external int _cindelDeleteMany(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> ids,
  int idsLen,
);

@Native<
  Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Uint8>, Size)
>(symbol: 'cindel_delete_many_native_documents', assetId: _assetId)
external int _cindelDeleteManyNativeDocuments(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> ids,
  int idsLen,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Uint64>)>(
  symbol: 'cindel_collection_revision',
  assetId: _assetId,
)
external int _cindelCollectionRevision(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint64> outRevision,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Pointer<Uint8>>, Pointer<Size>)>(
  symbol: 'cindel_take_changes',
  assetId: _assetId,
)
external int _cindelTakeChanges(
  Pointer<Void> handle,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'cindel_discard_changes',
  assetId: _assetId,
)
external int _cindelDiscardChanges(Pointer<Void> handle);

@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Uint64>)>(
  symbol: 'cindel_schema_version',
  assetId: _assetId,
)
external int _cindelSchemaVersion(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint64> outVersion,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Uint64>)>(
  symbol: 'cindel_migration_version',
  assetId: _assetId,
)
external int _cindelMigrationVersion(
  Pointer<Void> handle,
  Pointer<Uint64> outVersion,
);

@Native<Int32 Function(Pointer<Void>, Uint64)>(
  symbol: 'cindel_set_migration_version',
  assetId: _assetId,
)
external int _cindelSetMigrationVersion(Pointer<Void> handle, int version);

@Native<Int32 Function(Pointer<Void>)>(
  symbol: 'cindel_compact',
  assetId: _assetId,
)
external int _cindelCompact(Pointer<Void> handle);

// Legacy query exports.
@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_query_index_equal', assetId: _assetId)
external int _cindelQueryIndexEqual(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> index,
  int indexLen,
  Pointer<Uint8> value,
  int valueLen,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

// Query-plan exports.
@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_query_index_range', assetId: _assetId)
external int _cindelQueryIndexRange(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> index,
  int indexLen,
  Pointer<Uint8> lower,
  int lowerLen,
  Pointer<Uint8> upper,
  int upperLen,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_query_filter', assetId: _assetId)
external int _cindelQueryFilter(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> ids,
  int idsLen,
  Pointer<Uint8> filter,
  int filterLen,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_query_project', assetId: _assetId)
external int _cindelQueryProject(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> ids,
  int idsLen,
  Pointer<Uint8> field,
  int fieldLen,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_query_aggregate', assetId: _assetId)
external int _cindelQueryAggregate(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> ids,
  int idsLen,
  Pointer<Uint8> field,
  int fieldLen,
  Pointer<Uint8> operation,
  int operationLen,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_query_plan_ids', assetId: _assetId)
external int _cindelQueryPlanIds(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> plan,
  int planLen,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_query_plan_documents', assetId: _assetId)
external int _cindelQueryPlanDocuments(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> plan,
  int planLen,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_query_plan_count', assetId: _assetId)
external int _cindelQueryPlanCount(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> plan,
  int planLen,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_query_plan_project', assetId: _assetId)
external int _cindelQueryPlanProject(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> plan,
  int planLen,
  Pointer<Uint8> field,
  int fieldLen,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_query_plan_aggregate', assetId: _assetId)
external int _cindelQueryPlanAggregate(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> plan,
  int planLen,
  Pointer<Uint8> field,
  int fieldLen,
  Pointer<Uint8> operation,
  int operationLen,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'cindel_query_plan_delete', assetId: _assetId)
external int _cindelQueryPlanDelete(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> plan,
  int planLen,
  Pointer<Pointer<Uint8>> outPointer,
  Pointer<Size> outLength,
);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Bool,
    Pointer<Uint64>,
  )
>(symbol: 'cindel_query_plan_update', assetId: _assetId)
external int _cindelQueryPlanUpdate(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> plan,
  int planLen,
  Pointer<Uint8> updates,
  int updatesLen,
  bool collectChanges,
  Pointer<Uint64> outCount,
);

// Buffer ownership export for all native-owned pointer/length result buffers.
@Native<Void Function(Pointer<Uint8>, Size)>(
  symbol: 'cindel_free_buffer',
  assetId: _assetId,
)
external void _cindelFreeBuffer(Pointer<Uint8> pointer, int length);
