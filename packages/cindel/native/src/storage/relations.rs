// Instrumentation is confined to relation traversal; release builds retain no counters.
#[cfg(test)]
thread_local! {
    static STATS: std::cell::Cell<(usize, usize)> = const { std::cell::Cell::new((0, 0)) };
}

pub(super) fn observe_page(size: usize) {
    #[cfg(test)]
    STATS.with(|stats| {
        let (seen, peak) = stats.get();
        stats.set((seen + size, peak.max(size)));
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
