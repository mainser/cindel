#[cfg(feature = "mdbx")]
mod mdbx;
mod mdbx_key;
mod sqlite;

use serde::{Deserialize, Serialize};

pub use sqlite::SqliteStorage;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum StorageBackendKind {
    Sqlite,
    #[cfg(feature = "mdbx")]
    Mdbx,
}

pub enum StorageBackend {
    Sqlite(SqliteStorage),
}

impl StorageBackend {
    pub fn open(kind: StorageBackendKind, directory: &str) -> Result<Self, String> {
        match kind {
            StorageBackendKind::Sqlite => Ok(Self::Sqlite(SqliteStorage::open(directory)?)),
            #[cfg(feature = "mdbx")]
            StorageBackendKind::Mdbx => Err("MDBX storage backend is not implemented yet.".into()),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct IndexEntry {
    pub name: String,
    pub value: IndexValue,
}

#[derive(Debug, Clone, PartialEq)]
pub enum IndexValue {
    Bool(bool),
    Int(i64),
    Double(f64),
    String(String),
}

#[derive(Debug, Clone, PartialEq)]
pub struct DocumentWrite {
    pub id: u64,
    pub bytes: Vec<u8>,
    pub indexes: Vec<IndexEntry>,
}

#[derive(Debug, Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct SchemaManifest {
    pub collections: Vec<CollectionSchemaManifest>,
}

#[derive(Debug, Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct CollectionSchemaManifest {
    pub name: String,
    pub id_field: String,
    pub fields: Vec<FieldSchemaManifest>,
}

#[derive(Debug, Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct FieldSchemaManifest {
    pub name: String,
    pub dart_type: String,
    pub is_id: bool,
    pub is_indexed: bool,
    #[serde(default)]
    pub is_index_unique: bool,
    #[serde(default = "default_index_case_sensitive")]
    pub index_case_sensitive: bool,
    #[serde(default = "default_index_type")]
    pub index_type: String,
}

fn default_index_case_sensitive() -> bool {
    true
}

fn default_index_type() -> String {
    "value".to_string()
}

pub trait StorageEngine {
    fn begin_read_transaction(&mut self) -> Result<(), String>;
    fn begin_write_transaction(&mut self) -> Result<(), String>;
    fn commit_transaction(&mut self) -> Result<(), String>;
    fn rollback_transaction(&mut self) -> Result<(), String>;
    fn allocate_id(&mut self, collection: &str) -> Result<u64, String>;
    fn get(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String>;
    fn get_many(&self, collection: &str, ids: &[u64]) -> Result<Vec<Option<Vec<u8>>>, String>;
    fn document_ids(&self, collection: &str) -> Result<Vec<u64>, String>;
    fn put(&mut self, collection: &str, id: u64, bytes: &[u8]) -> Result<(), String>;
    fn put_indexed(
        &mut self,
        collection: &str,
        id: u64,
        bytes: &[u8],
        indexes: &[IndexEntry],
    ) -> Result<(), String>;
    fn put_many_indexed(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String>;
    fn delete(&mut self, collection: &str, id: u64) -> Result<(), String>;
    fn delete_many(&mut self, collection: &str, ids: &[u64]) -> Result<(), String>;
    fn query_index_equal(
        &self,
        collection: &str,
        index: &str,
        value: &IndexValue,
    ) -> Result<Vec<u64>, String>;
    fn query_index_range(
        &self,
        collection: &str,
        index: &str,
        lower: Option<&IndexValue>,
        upper: Option<&IndexValue>,
    ) -> Result<Vec<u64>, String>;
    fn collection_revision(&self, collection: &str) -> Result<u64, String>;
    fn register_schemas(&mut self, manifest: &SchemaManifest) -> Result<(), String>;
    fn register_schemas_after_migration(&mut self, manifest: &SchemaManifest)
        -> Result<(), String>;
    fn schema_version(&self, collection: &str) -> Result<Option<u64>, String>;
}

impl StorageEngine for StorageBackend {
    fn begin_read_transaction(&mut self) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.begin_read_transaction(),
        }
    }

    fn begin_write_transaction(&mut self) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.begin_write_transaction(),
        }
    }

    fn commit_transaction(&mut self) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.commit_transaction(),
        }
    }

    fn rollback_transaction(&mut self) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.rollback_transaction(),
        }
    }

    fn allocate_id(&mut self, collection: &str) -> Result<u64, String> {
        match self {
            Self::Sqlite(storage) => storage.allocate_id(collection),
        }
    }

    fn get(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String> {
        match self {
            Self::Sqlite(storage) => storage.get(collection, id),
        }
    }

    fn get_many(&self, collection: &str, ids: &[u64]) -> Result<Vec<Option<Vec<u8>>>, String> {
        match self {
            Self::Sqlite(storage) => storage.get_many(collection, ids),
        }
    }

    fn document_ids(&self, collection: &str) -> Result<Vec<u64>, String> {
        match self {
            Self::Sqlite(storage) => storage.document_ids(collection),
        }
    }

    fn put(&mut self, collection: &str, id: u64, bytes: &[u8]) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.put(collection, id, bytes),
        }
    }

    fn put_indexed(
        &mut self,
        collection: &str,
        id: u64,
        bytes: &[u8],
        indexes: &[IndexEntry],
    ) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.put_indexed(collection, id, bytes, indexes),
        }
    }

    fn put_many_indexed(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.put_many_indexed(collection, documents),
        }
    }

    fn delete(&mut self, collection: &str, id: u64) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.delete(collection, id),
        }
    }

    fn delete_many(&mut self, collection: &str, ids: &[u64]) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.delete_many(collection, ids),
        }
    }

    fn query_index_equal(
        &self,
        collection: &str,
        index: &str,
        value: &IndexValue,
    ) -> Result<Vec<u64>, String> {
        match self {
            Self::Sqlite(storage) => storage.query_index_equal(collection, index, value),
        }
    }

    fn query_index_range(
        &self,
        collection: &str,
        index: &str,
        lower: Option<&IndexValue>,
        upper: Option<&IndexValue>,
    ) -> Result<Vec<u64>, String> {
        match self {
            Self::Sqlite(storage) => storage.query_index_range(collection, index, lower, upper),
        }
    }

    fn collection_revision(&self, collection: &str) -> Result<u64, String> {
        match self {
            Self::Sqlite(storage) => storage.collection_revision(collection),
        }
    }

    fn register_schemas(&mut self, manifest: &SchemaManifest) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.register_schemas(manifest),
        }
    }

    fn register_schemas_after_migration(
        &mut self,
        manifest: &SchemaManifest,
    ) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.register_schemas_after_migration(manifest),
        }
    }

    fn schema_version(&self, collection: &str) -> Result<Option<u64>, String> {
        match self {
            Self::Sqlite(storage) => storage.schema_version(collection),
        }
    }
}
