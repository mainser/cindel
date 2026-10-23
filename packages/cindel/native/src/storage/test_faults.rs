//! Thread-local, one-shot failures. Entirely absent from production builds.
use std::cell::RefCell;

thread_local! {
    static FAULT: RefCell<Option<(&'static str, usize)>> = const { RefCell::new(None) };
}

pub(crate) struct Fault;

pub(crate) fn after(point: &'static str, successful_calls: usize) -> Fault {
    FAULT.with(|slot| *slot.borrow_mut() = Some((point, successful_calls)));
    Fault
}

pub(crate) fn check(point: &str) -> Result<(), String> {
    FAULT.with(|slot| {
        let mut fault = slot.borrow_mut();
        if let Some((selected, remaining)) = fault.as_mut() {
            if *selected == point {
                if *remaining == 0 {
                    *fault = None;
                    return Err(format!("controlled failure at {point}"));
                }
                *remaining -= 1;
            }
        }
        Ok(())
    })
}

impl Drop for Fault {
    fn drop(&mut self) {
        FAULT.with(|slot| *slot.borrow_mut() = None);
    }
}
