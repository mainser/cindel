use crate::storage::{
    DocumentWrite, IndexEntry, IndexValue, SchemaManifest, SqliteStorage, StorageEngine,
};

pub struct CindelEngine {
    storage: SqliteStorage,
}

impl CindelEngine {
    pub fn open(directory: &str) -> Result<Self, String> {
        Ok(Self {
            storage: SqliteStorage::open(directory)?,
        })
    }

    pub fn get(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String> {
        self.storage.get(collection, id)
    }

    pub fn get_many(&self, collection: &str, ids: &[u64]) -> Result<Vec<Option<Vec<u8>>>, String> {
        self.storage.get_many(collection, ids)
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

    pub fn collection_revision(&self, collection: &str) -> Result<u64, String> {
        self.storage.collection_revision(collection)
    }

    pub fn register_schemas(&mut self, manifest: &SchemaManifest) -> Result<(), String> {
        self.storage.register_schemas(manifest)
    }

    pub fn register_schemas_after_migration(
        &mut self,
        manifest: &SchemaManifest,
    ) -> Result<(), String> {
        self.storage.register_schemas_after_migration(manifest)
    }

    pub fn schema_version(&self, collection: &str) -> Result<Option<u64>, String> {
        self.storage.schema_version(collection)
    }
}
