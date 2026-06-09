use crate::engine::CindelEngine;
use crate::storage::{schema_manifest_from_wire, StorageMetadata};
use wasm_bindgen::prelude::*;

pub async fn install_web_opfs_sahpool() -> Result<(), String> {
    sqlite_wasm_vfs::sahpool::install::<rusqlite::ffi::WasmOsCallback>(
        &sqlite_wasm_vfs::sahpool::OpfsSAHPoolCfg::default(),
        true,
    )
    .await
    .map(|_| ())
    .map_err(|error| error.to_string())
}

#[wasm_bindgen]
pub struct CindelWebEngine {
    inner: CindelEngine,
}

#[wasm_bindgen]
impl CindelWebEngine {
    #[wasm_bindgen(js_name = openWithSchemas)]
    pub async fn open_with_schemas(
        db_name: String,
        manifest_bytes: Vec<u8>,
    ) -> Result<CindelWebEngine, JsValue> {
        install_web_opfs_sahpool()
            .await
            .map_err(|error| JsValue::from_str(&error))?;
        let manifest = schema_manifest_from_wire(&manifest_bytes)
            .map_err(|error| JsValue::from_str(&error))?;
        let inner = CindelEngine::open_web_sqlite_with_schemas(&db_name, &manifest)
            .map_err(|error| JsValue::from_str(&error))?;
        Ok(Self { inner })
    }

    #[wasm_bindgen(js_name = schemaVersion)]
    pub fn schema_version(&self, collection: String) -> Result<u32, JsValue> {
        let version = self
            .inner
            .schema_version(&collection)
            .map_err(|error| JsValue::from_str(&error))?
            .unwrap_or(0);
        u32::try_from(version).map_err(|error| JsValue::from_str(&error.to_string()))
    }

    #[wasm_bindgen(js_name = storageMetadataJson)]
    pub fn storage_metadata_json(&self) -> Result<String, JsValue> {
        self.inner
            .storage_metadata()
            .map(metadata_json)
            .map_err(|error| JsValue::from_str(&error))
    }
}

fn metadata_json(metadata: StorageMetadata) -> String {
    format!(
        "{{\"layout\":{},\"documentFormat\":{},\"schemaMetadataFormat\":{}}}",
        json_string(metadata.layout.as_str()),
        json_string(metadata.document_format.as_str()),
        json_string(metadata.schema_metadata_format.as_str()),
    )
}

fn json_string(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len() + 2);
    escaped.push('"');
    for ch in value.chars() {
        match ch {
            '"' => escaped.push_str("\\\""),
            '\\' => escaped.push_str("\\\\"),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            ch => escaped.push(ch),
        }
    }
    escaped.push('"');
    escaped
}
