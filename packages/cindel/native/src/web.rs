use crate::engine::CindelEngine;
use crate::storage::{
    schema_manifest_from_wire, DocumentWrite, IndexEntry, IndexValue, NativeDocumentValue,
    NativeDocumentWrite, StorageChangeSet, StorageMetadata,
};
use crate::wire::{
    decode_field_updates, decode_id_list, decode_index_value, decode_indexed_document_write_batch,
    decode_native_document_write_batch, decode_query_plan, encode_change_set_list, encode_id_list,
    encode_optional_document_batch, encode_scalar, WireChangeSet, WireIndexEntry, WireIndexValue,
    WireIndexedDocumentWrite, WireNativeDocumentValue, WireNativeDocumentWrite, WireScalar,
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

    #[wasm_bindgen(js_name = migrationVersion)]
    pub fn migration_version(&self) -> Result<u32, JsValue> {
        let version = self
            .inner
            .migration_version()
            .map_err(|error| JsValue::from_str(&error))?
            .unwrap_or(0);
        u32::try_from(version).map_err(|error| JsValue::from_str(&error.to_string()))
    }

    #[wasm_bindgen(js_name = setMigrationVersion)]
    pub fn set_migration_version(&mut self, version: u32) -> Result<(), JsValue> {
        self.inner
            .set_migration_version(u64::from(version))
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = registerMigratedSchemas)]
    pub fn register_migrated_schemas(&mut self, manifest_bytes: Vec<u8>) -> Result<(), JsValue> {
        let manifest = schema_manifest_from_wire(&manifest_bytes)
            .map_err(|error| JsValue::from_str(&error))?;
        self.inner
            .register_migrated_schemas(&manifest)
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = storageMetadataJson)]
    pub fn storage_metadata_json(&self) -> Result<String, JsValue> {
        self.inner
            .storage_metadata()
            .map(metadata_json)
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = compact)]
    pub fn compact(&mut self) -> Result<(), JsValue> {
        self.inner
            .compact()
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = beginReadTransaction)]
    pub fn begin_read_transaction(&mut self) -> Result<(), JsValue> {
        self.inner
            .begin_read_transaction()
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = beginWriteTransaction)]
    pub fn begin_write_transaction(&mut self) -> Result<(), JsValue> {
        self.inner
            .begin_write_transaction()
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = commitTransaction)]
    pub fn commit_transaction(&mut self) -> Result<(), JsValue> {
        self.inner
            .commit_transaction()
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = rollbackTransaction)]
    pub fn rollback_transaction(&mut self) -> Result<(), JsValue> {
        self.inner
            .rollback_transaction()
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

    #[wasm_bindgen(js_name = collectionRevision)]
    pub fn collection_revision(&self, collection: String) -> Result<Vec<u8>, JsValue> {
        let revision = self
            .inner
            .collection_revision(&collection)
            .map_err(|error| JsValue::from_str(&error))?;
        let revision =
            i64::try_from(revision).map_err(|error| JsValue::from_str(&error.to_string()))?;
        encode_scalar(&WireScalar::Int(revision)).map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = takeChanges)]
    pub fn take_changes(&mut self) -> Result<Vec<u8>, JsValue> {
        let changes = self
            .inner
            .take_change_sets()
            .map_err(|error| JsValue::from_str(&error))?;
        let changes = changes.into_iter().map(change_set).collect::<Vec<_>>();
        encode_change_set_list(&changes).map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = queryIndexEqual)]
    pub fn query_index_equal(
        &self,
        collection: String,
        index: String,
        value: Vec<u8>,
    ) -> Result<Vec<u8>, JsValue> {
        let value = decode_index_value(&value)
            .and_then(index_value)
            .map_err(|error| JsValue::from_str(&error))?;
        let ids = self
            .inner
            .query_index_equal(&collection, &index, &value)
            .map_err(|error| JsValue::from_str(&error))?;
        encode_id_list(&ids).map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = queryIndexRange)]
    pub fn query_index_range(
        &self,
        collection: String,
        index: String,
        lower_present: bool,
        lower: Vec<u8>,
        upper_present: bool,
        upper: Vec<u8>,
    ) -> Result<Vec<u8>, JsValue> {
        let lower = decode_optional_index_value(lower_present, &lower)?;
        let upper = decode_optional_index_value(upper_present, &upper)?;
        let ids = self
            .inner
            .query_index_range(&collection, &index, lower.as_ref(), upper.as_ref())
            .map_err(|error| JsValue::from_str(&error))?;
        encode_id_list(&ids).map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = queryPlanIds)]
    pub fn query_plan_ids(&self, collection: String, plan: Vec<u8>) -> Result<Vec<u8>, JsValue> {
        let plan = decode_query_plan(&plan).map_err(|error| JsValue::from_str(&error))?;
        let ids = self
            .inner
            .query_plan_ids(&collection, &plan)
            .map_err(|error| JsValue::from_str(&error))?;
        encode_id_list(&ids).map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = queryPlanDocuments)]
    pub fn query_plan_documents(
        &self,
        collection: String,
        plan: Vec<u8>,
    ) -> Result<Vec<u8>, JsValue> {
        let plan = decode_query_plan(&plan).map_err(|error| JsValue::from_str(&error))?;
        let documents = self
            .inner
            .query_plan_documents(&collection, &plan)
            .map_err(|error| JsValue::from_str(&error))?;
        encode_optional_document_batch(&documents.into_iter().map(Some).collect::<Vec<_>>())
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = queryPlanCount)]
    pub fn query_plan_count(&self, collection: String, plan: Vec<u8>) -> Result<Vec<u8>, JsValue> {
        let plan = decode_query_plan(&plan).map_err(|error| JsValue::from_str(&error))?;
        let count = self
            .inner
            .query_plan_count(&collection, &plan)
            .map_err(|error| JsValue::from_str(&error))?;
        let count = i64::try_from(count).map_err(|error| JsValue::from_str(&error.to_string()))?;
        encode_scalar(&WireScalar::Int(count)).map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = queryPlanProject)]
    pub fn query_plan_project(
        &self,
        collection: String,
        plan: Vec<u8>,
        field: String,
    ) -> Result<Vec<u8>, JsValue> {
        let plan = decode_query_plan(&plan).map_err(|error| JsValue::from_str(&error))?;
        self.inner
            .query_plan_project(&collection, &plan, &field)
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = queryPlanAggregate)]
    pub fn query_plan_aggregate(
        &self,
        collection: String,
        plan: Vec<u8>,
        field: String,
        operation: String,
    ) -> Result<Vec<u8>, JsValue> {
        let plan = decode_query_plan(&plan).map_err(|error| JsValue::from_str(&error))?;
        self.inner
            .query_plan_aggregate(&collection, &plan, &field, &operation)
            .map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = queryPlanDelete)]
    pub fn query_plan_delete(
        &mut self,
        collection: String,
        plan: Vec<u8>,
    ) -> Result<Vec<u8>, JsValue> {
        let plan = decode_query_plan(&plan).map_err(|error| JsValue::from_str(&error))?;
        let ids = self
            .inner
            .query_plan_delete(&collection, &plan)
            .map_err(|error| JsValue::from_str(&error))?;
        encode_id_list(&ids).map_err(|error| JsValue::from_str(&error))
    }

    #[wasm_bindgen(js_name = queryPlanUpdate)]
    pub fn query_plan_update(
        &mut self,
        collection: String,
        plan: Vec<u8>,
        updates: Vec<u8>,
        collect_changes: bool,
    ) -> Result<Vec<u8>, JsValue> {
        let plan = decode_query_plan(&plan).map_err(|error| JsValue::from_str(&error))?;
        let updates = decode_field_updates(&updates).map_err(|error| JsValue::from_str(&error))?;
        let count = self
            .inner
            .query_plan_update(&collection, &plan, &updates, collect_changes)
            .map_err(|error| JsValue::from_str(&error))?;
        let count = i64::try_from(count).map_err(|error| JsValue::from_str(&error.to_string()))?;
        encode_scalar(&WireScalar::Int(count)).map_err(|error| JsValue::from_str(&error))
    }
}

fn decode_optional_index_value(present: bool, bytes: &[u8]) -> Result<Option<IndexValue>, JsValue> {
    if !present {
        return Ok(None);
    }
    decode_index_value(bytes)
        .and_then(index_value)
        .map(Some)
        .map_err(|error| JsValue::from_str(&error))
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

fn change_set(change: StorageChangeSet) -> WireChangeSet {
    WireChangeSet {
        collection: change.collection,
        revision: change.revision,
        document_ids: change.document_ids,
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
