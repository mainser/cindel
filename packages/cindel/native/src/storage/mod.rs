#[cfg(test)]
mod contract_tests;
#[cfg(feature = "mdbx")]
mod mdbx;
mod mdbx_key;
#[cfg(feature = "benchmarks")]
mod mdbx_layout_v2;
mod metadata;
mod sqlite;

use serde::{Deserialize, Serialize};

#[cfg(feature = "mdbx")]
pub use mdbx::MdbxStorage;
#[cfg(feature = "benchmarks")]
pub(crate) use mdbx_layout_v2::MdbxLayoutV2Storage;
pub use metadata::{
    DocumentFormatVersion, IndexVerificationCheck, StorageLayoutVersion, StorageMetadata,
    StorageVerificationReport,
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

fn aggregate_json_values(
    values: &[serde_json::Value],
    operation: &str,
) -> Result<serde_json::Value, String> {
    match operation {
        "count" => Ok(serde_json::Value::from(
            values.iter().filter(|value| !value.is_null()).count() as u64,
        )),
        "min" => aggregate_json_min_max(values, AggregateOrder::Min),
        "max" => aggregate_json_min_max(values, AggregateOrder::Max),
        "sum" => aggregate_json_sum(values),
        "average" => aggregate_json_average(values),
        _ => Err(format!("unknown aggregate operation `{operation}`")),
    }
}

#[derive(Clone, Copy)]
enum AggregateOrder {
    Min,
    Max,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum AggregateKind {
    Number,
    String,
}

fn aggregate_json_min_max(
    values: &[serde_json::Value],
    order: AggregateOrder,
) -> Result<serde_json::Value, String> {
    let mut best: Option<(AggregateKind, serde_json::Value)> = None;
    for value in values {
        if value.is_null() {
            continue;
        }
        let kind = match value {
            serde_json::Value::Number(_) => AggregateKind::Number,
            serde_json::Value::String(_) => AggregateKind::String,
            _ => {
                return Err("min/max aggregates require number, string, or null values".into());
            }
        };
        let Some((best_kind, best_value)) = &best else {
            best = Some((kind, value.clone()));
            continue;
        };
        if kind != *best_kind {
            return Err("min/max aggregates cannot mix number and string values".into());
        }
        if aggregate_value_should_replace(value, best_value, kind, order)? {
            best = Some((kind, value.clone()));
        }
    }
    Ok(best
        .map(|(_, value)| value)
        .unwrap_or(serde_json::Value::Null))
}

fn aggregate_value_should_replace(
    candidate: &serde_json::Value,
    best: &serde_json::Value,
    kind: AggregateKind,
    order: AggregateOrder,
) -> Result<bool, String> {
    let comparison = match kind {
        AggregateKind::Number => {
            let candidate = candidate
                .as_f64()
                .ok_or_else(|| "number aggregate value cannot be represented as f64".to_string())?;
            let best = best
                .as_f64()
                .ok_or_else(|| "number aggregate value cannot be represented as f64".to_string())?;
            candidate.total_cmp(&best)
        }
        AggregateKind::String => {
            let candidate = candidate
                .as_str()
                .ok_or_else(|| "string aggregate value was not a string".to_string())?;
            let best = best
                .as_str()
                .ok_or_else(|| "string aggregate value was not a string".to_string())?;
            candidate.cmp(best)
        }
    };
    Ok(match order {
        AggregateOrder::Min => comparison.is_lt(),
        AggregateOrder::Max => comparison.is_gt(),
    })
}

fn aggregate_json_sum(values: &[serde_json::Value]) -> Result<serde_json::Value, String> {
    let mut sum = 0.0;
    let mut count = 0_u64;
    for value in values {
        if value.is_null() {
            continue;
        }
        let Some(number) = value.as_f64() else {
            return Err("sum aggregate requires number or null values".into());
        };
        sum += number;
        count += 1;
    }
    if count == 0 {
        return Ok(serde_json::Value::Null);
    }
    serde_json::Number::from_f64(sum)
        .map(serde_json::Value::Number)
        .ok_or_else(|| "sum aggregate produced a non-finite number".into())
}

fn aggregate_json_average(values: &[serde_json::Value]) -> Result<serde_json::Value, String> {
    let mut sum = 0.0;
    let mut count = 0_u64;
    for value in values {
        if value.is_null() {
            continue;
        }
        let Some(number) = value.as_f64() else {
            return Err("average aggregate requires number or null values".into());
        };
        sum += number;
        count += 1;
    }
    if count == 0 {
        return Ok(serde_json::Value::Null);
    }
    serde_json::Number::from_f64(sum / count as f64)
        .map(serde_json::Value::Number)
        .ok_or_else(|| "average aggregate produced a non-finite number".into())
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
        let documents = self.get_many_stored(collection, candidate_ids)?;
        let mut values = Vec::new();
        for document in documents {
            let Some(document) = document else {
                continue;
            };
            let value = serde_json::from_slice::<serde_json::Value>(&document)
                .map_err(|error| error.to_string())?;
            let serde_json::Value::Object(map) = value else {
                return Err("aggregate documents must be JSON objects".into());
            };
            values.push(map.get(field).cloned().unwrap_or(serde_json::Value::Null));
        }
        let result = aggregate_json_values(&values, operation)?;
        serde_json::to_vec(&result).map_err(|error| error.to_string())
    }
    fn collection_revision(&self, collection: &str) -> Result<u64, String>;
    fn register_schemas(&mut self, manifest: &SchemaManifest) -> Result<(), String>;
    fn schema_version(&self, collection: &str) -> Result<Option<u64>, String>;
    fn storage_metadata(&self) -> Result<StorageMetadata, String>;
    fn rebuild_indexes(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String>;

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
}
