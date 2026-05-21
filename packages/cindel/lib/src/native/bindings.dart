import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const _assetId = 'package:cindel/src/native/bindings.dart';

final class CindelNativeBindings {
  CindelNativeBindings() : _functions = _CindelNativeFunctions.resolve();

  final _CindelNativeFunctions _functions;

  int get abiVersion => _functions.abiVersion();

  Pointer<Void> open(String directory) {
    return _withNativeUtf8Bytes(directory, (directoryPointer, directoryLength) {
      return _functions.open(directoryPointer, directoryLength);
    });
  }

  void close(Pointer<Void> handle) => _functions.close(handle);

  void put(Pointer<Void> handle, String collection, int id, Uint8List bytes) {
    _checkId(id);
    final status = _withNativeUtf8Bytes(collection, (
      collectionPointer,
      collectionLength,
    ) {
      return _withNativeBytes(bytes, (bytesPointer, bytesLength) {
        return _functions.put(
          handle,
          collectionPointer,
          collectionLength,
          id,
          bytesPointer,
          bytesLength,
        );
      });
    });
    _checkStatus(status, 'put');
  }

  int allocateId(Pointer<Void> handle, String collection) {
    final outId = calloc<Uint64>();
    try {
      final status = _withNativeUtf8Bytes(collection, (
        collectionPointer,
        collectionLength,
      ) {
        return _functions.allocateId(
          handle,
          collectionPointer,
          collectionLength,
          outId,
        );
      });
      _checkStatus(status, 'allocate id');
      return outId.value;
    } finally {
      calloc.free(outId);
    }
  }

  void registerSchemas(Pointer<Void> handle, Uint8List schemas) {
    final status = _withNativeBytes(schemas, (schemasPointer, schemasLength) {
      return _functions.registerSchemas(handle, schemasPointer, schemasLength);
    });
    _checkStatus(status, 'register schemas');
  }

  void putIndexed(
    Pointer<Void> handle,
    String collection,
    int id,
    Uint8List bytes,
    Uint8List indexes,
  ) {
    _checkId(id);
    final status = _withNativeUtf8Bytes(collection, (
      collectionPointer,
      collectionLength,
    ) {
      return _withNativeBytes(bytes, (bytesPointer, bytesLength) {
        return _withNativeBytes(indexes, (indexesPointer, indexesLength) {
          return _functions.putIndexed(
            handle,
            collectionPointer,
            collectionLength,
            id,
            bytesPointer,
            bytesLength,
            indexesPointer,
            indexesLength,
          );
        });
      });
    });
    _checkStatus(status, 'put indexed');
  }

  void putManyIndexed(
    Pointer<Void> handle,
    String collection,
    Uint8List documents,
  ) {
    final status = _withNativeUtf8Bytes(collection, (
      collectionPointer,
      collectionLength,
    ) {
      return _withNativeBytes(documents, (documentsPointer, documentsLength) {
        return _functions.putManyIndexed(
          handle,
          collectionPointer,
          collectionLength,
          documentsPointer,
          documentsLength,
        );
      });
    });
    _checkStatus(status, 'put many indexed');
  }

  Uint8List? get(Pointer<Void> handle, String collection, int id) {
    _checkId(id);
    return _withNativeUtf8Bytes(collection, (collectionPointer, collectionLen) {
      final outPointer = calloc<Pointer<Uint8>>();
      final outLength = calloc<Size>();
      try {
        final status = _functions.get(
          handle,
          collectionPointer,
          collectionLen,
          id,
          outPointer,
          outLength,
        );

        if (status == 1) {
          return null;
        }
        _checkStatus(status, 'get');

        final pointer = outPointer.value;
        final length = outLength.value;
        final bytes = Uint8List.fromList(pointer.asTypedList(length));
        _functions.freeBuffer(pointer, length);
        return bytes;
      } finally {
        calloc
          ..free(outPointer)
          ..free(outLength);
      }
    });
  }

  List<int> documentIds(Pointer<Void> handle, String collection) {
    return _queryIds(
      (outPointer, outLength) {
        return _withNativeUtf8Bytes(collection, (
          collectionPointer,
          collectionLength,
        ) {
          return _functions.documentIds(
            handle,
            collectionPointer,
            collectionLength,
            outPointer,
            outLength,
          );
        });
      },
      _functions.freeBuffer,
      'document ids',
    );
  }

  void delete(Pointer<Void> handle, String collection, int id) {
    _checkId(id);
    final status = _withNativeUtf8Bytes(collection, (
      collectionPointer,
      collectionLength,
    ) {
      return _functions.delete(handle, collectionPointer, collectionLength, id);
    });
    _checkStatus(status, 'delete');
  }

  void deleteMany(Pointer<Void> handle, String collection, Uint8List ids) {
    final status = _withNativeUtf8Bytes(collection, (
      collectionPointer,
      collectionLength,
    ) {
      return _withNativeBytes(ids, (idsPointer, idsLength) {
        return _functions.deleteMany(
          handle,
          collectionPointer,
          collectionLength,
          idsPointer,
          idsLength,
        );
      });
    });
    _checkStatus(status, 'delete many');
  }

  int collectionRevision(Pointer<Void> handle, String collection) {
    final outRevision = calloc<Uint64>();
    try {
      final status = _withNativeUtf8Bytes(collection, (
        collectionPointer,
        collectionLength,
      ) {
        return _functions.collectionRevision(
          handle,
          collectionPointer,
          collectionLength,
          outRevision,
        );
      });
      _checkStatus(status, 'collection revision');
      return outRevision.value;
    } finally {
      calloc.free(outRevision);
    }
  }

  int? schemaVersion(Pointer<Void> handle, String collection) {
    final outVersion = calloc<Uint64>();
    try {
      final status = _withNativeUtf8Bytes(collection, (
        collectionPointer,
        collectionLength,
      ) {
        return _functions.schemaVersion(
          handle,
          collectionPointer,
          collectionLength,
          outVersion,
        );
      });
      if (status == 1) {
        return null;
      }
      _checkStatus(status, 'schema version');
      return outVersion.value;
    } finally {
      calloc.free(outVersion);
    }
  }

  List<int> queryIndexEqual(
    Pointer<Void> handle,
    String collection,
    String index,
    Uint8List value,
  ) {
    return _queryIds(
      (outPointer, outLength) {
        return _withNativeUtf8Bytes(collection, (
          collectionPointer,
          collectionLength,
        ) {
          return _withNativeUtf8Bytes(index, (indexPointer, indexLength) {
            return _withNativeBytes(value, (valuePointer, valueLength) {
              return _functions.queryIndexEqual(
                handle,
                collectionPointer,
                collectionLength,
                indexPointer,
                indexLength,
                valuePointer,
                valueLength,
                outPointer,
                outLength,
              );
            });
          });
        });
      },
      _functions.freeBuffer,
      'query index equal',
    );
  }

  List<int> queryIndexRange(
    Pointer<Void> handle,
    String collection,
    String index,
    Uint8List? lower,
    Uint8List? upper,
  ) {
    return _queryIds(
      (outPointer, outLength) {
        return _withNativeUtf8Bytes(collection, (
          collectionPointer,
          collectionLength,
        ) {
          return _withNativeUtf8Bytes(index, (indexPointer, indexLength) {
            return _withNullableNativeBytes(lower, (lowerPointer, lowerLength) {
              return _withNullableNativeBytes(upper, (
                upperPointer,
                upperLength,
              ) {
                return _functions.queryIndexRange(
                  handle,
                  collectionPointer,
                  collectionLength,
                  indexPointer,
                  indexLength,
                  lowerPointer,
                  lowerLength,
                  upperPointer,
                  upperLength,
                  outPointer,
                  outLength,
                );
              });
            });
          });
        });
      },
      _functions.freeBuffer,
      'query index range',
    );
  }
}

abstract interface class _CindelNativeFunctions {
  factory _CindelNativeFunctions.resolve() {
    final library = _openBundledLibrary();
    if (library != null) {
      return _DynamicCindelNativeFunctions(library);
    }
    return const _NativeAssetCindelNativeFunctions();
  }

  int Function() get abiVersion;

  Pointer<Void> Function(Pointer<Uint8>, int) get open;

  void Function(Pointer<Void>) get close;

  int Function(Pointer<Void>, Pointer<Uint8>, int, int, Pointer<Uint8>, int)
  get put;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  get allocateId;

  int Function(Pointer<Void>, Pointer<Uint8>, int) get registerSchemas;

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
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get documentIds;

  int Function(Pointer<Void>, Pointer<Uint8>, int, int) get delete;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  get deleteMany;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  get collectionRevision;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  get schemaVersion;

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

  void Function(Pointer<Uint8>, int) get freeBuffer;
}

final class _DynamicCindelNativeFunctions implements _CindelNativeFunctions {
  _DynamicCindelNativeFunctions(DynamicLibrary library)
    : abiVersion = library.lookupFunction<Uint32 Function(), int Function()>(
        'cindel_abi_version',
        isLeaf: true,
      ),
      open = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Uint8>, Size),
            Pointer<Void> Function(Pointer<Uint8>, int)
          >('cindel_open'),
      close = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('cindel_close', isLeaf: true),
      put = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Uint64,
              Pointer<Uint8>,
              Size,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              int,
              Pointer<Uint8>,
              int,
            )
          >('cindel_put'),
      allocateId = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Pointer<Uint64>,
            ),
            int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
          >('cindel_allocate_id'),
      registerSchemas = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Uint8>, Size),
            int Function(Pointer<Void>, Pointer<Uint8>, int)
          >('cindel_register_schemas'),
      putIndexed = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Uint64,
              Pointer<Uint8>,
              Size,
              Pointer<Uint8>,
              Size,
            ),
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
          >('cindel_put_indexed'),
      putManyIndexed = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Pointer<Uint8>,
              Size,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              int,
            )
          >('cindel_put_many_indexed'),
      get = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Uint64,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              int,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            )
          >('cindel_get'),
      documentIds = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            )
          >('cindel_document_ids'),
      delete = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Uint64),
            int Function(Pointer<Void>, Pointer<Uint8>, int, int)
          >('cindel_delete'),
      deleteMany = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Pointer<Uint8>,
              Size,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              int,
            )
          >('cindel_delete_many'),
      collectionRevision = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Pointer<Uint64>,
            ),
            int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
          >('cindel_collection_revision'),
      schemaVersion = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Pointer<Uint64>,
            ),
            int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
          >('cindel_schema_version'),
      queryIndexEqual = library
          .lookupFunction<
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
            ),
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
          >('cindel_query_index_equal'),
      queryIndexRange = library
          .lookupFunction<
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
            ),
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
          >('cindel_query_index_range'),
      freeBuffer = library
          .lookupFunction<
            Void Function(Pointer<Uint8>, Size),
            void Function(Pointer<Uint8>, int)
          >('cindel_free_buffer');

  @override
  final int Function() abiVersion;

  @override
  final Pointer<Void> Function(Pointer<Uint8>, int) open;

  @override
  final void Function(Pointer<Void>) close;

  @override
  final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    int,
    Pointer<Uint8>,
    int,
  )
  put;

  @override
  final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  allocateId;

  @override
  final int Function(Pointer<Void>, Pointer<Uint8>, int) registerSchemas;

  @override
  final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
  )
  putIndexed;

  @override
  final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  putManyIndexed;

  @override
  final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get;

  @override
  final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  documentIds;

  @override
  final int Function(Pointer<Void>, Pointer<Uint8>, int, int) delete;

  @override
  final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  deleteMany;

  @override
  final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  collectionRevision;

  @override
  final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  schemaVersion;

  @override
  final int Function(
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
  queryIndexEqual;

  @override
  final int Function(
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
  queryIndexRange;

  @override
  final void Function(Pointer<Uint8>, int) freeBuffer;
}

final class _NativeAssetCindelNativeFunctions
    implements _CindelNativeFunctions {
  const _NativeAssetCindelNativeFunctions();

  @override
  int Function() get abiVersion => _cindelAbiVersion;

  @override
  Pointer<Void> Function(Pointer<Uint8>, int) get open => _cindelOpen;

  @override
  void Function(Pointer<Void>) get close => _cindelClose;

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
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  get documentIds => _cindelDocumentIds;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, int) get delete =>
      _cindelDelete;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  get deleteMany => _cindelDeleteMany;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  get collectionRevision => _cindelCollectionRevision;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  get schemaVersion => _cindelSchemaVersion;

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
  void Function(Pointer<Uint8>, int) get freeBuffer => _cindelFreeBuffer;
}

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

String _joinPath(String base, String relativePath) {
  final separator = Platform.pathSeparator;
  final normalizedRelativePath = relativePath.replaceAll('/', separator);
  return '$base$separator$normalizedRelativePath';
}

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

@Native<Void Function(Pointer<Void>)>(
  symbol: 'cindel_close',
  assetId: _assetId,
  isLeaf: true,
)
external void _cindelClose(Pointer<Void> handle);

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

@Native<Void Function(Pointer<Uint8>, Size)>(
  symbol: 'cindel_free_buffer',
  assetId: _assetId,
)
external void _cindelFreeBuffer(Pointer<Uint8> pointer, int length);

T _withNativeUtf8Bytes<T>(
  String value,
  T Function(Pointer<Uint8> pointer, int length) action,
) {
  return _withNativeBytes(Uint8List.fromList(utf8.encode(value)), action);
}

T _withNativeBytes<T>(
  Uint8List bytes,
  T Function(Pointer<Uint8> pointer, int length) action,
) {
  final pointer = calloc<Uint8>(bytes.length);
  try {
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return action(pointer, bytes.length);
  } finally {
    calloc.free(pointer);
  }
}

T _withNullableNativeBytes<T>(
  Uint8List? bytes,
  T Function(Pointer<Uint8> pointer, int length) action,
) {
  if (bytes == null) {
    return action(nullptr, 0);
  }
  return _withNativeBytes(bytes, action);
}

List<int> _queryIds(
  int Function(Pointer<Pointer<Uint8>> outPointer, Pointer<Size> outLength)
  action,
  void Function(Pointer<Uint8> pointer, int length) freeBuffer,
  String operation,
) {
  final outPointer = calloc<Pointer<Uint8>>();
  final outLength = calloc<Size>();
  try {
    final status = action(outPointer, outLength);
    _checkStatus(status, operation);

    final pointer = outPointer.value;
    final length = outLength.value;
    final bytes = Uint8List.fromList(pointer.asTypedList(length));
    freeBuffer(pointer, length);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List) {
      throw StateError('Native Cindel returned invalid index query ids.');
    }
    return decoded.cast<int>();
  } finally {
    calloc
      ..free(outPointer)
      ..free(outLength);
  }
}

void _checkId(int id) {
  if (id < 0) {
    throw ArgumentError.value(id, 'id', 'Must be greater than or equal to 0.');
  }
}

void _checkStatus(int status, String operation) {
  if (status != 0) {
    throw StateError('Native Cindel $operation failed.');
  }
}
