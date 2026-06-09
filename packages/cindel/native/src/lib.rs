#[cfg(all(feature = "web", feature = "mdbx"))]
compile_error!("The `web` feature must be built without the default `mdbx` feature.");

mod document_format;
mod engine;
mod ffi;
#[cfg(feature = "mdbx")]
mod native_filter;
mod storage;
#[cfg(all(feature = "web", target_family = "wasm", target_os = "unknown"))]
mod web;
mod wire;

pub use engine::CindelEngine;
#[cfg(all(feature = "web", target_family = "wasm", target_os = "unknown"))]
pub use web::install_web_opfs_sahpool;
