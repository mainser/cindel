use crate::engine::CindelEngine;
use crate::storage::{DocumentWrite, IndexEntry, IndexValue, SchemaManifest, StorageBackendKind};

use serde::Deserialize;

#[no_mangle]
pub extern "C" fn cindel_abi_version() -> u32 {
    9
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
    let Ok(manifest) = serde_json::from_slice::<SchemaManifest>(schemas) else {
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
    let Some(ids) = read_json_ids(ids_ptr, ids_len) else {
        return -1;
    };

    match engine.get_many(collection, &ids) {
        Ok(documents) => write_json_documents(documents, out_ptr, out_len),
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
    let Some(ids) = read_json_ids(ids_ptr, ids_len) else {
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
        Ok(ids) => write_json_ids(ids, out_ptr, out_len),
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
    let Some(ids) = read_json_ids(ids_ptr, ids_len) else {
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
        Ok(ids) => write_json_ids(ids, out_ptr, out_len),
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
        Ok(ids) => write_json_ids(ids, out_ptr, out_len),
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
    let Some(ids) = read_json_ids(ids_ptr, ids_len) else {
        return -1;
    };
    let Some(filter) = read_bytes(filter_ptr, filter_len) else {
        return -1;
    };

    match engine.query_filter(collection, &ids, filter) {
        Ok(ids) => write_json_ids(ids, out_ptr, out_len),
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
    let Some(ids) = read_json_ids(ids_ptr, ids_len) else {
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
    let Some(ids) = read_json_ids(ids_ptr, ids_len) else {
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

fn write_json_ids(ids: Vec<u64>, out_ptr: *mut *mut u8, out_len: *mut usize) -> i32 {
    match serde_json::to_vec(&ids) {
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

fn write_json_documents(
    documents: Vec<Option<Vec<u8>>>,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    let mut bytes = Vec::new();
    bytes.push(b'[');
    for (index, document) in documents.into_iter().enumerate() {
        if index > 0 {
            bytes.push(b',');
        }
        match document {
            Some(document) => bytes.extend_from_slice(&document),
            None => bytes.extend_from_slice(b"null"),
        }
    }
    bytes.push(b']');

    let (ptr, len) = into_raw_bytes(bytes);
    unsafe {
        *out_ptr = ptr;
        *out_len = len;
    }
    0
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

unsafe fn read_index_entries(ptr: *const u8, len: usize) -> Result<Vec<IndexEntry>, ()> {
    if len == 0 {
        return Ok(Vec::new());
    }
    let bytes = read_bytes(ptr, len).ok_or(())?;
    let entries = serde_json::from_slice::<Vec<WireIndexEntry>>(bytes).map_err(|_| ())?;
    entries.into_iter().map(TryInto::try_into).collect()
}

unsafe fn read_document_writes(ptr: *const u8, len: usize) -> Result<Vec<DocumentWrite>, ()> {
    if len == 0 {
        return Ok(Vec::new());
    }
    let bytes = read_bytes(ptr, len).ok_or(())?;
    let documents = serde_json::from_slice::<Vec<WireDocumentWrite>>(bytes).map_err(|_| ())?;
    documents.into_iter().map(TryInto::try_into).collect()
}

unsafe fn read_binary_document_writes(
    ptr: *const u8,
    len: usize,
) -> Result<Vec<DocumentWrite>, ()> {
    let bytes = read_bytes(ptr, len).ok_or(())?;
    if bytes.len() < 4 {
        return Err(());
    }
    let count = read_u32_le(bytes, 0)? as usize;
    let mut offset = 4;
    let mut documents = Vec::with_capacity(count);
    for _ in 0..count {
        let id = read_u64_le(bytes, offset)?;
        offset += 8;
        let document_len = read_u32_le(bytes, offset)? as usize;
        offset += 4;
        let end = offset.checked_add(document_len).ok_or(())?;
        if end > bytes.len() {
            return Err(());
        }
        documents.push(DocumentWrite {
            id,
            bytes: bytes[offset..end].to_vec(),
            indexes: Vec::new(),
        });
        offset = end;
    }
    if offset != bytes.len() {
        return Err(());
    }
    Ok(documents)
}

unsafe fn read_json_ids(ptr: *const u8, len: usize) -> Option<Vec<u64>> {
    let bytes = read_bytes(ptr, len)?;
    serde_json::from_slice::<Vec<u64>>(bytes).ok()
}

unsafe fn read_index_value(ptr: *const u8, len: usize) -> Result<IndexValue, ()> {
    let bytes = read_bytes(ptr, len).ok_or(())?;
    serde_json::from_slice::<WireIndexValue>(bytes)
        .map_err(|_| ())?
        .try_into()
}

unsafe fn read_optional_index_value(ptr: *const u8, len: usize) -> Result<Option<IndexValue>, ()> {
    let bytes = read_optional_bytes(ptr, len).ok_or(())?;
    if bytes.is_empty() {
        return Ok(None);
    }
    serde_json::from_slice::<WireIndexValue>(bytes)
        .map_err(|_| ())?
        .try_into()
        .map(Some)
}

fn read_u32_le(bytes: &[u8], offset: usize) -> Result<u32, ()> {
    let end = offset.checked_add(4).ok_or(())?;
    let slice = bytes.get(offset..end).ok_or(())?;
    Ok(u32::from_le_bytes(slice.try_into().map_err(|_| ())?))
}

fn read_u64_le(bytes: &[u8], offset: usize) -> Result<u64, ()> {
    let end = offset.checked_add(8).ok_or(())?;
    let slice = bytes.get(offset..end).ok_or(())?;
    Ok(u64::from_le_bytes(slice.try_into().map_err(|_| ())?))
}

#[derive(Deserialize)]
struct WireIndexEntry {
    name: String,
    value: WireIndexValue,
}

#[derive(Deserialize)]
struct WireDocumentWrite {
    id: u64,
    document: serde_json::Value,
    indexes: Vec<WireIndexEntry>,
}

impl TryFrom<WireDocumentWrite> for DocumentWrite {
    type Error = ();

    fn try_from(value: WireDocumentWrite) -> Result<Self, Self::Error> {
        let bytes = serde_json::to_vec(&value.document).map_err(|_| ())?;
        let indexes = value
            .indexes
            .into_iter()
            .map(TryInto::try_into)
            .collect::<Result<Vec<_>, _>>()?;
        Ok(Self {
            id: value.id,
            bytes,
            indexes,
        })
    }
}

impl TryFrom<WireIndexEntry> for IndexEntry {
    type Error = ();

    fn try_from(value: WireIndexEntry) -> Result<Self, Self::Error> {
        Ok(Self {
            name: value.name,
            value: value.value.try_into()?,
        })
    }
}

#[derive(Deserialize)]
#[serde(tag = "type", content = "value")]
enum WireIndexValue {
    #[serde(rename = "bool")]
    Bool(bool),
    #[serde(rename = "int")]
    Int(i64),
    #[serde(rename = "double")]
    Double(f64),
    #[serde(rename = "string")]
    String(String),
    #[serde(rename = "list")]
    List(Vec<WireIndexValue>),
}

impl TryFrom<WireIndexValue> for IndexValue {
    type Error = ();

    fn try_from(value: WireIndexValue) -> Result<Self, Self::Error> {
        match value {
            WireIndexValue::Bool(value) => Ok(IndexValue::Bool(value)),
            WireIndexValue::Int(value) => Ok(IndexValue::Int(value)),
            WireIndexValue::Double(value) if value.is_finite() => Ok(IndexValue::Double(value)),
            WireIndexValue::Double(_) => Err(()),
            WireIndexValue::String(value) => Ok(IndexValue::String(value)),
            WireIndexValue::List(values) => values
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<Vec<_>, _>>()
                .map(IndexValue::List),
        }
    }
}
