use crate::engine::CindelEngine;

#[no_mangle]
pub extern "C" fn cindel_abi_version() -> u32 {
    1
}

#[no_mangle]
pub extern "C" fn cindel_open() -> *mut CindelEngine {
    Box::into_raw(Box::new(CindelEngine::new()))
}

#[no_mangle]
pub unsafe extern "C" fn cindel_close(handle: *mut CindelEngine) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}
