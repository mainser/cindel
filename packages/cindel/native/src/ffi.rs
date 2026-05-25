use crate::engine::CindelEngine;
use crate::storage::{
    schema_manifest_from_wire, DocumentWrite, IndexEntry, IndexValue, StorageBackendKind,
};
use crate::wire::{
    decode_document_write_batch, decode_id_list, decode_index_entry_list, decode_index_value,
    decode_indexed_document_write_batch, decode_query_plan, encode_change_set_list, encode_id_list,
    encode_scalar, WireChangeSet, WireDocumentWrite as WireBatchDocumentWrite,
    WireIndexEntry as WireBatchIndexEntry, WireIndexValue as WireBatchIndexValue,
    WireIndexedDocumentWrite as WireBatchIndexedDocumentWrite, WireQueryPlan, WireScalar,
};
use std::cell::RefCell;

#[no_mangle]
pub extern "C" fn cindel_abi_version() -> u32 {
    23
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
) -> *mut CindelNativeBatchWriter {
    let Some(field_type_bytes) = read_bytes(field_types_ptr, field_types_len) else {
        return std::ptr::null_mut();
    };
    let Ok(writer) = CindelNativeBatchWriter::new(field_type_bytes, capacity) else {
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
    if writer.failed || writer.current.is_some() {
        return -1;
    }
    match engine.put_many_indexed(collection, &writer.documents) {
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
    if writer.failed || writer.current.is_some() {
        return -1;
    }
    match engine.put_many_indexed_with_options(
        collection,
        &writer.documents,
        track_changes != 0,
        true,
    ) {
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
    let Ok(documents) = engine.get_many_stored(collection, &ids) else {
        return std::ptr::null_mut();
    };
    Box::into_raw(Box::new(CindelNativeDocumentReader {
        layout,
        documents,
        string_cache: RefCell::new(NativeStringCache::default()),
    }))
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
    let Ok(documents) = engine.query_plan_documents(collection, &plan) else {
        return std::ptr::null_mut();
    };
    Box::into_raw(Box::new(CindelNativeDocumentReader {
        layout,
        documents: documents.into_iter().map(Some).collect(),
        string_cache: RefCell::new(NativeStringCache::default()),
    }))
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_len(
    reader: *const CindelNativeDocumentReader,
) -> usize {
    let Some(reader) = reader.as_ref() else {
        return 0;
    };
    reader.documents.len()
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_is_present(
    reader: *const CindelNativeDocumentReader,
    document_index: usize,
) -> bool {
    let Some(reader) = reader.as_ref() else {
        return false;
    };
    reader
        .documents
        .get(document_index)
        .is_some_and(Option::is_some)
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_bool(
    reader: *const CindelNativeDocumentReader,
    document_index: usize,
    field_index: u32,
    out_value: *mut bool,
) -> bool {
    let Some(reader) = reader.as_ref() else {
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
pub unsafe extern "C" fn cindel_native_document_reader_read_int(
    reader: *const CindelNativeDocumentReader,
    document_index: usize,
    field_index: u32,
    out_value: *mut i64,
) -> bool {
    if out_value.is_null() {
        return false;
    }
    let Some(reader) = reader.as_ref() else {
        return false;
    };
    let Some(value) = reader.read_int(document_index, field_index as usize) else {
        return false;
    };
    *out_value = value;
    true
}

#[no_mangle]
pub unsafe extern "C" fn cindel_native_document_reader_read_double(
    reader: *const CindelNativeDocumentReader,
    document_index: usize,
    field_index: u32,
    out_value: *mut f64,
) -> bool {
    let Some(reader) = reader.as_ref() else {
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
pub unsafe extern "C" fn cindel_native_document_reader_read_bytes(
    reader: *const CindelNativeDocumentReader,
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
    let Some(reader) = reader.as_ref() else {
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
pub unsafe extern "C" fn cindel_native_document_reader_read_string(
    reader: *const CindelNativeDocumentReader,
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
    let Some(reader) = reader.as_ref() else {
        return false;
    };
    let Some(bytes) = reader.read_bytes(document_index, field_index as usize) else {
        return false;
    };
    *out_ptr = bytes.as_ptr();
    *out_len = bytes.len();
    *out_is_ascii = bytes.is_ascii();
    *out_intern_id = reader
        .string_cache
        .borrow_mut()
        .intern_id(field_index as usize, bytes);
    true
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
    layout: NativeBatchLayout,
    documents: Vec<DocumentWrite>,
    current: Option<NativeBatchDocumentBuilder>,
    failed: bool,
}

pub struct CindelNativeDocumentReader {
    layout: NativeBatchLayout,
    documents: Vec<Option<Vec<u8>>>,
    string_cache: RefCell<NativeStringCache>,
}

#[derive(Default)]
struct NativeStringCache {
    entries: Vec<NativeStringCacheEntry>,
    next_id: u64,
}

struct NativeStringCacheEntry {
    id: u64,
    field_index: usize,
    bytes: Vec<u8>,
}

impl NativeStringCache {
    fn intern_id(&mut self, field_index: usize, bytes: &[u8]) -> u64 {
        if bytes.len() < 128 {
            return 0;
        }
        for entry in self.entries.iter() {
            if entry.field_index == field_index && entry.bytes == bytes {
                return entry.id;
            }
        }
        self.next_id = self.next_id.saturating_add(1);
        let id = self.next_id;
        if self.entries.len() == 8 {
            self.entries.remove(0);
        }
        self.entries.push(NativeStringCacheEntry {
            id,
            field_index,
            bytes: bytes.to_vec(),
        });
        id
    }
}

struct NativeBatchLayout {
    field_types: Vec<NativeBatchFieldType>,
    offsets: Vec<usize>,
    static_size: usize,
    null_static_bytes: Vec<u8>,
}

struct NativeBatchDocumentBuilder {
    id: u64,
    bytes: Vec<u8>,
}

impl CindelNativeBatchWriter {
    fn new(field_type_bytes: &[u8], capacity: usize) -> Result<Self, String> {
        let layout = NativeBatchLayout::new(field_type_bytes)?;
        Ok(Self {
            layout,
            documents: Vec::with_capacity(capacity),
            current: None,
            failed: false,
        })
    }

    fn record(&mut self, action: impl FnOnce(&mut Self) -> Result<(), String>) {
        if self.failed {
            return;
        }
        if action(self).is_err() {
            self.failed = true;
        }
    }

    fn begin_document(&mut self, id: u64) -> Result<(), String> {
        if self.current.is_some() {
            return Err("native batch writer already has an open document".into());
        }
        let bytes = self.layout.null_static_bytes.clone();
        self.current = Some(NativeBatchDocumentBuilder { id, bytes });
        Ok(())
    }

    fn write_null(&mut self, index: usize) -> Result<(), String> {
        let (field_types, offsets) = (&self.layout.field_types, &self.layout.offsets);
        let Some(current) = self.current.as_mut() else {
            return Err("native batch writer has no open document".into());
        };
        write_null_for_field(field_types, offsets, &mut current.bytes, index)
    }

    fn write_bool(&mut self, index: usize, value: bool) -> Result<(), String> {
        self.require_field(index, NativeBatchFieldType::Bool)?;
        let offset = self.absolute_offset(index)?;
        let current = self.current_mut()?;
        current.bytes[offset] = if value { 1 } else { 0 };
        Ok(())
    }

    fn write_int(&mut self, index: usize, value: i64) -> Result<(), String> {
        self.require_field(index, NativeBatchFieldType::Int)?;
        if value == i64::MIN {
            return Err("native batch writer cannot store the int null sentinel".into());
        }
        let offset = self.absolute_offset(index)?;
        let current = self.current_mut()?;
        current.bytes[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
        Ok(())
    }

    fn write_double(&mut self, index: usize, value: f64) -> Result<(), String> {
        self.require_field(index, NativeBatchFieldType::Double)?;
        if !value.is_finite() {
            return Err("native batch writer double values must be finite".into());
        }
        let offset = self.absolute_offset(index)?;
        let current = self.current_mut()?;
        current.bytes[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
        Ok(())
    }

    fn write_bytes(&mut self, index: usize, payload: &[u8]) -> Result<(), String> {
        match self.field_type(index)? {
            NativeBatchFieldType::String
            | NativeBatchFieldType::List
            | NativeBatchFieldType::Object => {}
            _ => return Err("native batch writer expected a dynamic field".into()),
        }
        if payload.len() > 0x00ff_ffff {
            return Err("native batch writer dynamic payload is too large".into());
        }
        let static_size = self.layout.static_size;
        let offset = self.absolute_offset(index)?;
        let current = self.current_mut()?;
        let relative = static_size
            .checked_add(current.bytes.len().saturating_sub(3 + static_size))
            .ok_or_else(|| "native batch writer dynamic offset overflow".to_string())?;
        if relative > 0x00ff_ffff {
            return Err("native batch writer dynamic offset is too large".into());
        }
        write_u24(&mut current.bytes, offset, relative)?;
        let mut header = [0u8; 3];
        write_u24(&mut header, 0, payload.len())?;
        current.bytes.extend_from_slice(&header);
        current.bytes.extend_from_slice(payload);
        Ok(())
    }

    fn end_document(&mut self) -> Result<(), String> {
        let Some(current) = self.current.take() else {
            return Err("native batch writer has no open document".into());
        };
        self.documents.push(DocumentWrite {
            id: current.id,
            bytes: current.bytes,
            indexes: Vec::new(),
        });
        Ok(())
    }

    fn current_mut(&mut self) -> Result<&mut NativeBatchDocumentBuilder, String> {
        self.current
            .as_mut()
            .ok_or_else(|| "native batch writer has no open document".to_string())
    }

    fn field_type(&self, index: usize) -> Result<NativeBatchFieldType, String> {
        self.layout
            .field_types
            .get(index)
            .copied()
            .ok_or_else(|| format!("native batch writer field index `{index}` is out of range"))
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
        self.layout
            .offsets
            .get(index)
            .map(|offset| 3 + *offset)
            .ok_or_else(|| format!("native batch writer field index `{index}` is out of range"))
    }
}

impl CindelNativeDocumentReader {
    fn read_bool(&self, document_index: usize, field_index: usize) -> Option<bool> {
        self.layout
            .require_field(field_index, NativeBatchFieldType::Bool)?;
        let bytes = self.document_bytes(document_index)?;
        let offset = self.layout.absolute_offset(field_index)?;
        match *bytes.get(offset)? {
            0 => Some(false),
            1 => Some(true),
            _ => None,
        }
    }

    fn read_int(&self, document_index: usize, field_index: usize) -> Option<i64> {
        self.layout
            .require_field(field_index, NativeBatchFieldType::Int)?;
        let bytes = self.document_bytes(document_index)?;
        let offset = self.layout.absolute_offset(field_index)?;
        let value = i64::from_le_bytes(bytes.get(offset..offset + 8)?.try_into().ok()?);
        if value == i64::MIN {
            None
        } else {
            Some(value)
        }
    }

    fn read_double(&self, document_index: usize, field_index: usize) -> Option<f64> {
        self.layout
            .require_field(field_index, NativeBatchFieldType::Double)?;
        let bytes = self.document_bytes(document_index)?;
        let offset = self.layout.absolute_offset(field_index)?;
        let value = f64::from_le_bytes(bytes.get(offset..offset + 8)?.try_into().ok()?);
        if value.is_finite() {
            Some(value)
        } else {
            None
        }
    }

    fn read_bytes(&self, document_index: usize, field_index: usize) -> Option<&[u8]> {
        match self.layout.field_type(field_index)? {
            NativeBatchFieldType::String
            | NativeBatchFieldType::List
            | NativeBatchFieldType::Object => {}
            _ => return None,
        }
        let bytes = self.document_bytes(document_index)?;
        let offset = self.layout.absolute_offset(field_index)?;
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

    fn document_bytes(&self, document_index: usize) -> Option<&[u8]> {
        let bytes = self.documents.get(document_index)?.as_deref()?;
        let static_size = read_u24(bytes, 0)?;
        if static_size != self.layout.static_size {
            return None;
        }
        if bytes.len() < 3 + static_size {
            return None;
        }
        Some(bytes)
    }
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
