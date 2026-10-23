use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;

thread_local! {
    // Only the measured test thread participates; concurrent tests are excluded.
    static TRACKING: Cell<Option<(isize, usize)>> = const { Cell::new(None) };
}

fn record(delta: isize) {
    let _ = TRACKING.try_with(|tracking| {
        if let Some((live, peak)) = tracking.get() {
            let live = live + delta;
            tracking.set(Some((live, peak.max(live.max(0) as usize))));
        }
    });
}

struct TrackingAllocator;

#[global_allocator]
static ALLOCATOR: TrackingAllocator = TrackingAllocator;

unsafe impl GlobalAlloc for TrackingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let pointer = unsafe { System.alloc(layout) };
        if !pointer.is_null() {
            record(layout.size() as isize);
        }
        pointer
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let pointer = unsafe { System.alloc_zeroed(layout) };
        if !pointer.is_null() {
            record(layout.size() as isize);
        }
        pointer
    }

    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        record(-(layout.size() as isize));
        unsafe { System.dealloc(pointer, layout) };
    }

    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        let pointer = unsafe { System.realloc(pointer, layout, size) };
        if !pointer.is_null() {
            record(size as isize - layout.size() as isize);
        }
        pointer
    }
}

pub fn peak_bytes(work: impl FnOnce()) -> usize {
    struct Reset;
    impl Drop for Reset {
        fn drop(&mut self) {
            TRACKING.with(|tracking| tracking.set(None));
        }
    }
    TRACKING.with(|tracking| tracking.set(Some((0, 0))));
    let _reset = Reset;
    work();
    TRACKING.with(|tracking| tracking.get().unwrap().1)
}
