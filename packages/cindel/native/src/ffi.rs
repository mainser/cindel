use crate::document_format::{
    write_compact_string_list_records, write_list_records, write_string_value_record,
    write_value_record, BinaryValue,
};
use crate::engine::CindelEngine;
use crate::storage::{
    schema_manifest_from_wire, DocumentWrite, IndexEntry, IndexValue, NativeDocumentValue,
    NativeDocumentWrite, SqliteNativeDocumentCursor, SqliteNativeQueryCursor, StorageBackendKind,
};
#[cfg(feature = "mdbx")]
use crate::storage::{MdbxCursorDocumentReader, MdbxQueryDocumentReader};
use crate::wire::{
    decode_document_write_batch, decode_field_updates, decode_id_list, decode_index_entry_list,
    decode_index_value, decode_indexed_document_write_batch, decode_query_plan,
    encode_change_set_list, encode_id_list, encode_scalar, WireChangeSet,
    WireDocumentWrite as WireBatchDocumentWrite, WireIndexEntry as WireBatchIndexEntry,
    WireIndexValue as WireBatchIndexValue,
    WireIndexedDocumentWrite as WireBatchIndexedDocumentWrite, WireQueryPlan, WireScalar,
};
#[no_mangle]
pub extern "C" fn cindel_abi_version() -> u32 {
    29
}

#[no_mangle]
pub unsafe extern "C" fn cindel_open(
    directory_ptr: *const u8,
    directory_len: usize,
) -> *mut CindelEngine {
    let Some(directory) = read_str(directory_ptr, directory_len) else {
        return std::ptr::null_mut();
    };

    match CindelEngine::open(directory) {
        Ok(engine) => Box::into_raw(Box::new(engine)),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_open_with_backend(
    directory_ptr: *const u8,
    directory_len: usize,
    backend: u32,
) -> *mut CindelEngine {
    let Some(directory) = read_str(directory_ptr, directory_len) else {
        return std::ptr::null_mut();
    };
    let Some(backend) = decode_backend(backend) else {
        return std::ptr::null_mut();
    };

    match CindelEngine::open_with_backend(directory, backend) {
        Ok(engine) => Box::into_raw(Box::new(engine)),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_open_with_backend_and_schemas(
    directory_ptr: *const u8,
    directory_len: usize,
    backend: u32,
    schemas_ptr: *const u8,
    schemas_len: usize,
) -> *mut CindelEngine {
    let Some(directory) = read_str(directory_ptr, directory_len) else {
        return std::ptr::null_mut();
    };
    let Some(backend) = decode_backend(backend) else {
        return std::ptr::null_mut();
    };
    let Some(schemas) = read_bytes(schemas_ptr, schemas_len) else {
        return std::ptr::null_mut();
    };
    let Ok(manifest) = schema_manifest_from_wire(schemas) else {
        return std::ptr::null_mut();
    };

    match CindelEngine::open_with_backend_and_schemas(directory, backend, &manifest) {
        Ok(engine) => Box::into_raw(Box::new(engine)),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_close(handle: *mut CindelEngine) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_begin_read_txn(handle: *mut CindelEngine) -> i32 {
    let Some(engine) = handle.as_mut() else {
        return -1;
    };

    match engine.begin_read_transaction() {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_begin_write_txn(handle: *mut CindelEngine) -> i32 {
    let Some(engine) = handle.as_mut() else {
        return -1;
    };

    match engine.begin_write_transaction() {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_commit_txn(handle: *mut CindelEngine) -> i32 {
    let Some(engine) = handle.as_mut() else {
        return -1;
    };

    match engine.commit_transaction() {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_rollback_txn(handle: *mut CindelEngine) -> i32 {
    let Some(engine) = handle.as_mut() else {
        return -1;
    };

    match engine.rollback_transaction() {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_put(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    id: u64,
    bytes_ptr: *const u8,
    bytes_len: usize,
) -> i32 {
    let Some(engine) = handle.as_mut() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Some(bytes) = read_bytes(bytes_ptr, bytes_len) else {
        return -1;
    };

    match engine.put(collection, id, bytes) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_allocate_id(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    out_id: *mut u64,
) -> i32 {
    if out_id.is_null() {
        return -1;
    }

    *out_id = 0;

    let Some(engine) = handle.as_mut() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };

    match engine.allocate_id(collection) {
        Ok(id) => {
            *out_id = id;
            0
        }
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_register_schemas(
    handle: *mut CindelEngine,
    schemas_ptr: *const u8,
    schemas_len: usize,
) -> i32 {
    let Some(engine) = handle.as_mut() else {
        return -1;
    };
    let Some(schemas) = read_bytes(schemas_ptr, schemas_len) else {
        return -1;
    };
    let Ok(manifest) = schema_manifest_from_wire(schemas) else {
        return -1;
    };

    match engine.register_schemas(&manifest) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_put_indexed(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    id: u64,
    bytes_ptr: *const u8,
    bytes_len: usize,
    indexes_ptr: *const u8,
    indexes_len: usize,
) -> i32 {
    let Some(engine) = handle.as_mut() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Some(bytes) = read_bytes(bytes_ptr, bytes_len) else {
        return -1;
    };
    let Ok(indexes) = read_index_entries(indexes_ptr, indexes_len) else {
        return -1;
    };

    match engine.put_indexed(collection, id, bytes, &indexes) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_put_many_indexed(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    documents_ptr: *const u8,
    documents_len: usize,
) -> i32 {
    let Some(engine) = handle.as_mut() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Ok(documents) = read_document_writes(documents_ptr, documents_len) else {
        return -1;
    };

    match engine.put_many_indexed(collection, &documents) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_put_many_stored(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    documents_ptr: *const u8,
    documents_len: usize,
) -> i32 {
    let Some(engine) = handle.as_mut() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Ok(documents) = read_binary_document_writes(documents_ptr, documents_len) else {
        return -1;
    };

    match engine.put_many_indexed(collection, &documents) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_batch_writer_new(
    field_types_ptr: *const u8,
    field_types_len: usize,
    capacity: usize,
    collect_native_values: i32,
) -> *mut CindelNativeBatchWriter {
    let Some(field_type_bytes) = read_bytes(field_types_ptr, field_types_len) else {
        return std::ptr::null_mut();
    };
    let Ok(writer) =
        CindelNativeBatchWriter::new(field_type_bytes, capacity, collect_native_values != 0)
    else {
        return std::ptr::null_mut();
    };
    Box::into_raw(Box::new(writer))
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_batch_writer_begin_document(
    writer: *mut CindelNativeBatchWriter,
    id: u64,
) {
    let Some(writer) = writer.as_mut() else {
        return;
    };
    writer.record(|writer| writer.begin_document(id));
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_batch_writer_write_null(
    writer: *mut CindelNativeBatchWriter,
    index: u32,
) {
    let Some(writer) = writer.as_mut() else {
        return;
    };
    writer.record(|writer| writer.write_null(index as usize));
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_batch_writer_write_bool(
    writer: *mut CindelNativeBatchWriter,
    index: u32,
    value: bool,
) {
    let Some(writer) = writer.as_mut() else {
        return;
    };
    writer.record(|writer| writer.write_bool(index as usize, value));
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_batch_writer_write_int(
    writer: *mut CindelNativeBatchWriter,
    index: u32,
    value: i64,
) {
    let Some(writer) = writer.as_mut() else {
        return;
    };
    writer.record(|writer| writer.write_int(index as usize, value));
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_batch_writer_write_double(
    writer: *mut CindelNativeBatchWriter,
    index: u32,
    value: f64,
) {
    let Some(writer) = writer.as_mut() else {
        return;
    };
    writer.record(|writer| writer.write_double(index as usize, value));
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_batch_writer_write_bytes(
    writer: *mut CindelNativeBatchWriter,
    index: u32,
    bytes_ptr: *const u8,
    bytes_len: usize,
) {
    let Some(writer) = writer.as_mut() else {
        return;
    };
    let Some(bytes) = read_bytes(bytes_ptr, bytes_len) else {
        writer.failed = true;
        return;
    };
    writer.record(|writer| writer.write_bytes(index as usize, bytes));
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_batch_writer_begin_list(
    writer: *mut CindelNativeBatchWriter,
    index: u32,
    length: usize,
) -> *mut CindelNativeBatchWriter {
    let Some(writer) = writer.as_mut() else {
        return std::ptr::null_mut();
    };
    if writer.failed {
        return std::ptr::null_mut();
    }
    match writer.begin_list(index as usize, length) {
        Ok(list_writer) => Box::into_raw(Box::new(list_writer)),
        Err(_) => {
            writer.failed = true;
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_batch_writer_end_list(
    writer: *mut CindelNativeBatchWriter,
    list_writer: *mut CindelNativeBatchWriter,
) {
    let Some(writer) = writer.as_mut() else {
        if !list_writer.is_null() {
            drop(Box::from_raw(list_writer));
        }
        return;
    };
    if list_writer.is_null() {
        writer.failed = true;
        return;
    }
    let list_writer = *Box::from_raw(list_writer);
    writer.record(|writer| writer.end_list(list_writer));
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_batch_writer_save_document(
    writer: *mut CindelNativeBatchWriter,
    id: u64,
) {
    let Some(writer) = writer.as_mut() else {
        return;
    };
    writer.record(|writer| writer.save_document(id));
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_batch_writer_end_document(
    writer: *mut CindelNativeBatchWriter,
) {
    let Some(writer) = writer.as_mut() else {
        return;
    };
    writer.record(|writer| writer.end_document());
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_batch_writer_finish(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    writer: *mut CindelNativeBatchWriter,
) -> i32 {
    if writer.is_null() {
        return -1;
    }
    let Some(engine) = handle.as_mut() else {
        drop(Box::from_raw(writer));
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        drop(Box::from_raw(writer));
        return -1;
    };
    let writer = Box::from_raw(writer);
    if writer.failed {
        return -1;
    }
    let Ok(documents) = writer.take_documents() else {
        return -1;
    };
    match engine.put_many_indexed(collection, &documents) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_batch_writer_finish_with_options(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    writer: *mut CindelNativeBatchWriter,
    track_changes: i32,
) -> i32 {
    if writer.is_null() {
        return -1;
    }
    let Some(engine) = handle.as_mut() else {
        drop(Box::from_raw(writer));
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        drop(Box::from_raw(writer));
        return -1;
    };
    let writer = Box::from_raw(writer);
    if writer.failed {
        return -1;
    }
    let Ok((documents, native_documents)) = writer.take_documents_with_optional_native_values()
    else {
        return -1;
    };
    if let Some(native_documents) = native_documents {
        match engine.put_many_native_documents(collection, &native_documents, track_changes != 0) {
            Ok(true) => return 0,
            Ok(false) => return -1,
            Err(_) => return -1,
        }
    }
    match engine.put_many_indexed_with_options(collection, &documents, track_changes != 0, true) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_batch_writer_abort(writer: *mut CindelNativeBatchWriter) {
    if !writer.is_null() {
        drop(Box::from_raw(writer));
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_new(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    ids_ptr: *const u8,
    ids_len: usize,
    field_types_ptr: *const u8,
    field_types_len: usize,
) -> *mut CindelNativeDocumentReader {
    let Some(engine) = handle.as_ref() else {
        return std::ptr::null_mut();
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return std::ptr::null_mut();
    };
    let Some(ids) = read_wire_ids(ids_ptr, ids_len) else {
        return std::ptr::null_mut();
    };
    let Some(field_type_bytes) = read_bytes(field_types_ptr, field_types_len) else {
        return std::ptr::null_mut();
    };
    let Ok(layout) = NativeBatchLayout::new(field_type_bytes) else {
        return std::ptr::null_mut();
    };
    #[cfg(feature = "mdbx")]
    if let Ok(cursor) = engine.mdbx_cursor_document_reader(collection, &ids) {
        return Box::into_raw(Box::new(CindelNativeDocumentReader {
            current_index: None,
            mode: CindelNativeDocumentReaderMode::MdbxCursor { layout, cursor },
        }));
    }
    if let Ok(Some(cursor)) = engine.sqlite_native_document_cursor(collection, &ids) {
        return Box::into_raw(Box::new(CindelNativeDocumentReader {
            current_index: None,
            mode: CindelNativeDocumentReaderMode::SqliteCursor { layout, cursor },
        }));
    }
    std::ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_new_from_query_plan(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    plan_ptr: *const u8,
    plan_len: usize,
    field_types_ptr: *const u8,
    field_types_len: usize,
) -> *mut CindelNativeDocumentReader {
    let Some(engine) = handle.as_ref() else {
        return std::ptr::null_mut();
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return std::ptr::null_mut();
    };
    let Ok(plan) = read_query_plan(plan_ptr, plan_len) else {
        return std::ptr::null_mut();
    };
    let Some(field_type_bytes) = read_bytes(field_types_ptr, field_types_len) else {
        return std::ptr::null_mut();
    };
    let Ok(layout) = NativeBatchLayout::new(field_type_bytes) else {
        return std::ptr::null_mut();
    };
    #[cfg(feature = "mdbx")]
    if let Ok(Some(cursor)) = engine.mdbx_query_document_reader(collection, &plan) {
        return Box::into_raw(Box::new(CindelNativeDocumentReader {
            current_index: None,
            mode: CindelNativeDocumentReaderMode::MdbxQueryCursor { layout, cursor },
        }));
    }

    match engine.sqlite_query_plan_native_cursor(collection, &plan) {
        Ok(Some(cursor)) => {
            return Box::into_raw(Box::new(CindelNativeDocumentReader {
                current_index: None,
                mode: CindelNativeDocumentReaderMode::SqliteQueryCursor { layout, cursor },
            }));
        }
        Ok(None) => {}
        Err(_) => return std::ptr::null_mut(),
    }

    let Ok(ids) = engine.query_plan_ids(collection, &plan) else {
        return std::ptr::null_mut();
    };
    let Ok(documents) = engine.query_plan_documents(collection, &plan) else {
        return std::ptr::null_mut();
    };
    if ids.len() != documents.len() {
        return std::ptr::null_mut();
    }
    Box::into_raw(Box::new(CindelNativeDocumentReader {
        current_index: None,
        mode: CindelNativeDocumentReaderMode::Batch {
            layout,
            ids,
            documents: documents.into_iter().map(Some).collect(),
            all_present: true,
            trusted_static_size: true,
        },
    }))
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_len(
    reader: *const CindelNativeDocumentReader,
) -> usize {
    let Some(reader) = reader.as_ref() else {
        return 0;
    };
    reader.len()
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_is_streaming(
    reader: *const CindelNativeDocumentReader,
) -> bool {
    let Some(reader) = reader.as_ref() else {
        return false;
    };
    reader.is_streaming()
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_next(
    reader: *mut CindelNativeDocumentReader,
) -> bool {
    let Some(reader) = reader.as_mut() else {
        return false;
    };
    reader.next()
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_is_present(
    reader: *mut CindelNativeDocumentReader,
    document_index: usize,
) -> bool {
    let Some(reader) = reader.as_mut() else {
        return false;
    };
    reader.is_present(document_index)
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_id(
    reader: *mut CindelNativeDocumentReader,
    document_index: usize,
    out_value: *mut u64,
) -> bool {
    if out_value.is_null() {
        return false;
    }
    let Some(reader) = reader.as_mut() else {
        return false;
    };
    let Some(value) = reader.document_id(document_index) else {
        return false;
    };
    *out_value = value;
    true
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_id_value(
    reader: *mut CindelNativeDocumentReader,
    document_index: usize,
) -> u64 {
    let Some(reader) = reader.as_mut() else {
        return u64::MAX;
    };
    reader.document_id(document_index).unwrap_or(u64::MAX)
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_current_id_value(
    reader: *mut CindelNativeDocumentReader,
) -> u64 {
    let Some(reader) = reader.as_mut() else {
        return u64::MAX;
    };
    let Some(document_index) = reader.current_index else {
        return u64::MAX;
    };
    reader.document_id(document_index).unwrap_or(u64::MAX)
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_bool(
    reader: *mut CindelNativeDocumentReader,
    document_index: usize,
    field_index: u32,
    out_value: *mut bool,
) -> bool {
    let Some(reader) = reader.as_mut() else {
        return false;
    };
    let Some(value) = reader.read_bool(document_index, field_index as usize) else {
        return false;
    };
    if let Some(out_value) = out_value.as_mut() {
        *out_value = value;
        true
    } else {
        false
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_bool_value(
    reader: *mut CindelNativeDocumentReader,
    document_index: usize,
    field_index: u32,
) -> u8 {
    let Some(reader) = reader.as_mut() else {
        return 2;
    };
    match reader.read_bool(document_index, field_index as usize) {
        Some(false) => 0,
        Some(true) => 1,
        None => 2,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_current_bool_value(
    reader: *mut CindelNativeDocumentReader,
    field_index: u32,
) -> u8 {
    let Some(reader) = reader.as_mut() else {
        return 2;
    };
    let Some(document_index) = reader.current_index else {
        return 2;
    };
    match reader.read_bool(document_index, field_index as usize) {
        Some(false) => 0,
        Some(true) => 1,
        None => 2,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_int(
    reader: *mut CindelNativeDocumentReader,
    document_index: usize,
    field_index: u32,
    out_value: *mut i64,
) -> bool {
    if out_value.is_null() {
        return false;
    }
    let Some(reader) = reader.as_mut() else {
        return false;
    };
    let Some(value) = reader.read_int(document_index, field_index as usize) else {
        return false;
    };
    *out_value = value;
    true
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_int_value(
    reader: *mut CindelNativeDocumentReader,
    document_index: usize,
    field_index: u32,
) -> i64 {
    let Some(reader) = reader.as_mut() else {
        return i64::MIN;
    };
    reader
        .read_int(document_index, field_index as usize)
        .unwrap_or(i64::MIN)
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_current_int_value(
    reader: *mut CindelNativeDocumentReader,
    field_index: u32,
) -> i64 {
    let Some(reader) = reader.as_mut() else {
        return i64::MIN;
    };
    let Some(document_index) = reader.current_index else {
        return i64::MIN;
    };
    reader
        .read_int(document_index, field_index as usize)
        .unwrap_or(i64::MIN)
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_double(
    reader: *mut CindelNativeDocumentReader,
    document_index: usize,
    field_index: u32,
    out_value: *mut f64,
) -> bool {
    let Some(reader) = reader.as_mut() else {
        return false;
    };
    let Some(value) = reader.read_double(document_index, field_index as usize) else {
        return false;
    };
    if let Some(out_value) = out_value.as_mut() {
        *out_value = value;
        true
    } else {
        false
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_double_value(
    reader: *mut CindelNativeDocumentReader,
    document_index: usize,
    field_index: u32,
) -> f64 {
    let Some(reader) = reader.as_mut() else {
        return f64::NAN;
    };
    reader
        .read_double(document_index, field_index as usize)
        .unwrap_or(f64::NAN)
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_current_double_value(
    reader: *mut CindelNativeDocumentReader,
    field_index: u32,
) -> f64 {
    let Some(reader) = reader.as_mut() else {
        return f64::NAN;
    };
    let Some(document_index) = reader.current_index else {
        return f64::NAN;
    };
    reader
        .read_double(document_index, field_index as usize)
        .unwrap_or(f64::NAN)
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_bytes(
    reader: *mut CindelNativeDocumentReader,
    document_index: usize,
    field_index: u32,
    out_ptr: *mut *const u8,
    out_len: *mut usize,
) -> bool {
    if out_ptr.is_null() || out_len.is_null() {
        return false;
    }
    *out_ptr = std::ptr::null();
    *out_len = 0;
    let Some(reader) = reader.as_mut() else {
        return false;
    };
    let Some(bytes) = reader.read_bytes(document_index, field_index as usize) else {
        return false;
    };
    *out_ptr = bytes.as_ptr();
    *out_len = bytes.len();
    true
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_string_value(
    reader: *mut CindelNativeDocumentReader,
    document_index: usize,
    field_index: u32,
    out_ptr: *mut *const u8,
    out_is_ascii: *mut bool,
) -> usize {
    if out_ptr.is_null() || out_is_ascii.is_null() {
        return 0;
    }
    *out_ptr = std::ptr::null();
    *out_is_ascii = false;
    let Some(reader) = reader.as_mut() else {
        return 0;
    };
    let Some(bytes) = reader.read_bytes(document_index, field_index as usize) else {
        return 0;
    };
    *out_ptr = bytes.as_ptr();
    *out_is_ascii = bytes.is_ascii();
    bytes.len()
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_current_string_value(
    reader: *mut CindelNativeDocumentReader,
    field_index: u32,
    out_ptr: *mut *const u8,
    out_is_ascii: *mut bool,
) -> usize {
    if out_ptr.is_null() || out_is_ascii.is_null() {
        return 0;
    }
    *out_ptr = std::ptr::null();
    *out_is_ascii = false;
    let Some(reader) = reader.as_mut() else {
        return 0;
    };
    let Some(document_index) = reader.current_index else {
        return 0;
    };
    let Some(bytes) = reader.read_bytes(document_index, field_index as usize) else {
        return 0;
    };
    *out_ptr = bytes.as_ptr();
    *out_is_ascii = bytes.is_ascii();
    bytes.len()
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_string(
    reader: *mut CindelNativeDocumentReader,
    document_index: usize,
    field_index: u32,
    out_ptr: *mut *const u8,
    out_len: *mut usize,
    out_is_ascii: *mut bool,
    out_intern_id: *mut u64,
) -> bool {
    if out_ptr.is_null() || out_len.is_null() || out_is_ascii.is_null() || out_intern_id.is_null() {
        return false;
    }
    *out_ptr = std::ptr::null();
    *out_len = 0;
    *out_is_ascii = false;
    *out_intern_id = 0;
    let Some(reader) = reader.as_mut() else {
        return false;
    };
    let Some(bytes) = reader.read_bytes(document_index, field_index as usize) else {
        return false;
    };
    *out_ptr = bytes.as_ptr();
    *out_len = bytes.len();
    *out_is_ascii = bytes.is_ascii();
    true
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_list_bytes(
    reader: *mut CindelNativeDocumentReader,
    document_index: usize,
    field_index: u32,
    out_ptr: *mut *const u8,
    out_len: *mut usize,
) -> bool {
    if out_ptr.is_null() || out_len.is_null() {
        return false;
    }
    *out_ptr = std::ptr::null();
    *out_len = 0;
    let Some(reader) = reader.as_mut() else {
        return false;
    };
    let Some(bytes) = reader.read_bytes(document_index, field_index as usize) else {
        return false;
    };
    *out_ptr = bytes.as_ptr();
    *out_len = bytes.len();
    true
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_list(
    reader: *mut CindelNativeDocumentReader,
    document_index: usize,
    field_index: u32,
) -> *mut CindelNativeDocumentReader {
    let Some(reader) = reader.as_mut() else {
        return std::ptr::null_mut();
    };
    let Some(raw_list) = reader.read_list(document_index, field_index as usize) else {
        return std::ptr::null_mut();
    };
    Box::into_raw(Box::new(CindelNativeDocumentReader {
        current_index: None,
        mode: CindelNativeDocumentReaderMode::RawList {
            bytes: raw_list.bytes,
            entries: raw_list.entries,
        },
    }))
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_free(
    reader: *mut CindelNativeDocumentReader,
) {
    if !reader.is_null() {
        drop(Box::from_raw(reader));
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_get(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    id: u64,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };

    match engine.get(collection, id) {
        Ok(Some(bytes)) => {
            let (ptr, len) = into_raw_bytes(bytes);
            *out_ptr = ptr;
            *out_len = len;
            0
        }
        Ok(None) => 1,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_get_many(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    ids_ptr: *const u8,
    ids_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Some(ids) = read_wire_ids(ids_ptr, ids_len) else {
        return -1;
    };

    match engine.get_many(collection, &ids) {
        Ok(documents) => write_binary_documents(documents, out_ptr, out_len),
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_get_stored(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    id: u64,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };

    match engine.get_stored(collection, id) {
        Ok(Some(bytes)) => {
            let (ptr, len) = into_raw_bytes(bytes);
            *out_ptr = ptr;
            *out_len = len;
            0
        }
        Ok(None) => 1,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_get_many_stored(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    ids_ptr: *const u8,
    ids_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Some(ids) = read_wire_ids(ids_ptr, ids_len) else {
        return -1;
    };

    match engine.get_many_stored(collection, &ids) {
        Ok(documents) => write_binary_documents(documents, out_ptr, out_len),
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_document_ids(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };

    match engine.document_ids(collection) {
        Ok(ids) => write_wire_ids(&ids, out_ptr, out_len),
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_delete(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    id: u64,
) -> i32 {
    let Some(engine) = handle.as_mut() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };

    match engine.delete(collection, id) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_delete_many(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    ids_ptr: *const u8,
    ids_len: usize,
) -> i32 {
    let Some(engine) = handle.as_mut() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Some(ids) = read_wire_ids(ids_ptr, ids_len) else {
        return -1;
    };

    match engine.delete_many(collection, &ids) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_delete_many_native_documents(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    ids_ptr: *const u8,
    ids_len: usize,
) -> i32 {
    let Some(engine) = handle.as_mut() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Some(ids) = read_wire_ids(ids_ptr, ids_len) else {
        return -1;
    };

    match engine.delete_many_native_documents(collection, &ids) {
        Ok(true) => 0,
        Ok(false) | Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_collection_revision(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    out_revision: *mut u64,
) -> i32 {
    if out_revision.is_null() {
        return -1;
    }

    *out_revision = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };

    match engine.collection_revision(collection) {
        Ok(revision) => {
            *out_revision = revision;
            0
        }
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_take_changes(
    handle: *mut CindelEngine,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_mut() else {
        return -1;
    };

    match engine.take_change_sets() {
        Ok(changes) => {
            let changes = changes
                .into_iter()
                .map(|change| WireChangeSet {
                    collection: change.collection,
                    revision: change.revision,
                    document_ids: change.document_ids,
                })
                .collect::<Vec<_>>();
            match encode_change_set_list(&changes) {
                Ok(bytes) => {
                    let (ptr, len) = into_raw_bytes(bytes);
                    *out_ptr = ptr;
                    *out_len = len;
                    0
                }
                Err(_) => -1,
            }
        }
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_discard_changes(handle: *mut CindelEngine) -> i32 {
    let Some(engine) = handle.as_mut() else {
        return -1;
    };
    match engine.discard_change_sets() {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_schema_version(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    out_version: *mut u64,
) -> i32 {
    if out_version.is_null() {
        return -1;
    }

    *out_version = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };

    match engine.schema_version(collection) {
        Ok(Some(version)) => {
            *out_version = version;
            0
        }
        Ok(None) => 1,
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_query_index_equal(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    index_ptr: *const u8,
    index_len: usize,
    value_ptr: *const u8,
    value_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Some(index) = read_str(index_ptr, index_len) else {
        return -1;
    };
    let Ok(value) = read_index_value(value_ptr, value_len) else {
        return -1;
    };

    match engine.query_index_equal(collection, index, &value) {
        Ok(ids) => write_wire_ids(&ids, out_ptr, out_len),
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_query_index_range(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    index_ptr: *const u8,
    index_len: usize,
    lower_ptr: *const u8,
    lower_len: usize,
    upper_ptr: *const u8,
    upper_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Some(index) = read_str(index_ptr, index_len) else {
        return -1;
    };
    let Ok(lower) = read_optional_index_value(lower_ptr, lower_len) else {
        return -1;
    };
    let Ok(upper) = read_optional_index_value(upper_ptr, upper_len) else {
        return -1;
    };

    match engine.query_index_range(collection, index, lower.as_ref(), upper.as_ref()) {
        Ok(ids) => write_wire_ids(&ids, out_ptr, out_len),
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_query_filter(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    ids_ptr: *const u8,
    ids_len: usize,
    filter_ptr: *const u8,
    filter_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Some(ids) = read_wire_ids(ids_ptr, ids_len) else {
        return -1;
    };
    let Some(filter) = read_bytes(filter_ptr, filter_len) else {
        return -1;
    };

    match engine.query_filter(collection, &ids, filter) {
        Ok(ids) => write_wire_ids(&ids, out_ptr, out_len),
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_query_project(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    ids_ptr: *const u8,
    ids_len: usize,
    field_ptr: *const u8,
    field_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Some(ids) = read_wire_ids(ids_ptr, ids_len) else {
        return -1;
    };
    let Some(field) = read_str(field_ptr, field_len) else {
        return -1;
    };

    match engine.query_project(collection, &ids, field) {
        Ok(bytes) => {
            let (ptr, len) = into_raw_bytes(bytes);
            *out_ptr = ptr;
            *out_len = len;
            0
        }
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_query_aggregate(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    ids_ptr: *const u8,
    ids_len: usize,
    field_ptr: *const u8,
    field_len: usize,
    operation_ptr: *const u8,
    operation_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Some(ids) = read_wire_ids(ids_ptr, ids_len) else {
        return -1;
    };
    let Some(field) = read_str(field_ptr, field_len) else {
        return -1;
    };
    let Some(operation) = read_str(operation_ptr, operation_len) else {
        return -1;
    };

    match engine.query_aggregate(collection, &ids, field, operation) {
        Ok(bytes) => {
            let (ptr, len) = into_raw_bytes(bytes);
            *out_ptr = ptr;
            *out_len = len;
            0
        }
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_query_plan_ids(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    plan_ptr: *const u8,
    plan_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Ok(plan) = read_query_plan(plan_ptr, plan_len) else {
        return -1;
    };

    match engine.query_plan_ids(collection, &plan) {
        Ok(ids) => write_wire_ids(&ids, out_ptr, out_len),
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_query_plan_documents(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    plan_ptr: *const u8,
    plan_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Ok(plan) = read_query_plan(plan_ptr, plan_len) else {
        return -1;
    };

    match engine.query_plan_documents(collection, &plan) {
        Ok(documents) => {
            write_binary_documents(documents.into_iter().map(Some).collect(), out_ptr, out_len)
        }
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_query_plan_count(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    plan_ptr: *const u8,
    plan_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Ok(plan) = read_query_plan(plan_ptr, plan_len) else {
        return -1;
    };

    match engine
        .query_plan_count(collection, &plan)
        .and_then(|count| {
            i64::try_from(count)
                .map(WireScalar::Int)
                .map_err(|error| error.to_string())
        })
        .and_then(|scalar| encode_scalar(&scalar))
    {
        Ok(bytes) => {
            let (ptr, len) = into_raw_bytes(bytes);
            *out_ptr = ptr;
            *out_len = len;
            0
        }
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_query_plan_project(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    plan_ptr: *const u8,
    plan_len: usize,
    field_ptr: *const u8,
    field_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Ok(plan) = read_query_plan(plan_ptr, plan_len) else {
        return -1;
    };
    let Some(field) = read_str(field_ptr, field_len) else {
        return -1;
    };

    match engine.query_plan_project(collection, &plan, field) {
        Ok(bytes) => {
            let (ptr, len) = into_raw_bytes(bytes);
            *out_ptr = ptr;
            *out_len = len;
            0
        }
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_query_plan_aggregate(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    plan_ptr: *const u8,
    plan_len: usize,
    field_ptr: *const u8,
    field_len: usize,
    operation_ptr: *const u8,
    operation_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_ref() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Ok(plan) = read_query_plan(plan_ptr, plan_len) else {
        return -1;
    };
    let Some(field) = read_str(field_ptr, field_len) else {
        return -1;
    };
    let Some(operation) = read_str(operation_ptr, operation_len) else {
        return -1;
    };

    match engine.query_plan_aggregate(collection, &plan, field, operation) {
        Ok(bytes) => {
            let (ptr, len) = into_raw_bytes(bytes);
            *out_ptr = ptr;
            *out_len = len;
            0
        }
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_query_plan_delete(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    plan_ptr: *const u8,
    plan_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return -1;
    }

    *out_ptr = std::ptr::null_mut();
    *out_len = 0;

    let Some(engine) = handle.as_mut() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Ok(plan) = read_query_plan(plan_ptr, plan_len) else {
        return -1;
    };

    match engine.query_plan_delete(collection, &plan) {
        Ok(ids) => write_wire_ids(&ids, out_ptr, out_len),
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_query_plan_update(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    plan_ptr: *const u8,
    plan_len: usize,
    updates_ptr: *const u8,
    updates_len: usize,
    collect_changes: bool,
    out_count: *mut u64,
) -> i32 {
    if out_count.is_null() {
        return -1;
    }

    *out_count = 0;

    let Some(engine) = handle.as_mut() else {
        return -1;
    };
    let Some(collection) = read_str(collection_ptr, collection_len) else {
        return -1;
    };
    let Ok(plan) = read_query_plan(plan_ptr, plan_len) else {
        return -1;
    };
    let Some(updates_bytes) = read_bytes(updates_ptr, updates_len) else {
        return -1;
    };
    let Ok(updates) = decode_field_updates(updates_bytes) else {
        return -1;
    };

    match engine.query_plan_update(collection, &plan, &updates, collect_changes) {
        Ok(count) => {
            *out_count = count as u64;
            0
        }
        Err(_) => -1,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cindel_free_buffer(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }

    let slice = std::ptr::slice_from_raw_parts_mut(ptr, len);
    drop(Box::from_raw(slice));
}

unsafe fn read_str<'a>(ptr: *const u8, len: usize) -> Option<&'a str> {
    std::str::from_utf8(read_bytes(ptr, len)?).ok()
}

fn decode_backend(value: u32) -> Option<StorageBackendKind> {
    match value {
        0 => Some(StorageBackendKind::Sqlite),
        #[cfg(feature = "mdbx")]
        1 => Some(StorageBackendKind::Mdbx),
        _ => None,
    }
}

unsafe fn read_bytes<'a>(ptr: *const u8, len: usize) -> Option<&'a [u8]> {
    if ptr.is_null() {
        return None;
    }

    Some(std::slice::from_raw_parts(ptr, len))
}

unsafe fn read_optional_bytes<'a>(ptr: *const u8, len: usize) -> Option<&'a [u8]> {
    if ptr.is_null() && len == 0 {
        return Some(&[]);
    }
    read_bytes(ptr, len)
}

fn into_raw_bytes(bytes: Vec<u8>) -> (*mut u8, usize) {
    let mut boxed = bytes.into_boxed_slice();
    let len = boxed.len();
    let ptr = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    (ptr, len)
}

fn write_wire_ids(ids: &[u64], out_ptr: *mut *mut u8, out_len: *mut usize) -> i32 {
    match encode_id_list(ids) {
        Ok(bytes) => {
            let (ptr, len) = into_raw_bytes(bytes);
            unsafe {
                *out_ptr = ptr;
                *out_len = len;
            }
            0
        }
        Err(_) => -1,
    }
}

fn write_binary_documents(
    documents: Vec<Option<Vec<u8>>>,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&(documents.len() as u32).to_le_bytes());
    for document in documents {
        match document {
            Some(document) => {
                let Ok(length) = u32::try_from(document.len()) else {
                    return -1;
                };
                bytes.push(1);
                bytes.extend_from_slice(&length.to_le_bytes());
                bytes.extend_from_slice(&document);
            }
            None => {
                bytes.push(0);
                bytes.extend_from_slice(&0u32.to_le_bytes());
            }
        }
    }

    let (ptr, len) = into_raw_bytes(bytes);
    unsafe {
        *out_ptr = ptr;
        *out_len = len;
    }
    0
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum NativeBatchFieldType {
    Bool,
    Int,
    Double,
    String,
    List,
    Object,
}

pub struct CindelNativeBatchWriter {
    mode: NativeBatchWriterMode,
    failed: bool,
}

enum NativeBatchWriterMode {
    Batch {
        layout: NativeBatchLayout,
        documents: Vec<DocumentWrite>,
        native_documents: Option<Vec<NativeDocumentWrite>>,
        current: Option<NativeBatchDocumentBuilder>,
        document_capacity_hint: usize,
    },
    List {
        parent_index: usize,
        records: Vec<Option<Vec<u8>>>,
        encoding: NativeListEncoding,
    },
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum NativeListEncoding {
    Unknown,
    Generic,
    CompactString,
}

pub struct CindelNativeDocumentReader {
    current_index: Option<usize>,
    mode: CindelNativeDocumentReaderMode,
}

enum CindelNativeDocumentReaderMode {
    Batch {
        layout: NativeBatchLayout,
        ids: Vec<u64>,
        documents: Vec<Option<Vec<u8>>>,
        all_present: bool,
        trusted_static_size: bool,
    },
    SqliteCursor {
        layout: NativeBatchLayout,
        cursor: SqliteNativeDocumentCursor,
    },
    SqliteQueryCursor {
        layout: NativeBatchLayout,
        cursor: SqliteNativeQueryCursor,
    },
    #[cfg(feature = "mdbx")]
    MdbxCursor {
        layout: NativeBatchLayout,
        cursor: MdbxCursorDocumentReader,
    },
    #[cfg(feature = "mdbx")]
    MdbxQueryCursor {
        layout: NativeBatchLayout,
        cursor: MdbxQueryDocumentReader,
    },
    RawList {
        bytes: Vec<u8>,
        entries: Vec<NativeRawListEntry>,
    },
}

struct NativeRawListEntry {
    kind: u8,
    is_null: bool,
    payload_start: usize,
    payload_len: usize,
}

struct NativeRawList {
    bytes: Vec<u8>,
    entries: Vec<NativeRawListEntry>,
}

const NATIVE_VALUE_NULL: u8 = 0;
const NATIVE_VALUE_BOOL: u8 = 1;
const NATIVE_VALUE_INT: u8 = 2;
const NATIVE_VALUE_DOUBLE: u8 = 3;
const NATIVE_VALUE_STRING: u8 = 4;
const NATIVE_VALUE_DATETIME: u8 = 5;
const NATIVE_VALUE_DURATION: u8 = 6;
const NATIVE_VALUE_LIST: u8 = 7;
const NATIVE_VALUE_ENUM: u8 = 8;
const NATIVE_VALUE_NULL_FLAG: u8 = 0x01;

struct NativeBatchLayout {
    field_types: Vec<NativeBatchFieldType>,
    offsets: Vec<usize>,
    static_size: usize,
    null_static_bytes: Vec<u8>,
}

struct NativeBatchDocumentBuilder {
    id: u64,
    bytes: Option<Vec<u8>>,
    values: Option<Vec<NativeDocumentValue>>,
}

impl CindelNativeBatchWriter {
    fn new(
        field_type_bytes: &[u8],
        capacity: usize,
        collect_native_values: bool,
    ) -> Result<Self, String> {
        let layout = NativeBatchLayout::new(field_type_bytes)?;
        let document_capacity_hint = layout.null_static_bytes.len();
        let native_documents = collect_native_values.then(|| Vec::with_capacity(capacity));
        Ok(Self {
            mode: NativeBatchWriterMode::Batch {
                layout,
                documents: Vec::with_capacity(capacity),
                native_documents,
                current: None,
                document_capacity_hint,
            },
            failed: false,
        })
    }

    fn new_list(parent_index: usize, length: usize) -> Self {
        Self {
            mode: NativeBatchWriterMode::List {
                parent_index,
                records: vec![None; length],
                encoding: NativeListEncoding::Unknown,
            },
            failed: false,
        }
    }

    fn record(&mut self, action: impl FnOnce(&mut Self) -> Result<(), String>) {
        if self.failed {
            return;
        }
        if action(self).is_err() {
            self.failed = true;
        }
    }

    fn document_builder(
        layout: &NativeBatchLayout,
        id: u64,
        document_capacity_hint: usize,
        collect_native_values: bool,
    ) -> NativeBatchDocumentBuilder {
        let bytes = if collect_native_values {
            None
        } else {
            let mut bytes = Vec::with_capacity(document_capacity_hint);
            bytes.extend_from_slice(&layout.null_static_bytes);
            Some(bytes)
        };
        let values = collect_native_values
            .then(|| vec![NativeDocumentValue::Null; layout.field_types.len()]);
        NativeBatchDocumentBuilder { id, bytes, values }
    }

    fn begin_document(&mut self, id: u64) -> Result<(), String> {
        match &mut self.mode {
            NativeBatchWriterMode::Batch {
                layout,
                current,
                document_capacity_hint,
                native_documents,
                ..
            } => {
                if current.is_some() {
                    return Err("native batch writer already has an open document".into());
                }
                *current = Some(Self::document_builder(
                    layout,
                    id,
                    *document_capacity_hint,
                    native_documents.is_some(),
                ));
                Ok(())
            }
            NativeBatchWriterMode::List { .. } => {
                Err("native list writer cannot begin a document".into())
            }
        }
    }

    fn write_null(&mut self, index: usize) -> Result<(), String> {
        match &mut self.mode {
            NativeBatchWriterMode::Batch {
                layout, current, ..
            } => {
                layout.field_type_result(index)?;
                let Some(current) = current.as_mut() else {
                    return Err("native batch writer has no open document".into());
                };
                if let Some(bytes) = current.bytes.as_mut() {
                    write_null_for_field(&layout.field_types, &layout.offsets, bytes, index)?;
                }
                if let Some(values) = current.values.as_mut() {
                    let Some(value) = values.get_mut(index) else {
                        return Err(format!(
                            "native batch writer field index `{index}` is out of range"
                        ));
                    };
                    *value = NativeDocumentValue::Null;
                }
                Ok(())
            }
            NativeBatchWriterMode::List { records, .. } => {
                let Some(value) = records.get_mut(index) else {
                    return Err(format!(
                        "native list writer index `{index}` is out of range"
                    ));
                };
                *value = None;
                Ok(())
            }
        }
    }

    fn write_bool(&mut self, index: usize, value: bool) -> Result<(), String> {
        match &mut self.mode {
            NativeBatchWriterMode::Batch { .. } => {
                self.require_field(index, NativeBatchFieldType::Bool)?;
                let offset = self.absolute_offset(index)?;
                let current = self.current_mut()?;
                if let Some(bytes) = current.bytes.as_mut() {
                    bytes[offset] = if value { 1 } else { 0 };
                }
                if let Some(values) = current.values.as_mut() {
                    values[index] = NativeDocumentValue::Bool(value);
                }
                Ok(())
            }
            NativeBatchWriterMode::List {
                records, encoding, ..
            } => {
                ensure_generic_list_records(records, encoding)?;
                write_list_value_record(records, index, Some(BinaryValue::Bool(value)))
            }
        }
    }

    fn write_int(&mut self, index: usize, value: i64) -> Result<(), String> {
        if value == i64::MIN {
            return Err("native batch writer cannot store the int null sentinel".into());
        }
        match &mut self.mode {
            NativeBatchWriterMode::Batch { .. } => {
                self.require_field(index, NativeBatchFieldType::Int)?;
                let offset = self.absolute_offset(index)?;
                let current = self.current_mut()?;
                if let Some(bytes) = current.bytes.as_mut() {
                    bytes[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
                }
                if let Some(values) = current.values.as_mut() {
                    values[index] = NativeDocumentValue::Int(value);
                }
                Ok(())
            }
            NativeBatchWriterMode::List {
                records, encoding, ..
            } => {
                ensure_generic_list_records(records, encoding)?;
                write_list_value_record(records, index, Some(BinaryValue::Int(value)))
            }
        }
    }

    fn write_double(&mut self, index: usize, value: f64) -> Result<(), String> {
        if !value.is_finite() {
            return Err("native batch writer double values must be finite".into());
        }
        match &mut self.mode {
            NativeBatchWriterMode::Batch { .. } => {
                self.require_field(index, NativeBatchFieldType::Double)?;
                let offset = self.absolute_offset(index)?;
                let current = self.current_mut()?;
                if let Some(bytes) = current.bytes.as_mut() {
                    bytes[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
                }
                if let Some(values) = current.values.as_mut() {
                    values[index] = NativeDocumentValue::Double(value);
                }
                Ok(())
            }
            NativeBatchWriterMode::List {
                records, encoding, ..
            } => {
                ensure_generic_list_records(records, encoding)?;
                write_list_value_record(records, index, Some(BinaryValue::Double(value)))
            }
        }
    }

    fn write_bytes(&mut self, index: usize, payload: &[u8]) -> Result<(), String> {
        match &mut self.mode {
            NativeBatchWriterMode::Batch {
                layout, current, ..
            } => {
                match layout.field_type_result(index)? {
                    NativeBatchFieldType::String
                    | NativeBatchFieldType::List
                    | NativeBatchFieldType::Object => {}
                    _ => return Err("native batch writer expected a dynamic field".into()),
                }
                if payload.len() > 0x00ff_ffff {
                    return Err("native batch writer dynamic payload is too large".into());
                }
                let static_size = layout.static_size;
                let offset = layout.absolute_offset_result(index)?;
                let Some(current) = current.as_mut() else {
                    return Err("native batch writer has no open document".into());
                };
                if let Some(bytes) = current.bytes.as_mut() {
                    let relative = static_size
                        .checked_add(bytes.len().saturating_sub(3 + static_size))
                        .ok_or_else(|| "native batch writer dynamic offset overflow".to_string())?;
                    if relative > 0x00ff_ffff {
                        return Err("native batch writer dynamic offset is too large".into());
                    }
                    write_u24(bytes, offset, relative)?;
                    let mut header = [0u8; 3];
                    write_u24(&mut header, 0, payload.len())?;
                    bytes.extend_from_slice(&header);
                    bytes.extend_from_slice(payload);
                }
                if let Some(values) = current.values.as_mut() {
                    values[index] = NativeDocumentValue::Bytes(payload.to_vec());
                }
                Ok(())
            }
            NativeBatchWriterMode::List {
                records, encoding, ..
            } => match encoding {
                NativeListEncoding::Unknown | NativeListEncoding::CompactString => {
                    *encoding = NativeListEncoding::CompactString;
                    write_list_record(records, index, payload.to_vec())
                }
                NativeListEncoding::Generic => {
                    let record = write_string_value_record(payload)?;
                    write_list_record(records, index, record)
                }
            },
        }
    }

    fn begin_list(&mut self, index: usize, length: usize) -> Result<Self, String> {
        self.require_field(index, NativeBatchFieldType::List)?;
        Ok(Self::new_list(index, length))
    }

    fn end_list(&mut self, list_writer: Self) -> Result<(), String> {
        let NativeBatchWriterMode::List {
            parent_index,
            records,
            encoding,
        } = list_writer.mode
        else {
            return Err("native batch writer expected a list writer".into());
        };
        let bytes = if encoding == NativeListEncoding::CompactString {
            write_compact_string_list_records(&records)?
        } else {
            write_list_records(&records)?
        };
        self.write_bytes(parent_index, &bytes)
    }

    fn end_document(&mut self) -> Result<(), String> {
        match &mut self.mode {
            NativeBatchWriterMode::Batch {
                documents,
                native_documents,
                current,
                document_capacity_hint,
                ..
            } => {
                let Some(current) = current.take() else {
                    return Err("native batch writer has no open document".into());
                };
                let NativeBatchDocumentBuilder { id, bytes, values } = current;
                if let Some(bytes) = bytes {
                    *document_capacity_hint = (*document_capacity_hint).max(bytes.len());
                    documents.push(DocumentWrite {
                        id,
                        bytes,
                        indexes: Vec::new(),
                    });
                }
                if let (Some(native_documents), Some(values)) = (native_documents.as_mut(), values)
                {
                    native_documents.push(NativeDocumentWrite { id, values });
                }
                Ok(())
            }
            NativeBatchWriterMode::List { .. } => {
                Err("native list writer cannot end a document".into())
            }
        }
    }

    fn save_document(&mut self, id: u64) -> Result<(), String> {
        match &mut self.mode {
            NativeBatchWriterMode::Batch {
                layout,
                documents,
                native_documents,
                current,
                document_capacity_hint,
            } => {
                let current = if let Some(current) = current.take() {
                    current
                } else {
                    Self::document_builder(
                        layout,
                        id,
                        *document_capacity_hint,
                        native_documents.is_some(),
                    )
                };
                let NativeBatchDocumentBuilder { bytes, values, .. } = current;
                if let Some(bytes) = bytes {
                    *document_capacity_hint = (*document_capacity_hint).max(bytes.len());
                    documents.push(DocumentWrite {
                        id,
                        bytes,
                        indexes: Vec::new(),
                    });
                }
                if let (Some(native_documents), Some(values)) = (native_documents.as_mut(), values)
                {
                    native_documents.push(NativeDocumentWrite { id, values });
                }
                Ok(())
            }
            NativeBatchWriterMode::List { .. } => {
                Err("native list writer cannot save a document".into())
            }
        }
    }

    fn take_documents(self) -> Result<Vec<DocumentWrite>, String> {
        match self.mode {
            NativeBatchWriterMode::Batch {
                documents, current, ..
            } => {
                if current.is_some() {
                    Err("native batch writer has an open document".into())
                } else {
                    Ok(documents)
                }
            }
            NativeBatchWriterMode::List { .. } => {
                Err("native batch writer expected a document writer".into())
            }
        }
    }

    fn take_documents_with_optional_native_values(
        self,
    ) -> Result<(Vec<DocumentWrite>, Option<Vec<NativeDocumentWrite>>), String> {
        match self.mode {
            NativeBatchWriterMode::Batch {
                documents,
                native_documents,
                current,
                ..
            } => {
                if current.is_some() {
                    Err("native batch writer has an open document".into())
                } else {
                    Ok((documents, native_documents))
                }
            }
            NativeBatchWriterMode::List { .. } => {
                Err("native batch writer expected a document writer".into())
            }
        }
    }

    fn current_mut(&mut self) -> Result<&mut NativeBatchDocumentBuilder, String> {
        match &mut self.mode {
            NativeBatchWriterMode::Batch {
                layout,
                current,
                document_capacity_hint,
                native_documents,
                ..
            } => {
                if current.is_none() {
                    *current = Some(Self::document_builder(
                        layout,
                        0,
                        *document_capacity_hint,
                        native_documents.is_some(),
                    ));
                }
                current
                    .as_mut()
                    .ok_or_else(|| "native batch writer has no open document".to_string())
            }
            NativeBatchWriterMode::List { .. } => {
                Err("native list writer has no current document".into())
            }
        }
    }

    fn field_type(&self, index: usize) -> Result<NativeBatchFieldType, String> {
        match &self.mode {
            NativeBatchWriterMode::Batch { layout, .. } => layout.field_type_result(index),
            NativeBatchWriterMode::List { .. } => {
                Err("native list writer fields are dynamically typed".into())
            }
        }
    }

    fn require_field(&self, index: usize, expected: NativeBatchFieldType) -> Result<(), String> {
        let actual = self.field_type(index)?;
        if actual == expected {
            Ok(())
        } else {
            Err("native batch writer field type mismatch".into())
        }
    }

    fn absolute_offset(&self, index: usize) -> Result<usize, String> {
        match &self.mode {
            NativeBatchWriterMode::Batch { layout, .. } => layout.absolute_offset_result(index),
            NativeBatchWriterMode::List { .. } => {
                Err("native list writer fields have no static offsets".into())
            }
        }
    }
}

fn write_list_value_record(
    records: &mut [Option<Vec<u8>>],
    index: usize,
    value: Option<BinaryValue>,
) -> Result<(), String> {
    let record = write_value_record(&value)?;
    write_list_record(records, index, record)
}

fn ensure_generic_list_records(
    records: &mut [Option<Vec<u8>>],
    encoding: &mut NativeListEncoding,
) -> Result<(), String> {
    match *encoding {
        NativeListEncoding::Generic => Ok(()),
        NativeListEncoding::Unknown => {
            *encoding = NativeListEncoding::Generic;
            Ok(())
        }
        NativeListEncoding::CompactString => {
            for record in records.iter_mut() {
                if let Some(payload) = record.take() {
                    *record = Some(write_string_value_record(&payload)?);
                }
            }
            *encoding = NativeListEncoding::Generic;
            Ok(())
        }
    }
}

fn write_list_record(
    records: &mut [Option<Vec<u8>>],
    index: usize,
    record: Vec<u8>,
) -> Result<(), String> {
    let Some(slot) = records.get_mut(index) else {
        return Err(format!(
            "native list writer index `{index}` is out of range"
        ));
    };
    *slot = Some(record);
    Ok(())
}

impl CindelNativeDocumentReader {
    fn len(&self) -> usize {
        match &self.mode {
            CindelNativeDocumentReaderMode::Batch { documents, .. } => documents.len(),
            CindelNativeDocumentReaderMode::SqliteCursor { cursor, .. } => cursor.len(),
            CindelNativeDocumentReaderMode::SqliteQueryCursor { .. } => 0,
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxCursor { cursor, .. } => cursor.len(),
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxQueryCursor { .. } => 0,
            CindelNativeDocumentReaderMode::RawList { entries, .. } => entries.len(),
        }
    }

    fn is_streaming(&self) -> bool {
        match &self.mode {
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxQueryCursor { .. } => true,
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxCursor { .. } => false,
            CindelNativeDocumentReaderMode::SqliteQueryCursor { .. } => true,
            CindelNativeDocumentReaderMode::Batch { .. }
            | CindelNativeDocumentReaderMode::SqliteCursor { .. }
            | CindelNativeDocumentReaderMode::RawList { .. } => false,
        }
    }

    fn next(&mut self) -> bool {
        let has_next = match &mut self.mode {
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxQueryCursor { cursor, .. } => {
                cursor.next().unwrap_or(false)
            }
            CindelNativeDocumentReaderMode::SqliteQueryCursor { cursor, .. } => {
                cursor.next().unwrap_or(false)
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxCursor { .. } => false,
            CindelNativeDocumentReaderMode::Batch { .. }
            | CindelNativeDocumentReaderMode::SqliteCursor { .. }
            | CindelNativeDocumentReaderMode::RawList { .. } => false,
        };
        if has_next {
            self.current_index = Some(0);
        }
        has_next
    }

    fn is_present(&mut self, document_index: usize) -> bool {
        let present = match &mut self.mode {
            CindelNativeDocumentReaderMode::Batch {
                documents,
                all_present,
                ..
            } => {
                if *all_present {
                    document_index < documents.len()
                } else {
                    documents.get(document_index).is_some_and(Option::is_some)
                }
            }
            CindelNativeDocumentReaderMode::SqliteCursor { cursor, .. } => {
                cursor.is_present(document_index).unwrap_or(false)
            }
            CindelNativeDocumentReaderMode::SqliteQueryCursor { cursor, .. } => {
                cursor.document_id(document_index).is_some()
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxCursor { cursor, .. } => {
                cursor.is_present(document_index).unwrap_or(false)
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxQueryCursor { cursor, .. } => cursor
                .document_bytes(document_index)
                .ok()
                .flatten()
                .is_some(),
            CindelNativeDocumentReaderMode::RawList { entries, .. } => {
                document_index < entries.len()
            }
        };
        self.current_index = Some(document_index);
        present
    }

    fn document_id(&mut self, document_index: usize) -> Option<u64> {
        match &mut self.mode {
            CindelNativeDocumentReaderMode::Batch { ids, .. } => ids.get(document_index).copied(),
            CindelNativeDocumentReaderMode::SqliteCursor { cursor, .. } => {
                cursor.document_id(document_index)
            }
            CindelNativeDocumentReaderMode::SqliteQueryCursor { cursor, .. } => {
                cursor.document_id(document_index)
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxCursor { cursor, .. } => {
                cursor.document_id(document_index).ok().flatten()
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxQueryCursor { cursor, .. } => {
                cursor.document_id(document_index).ok().flatten()
            }
            CindelNativeDocumentReaderMode::RawList { .. } => None,
        }
    }

    fn read_bool(&mut self, document_index: usize, field_index: usize) -> Option<bool> {
        match &mut self.mode {
            CindelNativeDocumentReaderMode::Batch {
                layout,
                documents,
                trusted_static_size,
                ..
            } => {
                layout.require_field(field_index, NativeBatchFieldType::Bool)?;
                let bytes =
                    batch_document_bytes(layout, documents, *trusted_static_size, document_index)?;
                let offset = layout.absolute_offset(field_index)?;
                match *bytes.get(offset)? {
                    0 => Some(false),
                    1 => Some(true),
                    _ => None,
                }
            }
            CindelNativeDocumentReaderMode::SqliteCursor { layout, cursor } => {
                layout.require_field(field_index, NativeBatchFieldType::Bool)?;
                cursor.read_bool(document_index, field_index)
            }
            CindelNativeDocumentReaderMode::SqliteQueryCursor { layout, cursor } => {
                layout.require_field(field_index, NativeBatchFieldType::Bool)?;
                cursor.read_bool(document_index, field_index)
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxCursor { layout, cursor } => {
                layout.require_field(field_index, NativeBatchFieldType::Bool)?;
                let bytes = cursor.document_bytes(document_index).ok()??;
                let offset = layout.absolute_offset(field_index)?;
                match *bytes.get(offset)? {
                    0 => Some(false),
                    1 => Some(true),
                    _ => None,
                }
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxQueryCursor { layout, cursor } => {
                layout.require_field(field_index, NativeBatchFieldType::Bool)?;
                let bytes = cursor.document_bytes(document_index).ok()??;
                let offset = layout.absolute_offset(field_index)?;
                match *bytes.get(offset)? {
                    0 => Some(false),
                    1 => Some(true),
                    _ => None,
                }
            }
            CindelNativeDocumentReaderMode::RawList { bytes, entries } => {
                let entry = entries.get(field_index)?;
                if entry.is_null || entry.kind != NATIVE_VALUE_BOOL || entry.payload_len != 1 {
                    return None;
                }
                Some(*bytes.get(entry.payload_start)? != 0)
            }
        }
    }

    fn read_int(&mut self, document_index: usize, field_index: usize) -> Option<i64> {
        match &mut self.mode {
            CindelNativeDocumentReaderMode::Batch {
                layout,
                documents,
                trusted_static_size,
                ..
            } => {
                layout.require_field(field_index, NativeBatchFieldType::Int)?;
                let bytes =
                    batch_document_bytes(layout, documents, *trusted_static_size, document_index)?;
                let offset = layout.absolute_offset(field_index)?;
                let value = i64::from_le_bytes(bytes.get(offset..offset + 8)?.try_into().ok()?);
                if value == i64::MIN {
                    None
                } else {
                    Some(value)
                }
            }
            CindelNativeDocumentReaderMode::SqliteCursor { layout, cursor } => {
                layout.require_field(field_index, NativeBatchFieldType::Int)?;
                cursor.read_int(document_index, field_index)
            }
            CindelNativeDocumentReaderMode::SqliteQueryCursor { layout, cursor } => {
                layout.require_field(field_index, NativeBatchFieldType::Int)?;
                cursor.read_int(document_index, field_index)
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxCursor { layout, cursor } => {
                layout.require_field(field_index, NativeBatchFieldType::Int)?;
                let bytes = cursor.document_bytes(document_index).ok()??;
                let offset = layout.absolute_offset(field_index)?;
                let value = i64::from_le_bytes(bytes.get(offset..offset + 8)?.try_into().ok()?);
                if value == i64::MIN {
                    None
                } else {
                    Some(value)
                }
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxQueryCursor { layout, cursor } => {
                layout.require_field(field_index, NativeBatchFieldType::Int)?;
                let bytes = cursor.document_bytes(document_index).ok()??;
                let offset = layout.absolute_offset(field_index)?;
                let value = i64::from_le_bytes(bytes.get(offset..offset + 8)?.try_into().ok()?);
                if value == i64::MIN {
                    None
                } else {
                    Some(value)
                }
            }
            CindelNativeDocumentReaderMode::RawList { bytes, entries } => {
                let entry = entries.get(field_index)?;
                if entry.is_null
                    || !matches!(
                        entry.kind,
                        NATIVE_VALUE_INT | NATIVE_VALUE_DATETIME | NATIVE_VALUE_DURATION
                    )
                    || entry.payload_len != 8
                {
                    return None;
                }
                Some(i64::from_le_bytes(
                    bytes
                        .get(entry.payload_start..entry.payload_start + 8)?
                        .try_into()
                        .ok()?,
                ))
            }
        }
    }

    fn read_double(&mut self, document_index: usize, field_index: usize) -> Option<f64> {
        match &mut self.mode {
            CindelNativeDocumentReaderMode::Batch {
                layout,
                documents,
                trusted_static_size,
                ..
            } => {
                layout.require_field(field_index, NativeBatchFieldType::Double)?;
                let bytes =
                    batch_document_bytes(layout, documents, *trusted_static_size, document_index)?;
                let offset = layout.absolute_offset(field_index)?;
                let value = f64::from_le_bytes(bytes.get(offset..offset + 8)?.try_into().ok()?);
                if value.is_finite() {
                    Some(value)
                } else {
                    None
                }
            }
            CindelNativeDocumentReaderMode::SqliteCursor { layout, cursor } => {
                layout.require_field(field_index, NativeBatchFieldType::Double)?;
                cursor.read_double(document_index, field_index)
            }
            CindelNativeDocumentReaderMode::SqliteQueryCursor { layout, cursor } => {
                layout.require_field(field_index, NativeBatchFieldType::Double)?;
                cursor.read_double(document_index, field_index)
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxCursor { layout, cursor } => {
                layout.require_field(field_index, NativeBatchFieldType::Double)?;
                let bytes = cursor.document_bytes(document_index).ok()??;
                let offset = layout.absolute_offset(field_index)?;
                let value = f64::from_le_bytes(bytes.get(offset..offset + 8)?.try_into().ok()?);
                if value.is_finite() {
                    Some(value)
                } else {
                    None
                }
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxQueryCursor { layout, cursor } => {
                layout.require_field(field_index, NativeBatchFieldType::Double)?;
                let bytes = cursor.document_bytes(document_index).ok()??;
                let offset = layout.absolute_offset(field_index)?;
                let value = f64::from_le_bytes(bytes.get(offset..offset + 8)?.try_into().ok()?);
                if value.is_finite() {
                    Some(value)
                } else {
                    None
                }
            }
            CindelNativeDocumentReaderMode::RawList { bytes, entries } => {
                let entry = entries.get(field_index)?;
                if entry.is_null || entry.kind != NATIVE_VALUE_DOUBLE || entry.payload_len != 8 {
                    return None;
                }
                let value = f64::from_le_bytes(
                    bytes
                        .get(entry.payload_start..entry.payload_start + 8)?
                        .try_into()
                        .ok()?,
                );
                if value.is_finite() {
                    Some(value)
                } else {
                    None
                }
            }
        }
    }

    fn read_bytes(&mut self, document_index: usize, field_index: usize) -> Option<&[u8]> {
        match &mut self.mode {
            CindelNativeDocumentReaderMode::Batch {
                layout,
                documents,
                trusted_static_size,
                ..
            } => {
                match layout.field_type(field_index)? {
                    NativeBatchFieldType::String
                    | NativeBatchFieldType::List
                    | NativeBatchFieldType::Object => {}
                    _ => return None,
                }
                let bytes =
                    batch_document_bytes(layout, documents, *trusted_static_size, document_index)?;
                let offset = layout.absolute_offset(field_index)?;
                let relative = read_u24(bytes, offset)?;
                if relative == 0 {
                    return None;
                }
                let header_offset = 3usize.checked_add(relative)?;
                let len = read_u24(bytes, header_offset)?;
                let start = header_offset.checked_add(3)?;
                let end = start.checked_add(len)?;
                bytes.get(start..end)
            }
            CindelNativeDocumentReaderMode::SqliteCursor { layout, cursor } => {
                match layout.field_type(field_index)? {
                    NativeBatchFieldType::String
                    | NativeBatchFieldType::List
                    | NativeBatchFieldType::Object => {}
                    _ => return None,
                }
                cursor.read_bytes(document_index, field_index)
            }
            CindelNativeDocumentReaderMode::SqliteQueryCursor { layout, cursor } => {
                match layout.field_type(field_index)? {
                    NativeBatchFieldType::String
                    | NativeBatchFieldType::List
                    | NativeBatchFieldType::Object => {}
                    _ => return None,
                }
                cursor.read_bytes(document_index, field_index)
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxCursor { layout, cursor } => {
                match layout.field_type(field_index)? {
                    NativeBatchFieldType::String
                    | NativeBatchFieldType::List
                    | NativeBatchFieldType::Object => {}
                    _ => return None,
                }
                let bytes = cursor.document_bytes(document_index).ok()??;
                let offset = layout.absolute_offset(field_index)?;
                let relative = read_u24(bytes, offset)?;
                if relative == 0 {
                    return None;
                }
                let header_offset = 3usize.checked_add(relative)?;
                let len = read_u24(bytes, header_offset)?;
                let start = header_offset.checked_add(3)?;
                let end = start.checked_add(len)?;
                bytes.get(start..end)
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxQueryCursor { layout, cursor } => {
                match layout.field_type(field_index)? {
                    NativeBatchFieldType::String
                    | NativeBatchFieldType::List
                    | NativeBatchFieldType::Object => {}
                    _ => return None,
                }
                let bytes = cursor.document_bytes(document_index).ok()??;
                let offset = layout.absolute_offset(field_index)?;
                let relative = read_u24(bytes, offset)?;
                if relative == 0 {
                    return None;
                }
                let header_offset = 3usize.checked_add(relative)?;
                let len = read_u24(bytes, header_offset)?;
                let start = header_offset.checked_add(3)?;
                let end = start.checked_add(len)?;
                bytes.get(start..end)
            }
            CindelNativeDocumentReaderMode::RawList { bytes, entries } => {
                let entry = entries.get(field_index)?;
                if entry.is_null || !matches!(entry.kind, NATIVE_VALUE_STRING | NATIVE_VALUE_ENUM) {
                    return None;
                }
                let end = entry.payload_start.checked_add(entry.payload_len)?;
                bytes.get(entry.payload_start..end)
            }
        }
    }

    fn read_list(&mut self, document_index: usize, field_index: usize) -> Option<NativeRawList> {
        match &mut self.mode {
            CindelNativeDocumentReaderMode::Batch { .. } => {
                parse_native_raw_list(self.read_bytes(document_index, field_index)?).ok()
            }
            CindelNativeDocumentReaderMode::SqliteCursor { .. } => {
                parse_native_raw_list(self.read_bytes(document_index, field_index)?).ok()
            }
            CindelNativeDocumentReaderMode::SqliteQueryCursor { .. } => {
                parse_native_raw_list(self.read_bytes(document_index, field_index)?).ok()
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxCursor { .. } => {
                parse_native_raw_list(self.read_bytes(document_index, field_index)?).ok()
            }
            #[cfg(feature = "mdbx")]
            CindelNativeDocumentReaderMode::MdbxQueryCursor { .. } => {
                parse_native_raw_list(self.read_bytes(document_index, field_index)?).ok()
            }
            CindelNativeDocumentReaderMode::RawList { bytes, entries } => {
                let entry = entries.get(field_index)?;
                if entry.is_null || entry.kind != NATIVE_VALUE_LIST {
                    return None;
                }
                let end = entry.payload_start.checked_add(entry.payload_len)?;
                parse_native_raw_list(bytes.get(entry.payload_start..end)?).ok()
            }
        }
    }
}

fn batch_document_bytes<'a>(
    layout: &NativeBatchLayout,
    documents: &'a [Option<Vec<u8>>],
    trusted_static_size: bool,
    document_index: usize,
) -> Option<&'a [u8]> {
    let bytes = documents.get(document_index)?.as_deref()?;
    if !trusted_static_size {
        let static_size = read_u24(bytes, 0)?;
        if static_size != layout.static_size {
            return None;
        }
        if bytes.len() < 3 + static_size {
            return None;
        }
    }
    Some(bytes)
}

fn parse_native_raw_list(bytes: &[u8]) -> Result<NativeRawList, String> {
    if is_native_compact_string_list(bytes)? {
        return parse_native_compact_string_list(bytes);
    }
    if let Ok(list) = parse_native_nested_string_list(bytes) {
        return Ok(list);
    }
    let count = read_u32_le(bytes, 0)? as usize;
    let mut offset = 4usize;
    let mut entries = Vec::with_capacity(count);
    for _ in 0..count {
        let header = read_native_slice(bytes, offset, 8)?;
        let kind = header[0];
        let flags = header[1];
        let payload_len = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as usize;
        offset += 8;
        let payload_start = offset;
        let payload_end = payload_start
            .checked_add(payload_len)
            .ok_or_else(|| "native list value payload offset overflow".to_string())?;
        read_native_slice(bytes, payload_start, payload_len)?;
        offset = payload_end;
        entries.push(NativeRawListEntry {
            kind,
            is_null: flags & NATIVE_VALUE_NULL_FLAG != 0 || kind == NATIVE_VALUE_NULL,
            payload_start,
            payload_len,
        });
    }
    if offset != bytes.len() {
        return Err("native list contains trailing bytes".into());
    }
    Ok(NativeRawList {
        bytes: bytes.to_vec(),
        entries,
    })
}

fn parse_native_nested_string_list(bytes: &[u8]) -> Result<NativeRawList, String> {
    if bytes.len() < 3 {
        return Err("native nested string list is shorter than the header".into());
    }
    let static_size = read_u24_le(bytes, 0)? as usize;
    if static_size % 3 != 0 {
        return Err("native nested string list static size is not aligned".into());
    }
    let static_end = 3usize
        .checked_add(static_size)
        .ok_or_else(|| "native nested string list static section overflows".to_string())?;
    read_native_slice(bytes, 0, static_end)?;
    let count = static_size / 3;
    let mut entries = Vec::with_capacity(count);
    let mut max_end = static_end;
    for index in 0..count {
        let offset = read_u24_le(bytes, 3 + index * 3)? as usize;
        if offset == 0 {
            entries.push(NativeRawListEntry {
                kind: NATIVE_VALUE_NULL,
                is_null: true,
                payload_start: 0,
                payload_len: 0,
            });
            continue;
        }
        if offset < static_size {
            return Err("native nested string list payload points into offsets".into());
        }
        let absolute = 3usize
            .checked_add(offset)
            .ok_or_else(|| "native nested string list payload offset overflow".to_string())?;
        let len = read_u24_le(bytes, absolute)? as usize;
        let payload_start = absolute
            .checked_add(3)
            .ok_or_else(|| "native nested string list payload offset overflow".to_string())?;
        let payload_end = payload_start
            .checked_add(len)
            .ok_or_else(|| "native nested string list payload length overflow".to_string())?;
        read_native_slice(bytes, payload_start, len)?;
        max_end = max_end.max(payload_end);
        entries.push(NativeRawListEntry {
            kind: NATIVE_VALUE_STRING,
            is_null: false,
            payload_start,
            payload_len: len,
        });
    }
    if max_end != bytes.len() {
        return Err("native nested string list contains trailing bytes".into());
    }
    Ok(NativeRawList {
        bytes: bytes.to_vec(),
        entries,
    })
}

fn is_native_compact_string_list(bytes: &[u8]) -> Result<bool, String> {
    if bytes.len() < 9 {
        return Ok(false);
    }
    Ok(read_u32_le(bytes, 0)? == u32::MAX && bytes[4] == 1)
}

fn parse_native_compact_string_list(bytes: &[u8]) -> Result<NativeRawList, String> {
    let count = read_u32_le(bytes, 5)? as usize;
    let offsets_start = 9usize;
    let offsets_len = count
        .checked_mul(3)
        .ok_or_else(|| "native compact string list offsets overflow".to_string())?;
    read_native_slice(bytes, offsets_start, offsets_len)?;
    let mut entries = Vec::with_capacity(count);
    let mut max_end = offsets_start + offsets_len;
    for index in 0..count {
        let offset = read_u24_le(bytes, offsets_start + index * 3)? as usize;
        if offset == 0 {
            entries.push(NativeRawListEntry {
                kind: NATIVE_VALUE_NULL,
                is_null: true,
                payload_start: 0,
                payload_len: 0,
            });
            continue;
        }
        if offset < offsets_start + offsets_len {
            return Err("native compact string list payload points into offsets".into());
        }
        let len = read_u24_le(bytes, offset)? as usize;
        let payload_start = offset
            .checked_add(3)
            .ok_or_else(|| "native compact string list payload offset overflow".to_string())?;
        let payload_end = payload_start
            .checked_add(len)
            .ok_or_else(|| "native compact string list payload length overflow".to_string())?;
        read_native_slice(bytes, payload_start, len)?;
        max_end = max_end.max(payload_end);
        entries.push(NativeRawListEntry {
            kind: NATIVE_VALUE_STRING,
            is_null: false,
            payload_start,
            payload_len: len,
        });
    }
    if max_end != bytes.len() {
        return Err("native compact string list contains trailing bytes".into());
    }
    Ok(NativeRawList {
        bytes: bytes.to_vec(),
        entries,
    })
}

fn read_u32_le(bytes: &[u8], offset: usize) -> Result<u32, String> {
    let bytes = read_native_slice(bytes, offset, 4)?;
    Ok(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
}

fn read_u24_le(bytes: &[u8], offset: usize) -> Result<u32, String> {
    let bytes = read_native_slice(bytes, offset, 3)?;
    Ok(bytes[0] as u32 | ((bytes[1] as u32) << 8) | ((bytes[2] as u32) << 16))
}

fn read_native_slice(bytes: &[u8], offset: usize, len: usize) -> Result<&[u8], String> {
    let end = offset
        .checked_add(len)
        .ok_or_else(|| "native list offset overflow".to_string())?;
    bytes
        .get(offset..end)
        .ok_or_else(|| "native list is truncated".to_string())
}

impl NativeBatchLayout {
    fn new(field_type_bytes: &[u8]) -> Result<Self, String> {
        let mut field_types = Vec::with_capacity(field_type_bytes.len());
        let mut offsets = Vec::with_capacity(field_type_bytes.len());
        let mut static_size = 0usize;
        for value in field_type_bytes {
            let field_type = NativeBatchFieldType::from_byte(*value)?;
            offsets.push(static_size);
            static_size = static_size
                .checked_add(field_type.static_size())
                .ok_or_else(|| "native document layout static size overflow".to_string())?;
            field_types.push(field_type);
        }
        if static_size > 0x00ff_ffff {
            return Err("native document layout static section is too large".into());
        }
        let mut null_static_bytes = vec![0; 3 + static_size];
        write_u24(&mut null_static_bytes, 0, static_size)?;
        for index in 0..field_types.len() {
            write_null_for_field(&field_types, &offsets, &mut null_static_bytes, index)?;
        }
        Ok(Self {
            field_types,
            offsets,
            static_size,
            null_static_bytes,
        })
    }

    fn field_type(&self, index: usize) -> Option<NativeBatchFieldType> {
        self.field_types.get(index).copied()
    }

    fn require_field(&self, index: usize, expected: NativeBatchFieldType) -> Option<()> {
        if self.field_type(index)? == expected {
            Some(())
        } else {
            None
        }
    }

    fn absolute_offset(&self, index: usize) -> Option<usize> {
        self.offsets.get(index).map(|offset| 3 + *offset)
    }

    fn field_type_result(&self, index: usize) -> Result<NativeBatchFieldType, String> {
        self.field_type(index)
            .ok_or_else(|| format!("native batch writer field index `{index}` is out of range"))
    }

    fn absolute_offset_result(&self, index: usize) -> Result<usize, String> {
        self.absolute_offset(index)
            .ok_or_else(|| format!("native batch writer field index `{index}` is out of range"))
    }
}

impl NativeBatchFieldType {
    fn from_byte(value: u8) -> Result<Self, String> {
        match value {
            0 => Ok(Self::Bool),
            1 => Ok(Self::Int),
            2 => Ok(Self::Double),
            3 => Ok(Self::String),
            4 => Ok(Self::List),
            5 => Ok(Self::Object),
            _ => Err(format!("unknown native batch writer field type `{value}`")),
        }
    }

    fn static_size(self) -> usize {
        match self {
            Self::Bool => 1,
            Self::Int | Self::Double => 8,
            Self::String | Self::List | Self::Object => 3,
        }
    }
}

fn write_null_for_field(
    field_types: &[NativeBatchFieldType],
    offsets: &[usize],
    bytes: &mut [u8],
    index: usize,
) -> Result<(), String> {
    let field_type = field_types
        .get(index)
        .copied()
        .ok_or_else(|| format!("native batch writer field index `{index}` is out of range"))?;
    let absolute = 3 + offsets
        .get(index)
        .copied()
        .ok_or_else(|| format!("native batch writer field index `{index}` is out of range"))?;
    match field_type {
        NativeBatchFieldType::Bool => bytes[absolute] = 0xff,
        NativeBatchFieldType::Int => {
            bytes[absolute..absolute + 8].copy_from_slice(&i64::MIN.to_le_bytes())
        }
        NativeBatchFieldType::Double => {
            bytes[absolute..absolute + 8].copy_from_slice(&0x7ff8_0000_0000_0001u64.to_le_bytes())
        }
        NativeBatchFieldType::String
        | NativeBatchFieldType::List
        | NativeBatchFieldType::Object => write_u24(bytes, absolute, 0)?,
    }
    Ok(())
}

fn write_u24(bytes: &mut [u8], offset: usize, value: usize) -> Result<(), String> {
    if value > 0x00ff_ffff || offset + 3 > bytes.len() {
        return Err("native batch writer uint24 write is out of range".into());
    }
    bytes[offset] = (value & 0xff) as u8;
    bytes[offset + 1] = ((value >> 8) & 0xff) as u8;
    bytes[offset + 2] = ((value >> 16) & 0xff) as u8;
    Ok(())
}

fn read_u24(bytes: &[u8], offset: usize) -> Option<usize> {
    if offset + 3 > bytes.len() {
        return None;
    }
    Some(
        bytes[offset] as usize
            | ((bytes[offset + 1] as usize) << 8)
            | ((bytes[offset + 2] as usize) << 16),
    )
}

unsafe fn read_index_entries(ptr: *const u8, len: usize) -> Result<Vec<IndexEntry>, ()> {
    if len == 0 {
        return Ok(Vec::new());
    }
    let bytes = read_bytes(ptr, len).ok_or(())?;
    decode_index_entry_list(bytes)
        .map_err(|_| ())?
        .into_iter()
        .map(WireBatchIndexEntry::into_index_entry)
        .collect()
}

unsafe fn read_document_writes(ptr: *const u8, len: usize) -> Result<Vec<DocumentWrite>, ()> {
    if len == 0 {
        return Ok(Vec::new());
    }
    let bytes = read_bytes(ptr, len).ok_or(())?;
    decode_indexed_document_write_batch(bytes)
        .map_err(|_| ())?
        .into_iter()
        .map(WireBatchIndexedDocumentWrite::into_document_write)
        .collect()
}

unsafe fn read_binary_document_writes(
    ptr: *const u8,
    len: usize,
) -> Result<Vec<DocumentWrite>, ()> {
    let bytes = read_bytes(ptr, len).ok_or(())?;
    decode_document_write_batch(bytes)
        .map_err(|_| ())?
        .into_iter()
        .map(WireBatchDocumentWrite::into_document_write)
        .collect()
}

unsafe fn read_wire_ids(ptr: *const u8, len: usize) -> Option<Vec<u64>> {
    let bytes = read_bytes(ptr, len)?;
    decode_id_list(bytes).ok()
}

unsafe fn read_query_plan(ptr: *const u8, len: usize) -> Result<WireQueryPlan, ()> {
    let bytes = read_bytes(ptr, len).ok_or(())?;
    decode_query_plan(bytes).map_err(|_| ())
}

unsafe fn read_index_value(ptr: *const u8, len: usize) -> Result<IndexValue, ()> {
    let bytes = read_bytes(ptr, len).ok_or(())?;
    decode_index_value(bytes)
        .map_err(|_| ())?
        .into_index_value()
}

unsafe fn read_optional_index_value(ptr: *const u8, len: usize) -> Result<Option<IndexValue>, ()> {
    let bytes = read_optional_bytes(ptr, len).ok_or(())?;
    if bytes.is_empty() {
        return Ok(None);
    }
    decode_index_value(bytes)
        .map_err(|_| ())?
        .into_index_value()
        .map(Some)
}

impl WireBatchDocumentWrite {
    fn into_document_write(self) -> Result<DocumentWrite, ()> {
        Ok(DocumentWrite {
            id: self.id,
            bytes: self.bytes,
            indexes: Vec::new(),
        })
    }
}

impl WireBatchIndexedDocumentWrite {
    fn into_document_write(self) -> Result<DocumentWrite, ()> {
        let indexes = self
            .indexes
            .into_iter()
            .map(WireBatchIndexEntry::into_index_entry)
            .collect::<Result<Vec<_>, _>>()?;
        Ok(DocumentWrite {
            id: self.id,
            bytes: self.bytes,
            indexes,
        })
    }
}

impl WireBatchIndexEntry {
    fn into_index_entry(self) -> Result<IndexEntry, ()> {
        Ok(IndexEntry {
            name: self.index_name,
            value: self.value.into_index_value()?,
        })
    }
}

impl WireBatchIndexValue {
    fn into_index_value(self) -> Result<IndexValue, ()> {
        match self {
            WireBatchIndexValue::Null => Err(()),
            WireBatchIndexValue::Bool(value) => Ok(IndexValue::Bool(value)),
            WireBatchIndexValue::Int(value) => Ok(IndexValue::Int(value)),
            WireBatchIndexValue::Double(value) if value.is_finite() => {
                Ok(IndexValue::Double(value))
            }
            WireBatchIndexValue::Double(_) => Err(()),
            WireBatchIndexValue::String(value) => Ok(IndexValue::String(value)),
            WireBatchIndexValue::List(values) => values
                .into_iter()
                .map(WireBatchIndexValue::into_index_value)
                .collect::<Result<Vec<_>, _>>()
                .map(IndexValue::List),
        }
    }
}
