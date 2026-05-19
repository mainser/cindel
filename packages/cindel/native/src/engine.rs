use crate::storage::{SqliteStorage, StorageEngine};

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

    pub fn put(&self, collection: &str, id: u64, bytes: &[u8]) -> Result<(), String> {
        self.storage.put(collection, id, bytes)
    }

    pub fn delete(&self, collection: &str, id: u64) -> Result<(), String> {
        self.storage.delete(collection, id)
    }
}
