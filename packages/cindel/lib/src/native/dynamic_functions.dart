part of 'bindings.dart';

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
            Pointer<Void> Function(Pointer<Uint8>, Size, Size, Int32),
            Pointer<Void> Function(Pointer<Uint8>, int, int, int)
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
      nativeDocumentReaderIsStreaming = library
          .lookupFunction<
            Bool Function(Pointer<Void>),
            bool Function(Pointer<Void>)
          >('cindel_native_document_reader_is_streaming', isLeaf: true),
      nativeDocumentReaderNext = library
          .lookupFunction<
            Bool Function(Pointer<Void>),
            bool Function(Pointer<Void>)
          >('cindel_native_document_reader_next'),
      nativeDocumentReaderIsPresent = library
          .lookupFunction<
            Bool Function(Pointer<Void>, Size),
            bool Function(Pointer<Void>, int)
          >('cindel_native_document_reader_is_present', isLeaf: true),
      nativeDocumentReaderReadId = library
          .lookupFunction<
            Bool Function(Pointer<Void>, Size, Pointer<Uint64>),
            bool Function(Pointer<Void>, int, Pointer<Uint64>)
          >('cindel_native_document_reader_read_id', isLeaf: true),
      nativeDocumentReaderReadIdValue = library
          .lookupFunction<
            Uint64 Function(Pointer<Void>, Size),
            int Function(Pointer<Void>, int)
          >('cindel_native_document_reader_read_id_value', isLeaf: true),
      nativeDocumentReaderReadCurrentIdValue = library
          .lookupFunction<
            Uint64 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >(
            'cindel_native_document_reader_read_current_id_value',
            isLeaf: true,
          ),
      nativeDocumentReaderReadBool = library
          .lookupFunction<
            Bool Function(Pointer<Void>, Size, Uint32, Pointer<Bool>),
            bool Function(Pointer<Void>, int, int, Pointer<Bool>)
          >('cindel_native_document_reader_read_bool', isLeaf: true),
      nativeDocumentReaderReadBoolValue = library
          .lookupFunction<
            Uint8 Function(Pointer<Void>, Size, Uint32),
            int Function(Pointer<Void>, int, int)
          >('cindel_native_document_reader_read_bool_value', isLeaf: true),
      nativeDocumentReaderReadCurrentBoolValue = library
          .lookupFunction<
            Uint8 Function(Pointer<Void>, Uint32),
            int Function(Pointer<Void>, int)
          >(
            'cindel_native_document_reader_read_current_bool_value',
            isLeaf: true,
          ),
      nativeDocumentReaderReadInt = library
          .lookupFunction<
            Bool Function(Pointer<Void>, Size, Uint32, Pointer<Int64>),
            bool Function(Pointer<Void>, int, int, Pointer<Int64>)
          >('cindel_native_document_reader_read_int', isLeaf: true),
      nativeDocumentReaderReadIntValue = library
          .lookupFunction<
            Int64 Function(Pointer<Void>, Size, Uint32),
            int Function(Pointer<Void>, int, int)
          >('cindel_native_document_reader_read_int_value', isLeaf: true),
      nativeDocumentReaderReadCurrentIntValue = library
          .lookupFunction<
            Int64 Function(Pointer<Void>, Uint32),
            int Function(Pointer<Void>, int)
          >(
            'cindel_native_document_reader_read_current_int_value',
            isLeaf: true,
          ),
      nativeDocumentReaderReadDouble = library
          .lookupFunction<
            Bool Function(Pointer<Void>, Size, Uint32, Pointer<Double>),
            bool Function(Pointer<Void>, int, int, Pointer<Double>)
          >('cindel_native_document_reader_read_double', isLeaf: true),
      nativeDocumentReaderReadDoubleValue = library
          .lookupFunction<
            Double Function(Pointer<Void>, Size, Uint32),
            double Function(Pointer<Void>, int, int)
          >('cindel_native_document_reader_read_double_value', isLeaf: true),
      nativeDocumentReaderReadCurrentDoubleValue = library
          .lookupFunction<
            Double Function(Pointer<Void>, Uint32),
            double Function(Pointer<Void>, int)
          >(
            'cindel_native_document_reader_read_current_double_value',
            isLeaf: true,
          ),
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
      nativeDocumentReaderReadCurrentBytes = library
          .lookupFunction<
            Bool Function(
              Pointer<Void>,
              Uint32,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            ),
            bool Function(
              Pointer<Void>,
              int,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            )
          >('cindel_native_document_reader_read_current_bytes', isLeaf: true),
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
      nativeDocumentReaderReadStringValue = library
          .lookupFunction<
            Size Function(
              Pointer<Void>,
              Size,
              Uint32,
              Pointer<Pointer<Uint8>>,
              Pointer<Bool>,
            ),
            int Function(
              Pointer<Void>,
              int,
              int,
              Pointer<Pointer<Uint8>>,
              Pointer<Bool>,
            )
          >('cindel_native_document_reader_read_string_value', isLeaf: true),
      nativeDocumentReaderReadCurrentStringValue = library
          .lookupFunction<
            Size Function(
              Pointer<Void>,
              Uint32,
              Pointer<Pointer<Uint8>>,
              Pointer<Bool>,
            ),
            int Function(
              Pointer<Void>,
              int,
              Pointer<Pointer<Uint8>>,
              Pointer<Bool>,
            )
          >(
            'cindel_native_document_reader_read_current_string_value',
            isLeaf: true,
          ),
      nativeDocumentReaderReadListBytes = library
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
          >('cindel_native_document_reader_read_list_bytes', isLeaf: true),
      nativeDocumentReaderReadCurrentListBytes = library
          .lookupFunction<
            Bool Function(
              Pointer<Void>,
              Uint32,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            ),
            bool Function(
              Pointer<Void>,
              int,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
            )
          >(
            'cindel_native_document_reader_read_current_list_bytes',
            isLeaf: true,
          ),
      nativeDocumentReaderReadList = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Size, Uint32),
            Pointer<Void> Function(Pointer<Void>, int, int)
          >('cindel_native_document_reader_read_list'),
      nativeDocumentReaderReadCurrentList = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Uint32),
            Pointer<Void> Function(Pointer<Void>, int)
          >('cindel_native_document_reader_read_current_list'),
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
      deleteManyNativeDocuments = library
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
          >('cindel_delete_many_native_documents'),
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
              Bool,
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
              bool,
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
  final Pointer<Void> Function(Pointer<Uint8>, int, int, int)
  nativeBatchWriterNew;

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
  final bool Function(Pointer<Void>) nativeDocumentReaderIsStreaming;

  @override
  final bool Function(Pointer<Void>) nativeDocumentReaderNext;

  @override
  final bool Function(Pointer<Void>, int) nativeDocumentReaderIsPresent;

  @override
  final bool Function(Pointer<Void>, int, Pointer<Uint64>)
  nativeDocumentReaderReadId;

  @override
  final int Function(Pointer<Void>, int) nativeDocumentReaderReadIdValue;

  @override
  final int Function(Pointer<Void>) nativeDocumentReaderReadCurrentIdValue;

  @override
  final bool Function(Pointer<Void>, int, int, Pointer<Bool>)
  nativeDocumentReaderReadBool;

  @override
  final int Function(Pointer<Void>, int, int) nativeDocumentReaderReadBoolValue;

  @override
  final int Function(Pointer<Void>, int)
  nativeDocumentReaderReadCurrentBoolValue;

  @override
  final bool Function(Pointer<Void>, int, int, Pointer<Int64>)
  nativeDocumentReaderReadInt;

  @override
  final int Function(Pointer<Void>, int, int) nativeDocumentReaderReadIntValue;

  @override
  final int Function(Pointer<Void>, int)
  nativeDocumentReaderReadCurrentIntValue;

  @override
  final bool Function(Pointer<Void>, int, int, Pointer<Double>)
  nativeDocumentReaderReadDouble;

  @override
  final double Function(Pointer<Void>, int, int)
  nativeDocumentReaderReadDoubleValue;

  @override
  final double Function(Pointer<Void>, int)
  nativeDocumentReaderReadCurrentDoubleValue;

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
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  nativeDocumentReaderReadCurrentBytes;

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
  final int Function(
    Pointer<Void>,
    int,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Bool>,
  )
  nativeDocumentReaderReadStringValue;

  @override
  final int Function(Pointer<Void>, int, Pointer<Pointer<Uint8>>, Pointer<Bool>)
  nativeDocumentReaderReadCurrentStringValue;

  @override
  final bool Function(
    Pointer<Void>,
    int,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  nativeDocumentReaderReadListBytes;

  @override
  final bool Function(
    Pointer<Void>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
  nativeDocumentReaderReadCurrentListBytes;

  @override
  final Pointer<Void> Function(Pointer<Void>, int, int)
  nativeDocumentReaderReadList;

  @override
  final Pointer<Void> Function(Pointer<Void>, int)
  nativeDocumentReaderReadCurrentList;

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
  final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int)
  deleteManyNativeDocuments;

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
    bool,
    Pointer<Uint64>,
  )
  queryPlanUpdate;

  @override
  final void Function(Pointer<Uint8>, int) freeBuffer;
}
