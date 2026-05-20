use crate::storage::{IndexEntry, IndexValue, SqliteStorage, StorageEngine};

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

    pub fn document_ids(&self, collection: &str) -> Result<Vec<u64>, String> {
        self.storage.document_ids(collection)
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

    pub fn delete(&mut self, collection: &str, id: u64) -> Result<(), String> {
        self.storage.delete(collection, id)
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
}
