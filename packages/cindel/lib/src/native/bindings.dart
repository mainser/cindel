import 'dart:convert';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../binary_document.dart';
import '../schema.dart';
import 'wire.dart';

part 'document_reader.dart';
part 'document_writer.dart';
part 'document_codecs.dart';
part 'functions.dart';
part 'dynamic_functions.dart';
part 'native_asset_functions.dart';
part 'binding_utils.dart';

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
    bool collectNativeValues,
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
        collectNativeValues ? 1 : 0,
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
    bool collectNativeValues,
  ) {
    final writer = _withNativeBytes(fieldTypes, (
      fieldTypesPointer,
      fieldTypesLength,
    ) {
      return _functions.nativeBatchWriterNew(
        fieldTypesPointer,
        fieldTypesLength,
        objects.length,
        collectNativeValues ? 1 : 0,
      );
    });
    if (writer == nullptr) {
      throw StateError('Native Cindel batch writer allocation failed.');
    }

    var finished = false;
    try {
      final nativeWriter = _CindelNativeDocumentWriter(_functions, writer);
      try {
        for (final object in objects) {
          final id = getId(object);
          _checkId(id);
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
          final reader = _CindelNativeDocumentReader(
            _functions,
            readerPointer,
            useCurrentDocument: true,
          );
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
          final isStreaming = _functions.nativeDocumentReaderIsStreaming(
            readerPointer,
          );
          final reader = _CindelNativeDocumentReader(
            _functions,
            readerPointer,
            useCurrentDocument: isStreaming,
          );
          try {
            if (isStreaming) {
              final values = <T>[];
              while (_functions.nativeDocumentReaderNext(readerPointer)) {
                values.add(readDocument(reader, 0));
              }
              return values;
            }
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

  void deleteManyNativeDocuments(
    Pointer<Void> handle,
    String collection,
    Uint8List ids,
  ) {
    final status = _withNativeUtf8Bytes(collection, (
      collectionPointer,
      collectionLength,
    ) {
      return _withNativeBytes(ids, (idsPointer, idsLength) {
        return _functions.deleteManyNativeDocuments(
          handle,
          collectionPointer,
          collectionLength,
          idsPointer,
          idsLength,
        );
      });
    });
    _checkStatus(status, 'delete many native documents');
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
    bool collectChanges,
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
              collectChanges,
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
