use crate::engine::CindelEngine;
use crate::storage::{
    schema_manifest_from_wire, DocumentWrite, IndexEntry, IndexValue, NativeDocumentValue,
    NativeDocumentWrite, StorageMetadata,
};
use crate::wire::{
    decode_id_list, decode_indexed_document_write_batch, decode_native_document_write_batch,
    encode_id_list, encode_optional_document_batch, WireIndexEntry, WireIndexValue,
    WireIndexedDocumentWrite, WireNativeDocumentValue, WireNativeDocumentWrite,
};
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

    #[wasm_bindgen(js_name = allocateId)]
    pub fn allocate_id(&mut self, collection: String) -> Result<Vec<u8>, JsValue> {
        let id = self
            .inner
            .allocate_id(&collection)
            .map_err(|error| JsValue::from_str(&error))?;
        encode_id_list(&[id]).map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = allocateIds)]
    pub fn allocate_ids(&mut self, collection: String, count: u32) -> Result<Vec<u8>, JsValue> {
        let mut ids = Vec::with_capacity(count as usize);
        for _ in 0..count {
            ids.push(
                self.inner
                    .allocate_id(&collection)
                    .map_err(|error| JsValue::from_str(&error))?,
            );
        }
        encode_id_list(&ids).map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = put)]
    pub fn put(&mut self, collection: String, document_batch: Vec<u8>) -> Result<(), JsValue> {
        let documents =
            decode_document_writes(&document_batch).map_err(|error| JsValue::from_str(&error))?;
        ensure_single_document(&documents)?;
        self.inner
            .put_many_indexed(&collection, &documents)
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = putAll)]
    pub fn put_all(&mut self, collection: String, document_batch: Vec<u8>) -> Result<(), JsValue> {
        let documents =
            decode_document_writes(&document_batch).map_err(|error| JsValue::from_str(&error))?;
        self.inner
            .put_many_indexed(&collection, &documents)
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = putNativeAll)]
    pub fn put_native_all(
        &mut self,
        collection: String,
        document_batch: Vec<u8>,
    ) -> Result<bool, JsValue> {
        let documents = decode_native_document_writes(&document_batch)
            .map_err(|error| JsValue::from_str(&error))?;
        self.inner
            .put_many_native_documents(&collection, &documents, true)
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = get)]
    pub fn get(&self, collection: String, ids: Vec<u8>) -> Result<Vec<u8>, JsValue> {
        let ids = decode_single_id_list(&ids)?;
        let documents = self
            .inner
            .get_many(&collection, &ids)
            .map_err(|error| JsValue::from_str(&error))?;
        encode_optional_document_batch(&documents).map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = getAll)]
    pub fn get_all(&self, collection: String, ids: Vec<u8>) -> Result<Vec<u8>, JsValue> {
        let ids = decode_id_list(&ids).map_err(|error| JsValue::from_str(&error))?;
        let documents = self
            .inner
            .get_many(&collection, &ids)
            .map_err(|error| JsValue::from_str(&error))?;
        encode_optional_document_batch(&documents).map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = getStored)]
    pub fn get_stored(&self, collection: String, ids: Vec<u8>) -> Result<Vec<u8>, JsValue> {
        let ids = decode_single_id_list(&ids)?;
        let documents = self
            .inner
            .get_many_stored(&collection, &ids)
            .map_err(|error| JsValue::from_str(&error))?;
        encode_optional_document_batch(&documents).map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = getAllStored)]
    pub fn get_all_stored(&self, collection: String, ids: Vec<u8>) -> Result<Vec<u8>, JsValue> {
        let ids = decode_id_list(&ids).map_err(|error| JsValue::from_str(&error))?;
        let documents = self
            .inner
            .get_many_stored(&collection, &ids)
            .map_err(|error| JsValue::from_str(&error))?;
        encode_optional_document_batch(&documents).map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = delete)]
    pub fn delete(&mut self, collection: String, ids: Vec<u8>) -> Result<(), JsValue> {
        let ids = decode_single_id_list(&ids)?;
        self.inner
            .delete_many(&collection, &ids)
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = deleteAll)]
    pub fn delete_all(&mut self, collection: String, ids: Vec<u8>) -> Result<(), JsValue> {
        let ids = decode_id_list(&ids).map_err(|error| JsValue::from_str(&error))?;
        self.inner
            .delete_many(&collection, &ids)
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = deleteNativeAll)]
    pub fn delete_native_all(&mut self, collection: String, ids: Vec<u8>) -> Result<bool, JsValue> {
        let ids = decode_id_list(&ids).map_err(|error| JsValue::from_str(&error))?;
        self.inner
            .delete_many_native_documents(&collection, &ids)
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = documentIds)]
    pub fn document_ids(&self, collection: String) -> Result<Vec<u8>, JsValue> {
        let ids = self
            .inner
            .document_ids(&collection)
            .map_err(|error| JsValue::from_str(&error))?;
        encode_id_list(&ids).map_err(|error| JsValue::from_str(&error))
    }
}

fn decode_single_id_list(bytes: &[u8]) -> Result<Vec<u64>, JsValue> {
    let ids = decode_id_list(bytes).map_err(|error| JsValue::from_str(&error))?;
    if ids.len() == 1 {
        Ok(ids)
    } else {
        Err(JsValue::from_str(
            "single-document Web operation requires exactly one id",
        ))
    }
}

fn ensure_single_document(documents: &[DocumentWrite]) -> Result<(), JsValue> {
    if documents.len() == 1 {
        Ok(())
    } else {
        Err(JsValue::from_str(
            "single-document Web operation requires exactly one document",
        ))
    }
}

fn decode_document_writes(bytes: &[u8]) -> Result<Vec<DocumentWrite>, String> {
    decode_indexed_document_write_batch(bytes)?
        .into_iter()
        .map(indexed_document_write)
        .collect()
}

fn indexed_document_write(document: WireIndexedDocumentWrite) -> Result<DocumentWrite, String> {
    let indexes = document
        .indexes
        .into_iter()
        .map(index_entry)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(DocumentWrite {
        id: document.id,
        bytes: document.bytes,
        indexes,
    })
}

fn index_entry(index: WireIndexEntry) -> Result<IndexEntry, String> {
    Ok(IndexEntry {
        name: index.index_name,
        value: index_value(index.value)?,
    })
}

fn index_value(value: WireIndexValue) -> Result<IndexValue, String> {
    match value {
        WireIndexValue::Null => Err("Web index entries cannot use null index values".into()),
        WireIndexValue::Bool(value) => Ok(IndexValue::Bool(value)),
        WireIndexValue::Int(value) => Ok(IndexValue::Int(value)),
        WireIndexValue::Double(value) if value.is_finite() => Ok(IndexValue::Double(value)),
        WireIndexValue::Double(_) => Err("Web index double values must be finite".into()),
        WireIndexValue::String(value) => Ok(IndexValue::String(value)),
        WireIndexValue::List(values) => values
            .into_iter()
            .map(index_value)
            .collect::<Result<Vec<_>, _>>()
            .map(IndexValue::List),
    }
}

fn decode_native_document_writes(bytes: &[u8]) -> Result<Vec<NativeDocumentWrite>, String> {
    decode_native_document_write_batch(bytes)?
        .into_iter()
        .map(native_document_write)
        .collect()
}

fn native_document_write(document: WireNativeDocumentWrite) -> Result<NativeDocumentWrite, String> {
    let values = document
        .values
        .into_iter()
        .map(native_document_value)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(NativeDocumentWrite {
        id: document.id,
        values,
    })
}

fn native_document_value(value: WireNativeDocumentValue) -> Result<NativeDocumentValue, String> {
    match value {
        WireNativeDocumentValue::Null => Ok(NativeDocumentValue::Null),
        WireNativeDocumentValue::Bool(value) => Ok(NativeDocumentValue::Bool(value)),
        WireNativeDocumentValue::Int(value) => Ok(NativeDocumentValue::Int(value)),
        WireNativeDocumentValue::Double(value) if value.is_finite() => {
            Ok(NativeDocumentValue::Double(value))
        }
        WireNativeDocumentValue::Double(_) => {
            Err("Web native document double values must be finite".into())
        }
        WireNativeDocumentValue::Bytes(value) => Ok(NativeDocumentValue::Bytes(value)),
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
