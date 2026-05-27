import 'dart:convert';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../schema.dart';
import 'wire.dart';

const _assetId = 'package:cindel/src/native/bindings.dart';

final class CindelNativeBindings {
  CindelNativeBindings() : _functions = _resolvedFunctions;

  static final _resolvedFunctions = _CindelNativeFunctions.resolve();
  final _CindelNativeFunctions _functions;

  int get abiVersion => _functions.abiVersion();

  Pointer<Void> open(String directory, {int backend = 1}) {
    return _withNativeUtf8Bytes(directory, (directoryPointer, directoryLength) {
      try {
        return _functions.openWithBackend(
          directoryPointer,
          directoryLength,
          backend,
        );
      } on ArgumentError {
        if (backend == 0) {
          return _functions.open(directoryPointer, directoryLength);
        }
        return nullptr;
      } on OSError {
        if (backend == 0) {
          return _functions.open(directoryPointer, directoryLength);
        }
        return nullptr;
      }
    });
  }

  Pointer<Void> openWithSchemas(
    String directory,
    Uint8List schemas, {
    int backend = 1,
  }) {
    return _withNativeUtf8Bytes(directory, (directoryPointer, directoryLength) {
      return _withNativeBytes(schemas, (schemasPointer, schemasLength) {
        try {
          return _functions.openWithBackendAndSchemas(
            directoryPointer,
            directoryLength,
            backend,
            schemasPointer,
            schemasLength,
          );
        } on ArgumentError {
          return nullptr;
        } on OSError {
          return nullptr;
        }
      });
    });
  }

  void close(Pointer<Void> handle) => _functions.close(handle);

  void beginReadTransaction(Pointer<Void> handle) {
    final status = _functions.beginReadTransaction(handle);
    _checkStatus(status, 'begin read transaction');
  }

  void beginWriteTransaction(Pointer<Void> handle) {
    final status = _functions.beginWriteTransaction(handle);
    _checkStatus(status, 'begin write transaction');
  }

  void commitTransaction(Pointer<Void> handle) {
    final status = _functions.commitTransaction(handle);
    _checkStatus(status, 'commit transaction');
  }

  void rollbackTransaction(Pointer<Void> handle) {
    final status = _functions.rollbackTransaction(handle);
    _checkStatus(status, 'rollback transaction');
  }

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

  void putManyStored(
    Pointer<Void> handle,
    String collection,
    Uint8List documents,
  ) {
    final status = _withNativeUtf8Bytes(collection, (
      collectionPointer,
      collectionLength,
    ) {
      return _withNativeBytes(documents, (documentsPointer, documentsLength) {
        return _functions.putManyStored(
          handle,
          collectionPointer,
          collectionLength,
          documentsPointer,
          documentsLength,
        );
      });
    });
    _checkStatus(status, 'put many stored');
  }

  void putManyNativeDocuments<T>(
    Pointer<Void> handle,
    String collection,
    Uint8List fieldTypes,
    List<int> ids,
    List<T> objects,
    CindelWriteNativeDocument<T> writeDocument,
    bool trackChanges,
  ) {
    if (ids.length != objects.length) {
      throw ArgumentError.value(
        ids.length,
        'ids',
        'Must match the object count.',
      );
    }

    final writer = _withNativeBytes(fieldTypes, (
      fieldTypesPointer,
      fieldTypesLength,
    ) {
      return _functions.nativeBatchWriterNew(
        fieldTypesPointer,
        fieldTypesLength,
        objects.length,
      );
    });
    if (writer == nullptr) {
      throw StateError('Native Cindel batch writer allocation failed.');
    }

    var finished = false;
    try {
      final nativeWriter = _CindelNativeDocumentWriter(_functions, writer);
      try {
        for (var i = 0; i < objects.length; i += 1) {
          writeDocument(nativeWriter, objects[i]);
          _functions.nativeBatchWriterSaveDocument(writer, ids[i]);
        }
      } finally {
        nativeWriter.release();
      }
      final status = _withNativeUtf8Bytes(collection, (
        collectionPointer,
        collectionLength,
      ) {
        return _functions.nativeBatchWriterFinishWithOptions(
          handle,
          collectionPointer,
          collectionLength,
          writer,
          trackChanges ? 1 : 0,
        );
      });
      finished = true;
      _checkStatus(status, 'put many native documents');
    } finally {
      if (!finished) {
        _functions.nativeBatchWriterAbort(writer);
      }
    }
  }

  void putManyNativeObjects<T>(
    Pointer<Void> handle,
    String collection,
    Uint8List fieldTypes,
    List<T> objects,
    CindelGetId<T> getId,
    CindelWriteNativeDocument<T> writeDocument,
    bool trackChanges,
  ) {
    final writer = _withNativeBytes(fieldTypes, (
      fieldTypesPointer,
      fieldTypesLength,
    ) {
      return _functions.nativeBatchWriterNew(
        fieldTypesPointer,
        fieldTypesLength,
        objects.length,
      );
    });
    if (writer == nullptr) {
      throw StateError('Native Cindel batch writer allocation failed.');
    }

    var finished = false;
    try {
      final nativeWriter = _CindelNativeDocumentWriter(_functions, writer);
      final seenIds = <int>{};
      try {
        for (final object in objects) {
          final id = getId(object);
          _checkId(id);
          if (!seenIds.add(id)) {
            throw ArgumentError.value(
              id,
              'objects',
              'Bulk writes cannot contain duplicate ids.',
            );
          }
          writeDocument(nativeWriter, object);
          _functions.nativeBatchWriterSaveDocument(writer, id);
        }
      } finally {
        nativeWriter.release();
      }
      final status = _withNativeUtf8Bytes(collection, (
        collectionPointer,
        collectionLength,
      ) {
        return _functions.nativeBatchWriterFinishWithOptions(
          handle,
          collectionPointer,
          collectionLength,
          writer,
          trackChanges ? 1 : 0,
        );
      });
      finished = true;
      _checkStatus(status, 'put many native objects');
    } finally {
      if (!finished) {
        _functions.nativeBatchWriterAbort(writer);
      }
    }
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

  Uint8List? getStored(Pointer<Void> handle, String collection, int id) {
    _checkId(id);
    return _withNativeUtf8Bytes(collection, (collectionPointer, collectionLen) {
      final outPointer = calloc<Pointer<Uint8>>();
      final outLength = calloc<Size>();
      try {
        final status = _functions.getStored(
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
        _checkStatus(status, 'get stored');

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

  Uint8List getMany(Pointer<Void> handle, String collection, Uint8List ids) {
    return _withNativeUtf8Bytes(collection, (collectionPointer, collectionLen) {
      return _withNativeBytes(ids, (idsPointer, idsLength) {
        return _queryBytes(
          (outPointer, outLength) {
            return _functions.getMany(
              handle,
              collectionPointer,
              collectionLen,
              idsPointer,
              idsLength,
              outPointer,
              outLength,
            );
          },
          _functions.freeBuffer,
          'get many',
        );
      });
    });
  }

  Uint8List getManyStored(
    Pointer<Void> handle,
    String collection,
    Uint8List ids,
  ) {
    return _withNativeUtf8Bytes(collection, (collectionPointer, collectionLen) {
      return _withNativeBytes(ids, (idsPointer, idsLength) {
        return _queryBytes(
          (outPointer, outLength) {
            return _functions.getManyStored(
              handle,
              collectionPointer,
              collectionLen,
              idsPointer,
              idsLength,
              outPointer,
              outLength,
            );
          },
          _functions.freeBuffer,
          'get many stored',
        );
      });
    });
  }

  List<T?> getManyNativeDocuments<T>(
    Pointer<Void> handle,
    String collection,
    Uint8List ids,
    Uint8List fieldTypes,
    CindelReadNativeDocument<T> readDocument,
  ) {
    return _withNativeUtf8Bytes(collection, (collectionPointer, collectionLen) {
      return _withNativeBytes(ids, (idsPointer, idsLength) {
        return _withNativeBytes(fieldTypes, (fieldTypesPointer, fieldTypesLen) {
          final readerPointer = _functions.nativeDocumentReaderNew(
            handle,
            collectionPointer,
            collectionLen,
            idsPointer,
            idsLength,
            fieldTypesPointer,
            fieldTypesLen,
          );
          if (readerPointer == nullptr) {
            throw StateError(
              'Native Cindel document reader allocation failed.',
            );
          }
          final reader = _CindelNativeDocumentReader(_functions, readerPointer);
          try {
            final length = _functions.nativeDocumentReaderLen(readerPointer);
            return <T?>[
              for (var i = 0; i < length; i += 1)
                if (reader.isPresent(i)) readDocument(reader, i) else null,
            ];
          } finally {
            reader.release();
          }
        });
      });
    });
  }

  List<T> queryPlanNativeDocuments<T>(
    Pointer<Void> handle,
    String collection,
    Uint8List plan,
    Uint8List fieldTypes,
    CindelReadNativeDocument<T> readDocument,
  ) {
    return _withNativeUtf8Bytes(collection, (collectionPointer, collectionLen) {
      return _withNativeBytes(plan, (planPointer, planLength) {
        return _withNativeBytes(fieldTypes, (fieldTypesPointer, fieldTypesLen) {
          final readerPointer = _functions.nativeDocumentReaderNewFromQueryPlan(
            handle,
            collectionPointer,
            collectionLen,
            planPointer,
            planLength,
            fieldTypesPointer,
            fieldTypesLen,
          );
          if (readerPointer == nullptr) {
            throw StateError(
              'Native Cindel query document reader allocation failed.',
            );
          }
          final reader = _CindelNativeDocumentReader(_functions, readerPointer);
          try {
            final length = _functions.nativeDocumentReaderLen(readerPointer);
            return List<T>.generate(
              length,
              (index) => readDocument(reader, index),
              growable: false,
            );
          } finally {
            reader.release();
          }
        });
      });
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

  Uint8List takeChanges(Pointer<Void> handle) {
    return _queryBytes(
      (outPointer, outLength) {
        return _functions.takeChanges(handle, outPointer, outLength);
      },
      _functions.freeBuffer,
      'take changes',
    );
  }

  void discardChanges(Pointer<Void> handle) {
    _checkStatus(_functions.discardChanges(handle), 'discard changes');
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

  List<int> queryFilter(
    Pointer<Void> handle,
    String collection,
    Uint8List ids,
    Uint8List filter,
  ) {
    return _queryIds(
      (outPointer, outLength) {
        return _withNativeUtf8Bytes(collection, (
          collectionPointer,
          collectionLength,
        ) {
          return _withNativeBytes(ids, (idsPointer, idsLength) {
            return _withNativeBytes(filter, (filterPointer, filterLength) {
              return _functions.queryFilter(
                handle,
                collectionPointer,
                collectionLength,
                idsPointer,
                idsLength,
                filterPointer,
                filterLength,
                outPointer,
                outLength,
              );
            });
          });
        });
      },
      _functions.freeBuffer,
      'query filter',
    );
  }

  Uint8List queryProject(
    Pointer<Void> handle,
    String collection,
    Uint8List ids,
    String field,
  ) {
    return _withNativeUtf8Bytes(collection, (
      collectionPointer,
      collectionLength,
    ) {
      return _withNativeBytes(ids, (idsPointer, idsLength) {
        return _withNativeUtf8Bytes(field, (fieldPointer, fieldLength) {
          return _queryBytes(
            (outPointer, outLength) {
              return _functions.queryProject(
                handle,
                collectionPointer,
                collectionLength,
                idsPointer,
                idsLength,
                fieldPointer,
                fieldLength,
                outPointer,
                outLength,
              );
            },
            _functions.freeBuffer,
            'query project',
          );
        });
      });
    });
  }

  Uint8List queryAggregate(
    Pointer<Void> handle,
    String collection,
    Uint8List ids,
    String field,
    String operation,
  ) {
    return _withNativeUtf8Bytes(collection, (
      collectionPointer,
      collectionLength,
    ) {
      return _withNativeBytes(ids, (idsPointer, idsLength) {
        return _withNativeUtf8Bytes(field, (fieldPointer, fieldLength) {
          return _withNativeUtf8Bytes(operation, (
            operationPointer,
            operationLength,
          ) {
            return _queryBytes(
              (outPointer, outLength) {
                return _functions.queryAggregate(
                  handle,
                  collectionPointer,
                  collectionLength,
                  idsPointer,
                  idsLength,
                  fieldPointer,
                  fieldLength,
                  operationPointer,
                  operationLength,
                  outPointer,
                  outLength,
                );
              },
              _functions.freeBuffer,
              'query aggregate',
            );
          });
        });
      });
    });
  }

  List<int> queryPlanIds(
    Pointer<Void> handle,
    String collection,
    Uint8List plan,
  ) {
    return _queryIds(
      (outPointer, outLength) {
        return _withNativeUtf8Bytes(collection, (
          collectionPointer,
          collectionLength,
        ) {
          return _withNativeBytes(plan, (planPointer, planLength) {
            return _functions.queryPlanIds(
              handle,
              collectionPointer,
              collectionLength,
              planPointer,
              planLength,
              outPointer,
              outLength,
            );
          });
        });
      },
      _functions.freeBuffer,
      'query plan ids',
    );
  }

  Uint8List queryPlanDocuments(
    Pointer<Void> handle,
    String collection,
    Uint8List plan,
  ) {
    return _queryPlanBytes(
      handle,
      collection,
      plan,
      (args) {
        return _functions.queryPlanDocuments(
          args.handle,
          args.collectionPointer,
          args.collectionLength,
          args.planPointer,
          args.planLength,
          args.outPointer,
          args.outLength,
        );
      },
      _functions.freeBuffer,
      'query plan documents',
    );
  }

  Uint8List queryPlanCount(
    Pointer<Void> handle,
    String collection,
    Uint8List plan,
  ) {
    return _queryPlanBytes(
      handle,
      collection,
      plan,
      (args) {
        return _functions.queryPlanCount(
          args.handle,
          args.collectionPointer,
          args.collectionLength,
          args.planPointer,
          args.planLength,
          args.outPointer,
          args.outLength,
        );
      },
      _functions.freeBuffer,
      'query plan count',
    );
  }

  Uint8List queryPlanProject(
    Pointer<Void> handle,
    String collection,
    Uint8List plan,
    String field,
  ) {
    return _withNativeUtf8Bytes(collection, (
      collectionPointer,
      collectionLength,
    ) {
      return _withNativeBytes(plan, (planPointer, planLength) {
        return _withNativeUtf8Bytes(field, (fieldPointer, fieldLength) {
          return _queryBytes(
            (outPointer, outLength) {
              return _functions.queryPlanProject(
                handle,
                collectionPointer,
                collectionLength,
                planPointer,
                planLength,
                fieldPointer,
                fieldLength,
                outPointer,
                outLength,
              );
            },
            _functions.freeBuffer,
            'query plan project',
          );
        });
      });
    });
  }

  Uint8List queryPlanAggregate(
    Pointer<Void> handle,
    String collection,
    Uint8List plan,
    String field,
    String operation,
  ) {
    return _withNativeUtf8Bytes(collection, (
      collectionPointer,
      collectionLength,
    ) {
      return _withNativeBytes(plan, (planPointer, planLength) {
        return _withNativeUtf8Bytes(field, (fieldPointer, fieldLength) {
          return _withNativeUtf8Bytes(operation, (
            operationPointer,
            operationLength,
          ) {
            return _queryBytes(
              (outPointer, outLength) {
                return _functions.queryPlanAggregate(
                  handle,
                  collectionPointer,
                  collectionLength,
                  planPointer,
                  planLength,
                  fieldPointer,
                  fieldLength,
                  operationPointer,
                  operationLength,
                  outPointer,
                  outLength,
                );
              },
              _functions.freeBuffer,
              'query plan aggregate',
            );
          });
        });
      });
    });
  }

  List<int> queryPlanDelete(
    Pointer<Void> handle,
    String collection,
    Uint8List plan,
  ) {
    return _queryIds(
      (outPointer, outLength) {
        return _withNativeUtf8Bytes(collection, (
          collectionPointer,
          collectionLength,
        ) {
          return _withNativeBytes(plan, (planPointer, planLength) {
            return _functions.queryPlanDelete(
              handle,
              collectionPointer,
              collectionLength,
              planPointer,
              planLength,
              outPointer,
              outLength,
            );
          });
        });
      },
      _functions.freeBuffer,
      'query plan delete',
    );
  }

  int queryPlanUpdate(
    Pointer<Void> handle,
    String collection,
    Uint8List plan,
    Uint8List updates,
  ) {
    final outCount = calloc<Uint64>();
    try {
      final status = _withNativeUtf8Bytes(collection, (
        collectionPointer,
        collectionLength,
      ) {
        return _withNativeBytes(plan, (planPointer, planLength) {
          return _withNativeBytes(updates, (updatesPointer, updatesLength) {
            return _functions.queryPlanUpdate(
              handle,
              collectionPointer,
              collectionLength,
              planPointer,
              planLength,
              updatesPointer,
              updatesLength,
              outCount,
            );
          });
        });
      });
      _checkStatus(status, 'query plan update');
      return outCount.value;
    } finally {
      calloc.free(outCount);
    }
  }
}

final class _CindelNativeDocumentWriter implements CindelNativeDocumentWriter {
  _CindelNativeDocumentWriter(this._functions, this._writer)
    : _stringBytes = _ReusableNativeBytes(256),
      _largeStringCache = LinkedHashMap<String, Uint8List>(),
      _ownsBuffers = true;

  _CindelNativeDocumentWriter._child(
    this._functions,
    this._writer,
    this._stringBytes,
    this._largeStringCache,
  ) : _ownsBuffers = false;

  final _CindelNativeFunctions _functions;
  final Pointer<Void> _writer;
  final _ReusableNativeBytes _stringBytes;
  final LinkedHashMap<String, Uint8List> _largeStringCache;
  final bool _ownsBuffers;

  @override
  void writeNull(int fieldIndex) {
    _functions.nativeBatchWriterWriteNull(_writer, fieldIndex);
  }

  @override
  void writeBool(int fieldIndex, bool value) {
    _functions.nativeBatchWriterWriteBool(_writer, fieldIndex, value);
  }

  @override
  void writeInt(int fieldIndex, int value) {
    _functions.nativeBatchWriterWriteInt(_writer, fieldIndex, value);
  }

  @override
  void writeDouble(int fieldIndex, double value) {
    _functions.nativeBatchWriterWriteDouble(_writer, fieldIndex, value);
  }

  @override
  void writeString(int fieldIndex, String value) {
    final cachedBytes = _cachedLargeStringBytes(value);
    final write = (Pointer<Uint8> pointer, int length) {
      _functions.nativeBatchWriterWriteBytes(
        _writer,
        fieldIndex,
        pointer,
        length,
      );
    };
    if (cachedBytes == null) {
      _stringBytes.withUtf8String(value, write);
    } else {
      _stringBytes.withBytes(cachedBytes, write);
    }
  }

  @override
  CindelNativeDocumentWriter beginList(int fieldIndex, int length) {
    final writer = _functions.nativeBatchWriterBeginList(
      _writer,
      fieldIndex,
      length,
    );
    if (writer == nullptr) {
      throw StateError('Native Cindel list writer allocation failed.');
    }
    return _CindelNativeDocumentWriter._child(
      _functions,
      writer,
      _stringBytes,
      _largeStringCache,
    );
  }

  @override
  void endList(CindelNativeDocumentWriter listWriter) {
    if (listWriter is! _CindelNativeDocumentWriter) {
      throw ArgumentError.value(
        listWriter,
        'listWriter',
        'Must be a Cindel native list writer.',
      );
    }
    _functions.nativeBatchWriterEndList(_writer, listWriter._writer);
    listWriter.release();
  }

  void release() {
    if (_ownsBuffers) {
      _stringBytes.free();
    }
  }

  Uint8List? _cachedLargeStringBytes(String value) {
    if (value.length < 128) {
      return null;
    }
    final existing = _largeStringCache[value];
    if (existing != null) {
      return existing;
    }
    final bytes = Uint8List.fromList(utf8.encode(value));
    if (_largeStringCache.length >= 8) {
      _largeStringCache.remove(_largeStringCache.keys.first);
    }
    _largeStringCache[value] = bytes;
    return bytes;
  }
}

final class _ReusableNativeBytes {
  _ReusableNativeBytes(int capacity)
    : pointer = calloc<Uint8>(capacity),
      capacity = capacity;

  Pointer<Uint8> pointer;
  int capacity;

  void withUtf8String(String value, void Function(Pointer<Uint8>, int) action) {
    if (value.length > capacity) {
      calloc.free(pointer);
      capacity = value.length;
      pointer = calloc<Uint8>(capacity);
    }
    final list = pointer.asTypedList(value.length);
    for (var i = 0; i < value.length; i += 1) {
      final codeUnit = value.codeUnitAt(i);
      if (codeUnit > 0x7f) {
        withBytes(utf8.encode(value), action);
        return;
      }
      list[i] = codeUnit;
    }
    action(pointer, value.length);
  }

  void withBytes(List<int> bytes, void Function(Pointer<Uint8>, int) action) {
    if (bytes.length > capacity) {
      calloc.free(pointer);
      capacity = bytes.length;
      pointer = calloc<Uint8>(capacity);
    }
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    action(pointer, bytes.length);
  }

  void free() {
    calloc.free(pointer);
  }
}

final class _CindelNativeDocumentReader implements CindelNativeDocumentReader {
  _CindelNativeDocumentReader(this._functions, this._reader)
    : _boolValue = calloc<Bool>(),
      _intValue = calloc<Int64>(),
      _doubleValue = calloc<Double>(),
      _bytesPointer = calloc<Pointer<Uint8>>(),
      _bytesLength = calloc<Size>(),
      _stringIsAscii = calloc<Bool>(),
      _stringInternId = calloc<Uint64>();

  final _CindelNativeFunctions _functions;
  final Pointer<Void> _reader;
  final Pointer<Bool> _boolValue;
  final Pointer<Int64> _intValue;
  final Pointer<Double> _doubleValue;
  final Pointer<Pointer<Uint8>> _bytesPointer;
  final Pointer<Size> _bytesLength;
  final Pointer<Bool> _stringIsAscii;
  final Pointer<Uint64> _stringInternId;
  final Map<int, String> _internedStrings = {};
  bool _released = false;

  @override
  int get length => _functions.nativeDocumentReaderLen(_reader);

  @override
  bool isPresent(int documentIndex) {
    return _functions.nativeDocumentReaderIsPresent(_reader, documentIndex);
  }

  @override
  bool? readBool(int documentIndex, int fieldIndex) {
    if (!_functions.nativeDocumentReaderReadBool(
      _reader,
      documentIndex,
      fieldIndex,
      _boolValue,
    )) {
      return null;
    }
    return _boolValue.value;
  }

  @override
  int? readInt(int documentIndex, int fieldIndex) {
    if (!_functions.nativeDocumentReaderReadInt(
      _reader,
      documentIndex,
      fieldIndex,
      _intValue,
    )) {
      return null;
    }
    return _intValue.value;
  }

  @override
  double? readDouble(int documentIndex, int fieldIndex) {
    if (!_functions.nativeDocumentReaderReadDouble(
      _reader,
      documentIndex,
      fieldIndex,
      _doubleValue,
    )) {
      return null;
    }
    return _doubleValue.value;
  }

  @override
  String? readString(int documentIndex, int fieldIndex) {
    if (!_functions.nativeDocumentReaderReadString(
      _reader,
      documentIndex,
      fieldIndex,
      _bytesPointer,
      _bytesLength,
      _stringIsAscii,
      _stringInternId,
    )) {
      return null;
    }
    final internId = _stringInternId.value;
    if (internId != 0) {
      final cached = _internedStrings[internId];
      if (cached != null) {
        return cached;
      }
    }
    final bytes = _bytesPointer.value.asTypedList(_bytesLength.value);
    final value = _decodeNativeString(bytes, isAscii: _stringIsAscii.value);
    if (internId != 0) {
      _internedStrings[internId] = value;
    }
    return value;
  }

  @override
  CindelNativeDocumentReader? readList(int documentIndex, int fieldIndex) {
    final listReader = _functions.nativeDocumentReaderReadList(
      _reader,
      documentIndex,
      fieldIndex,
    );
    if (listReader == nullptr) {
      return null;
    }
    return _CindelNativeDocumentReader(_functions, listReader);
  }

  @override
  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _functions.nativeDocumentReaderFree(_reader);
    calloc
      ..free(_boolValue)
      ..free(_intValue)
      ..free(_doubleValue)
      ..free(_bytesPointer)
      ..free(_bytesLength)
      ..free(_stringIsAscii)
      ..free(_stringInternId);
  }
}

String _decodeNativeString(Uint8List bytes, {required bool isAscii}) {
  if (isAscii) {
    return String.fromCharCodes(bytes);
  }
  return utf8.decode(bytes);
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

  void Function(Pointer<Void>) get close;

  int Function(Pointer<Void>) get beginReadTransaction;

  int Function(Pointer<Void>) get beginWriteTransaction;

  int Function(Pointer<Void>) get commitTransaction;

  int Function(Pointer<Void>) get rollbackTransaction;

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

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  get putManyStored;

  Pointer<Void> Function(Pointer<Uint8>, int, int) get nativeBatchWriterNew;

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

  void Function(Pointer<Void>, int) get nativeBatchWriterSaveDocument;

  void Function(Pointer<Void>) get nativeBatchWriterEndDocument;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>)
  get nativeBatchWriterFinish;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>, int)
  get nativeBatchWriterFinishWithOptions;

  void Function(Pointer<Void>) get nativeBatchWriterAbort;

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

  bool Function(Pointer<Void>, int) get nativeDocumentReaderIsPresent;

  bool Function(Pointer<Void>, int, int, Pointer<Bool>)
  get nativeDocumentReaderReadBool;

  bool Function(Pointer<Void>, int, int, Pointer<Int64>)
  get nativeDocumentReaderReadInt;

  bool Function(Pointer<Void>, int, int, Pointer<Double>)
  get nativeDocumentReaderReadDouble;

  bool Function(Pointer<Void>, int, int, Pointer<Pointer<Uint8>>, Pointer<Size>)
  get nativeDocumentReaderReadBytes;

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

  Pointer<Void> Function(Pointer<Void>, int, int)
  get nativeDocumentReaderReadList;

  void Function(Pointer<Void>) get nativeDocumentReaderFree;

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

  int Function(Pointer<Void>, Pointer<Uint8>, int, int) get delete;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  get deleteMany;

  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>)
  get collectionRevision;

  int Function(Pointer<Void>, Pointer<Pointer<Uint8>>, Pointer<Size>)
  get takeChanges;

  int Function(Pointer<Void>) get discardChanges;

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
    Pointer<Uint64>,
  )
  get queryPlanUpdate;

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
      beginReadTransaction = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('cindel_begin_read_txn'),
      beginWriteTransaction = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('cindel_begin_write_txn'),
      commitTransaction = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('cindel_commit_txn'),
      rollbackTransaction = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('cindel_rollback_txn'),
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
      putManyStored = library
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
          >('cindel_put_many_stored'),
      nativeBatchWriterNew = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Uint8>, Size, Size),
            Pointer<Void> Function(Pointer<Uint8>, int, int)
          >('cindel_native_batch_writer_new'),
      nativeBatchWriterBeginDocument = library
          .lookupFunction<
            Void Function(Pointer<Void>, Uint64),
            void Function(Pointer<Void>, int)
          >('cindel_native_batch_writer_begin_document', isLeaf: true),
      nativeBatchWriterWriteNull = library
          .lookupFunction<
            Void Function(Pointer<Void>, Uint32),
            void Function(Pointer<Void>, int)
          >('cindel_native_batch_writer_write_null', isLeaf: true),
      nativeBatchWriterWriteBool = library
          .lookupFunction<
            Void Function(Pointer<Void>, Uint32, Bool),
            void Function(Pointer<Void>, int, bool)
          >('cindel_native_batch_writer_write_bool', isLeaf: true),
      nativeBatchWriterWriteInt = library
          .lookupFunction<
            Void Function(Pointer<Void>, Uint32, Int64),
            void Function(Pointer<Void>, int, int)
          >('cindel_native_batch_writer_write_int', isLeaf: true),
      nativeBatchWriterWriteDouble = library
          .lookupFunction<
            Void Function(Pointer<Void>, Uint32, Double),
            void Function(Pointer<Void>, int, double)
          >('cindel_native_batch_writer_write_double', isLeaf: true),
      nativeBatchWriterWriteBytes = library
          .lookupFunction<
            Void Function(Pointer<Void>, Uint32, Pointer<Uint8>, Size),
            void Function(Pointer<Void>, int, Pointer<Uint8>, int)
          >('cindel_native_batch_writer_write_bytes', isLeaf: true),
      nativeBatchWriterBeginList = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Uint32, Size),
            Pointer<Void> Function(Pointer<Void>, int, int)
          >('cindel_native_batch_writer_begin_list', isLeaf: true),
      nativeBatchWriterEndList = library
          .lookupFunction<
            Void Function(Pointer<Void>, Pointer<Void>),
            void Function(Pointer<Void>, Pointer<Void>)
          >('cindel_native_batch_writer_end_list', isLeaf: true),
      nativeBatchWriterSaveDocument = library
          .lookupFunction<
            Void Function(Pointer<Void>, Uint64),
            void Function(Pointer<Void>, int)
          >('cindel_native_batch_writer_save_document', isLeaf: true),
      nativeBatchWriterEndDocument = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('cindel_native_batch_writer_end_document', isLeaf: true),
      nativeBatchWriterFinish = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Void>),
            int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>)
          >('cindel_native_batch_writer_finish'),
      nativeBatchWriterFinishWithOptions = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Pointer<Void>,
              Int32,
            ),
            int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>, int)
          >('cindel_native_batch_writer_finish_with_options'),
      nativeBatchWriterAbort = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('cindel_native_batch_writer_abort'),
      nativeDocumentReaderNew = library
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Pointer<Uint8>,
              Size,
              Pointer<Uint8>,
              Size,
            ),
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              int,
            )
          >('cindel_native_document_reader_new'),
      nativeDocumentReaderNewFromQueryPlan = library
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Pointer<Uint8>,
              Size,
              Pointer<Uint8>,
              Size,
            ),
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              int,
            )
          >('cindel_native_document_reader_new_from_query_plan'),
      nativeDocumentReaderLen = library
          .lookupFunction<
            Size Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('cindel_native_document_reader_len', isLeaf: true),
      nativeDocumentReaderIsPresent = library
          .lookupFunction<
            Bool Function(Pointer<Void>, Size),
            bool Function(Pointer<Void>, int)
          >('cindel_native_document_reader_is_present', isLeaf: true),
      nativeDocumentReaderReadBool = library
          .lookupFunction<
            Bool Function(Pointer<Void>, Size, Uint32, Pointer<Bool>),
            bool Function(Pointer<Void>, int, int, Pointer<Bool>)
          >('cindel_native_document_reader_read_bool', isLeaf: true),
      nativeDocumentReaderReadInt = library
          .lookupFunction<
            Bool Function(Pointer<Void>, Size, Uint32, Pointer<Int64>),
            bool Function(Pointer<Void>, int, int, Pointer<Int64>)
          >('cindel_native_document_reader_read_int', isLeaf: true),
      nativeDocumentReaderReadDouble = library
          .lookupFunction<
            Bool Function(Pointer<Void>, Size, Uint32, Pointer<Double>),
            bool Function(Pointer<Void>, int, int, Pointer<Double>)
          >('cindel_native_document_reader_read_double', isLeaf: true),
      nativeDocumentReaderReadBytes = library
          .lookupFunction<
            Bool Function(
              Pointer<Void>,
              Size,
              Uint32,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            ),
            bool Function(
              Pointer<Void>,
              int,
              int,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            )
          >('cindel_native_document_reader_read_bytes', isLeaf: true),
      nativeDocumentReaderReadString = library
          .lookupFunction<
            Bool Function(
              Pointer<Void>,
              Size,
              Uint32,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
              Pointer<Bool>,
              Pointer<Uint64>,
            ),
            bool Function(
              Pointer<Void>,
              int,
              int,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
              Pointer<Bool>,
              Pointer<Uint64>,
            )
          >('cindel_native_document_reader_read_string', isLeaf: true),
      nativeDocumentReaderReadList = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Size, Uint32),
            Pointer<Void> Function(Pointer<Void>, int, int)
          >('cindel_native_document_reader_read_list'),
      nativeDocumentReaderFree = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('cindel_native_document_reader_free'),
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
      getStored = library
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
          >('cindel_get_stored'),
      getMany = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
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
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            )
          >('cindel_get_many'),
      getManyStored = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
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
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            )
          >('cindel_get_many_stored'),
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
      takeChanges = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            ),
            int Function(Pointer<Void>, Pointer<Pointer<Uint8>>, Pointer<Size>)
          >('cindel_take_changes'),
      discardChanges = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('cindel_discard_changes'),
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
      queryFilter = library
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
          >('cindel_query_filter'),
      queryProject = library
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
          >('cindel_query_project'),
      queryAggregate = library
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
          >('cindel_query_aggregate'),
      queryPlanIds = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
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
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            )
          >('cindel_query_plan_ids'),
      queryPlanDocuments = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
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
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            )
          >('cindel_query_plan_documents'),
      queryPlanCount = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
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
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            )
          >('cindel_query_plan_count'),
      queryPlanProject = library
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
          >('cindel_query_plan_project'),
      queryPlanAggregate = library
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
          >('cindel_query_plan_aggregate'),
      queryPlanDelete = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
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
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            )
          >('cindel_query_plan_delete'),
      queryPlanUpdate = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Pointer<Uint8>,
              Size,
              Pointer<Uint8>,
              Size,
              Pointer<Uint64>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              int,
              Pointer<Uint64>,
            )
          >('cindel_query_plan_update'),
      freeBuffer = library
          .lookupFunction<
            Void Function(Pointer<Uint8>, Size),
            void Function(Pointer<Uint8>, int)
          >('cindel_free_buffer'),
      _library = library;

  @override
  final int Function() abiVersion;

  @override
  final Pointer<Void> Function(Pointer<Uint8>, int) open;

  final DynamicLibrary _library;

  late final Pointer<Void> Function(Pointer<Uint8>, int, int) _openWithBackend =
      _library.lookupFunction<
        Pointer<Void> Function(Pointer<Uint8>, Size, Uint32),
        Pointer<Void> Function(Pointer<Uint8>, int, int)
      >('cindel_open_with_backend');

  @override
  Pointer<Void> openWithBackend(
    Pointer<Uint8> directory,
    int length,
    int backend,
  ) {
    return _openWithBackend(directory, length, backend);
  }

  late final Pointer<Void> Function(
    Pointer<Uint8>,
    int,
    int,
    Pointer<Uint8>,
    int,
  )
  _openWithBackendAndSchemas = _library
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<Uint8>,
          Size,
          Uint32,
          Pointer<Uint8>,
          Size,
        ),
        Pointer<Void> Function(Pointer<Uint8>, int, int, Pointer<Uint8>, int)
      >('cindel_open_with_backend_and_schemas');

  @override
  Pointer<Void> openWithBackendAndSchemas(
    Pointer<Uint8> directory,
    int length,
    int backend,
    Pointer<Uint8> schemas,
    int schemasLength,
  ) {
    return _openWithBackendAndSchemas(
      directory,
      length,
      backend,
      schemas,
      schemasLength,
    );
  }

  @override
  final void Function(Pointer<Void>) close;

  @override
  final int Function(Pointer<Void>) beginReadTransaction;

  @override
  final int Function(Pointer<Void>) beginWriteTransaction;

  @override
  final int Function(Pointer<Void>) commitTransaction;

  @override
  final int Function(Pointer<Void>) rollbackTransaction;

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
  final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  putManyStored;

  @override
  final Pointer<Void> Function(Pointer<Uint8>, int, int) nativeBatchWriterNew;

  @override
  final void Function(Pointer<Void>, int) nativeBatchWriterBeginDocument;

  @override
  final void Function(Pointer<Void>, int) nativeBatchWriterWriteNull;

  @override
  final void Function(Pointer<Void>, int, bool) nativeBatchWriterWriteBool;

  @override
  final void Function(Pointer<Void>, int, int) nativeBatchWriterWriteInt;

  @override
  final void Function(Pointer<Void>, int, double) nativeBatchWriterWriteDouble;

  @override
  final void Function(Pointer<Void>, int, Pointer<Uint8>, int)
  nativeBatchWriterWriteBytes;

  @override
  final Pointer<Void> Function(Pointer<Void>, int, int)
  nativeBatchWriterBeginList;

  @override
  final void Function(Pointer<Void>, Pointer<Void>) nativeBatchWriterEndList;

  @override
  final void Function(Pointer<Void>, int) nativeBatchWriterSaveDocument;

  @override
  final void Function(Pointer<Void>) nativeBatchWriterEndDocument;

  @override
  final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>)
  nativeBatchWriterFinish;

  @override
  final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>, int)
  nativeBatchWriterFinishWithOptions;

  @override
  final void Function(Pointer<Void>) nativeBatchWriterAbort;

  @override
  final Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
  )
  nativeDocumentReaderNew;

  @override
  final Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
  )
  nativeDocumentReaderNewFromQueryPlan;

  @override
  final int Function(Pointer<Void>) nativeDocumentReaderLen;

  @override
  final bool Function(Pointer<Void>, int) nativeDocumentReaderIsPresent;

  @override
  final bool Function(Pointer<Void>, int, int, Pointer<Bool>)
  nativeDocumentReaderReadBool;

  @override
  final bool Function(Pointer<Void>, int, int, Pointer<Int64>)
  nativeDocumentReaderReadInt;

  @override
  final bool Function(Pointer<Void>, int, int, Pointer<Double>)
  nativeDocumentReaderReadDouble;

  @override
  final bool Function(
    Pointer<Void>,
    int,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  nativeDocumentReaderReadBytes;

  @override
  final bool Function(
    Pointer<Void>,
    int,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
    Pointer<Bool>,
    Pointer<Uint64>,
  )
  nativeDocumentReaderReadString;

  @override
  final Pointer<Void> Function(Pointer<Void>, int, int)
  nativeDocumentReaderReadList;

  @override
  final void Function(Pointer<Void>) nativeDocumentReaderFree;

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
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  getStored;

  @override
  final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  getMany;

  @override
  final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  getManyStored;

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
  final int Function(Pointer<Void>, Pointer<Pointer<Uint8>>, Pointer<Size>)
  takeChanges;

  @override
  final int Function(Pointer<Void>) discardChanges;

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
  queryFilter;

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
  queryProject;

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
  queryAggregate;

  @override
  final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  queryPlanIds;

  @override
  final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  queryPlanDocuments;

  @override
  final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  queryPlanCount;

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
  queryPlanProject;

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
  queryPlanAggregate;

  @override
  final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  queryPlanDelete;

  @override
  final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint64>,
  )
  queryPlanUpdate;

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
  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  get putManyStored => _cindelPutManyStored;

  @override
  Pointer<Void> Function(Pointer<Uint8>, int, int) get nativeBatchWriterNew =>
      _cindelNativeBatchWriterNew;

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
  bool Function(Pointer<Void>, int) get nativeDocumentReaderIsPresent =>
      _cindelNativeDocumentReaderIsPresent;

  @override
  bool Function(Pointer<Void>, int, int, Pointer<Bool>)
  get nativeDocumentReaderReadBool => _cindelNativeDocumentReaderReadBool;

  @override
  bool Function(Pointer<Void>, int, int, Pointer<Int64>)
  get nativeDocumentReaderReadInt => _cindelNativeDocumentReaderReadInt;

  @override
  bool Function(Pointer<Void>, int, int, Pointer<Double>)
  get nativeDocumentReaderReadDouble => _cindelNativeDocumentReaderReadDouble;

  @override
  bool Function(Pointer<Void>, int, int, Pointer<Pointer<Uint8>>, Pointer<Size>)
  get nativeDocumentReaderReadBytes => _cindelNativeDocumentReaderReadBytes;

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
  Pointer<Void> Function(Pointer<Void>, int, int)
  get nativeDocumentReaderReadList => _cindelNativeDocumentReaderReadList;

  @override
  void Function(Pointer<Void>) get nativeDocumentReaderFree =>
      _cindelNativeDocumentReaderFree;

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
  int Function(Pointer<Void>, Pointer<Uint8>, int, int) get delete =>
      _cindelDelete;

  @override
  int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  get deleteMany => _cindelDeleteMany;

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
    Pointer<Uint64>,
  )
  get queryPlanUpdate => _cindelQueryPlanUpdate;

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
  Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Uint8>, Size)
>(symbol: 'cindel_put_many_stored', assetId: _assetId)
external int _cindelPutManyStored(
  Pointer<Void> handle,
  Pointer<Uint8> collection,
  int collectionLen,
  Pointer<Uint8> documents,
  int documentsLen,
);

@Native<Pointer<Void> Function(Pointer<Uint8>, Size, Size)>(
  symbol: 'cindel_native_batch_writer_new',
  assetId: _assetId,
)
external Pointer<Void> _cindelNativeBatchWriterNew(
  Pointer<Uint8> fieldTypes,
  int fieldTypesLen,
  int capacity,
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

@Native<Bool Function(Pointer<Void>, Size)>(
  symbol: 'cindel_native_document_reader_is_present',
  assetId: _assetId,
  isLeaf: true,
)
external bool _cindelNativeDocumentReaderIsPresent(
  Pointer<Void> reader,
  int documentIndex,
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

@Native<Pointer<Void> Function(Pointer<Void>, Size, Uint32)>(
  symbol: 'cindel_native_document_reader_read_list',
  assetId: _assetId,
)
external Pointer<Void> _cindelNativeDocumentReaderReadList(
  Pointer<Void> reader,
  int documentIndex,
  int fieldIndex,
);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'cindel_native_document_reader_free',
  assetId: _assetId,
)
external void _cindelNativeDocumentReaderFree(Pointer<Void> reader);

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
  Pointer<Uint64> outCount,
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
  final bytes = _queryBytes(action, freeBuffer, operation);
  try {
    return decodeIdList(bytes);
  } on FormatException {
    throw StateError('Native Cindel returned invalid binary id list.');
  } catch (_) {
    throw StateError('Native Cindel returned invalid binary id list.');
  }
}

Uint8List _queryBytes(
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
    return bytes;
  } finally {
    calloc
      ..free(outPointer)
      ..free(outLength);
  }
}

Uint8List _queryPlanBytes(
  Pointer<Void> handle,
  String collection,
  Uint8List plan,
  int Function(_QueryPlanCallArgs args) action,
  void Function(Pointer<Uint8> pointer, int length) freeBuffer,
  String operation,
) {
  return _withNativeUtf8Bytes(collection, (
    collectionPointer,
    collectionLength,
  ) {
    return _withNativeBytes(plan, (planPointer, planLength) {
      return _queryBytes(
        (outPointer, outLength) {
          return action(
            _QueryPlanCallArgs(
              handle: handle,
              collectionPointer: collectionPointer,
              collectionLength: collectionLength,
              planPointer: planPointer,
              planLength: planLength,
              outPointer: outPointer,
              outLength: outLength,
            ),
          );
        },
        freeBuffer,
        operation,
      );
    });
  });
}

final class _QueryPlanCallArgs {
  const _QueryPlanCallArgs({
    required this.handle,
    required this.collectionPointer,
    required this.collectionLength,
    required this.planPointer,
    required this.planLength,
    required this.outPointer,
    required this.outLength,
  });

  final Pointer<Void> handle;
  final Pointer<Uint8> collectionPointer;
  final int collectionLength;
  final Pointer<Uint8> planPointer;
  final int planLength;
  final Pointer<Pointer<Uint8>> outPointer;
  final Pointer<Size> outLength;
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
