use crate::engine::CindelEngine;
use crate::storage::{IndexEntry, IndexValue};

use serde::Deserialize;

#[no_mangle]
pub extern "C" fn cindel_abi_version() -> u32 {
    1
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
pub unsafe extern "C" fn cindel_close(handle: *mut CindelEngine) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
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

unsafe fn read_index_entries(ptr: *const u8, len: usize) -> Result<Vec<IndexEntry>, ()> {
    if len == 0 {
        return Ok(Vec::new());
    }
    let bytes = read_bytes(ptr, len).ok_or(())?;
    let entries = serde_json::from_slice::<Vec<WireIndexEntry>>(bytes).map_err(|_| ())?;
    entries.into_iter().map(TryInto::try_into).collect()
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

#[derive(Deserialize)]
struct WireIndexEntry {
    name: String,
    value: WireIndexValue,
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
        }
    }
}
