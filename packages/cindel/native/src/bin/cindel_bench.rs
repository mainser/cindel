#[cfg(feature = "benchmarks")]
fn main() {
    if let Err(error) = cindel_native::benchmark::run_cli(std::env::args().skip(1)) {
        eprintln!("benchmark failed: {error}");
        std::process::exit(1);
    }
}

#[cfg(not(feature = "benchmarks"))]
fn main() {
    eprintln!("cindel_bench requires building with `--features benchmarks`.");
    std::process::exit(1);
}
