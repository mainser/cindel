fn main() {
    if let Err(error) = cindel_native::benchmark::run_cli(std::env::args().skip(1)) {
        eprintln!("benchmark failed: {error}");
        std::process::exit(1);
    }
}
