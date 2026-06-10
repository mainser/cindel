use crate::storage::{
    DocumentWrite, IndexEntry, IndexValue, NativeDocumentWrite, SchemaManifest,
    SqliteNativeDocumentCursor, SqliteNativeQueryCursor, StorageBackend, StorageBackendKind,
    StorageChangeSet, StorageEngine, StorageMetadata,
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

    pub fn open_web_sqlite_with_schemas(
        directory: &str,
        manifest: &SchemaManifest,
    ) -> Result<Self, String> {
        Ok(Self {
            storage: StorageBackend::open_sqlite_with_persisted_schemas(directory, manifest)?,
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

    pub fn storage_metadata(&self) -> Result<StorageMetadata, String> {
        self.storage.storage_metadata()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::storage::{
        CollectionSchemaManifest, DocumentWrite, FieldSchemaManifest, IndexEntry, IndexValue,
        NativeDocumentValue, NativeDocumentWrite,
    };

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

    #[test]
    fn sqlite_web_baseline_handles_schema_crud_and_transactions_in_memory() {
        // Scenario: The Web target uses the same SQLite storage semantics as
        // native Cindel before OPFS/Worker integration.
        // Covers:
        // - [CindelEngine::open_with_backend_and_schemas] with SQLite.
        // - Schema registration, CRUD, auto-increment allocation, and
        //   transaction rollback through the shared engine boundary.
        // Expected: The portable SQLite core supports the MVP Web baseline
        //   without a separate storage implementation.
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
                        is_index_replace: false,
                        index_case_sensitive: true,
                        index_type: "value".into(),
                    },
                    FieldSchemaManifest {
                        name: "name".into(),
                        dart_type: "String".into(),
                        binary_type: "String".into(),
                        is_id: false,
                        is_indexed: false,
                        is_index_unique: false,
                        is_index_replace: false,
                        index_case_sensitive: true,
                        index_type: "value".into(),
                    },
                ],
                composite_indexes: Vec::new(),
            }],
        };
        let mut engine = CindelEngine::open_with_backend_and_schemas(
            ":memory:",
            StorageBackendKind::Sqlite,
            &manifest,
        )
        .unwrap();

        assert_eq!(engine.schema_version("users").unwrap(), Some(1));

        let first_id = engine.allocate_id("users").unwrap();
        assert_eq!(first_id, 1);
        engine
            .put("users", first_id, &generic_document("Ana"))
            .unwrap();
        assert_eq!(engine.document_ids("users").unwrap(), vec![1]);
        assert_eq!(
            engine.get("users", first_id).unwrap(),
            Some(generic_document("Ana"))
        );

        engine.begin_write_transaction().unwrap();
        let rolled_back_id = engine.allocate_id("users").unwrap();
        assert_eq!(rolled_back_id, 2);
        engine
            .put("users", rolled_back_id, &generic_document("Ben"))
            .unwrap();
        engine.rollback_transaction().unwrap();

        assert_eq!(engine.document_ids("users").unwrap(), vec![1]);
        assert_eq!(engine.get("users", rolled_back_id).unwrap(), None);

        engine.delete("users", first_id).unwrap();
        assert_eq!(engine.document_ids("users").unwrap(), Vec::<u64>::new());
    }

    #[test]
    fn sqlite_web_typed_crud_matches_native_sqlite_reference() {
        // Scenario: The Web SQLite opener exposes the typed CRUD
        // surface through the shared engine instead of a separate Web backend.
        // Covers:
        // - Auto-increment ids, put/putAll, get/getAll, delete/deleteAll.
        // - Ordered getAll missing-id behavior.
        // - Compact/generated document bytes through the generic batch path.
        // - SQLite-native generated document writes and stored reads.
        // - Close/reopen persistence for the Web SQLite path.
        // - Parity against native SQLite on the same dataset.
        // Expected: Web SQLite and native SQLite produce the same CRUD result,
        // and reopened Web SQLite keeps stored rows available.
        let manifest = web_typed_crud_manifest();
        let directory =
            std::env::temp_dir().join(format!("cindel_web_typed_crud_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&directory);

        let mut web =
            CindelEngine::open_web_sqlite_with_schemas(directory.to_str().unwrap(), &manifest)
                .unwrap();
        let web_result = run_web_typed_crud(&mut web).unwrap();
        drop(web);

        let reopened =
            CindelEngine::open_web_sqlite_with_schemas(directory.to_str().unwrap(), &manifest)
                .unwrap();
        assert_eq!(reopened.document_ids("native_users").unwrap(), vec![2]);
        assert!(reopened
            .get_many_stored("native_users", &[2])
            .unwrap()
            .into_iter()
            .all(|document| document.is_some()));

        let mut reference = CindelEngine::open_with_backend_and_schemas(
            ":memory:",
            StorageBackendKind::Sqlite,
            &manifest,
        )
        .unwrap();
        let reference_result = run_web_typed_crud(&mut reference).unwrap();

        assert_eq!(web_result, reference_result);

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
        // Scenario: MDBX opens with an initial schema manifest.
        // Covers:
        // - [CindelEngine::open_with_backend_and_schemas] with MDBX.
        // - Schema registration during native engine construction.
        // Expected: The opened engine reports the registered schema version.
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
                        is_index_replace: false,
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
                        is_index_replace: false,
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

    fn generic_document(name: &str) -> Vec<u8> {
        let key = b"name";
        let value = name.as_bytes();
        let mut bytes = Vec::new();
        bytes.extend_from_slice(b"CGD1");
        bytes.extend_from_slice(&1u32.to_le_bytes());
        bytes.push(6);
        bytes.extend_from_slice(&1u32.to_le_bytes());
        bytes.extend_from_slice(&(key.len() as u32).to_le_bytes());
        bytes.extend_from_slice(key);
        bytes.push(5);
        bytes.extend_from_slice(&(value.len() as u32).to_le_bytes());
        bytes.extend_from_slice(value);
        bytes
    }

    #[derive(Debug, PartialEq)]
    struct WebTypedCrudResult {
        ids: Vec<u64>,
        ordered_get_all: Vec<Option<Vec<u8>>>,
        native_document_path: bool,
        native_after_delete: Vec<u64>,
        compact_count: usize,
    }

    fn run_web_typed_crud(engine: &mut CindelEngine) -> Result<WebTypedCrudResult, String> {
        let ana_id = engine.allocate_id("users")?;
        let ben_id = engine.allocate_id("users")?;
        let cid_id = engine.allocate_id("users")?;
        let ana = generic_document("Ana");
        let ben = generic_document("Ben");
        let cid = generic_document("Cid");

        engine.put_indexed("users", ana_id, &ana, &[])?;
        engine.put_many_indexed(
            "users",
            &[
                DocumentWrite {
                    id: ben_id,
                    bytes: ben.clone(),
                    indexes: Vec::new(),
                },
                DocumentWrite {
                    id: cid_id,
                    bytes: cid.clone(),
                    indexes: Vec::new(),
                },
            ],
        )?;
        let ordered_get_all = engine.get_many("users", &[cid_id, ana_id, 404, ben_id])?;
        engine.delete("users", ana_id)?;
        engine.delete_many("users", &[ben_id, cid_id])?;

        engine.put_many_indexed(
            "compact_users",
            &[
                DocumentWrite {
                    id: 1,
                    bytes: generic_document("Compact Ana"),
                    indexes: vec![IndexEntry {
                        name: "name".into(),
                        value: IndexValue::String("Compact Ana".into()),
                    }],
                },
                DocumentWrite {
                    id: 2,
                    bytes: generic_document("Compact Ben"),
                    indexes: vec![IndexEntry {
                        name: "name".into(),
                        value: IndexValue::String("Compact Ben".into()),
                    }],
                },
            ],
        )?;
        let compact_count = engine.document_ids("compact_users")?.len();

        let native_document_path = engine.put_many_native_documents(
            "native_users",
            &[
                NativeDocumentWrite {
                    id: 1,
                    values: vec![
                        NativeDocumentValue::Bool(true),
                        NativeDocumentValue::Bytes(b"Native Ana".to_vec()),
                        NativeDocumentValue::Int(42),
                    ],
                },
                NativeDocumentWrite {
                    id: 2,
                    values: vec![
                        NativeDocumentValue::Bool(false),
                        NativeDocumentValue::Bytes(b"Native Ben".to_vec()),
                        NativeDocumentValue::Int(84),
                    ],
                },
            ],
            true,
        )?;
        assert!(engine
            .get_many_stored("native_users", &[1, 2])?
            .iter()
            .all(Option::is_some));
        engine.delete_many_native_documents("native_users", &[1])?;
        let native_after_delete = engine.document_ids("native_users")?;

        Ok(WebTypedCrudResult {
            ids: vec![ana_id, ben_id, cid_id],
            ordered_get_all,
            native_document_path,
            native_after_delete,
            compact_count,
        })
    }

    fn web_typed_crud_manifest() -> SchemaManifest {
        SchemaManifest {
            collections: vec![
                CollectionSchemaManifest {
                    name: "users".into(),
                    id_field: "id".into(),
                    fields: vec![field("id", "int", true, false)],
                    composite_indexes: Vec::new(),
                },
                CollectionSchemaManifest {
                    name: "compact_users".into(),
                    id_field: "id".into(),
                    fields: vec![
                        field("id", "int", true, false),
                        field("name", "string", false, true),
                    ],
                    composite_indexes: Vec::new(),
                },
                CollectionSchemaManifest {
                    name: "native_users".into(),
                    id_field: "id".into(),
                    fields: vec![
                        field("id", "int", true, false),
                        field("active", "bool", false, false),
                        field("score", "int", false, false),
                        field("name", "string", false, false),
                    ],
                    composite_indexes: Vec::new(),
                },
            ],
        }
    }

    fn field(name: &str, binary_type: &str, is_id: bool, is_indexed: bool) -> FieldSchemaManifest {
        FieldSchemaManifest {
            name: name.into(),
            dart_type: binary_type.into(),
            binary_type: binary_type.into(),
            is_id,
            is_indexed,
            is_index_unique: false,
            is_index_replace: false,
            index_case_sensitive: true,
            index_type: "value".into(),
        }
    }
}
