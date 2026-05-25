#[cfg(test)]
mod contract_tests;
#[cfg(feature = "mdbx")]
mod mdbx;
mod mdbx_key;
mod metadata;
mod sqlite;

use serde::{Deserialize, Serialize};

use crate::wire::WireQueryPlan;

#[cfg(feature = "mdbx")]
pub use mdbx::MdbxStorage;
pub use metadata::{
    DocumentFormatVersion, IndexVerificationCheck, SchemaMetadataVersion, StorageLayoutVersion,
    StorageMetadata, StorageVerificationReport,
};
pub use sqlite::SqliteStorage;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum StorageBackendKind {
    Sqlite,
    #[cfg(feature = "mdbx")]
    Mdbx,
}

pub enum StorageBackend {
    Sqlite(SqliteStorage),
    #[cfg(feature = "mdbx")]
    Mdbx(MdbxStorage),
}

impl StorageBackend {
    pub fn open(kind: StorageBackendKind, directory: &str) -> Result<Self, String> {
        match kind {
            StorageBackendKind::Sqlite => Ok(Self::Sqlite(SqliteStorage::open(directory)?)),
            #[cfg(feature = "mdbx")]
            StorageBackendKind::Mdbx => Ok(Self::Mdbx(MdbxStorage::open(directory)?)),
        }
    }
}

#[derive(Debug, Clone, Deserialize, PartialEq, Serialize)]
pub struct IndexEntry {
    pub name: String,
    pub value: IndexValue,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Serialize)]
pub enum IndexValue {
    Bool(bool),
    Int(i64),
    Double(f64),
    String(String),
    List(Vec<IndexValue>),
}

#[derive(Debug, Clone, PartialEq)]
pub struct DocumentWrite {
    pub id: u64,
    pub bytes: Vec<u8>,
    pub indexes: Vec<IndexEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StorageChangeSet {
    pub collection: String,
    pub revision: u64,
    pub document_ids: Vec<u64>,
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
    #[serde(default)]
    pub composite_indexes: Vec<CompositeIndexSchemaManifest>,
}

#[derive(Debug, Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct CompositeIndexSchemaManifest {
    pub name: String,
    pub fields: Vec<String>,
    #[serde(default)]
    pub is_unique: bool,
    #[serde(default = "default_index_case_sensitive")]
    pub case_sensitive: bool,
}

#[derive(Debug, Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct FieldSchemaManifest {
    pub name: String,
    pub dart_type: String,
    pub binary_type: String,
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

pub(crate) fn schema_manifest_from_wire(bytes: &[u8]) -> Result<SchemaManifest, String> {
    metadata::decode_wire_schema_manifest(bytes)
}

pub(crate) fn encode_schema_record(
    version: u64,
    schema: &CollectionSchemaManifest,
) -> Result<Vec<u8>, String> {
    metadata::encode_schema_record(version, schema)
}

pub(crate) fn decode_schema_record(
    bytes: &[u8],
) -> Result<(u64, CollectionSchemaManifest), String> {
    metadata::decode_schema_record(bytes)
}

#[cfg(feature = "mdbx")]
pub(crate) fn encode_index_entry_metadata(
    document_id: u64,
    entries: &[IndexEntry],
) -> Result<Vec<u8>, String> {
    metadata::encode_index_entry_metadata(document_id, entries)
}

#[cfg(feature = "mdbx")]
pub(crate) fn decode_index_entry_metadata(bytes: &[u8]) -> Result<Vec<IndexEntry>, String> {
    metadata::decode_index_entry_metadata(bytes)
}

#[allow(dead_code)]
pub trait StorageEngine {
    fn begin_read_transaction(&mut self) -> Result<(), String>;
    fn begin_write_transaction(&mut self) -> Result<(), String>;
    fn commit_transaction(&mut self) -> Result<(), String>;
    fn rollback_transaction(&mut self) -> Result<(), String>;
    fn allocate_id(&mut self, collection: &str) -> Result<u64, String>;
    fn get(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String>;
    fn get_many(&self, collection: &str, ids: &[u64]) -> Result<Vec<Option<Vec<u8>>>, String>;
    fn get_stored(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String> {
        self.get(collection, id)
    }
    fn get_many_stored(
        &self,
        collection: &str,
        ids: &[u64],
    ) -> Result<Vec<Option<Vec<u8>>>, String> {
        self.get_many(collection, ids)
    }
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
    fn put_many_indexed_with_change_tracking(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
        track_changes: bool,
    ) -> Result<(), String> {
        self.put_many_indexed_with_options(collection, documents, track_changes, false)
    }
    fn put_many_indexed_with_options(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
        track_changes: bool,
        trust_schema_documents: bool,
    ) -> Result<(), String> {
        let _ = (track_changes, trust_schema_documents);
        self.put_many_indexed(collection, documents)
    }
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
    fn query_filter(
        &self,
        collection: &str,
        candidate_ids: &[u64],
        filter: &[u8],
    ) -> Result<Vec<u64>, String> {
        let _ = (collection, candidate_ids, filter);
        Err("native filters are not supported by this storage backend".into())
    }
    fn query_project(
        &self,
        collection: &str,
        candidate_ids: &[u64],
        field: &str,
    ) -> Result<Vec<u8>, String> {
        let _ = (collection, candidate_ids, field);
        Err("native projections are not supported by this storage backend".into())
    }
    fn query_aggregate(
        &self,
        collection: &str,
        candidate_ids: &[u64],
        field: &str,
        operation: &str,
    ) -> Result<Vec<u8>, String> {
        let _ = (collection, candidate_ids, field, operation);
        Err("native aggregates are not supported by this storage backend".into())
    }
    fn collection_revision(&self, collection: &str) -> Result<u64, String>;
    fn take_change_sets(&mut self) -> Result<Vec<StorageChangeSet>, String> {
        Ok(Vec::new())
    }
    fn register_schemas(&mut self, manifest: &SchemaManifest) -> Result<(), String>;
    fn schema_version(&self, collection: &str) -> Result<Option<u64>, String>;
    fn storage_metadata(&self) -> Result<StorageMetadata, String>;
    fn rebuild_indexes(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String>;
    fn query_plan_ids(&self, collection: &str, plan: &WireQueryPlan) -> Result<Vec<u64>, String> {
        let _ = (collection, plan);
        Err("native query plans are not supported by this storage backend".into())
    }
    fn query_plan_documents(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Vec<Vec<u8>>, String> {
        let _ = (collection, plan);
        Err("native query plan documents are not supported by this storage backend".into())
    }
    fn query_plan_count(&self, collection: &str, plan: &WireQueryPlan) -> Result<u64, String> {
        let _ = (collection, plan);
        Err("native query plan count is not supported by this storage backend".into())
    }
    fn query_plan_project(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
        field: &str,
    ) -> Result<Vec<u8>, String> {
        let _ = (collection, plan, field);
        Err("native query plan projections are not supported by this storage backend".into())
    }
    fn query_plan_aggregate(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
        field: &str,
        operation: &str,
    ) -> Result<Vec<u8>, String> {
        let _ = (collection, plan, field, operation);
        Err("native query plan aggregates are not supported by this storage backend".into())
    }
    fn query_plan_delete(
        &mut self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Vec<u64>, String> {
        let _ = (collection, plan);
        Err("native query plan deletes are not supported by this storage backend".into())
    }

    fn verify_storage(
        &self,
        manifest: &SchemaManifest,
        checks: &[IndexVerificationCheck],
    ) -> Result<StorageVerificationReport, String> {
        StorageVerificationReport::from_storage(self, manifest, checks)
    }
}

impl StorageEngine for StorageBackend {
    fn begin_read_transaction(&mut self) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.begin_read_transaction(),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.begin_read_transaction(),
        }
    }

    fn begin_write_transaction(&mut self) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.begin_write_transaction(),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.begin_write_transaction(),
        }
    }

    fn commit_transaction(&mut self) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.commit_transaction(),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.commit_transaction(),
        }
    }

    fn rollback_transaction(&mut self) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.rollback_transaction(),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.rollback_transaction(),
        }
    }

    fn allocate_id(&mut self, collection: &str) -> Result<u64, String> {
        match self {
            Self::Sqlite(storage) => storage.allocate_id(collection),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.allocate_id(collection),
        }
    }

    fn get(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String> {
        match self {
            Self::Sqlite(storage) => storage.get(collection, id),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.get(collection, id),
        }
    }

    fn get_many(&self, collection: &str, ids: &[u64]) -> Result<Vec<Option<Vec<u8>>>, String> {
        match self {
            Self::Sqlite(storage) => storage.get_many(collection, ids),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.get_many(collection, ids),
        }
    }

    fn get_stored(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String> {
        match self {
            Self::Sqlite(storage) => storage.get_stored(collection, id),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.get_stored(collection, id),
        }
    }

    fn get_many_stored(
        &self,
        collection: &str,
        ids: &[u64],
    ) -> Result<Vec<Option<Vec<u8>>>, String> {
        match self {
            Self::Sqlite(storage) => storage.get_many_stored(collection, ids),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.get_many_stored(collection, ids),
        }
    }

    fn document_ids(&self, collection: &str) -> Result<Vec<u64>, String> {
        match self {
            Self::Sqlite(storage) => storage.document_ids(collection),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.document_ids(collection),
        }
    }

    fn put(&mut self, collection: &str, id: u64, bytes: &[u8]) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.put(collection, id, bytes),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.put(collection, id, bytes),
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
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.put_indexed(collection, id, bytes, indexes),
        }
    }

    fn put_many_indexed(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.put_many_indexed(collection, documents),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.put_many_indexed(collection, documents),
        }
    }

    fn put_many_indexed_with_change_tracking(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
        track_changes: bool,
    ) -> Result<(), String> {
        self.put_many_indexed_with_options(collection, documents, track_changes, false)
    }

    fn put_many_indexed_with_options(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
        track_changes: bool,
        trust_schema_documents: bool,
    ) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.put_many_indexed_with_options(
                collection,
                documents,
                track_changes,
                trust_schema_documents,
            ),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.put_many_indexed_with_options(
                collection,
                documents,
                track_changes,
                trust_schema_documents,
            ),
        }
    }

    fn delete(&mut self, collection: &str, id: u64) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.delete(collection, id),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.delete(collection, id),
        }
    }

    fn delete_many(&mut self, collection: &str, ids: &[u64]) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.delete_many(collection, ids),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.delete_many(collection, ids),
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
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.query_index_equal(collection, index, value),
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
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.query_index_range(collection, index, lower, upper),
        }
    }

    fn query_filter(
        &self,
        collection: &str,
        candidate_ids: &[u64],
        filter: &[u8],
    ) -> Result<Vec<u64>, String> {
        match self {
            Self::Sqlite(storage) => storage.query_filter(collection, candidate_ids, filter),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.query_filter(collection, candidate_ids, filter),
        }
    }

    fn query_project(
        &self,
        collection: &str,
        candidate_ids: &[u64],
        field: &str,
    ) -> Result<Vec<u8>, String> {
        match self {
            Self::Sqlite(storage) => storage.query_project(collection, candidate_ids, field),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.query_project(collection, candidate_ids, field),
        }
    }

    fn query_aggregate(
        &self,
        collection: &str,
        candidate_ids: &[u64],
        field: &str,
        operation: &str,
    ) -> Result<Vec<u8>, String> {
        match self {
            Self::Sqlite(storage) => {
                storage.query_aggregate(collection, candidate_ids, field, operation)
            }
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => {
                storage.query_aggregate(collection, candidate_ids, field, operation)
            }
        }
    }

    fn collection_revision(&self, collection: &str) -> Result<u64, String> {
        match self {
            Self::Sqlite(storage) => storage.collection_revision(collection),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.collection_revision(collection),
        }
    }

    fn take_change_sets(&mut self) -> Result<Vec<StorageChangeSet>, String> {
        match self {
            Self::Sqlite(storage) => storage.take_change_sets(),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.take_change_sets(),
        }
    }

    fn register_schemas(&mut self, manifest: &SchemaManifest) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.register_schemas(manifest),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.register_schemas(manifest),
        }
    }

    fn schema_version(&self, collection: &str) -> Result<Option<u64>, String> {
        match self {
            Self::Sqlite(storage) => storage.schema_version(collection),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.schema_version(collection),
        }
    }

    fn storage_metadata(&self) -> Result<StorageMetadata, String> {
        match self {
            Self::Sqlite(storage) => storage.storage_metadata(),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.storage_metadata(),
        }
    }

    fn rebuild_indexes(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String> {
        match self {
            Self::Sqlite(storage) => storage.rebuild_indexes(collection, documents),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.rebuild_indexes(collection, documents),
        }
    }

    fn query_plan_ids(&self, collection: &str, plan: &WireQueryPlan) -> Result<Vec<u64>, String> {
        match self {
            Self::Sqlite(storage) => storage.query_plan_ids(collection, plan),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.query_plan_ids(collection, plan),
        }
    }

    fn query_plan_documents(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Vec<Vec<u8>>, String> {
        match self {
            Self::Sqlite(storage) => storage.query_plan_documents(collection, plan),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.query_plan_documents(collection, plan),
        }
    }

    fn query_plan_count(&self, collection: &str, plan: &WireQueryPlan) -> Result<u64, String> {
        match self {
            Self::Sqlite(storage) => storage.query_plan_count(collection, plan),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.query_plan_count(collection, plan),
        }
    }

    fn query_plan_project(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
        field: &str,
    ) -> Result<Vec<u8>, String> {
        match self {
            Self::Sqlite(storage) => storage.query_plan_project(collection, plan, field),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.query_plan_project(collection, plan, field),
        }
    }

    fn query_plan_aggregate(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
        field: &str,
        operation: &str,
    ) -> Result<Vec<u8>, String> {
        match self {
            Self::Sqlite(storage) => {
                storage.query_plan_aggregate(collection, plan, field, operation)
            }
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.query_plan_aggregate(collection, plan, field, operation),
        }
    }

    fn query_plan_delete(
        &mut self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Vec<u64>, String> {
        match self {
            Self::Sqlite(storage) => storage.query_plan_delete(collection, plan),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(storage) => storage.query_plan_delete(collection, plan),
        }
    }
}
