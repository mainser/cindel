use crate::engine::CindelEngine;

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
    let Some(engine) = handle.as_ref() else {
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
pub unsafe extern "C" fn cindel_delete(
    handle: *mut CindelEngine,
    collection_ptr: *const u8,
    collection_len: usize,
    id: u64,
) -> i32 {
    let Some(engine) = handle.as_ref() else {
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

fn into_raw_bytes(bytes: Vec<u8>) -> (*mut u8, usize) {
    let mut boxed = bytes.into_boxed_slice();
    let len = boxed.len();
    let ptr = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    (ptr, len)
}
