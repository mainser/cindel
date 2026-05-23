use crate::storage::{
    DocumentWrite, IndexEntry, IndexValue, SchemaManifest, StorageBackend, StorageBackendKind,
    StorageEngine,
};

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

    pub fn delete(&mut self, collection: &str, id: u64) -> Result<(), String> {
        self.storage.delete(collection, id)
    }

    pub fn delete_many(&mut self, collection: &str, ids: &[u64]) -> Result<(), String> {
        self.storage.delete_many(collection, ids)
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

    pub fn collection_revision(&self, collection: &str) -> Result<u64, String> {
        self.storage.collection_revision(collection)
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
}
