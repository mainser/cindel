pub async fn install_web_opfs_sahpool() -> Result<(), String> {
    sqlite_wasm_vfs::sahpool::install::<rusqlite::ffi::WasmOsCallback>(
        &sqlite_wasm_vfs::sahpool::OpfsSAHPoolCfg::default(),
        true,
    )
    .await
    .map(|_| ())
    .map_err(|error| error.to_string())
}
