// Instrumentation is confined to relation traversal; release builds retain no counters.
#[cfg(test)]
thread_local! {
    static STATS: std::cell::Cell<(usize, usize)> = const { std::cell::Cell::new((0, 0)) };
    static WORK: std::cell::Cell<DeleteWork> = const { std::cell::Cell::new(DeleteWork {
        resources: 0, collection_checks: 0, pages: 0,
    }) };
}

#[cfg(test)]
#[derive(Clone, Copy, Debug, Default)]
pub(super) struct DeleteWork {
    pub resources: usize,
    pub collection_checks: usize,
    pub pages: usize,
}

#[cfg(test)]
pub(super) fn observe_resource() {
    WORK.with(|work| {
        let mut value = work.get();
        value.resources += 1;
        work.set(value);
    });
}

#[cfg(test)]
pub(super) fn observe_collection_check() {
    WORK.with(|work| {
        let mut value = work.get();
        value.collection_checks += 1;
        work.set(value);
    });
}

#[cfg(test)]
pub(super) fn measure_work<T>(action: impl FnOnce() -> T) -> (T, DeleteWork) {
    WORK.with(|work| work.set(DeleteWork::default()));
    let value = action();
    (value, WORK.with(|work| work.get()))
}

pub(super) fn observe_page(size: usize) {
    #[cfg(test)]
    STATS.with(|stats| {
        let (seen, peak) = stats.get();
        stats.set((seen + size, peak.max(size)));
    });
    #[cfg(test)]
    WORK.with(|work| {
        let mut value = work.get();
        value.pages += 1;
        work.set(value);
    });
    #[cfg(not(test))]
    let _ = size;
}

#[cfg(test)]
pub(super) fn measure<T>(action: impl FnOnce() -> T) -> (T, usize, usize) {
    STATS.with(|s| s.set((0, 0)));
    let value = action();
    let (seen, peak) = STATS.with(|s| s.get());
    (value, seen, peak)
}
