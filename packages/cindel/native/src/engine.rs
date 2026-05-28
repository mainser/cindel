use crate::storage::{
    DocumentWrite, IndexEntry, IndexValue, NativeDocumentWrite, SchemaManifest,
    SqliteNativeDocumentCursor, SqliteNativeQueryCursor, StorageBackend, StorageBackendKind,
    StorageChangeSet, StorageEngine,
};
#[cfg(feature = "mdbx")]
use crate::storage::{MdbxCursorDocumentReader, MdbxQueryDocumentReader};
use crate::wire::WireQueryPlan;

pub struct CindelEngine {
    storage: StorageBackend,
}

impl CindelEngine {
    pub fn open(directory: &str) -> Result<Self, String> {
        #[cfg(feature = "mdbx")]
        {
            Self::open_with_backend(directory, StorageBackendKind::Mdbx)
        }
        #[cfg(not(feature = "mdbx"))]
        {
            Self::open_with_backend(directory, StorageBackendKind::Sqlite)
        }
    }

    pub fn open_with_backend(directory: &str, backend: StorageBackendKind) -> Result<Self, String> {
        Ok(Self {
            storage: StorageBackend::open(backend, directory)?,
        })
    }

    pub fn open_with_backend_and_schemas(
        directory: &str,
        backend: StorageBackendKind,
        manifest: &SchemaManifest,
    ) -> Result<Self, String> {
        Ok(Self {
            storage: StorageBackend::open_with_schemas(backend, directory, manifest)?,
        })
    }

    pub fn get(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String> {
        self.storage.get(collection, id)
    }

    pub fn get_many(&self, collection: &str, ids: &[u64]) -> Result<Vec<Option<Vec<u8>>>, String> {
        self.storage.get_many(collection, ids)
    }

    pub fn get_stored(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String> {
        self.storage.get_stored(collection, id)
    }

    pub fn get_many_stored(
        &self,
        collection: &str,
        ids: &[u64],
    ) -> Result<Vec<Option<Vec<u8>>>, String> {
        self.storage.get_many_stored(collection, ids)
    }

    pub(crate) fn sqlite_native_document_cursor(
        &self,
        collection: &str,
        ids: &[u64],
    ) -> Result<Option<SqliteNativeDocumentCursor>, String> {
        self.storage.sqlite_native_document_cursor(collection, ids)
    }

    pub(crate) fn sqlite_query_plan_native_documents(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Option<Vec<(u64, Vec<u8>)>>, String> {
        self.storage
            .sqlite_query_plan_native_documents(collection, plan)
    }

    pub(crate) fn sqlite_query_plan_native_cursor(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Option<SqliteNativeQueryCursor>, String> {
        self.storage
            .sqlite_query_plan_native_cursor(collection, plan)
    }

    #[cfg(feature = "mdbx")]
    pub(crate) fn mdbx_cursor_document_reader(
        &self,
        collection: &str,
        ids: &[u64],
    ) -> Result<MdbxCursorDocumentReader, String> {
        self.storage.mdbx_cursor_document_reader(collection, ids)
    }

    #[cfg(feature = "mdbx")]
    pub(crate) fn mdbx_query_document_reader(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Option<MdbxQueryDocumentReader>, String> {
        self.storage.mdbx_query_document_reader(collection, plan)
    }

    pub fn document_ids(&self, collection: &str) -> Result<Vec<u64>, String> {
        self.storage.document_ids(collection)
    }

    pub fn begin_read_transaction(&mut self) -> Result<(), String> {
        self.storage.begin_read_transaction()
    }

    pub fn begin_write_transaction(&mut self) -> Result<(), String> {
        self.storage.begin_write_transaction()
    }

    pub fn commit_transaction(&mut self) -> Result<(), String> {
        self.storage.commit_transaction()
    }

    pub fn rollback_transaction(&mut self) -> Result<(), String> {
        self.storage.rollback_transaction()
    }

    pub fn allocate_id(&mut self, collection: &str) -> Result<u64, String> {
        self.storage.allocate_id(collection)
    }

    pub fn put(&mut self, collection: &str, id: u64, bytes: &[u8]) -> Result<(), String> {
        self.storage.put(collection, id, bytes)
    }

    pub fn put_indexed(
        &mut self,
        collection: &str,
        id: u64,
        bytes: &[u8],
        indexes: &[IndexEntry],
    ) -> Result<(), String> {
        self.storage.put_indexed(collection, id, bytes, indexes)
    }

    pub fn put_many_indexed(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String> {
        self.storage.put_many_indexed(collection, documents)
    }

    pub fn put_many_indexed_with_change_tracking(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
        track_changes: bool,
    ) -> Result<(), String> {
        self.storage
            .put_many_indexed_with_change_tracking(collection, documents, track_changes)
    }

    pub fn put_many_indexed_with_options(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
        track_changes: bool,
        trust_schema_documents: bool,
    ) -> Result<(), String> {
        self.storage.put_many_indexed_with_options(
            collection,
            documents,
            track_changes,
            trust_schema_documents,
        )
    }

    pub fn put_many_native_documents(
        &mut self,
        collection: &str,
        documents: &[NativeDocumentWrite],
        track_changes: bool,
    ) -> Result<bool, String> {
        self.storage
            .put_many_native_documents(collection, documents, track_changes)
    }

    pub fn delete(&mut self, collection: &str, id: u64) -> Result<(), String> {
        self.storage.delete(collection, id)
    }

    pub fn delete_many(&mut self, collection: &str, ids: &[u64]) -> Result<(), String> {
        self.storage.delete_many(collection, ids)
    }

    pub fn delete_many_native_documents(
        &mut self,
        collection: &str,
        ids: &[u64],
    ) -> Result<bool, String> {
        self.storage.delete_many_native_documents(collection, ids)
    }

    pub fn query_index_equal(
        &self,
        collection: &str,
        index: &str,
        value: &IndexValue,
    ) -> Result<Vec<u64>, String> {
        self.storage.query_index_equal(collection, index, value)
    }

    pub fn query_index_range(
        &self,
        collection: &str,
        index: &str,
        lower: Option<&IndexValue>,
        upper: Option<&IndexValue>,
    ) -> Result<Vec<u64>, String> {
        self.storage
            .query_index_range(collection, index, lower, upper)
    }

    pub fn query_filter(
        &self,
        collection: &str,
        candidate_ids: &[u64],
        filter: &[u8],
    ) -> Result<Vec<u64>, String> {
        self.storage.query_filter(collection, candidate_ids, filter)
    }

    pub fn query_project(
        &self,
        collection: &str,
        candidate_ids: &[u64],
        field: &str,
    ) -> Result<Vec<u8>, String> {
        self.storage.query_project(collection, candidate_ids, field)
    }

    pub fn query_aggregate(
        &self,
        collection: &str,
        candidate_ids: &[u64],
        field: &str,
        operation: &str,
    ) -> Result<Vec<u8>, String> {
        self.storage
            .query_aggregate(collection, candidate_ids, field, operation)
    }

    pub(crate) fn query_plan_ids(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Vec<u64>, String> {
        self.storage.query_plan_ids(collection, plan)
    }

    pub(crate) fn query_plan_documents(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Vec<Vec<u8>>, String> {
        self.storage.query_plan_documents(collection, plan)
    }

    pub(crate) fn query_plan_count(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<u64, String> {
        self.storage.query_plan_count(collection, plan)
    }

    pub(crate) fn query_plan_project(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
        field: &str,
    ) -> Result<Vec<u8>, String> {
        self.storage.query_plan_project(collection, plan, field)
    }

    pub(crate) fn query_plan_aggregate(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
        field: &str,
        operation: &str,
    ) -> Result<Vec<u8>, String> {
        self.storage
            .query_plan_aggregate(collection, plan, field, operation)
    }

    pub(crate) fn query_plan_delete(
        &mut self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Vec<u64>, String> {
        self.storage.query_plan_delete(collection, plan)
    }

    pub(crate) fn query_plan_update(
        &mut self,
        collection: &str,
        plan: &WireQueryPlan,
        updates: &[(String, crate::wire::WireValue)],
        collect_changes: bool,
    ) -> Result<usize, String> {
        self.storage
            .query_plan_update(collection, plan, updates, collect_changes)
    }

    pub fn collection_revision(&self, collection: &str) -> Result<u64, String> {
        self.storage.collection_revision(collection)
    }

    pub(crate) fn take_change_sets(&mut self) -> Result<Vec<StorageChangeSet>, String> {
        self.storage.take_change_sets()
    }

    pub(crate) fn discard_change_sets(&mut self) -> Result<(), String> {
        self.storage.take_change_sets().map(|_| ())
    }

    pub fn register_schemas(&mut self, manifest: &SchemaManifest) -> Result<(), String> {
        self.storage.register_schemas(manifest)
    }

    pub fn schema_version(&self, collection: &str) -> Result<Option<u64>, String> {
        self.storage.schema_version(collection)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::{CollectionSchemaManifest, FieldSchemaManifest};

    #[test]
    fn opens_sqlite_through_backend_selection_boundary() {
        // Scenario: The Rust engine opens through the internal backend
        // selection boundary while SQLite remains the selected backend.
        // Covers:
        // - [CindelEngine::open_with_backend] routing through [StorageBackend].
        // - SQLite behavior after decoupling the engine from [SqliteStorage].
        // Expected: Reads and writes keep working through the new boundary.
        let directory = std::env::temp_dir().join(format!("cindel_backend_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&directory);

        let mut engine = CindelEngine::open_with_backend(
            directory.to_str().unwrap(),
            StorageBackendKind::Sqlite,
        )
        .unwrap();

        engine.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
        let stored = engine.get("users", 1).unwrap().unwrap();

        assert_eq!(stored, br#"{"name":"Ana"}"#);

        let _ = std::fs::remove_dir_all(&directory);
    }

    #[cfg(feature = "mdbx")]
    #[test]
    fn opens_mdbx_through_backend_selection_boundary() {
        // Scenario: MDBX is compiled as an optional dependency and has a
        // minimal storage prototype.
        // Covers:
        // - The Rust-side backend option can be selected internally.
        // - Basic read/write behavior through the [StorageBackend] enum.
        // Expected: Selecting MDBX succeeds through the default native build.
        let mut engine =
            CindelEngine::open_with_backend(":memory:", StorageBackendKind::Mdbx).unwrap();

        engine.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
        let stored = engine.get("users", 1).unwrap().unwrap();

        assert_eq!(stored, br#"{"name":"Ana"}"#);
    }

    #[cfg(feature = "mdbx")]
    #[test]
    fn opens_mdbx_with_schema_manifest_during_open() {
        let manifest = SchemaManifest {
            collections: vec![CollectionSchemaManifest {
                name: "users".into(),
                id_field: "id".into(),
                fields: vec![
                    FieldSchemaManifest {
                        name: "id".into(),
                        dart_type: "int".into(),
                        binary_type: "int".into(),
                        is_id: true,
                        is_indexed: false,
                        is_index_unique: false,
                        index_case_sensitive: true,
                        index_type: "value".into(),
                    },
                    FieldSchemaManifest {
                        name: "active".into(),
                        dart_type: "bool".into(),
                        binary_type: "bool".into(),
                        is_id: false,
                        is_indexed: true,
                        is_index_unique: false,
                        index_case_sensitive: true,
                        index_type: "value".into(),
                    },
                ],
                composite_indexes: Vec::new(),
            }],
        };

        let engine = CindelEngine::open_with_backend_and_schemas(
            ":memory:",
            StorageBackendKind::Mdbx,
            &manifest,
        )
        .unwrap();

        assert_eq!(engine.schema_version("users").unwrap(), Some(1));
    }
}
