#![allow(dead_code)]

use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;

use libmdbx::{
    Database, DatabaseOptions, NoWriteMap, Table, TableFlags, Transaction, WriteFlags, RO, RW,
};
use serde::{Deserialize, Serialize};

use super::mdbx_key::{encode_document_key, encode_index_equal_prefix, encode_index_range};
use super::{
    CollectionSchemaManifest, DocumentWrite, IndexEntry, IndexValue, SchemaManifest, StorageEngine,
};
use super::{DocumentFormatVersion, StorageLayoutVersion, StorageMetadata};

const COUNTERS_TABLE: &str = "__v2_id_counters";
const DOCUMENT_INDEXES_TABLE: &str = "__v2_document_indexes";
const REVISIONS_TABLE: &str = "__v2_collection_revisions";
const SCHEMAS_TABLE: &str = "__v2_schema_collections";
const EMPTY_VALUE: &[u8] = &[];

pub(crate) struct MdbxLayoutV2Storage {
    database: Arc<Database<NoWriteMap>>,
    schemas: HashMap<String, CollectionV2Schema>,
}

#[derive(Clone, Debug, Default)]
struct CollectionV2Schema {
    indexes: HashSet<String>,
    unique_indexes: HashSet<String>,
}

#[derive(Debug, Deserialize, Serialize)]
struct LayoutV2SchemaRecord {
    version: u64,
    schema: CollectionSchemaManifest,
}

impl MdbxLayoutV2Storage {
    pub(crate) fn open(directory: &str) -> Result<Self, String> {
        let path = PathBuf::from(directory);
        fs::create_dir_all(&path).map_err(|error| error.to_string())?;
        let database = Arc::new(
            Database::<NoWriteMap>::open_with_options(
                &path,
                DatabaseOptions {
                    max_tables: Some(2048),
                    accede: true,
                    ..Default::default()
                },
            )
            .map_err(|error| error.to_string())?,
        );
        let storage = Self {
            database,
            schemas: HashMap::new(),
        };
        storage.initialize()?;
        Ok(storage)
    }

    fn initialize(&self) -> Result<(), String> {
        self.with_write_transaction(|transaction| {
            transaction
                .create_table(Some(COUNTERS_TABLE), TableFlags::default())
                .map_err(|error| error.to_string())?;
            transaction
                .create_table(Some(DOCUMENT_INDEXES_TABLE), TableFlags::default())
                .map_err(|error| error.to_string())?;
            transaction
                .create_table(Some(REVISIONS_TABLE), TableFlags::default())
                .map_err(|error| error.to_string())?;
            transaction
                .create_table(Some(SCHEMAS_TABLE), TableFlags::default())
                .map_err(|error| error.to_string())?;
            Ok(())
        })
    }

    fn with_read_transaction<T>(
        &self,
        action: impl FnOnce(&Transaction<'_, RO, NoWriteMap>) -> Result<T, String>,
    ) -> Result<T, String> {
        let transaction = self
            .database
            .begin_ro_txn()
            .map_err(|error| error.to_string())?;
        let result = action(&transaction)?;
        transaction.commit().map_err(|error| error.to_string())?;
        Ok(result)
    }

    fn with_write_transaction<T>(
        &self,
        action: impl FnOnce(&Transaction<'_, RW, NoWriteMap>) -> Result<T, String>,
    ) -> Result<T, String> {
        let transaction = self
            .database
            .begin_rw_txn()
            .map_err(|error| error.to_string())?;
        let result = action(&transaction)?;
        transaction.commit().map_err(|error| error.to_string())?;
        Ok(result)
    }

    fn put_document_with_indexes(
        &self,
        transaction: &Transaction<'_, RW, NoWriteMap>,
        collection: &str,
        id: u64,
        bytes: &[u8],
        indexes: &[IndexEntry],
    ) -> Result<(), String> {
        self.validate_unique_indexes(transaction, collection, id, indexes)?;
        let documents = create_documents_table(transaction, collection)?;
        transaction
            .put(&documents, id_key(id), bytes, WriteFlags::UPSERT)
            .map_err(|error| error.to_string())?;
        self.replace_document_indexes(transaction, collection, id, indexes)?;
        set_id_counter_at_least(transaction, collection, id.saturating_add(1))?;
        Ok(())
    }

    fn validate_unique_indexes(
        &self,
        transaction: &Transaction<'_, RW, NoWriteMap>,
        collection: &str,
        id: u64,
        indexes: &[IndexEntry],
    ) -> Result<(), String> {
        let Some(schema) = self.schemas.get(collection) else {
            return Ok(());
        };
        for index in indexes {
            if !schema.unique_indexes.contains(&index.name) {
                continue;
            }
            let unique_table = create_unique_table(transaction, collection, &index.name)?;
            let key = index_value_key(&index.value)?;
            if let Some(existing_id) = transaction
                .get::<Vec<u8>>(&unique_table, &key)
                .map_err(|error| error.to_string())?
            {
                let existing_id = decode_u64(&existing_id)?;
                if existing_id != id {
                    return Err(format!(
                        "Unique index `{}` already contains this value.",
                        index.name
                    ));
                }
            }
        }
        Ok(())
    }

    fn replace_document_indexes(
        &self,
        transaction: &Transaction<'_, RW, NoWriteMap>,
        collection: &str,
        id: u64,
        indexes: &[IndexEntry],
    ) -> Result<(), String> {
        self.delete_document_indexes(transaction, collection, id)?;
        for index in indexes {
            self.insert_index(transaction, collection, id, index)?;
        }
        let document_indexes = open_document_indexes_table(transaction)?;
        transaction
            .put(
                &document_indexes,
                document_index_key(collection, id),
                serde_json::to_vec(indexes).map_err(|error| error.to_string())?,
                WriteFlags::UPSERT,
            )
            .map_err(|error| error.to_string())?;
        Ok(())
    }

    fn insert_index(
        &self,
        transaction: &Transaction<'_, RW, NoWriteMap>,
        collection: &str,
        id: u64,
        index: &IndexEntry,
    ) -> Result<(), String> {
        let index_table = create_index_table(transaction, collection, &index.name)?;
        transaction
            .put(
                &index_table,
                index_value_key(&index.value)?,
                id_key(id),
                WriteFlags::UPSERT,
            )
            .map_err(|error| error.to_string())?;

        if self
            .schemas
            .get(collection)
            .is_some_and(|schema| schema.unique_indexes.contains(&index.name))
        {
            let unique_table = create_unique_table(transaction, collection, &index.name)?;
            transaction
                .put(
                    &unique_table,
                    index_value_key(&index.value)?,
                    id_key(id),
                    WriteFlags::UPSERT,
                )
                .map_err(|error| error.to_string())?;
        }
        Ok(())
    }

    fn delete_document_indexes(
        &self,
        transaction: &Transaction<'_, RW, NoWriteMap>,
        collection: &str,
        id: u64,
    ) -> Result<(), String> {
        let document_indexes = open_document_indexes_table(transaction)?;
        let key = document_index_key(collection, id);
        let Some(indexes) = transaction
            .get::<Vec<u8>>(&document_indexes, &key)
            .map_err(|error| error.to_string())?
        else {
            return Ok(());
        };
        let indexes = serde_json::from_slice::<Vec<IndexEntry>>(&indexes)
            .map_err(|error| error.to_string())?;
        for index in indexes {
            let index_table = create_index_table(transaction, collection, &index.name)?;
            transaction
                .del(
                    &index_table,
                    index_value_key(&index.value)?,
                    Some(&id_key(id)),
                )
                .map_err(|error| error.to_string())?;
            if self
                .schemas
                .get(collection)
                .is_some_and(|schema| schema.unique_indexes.contains(&index.name))
            {
                let unique_table = create_unique_table(transaction, collection, &index.name)?;
                transaction
                    .del(&unique_table, index_value_key(&index.value)?, None)
                    .map_err(|error| error.to_string())?;
            }
        }
        transaction
            .del(&document_indexes, key, None)
            .map_err(|error| error.to_string())?;
        Ok(())
    }

    fn registered_indexes(&self, collection: &str) -> CollectionV2Schema {
        self.schemas.get(collection).cloned().unwrap_or_default()
    }
}

impl StorageEngine for MdbxLayoutV2Storage {
    fn begin_read_transaction(&mut self) -> Result<(), String> {
        Err("layout v2 spike does not implement explicit transactions".into())
    }

    fn begin_write_transaction(&mut self) -> Result<(), String> {
        Err("layout v2 spike does not implement explicit transactions".into())
    }

    fn commit_transaction(&mut self) -> Result<(), String> {
        Err("layout v2 spike does not implement explicit transactions".into())
    }

    fn rollback_transaction(&mut self) -> Result<(), String> {
        Err("layout v2 spike does not implement explicit transactions".into())
    }

    fn allocate_id(&mut self, collection: &str) -> Result<u64, String> {
        self.with_write_transaction(|transaction| {
            let counters = open_counters_table(transaction)?;
            let key = collection_key(collection);
            let id = transaction
                .get::<Vec<u8>>(&counters, &key)
                .map_err(|error| error.to_string())?
                .map(|bytes| decode_u64(&bytes))
                .transpose()?
                .unwrap_or(1);
            transaction
                .put(
                    &counters,
                    key,
                    id_key(id.saturating_add(1)),
                    WriteFlags::UPSERT,
                )
                .map_err(|error| error.to_string())?;
            Ok(id)
        })
    }

    fn get(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String> {
        self.with_read_transaction(|transaction| {
            let documents = open_documents_table(transaction, collection)?;
            transaction
                .get::<Vec<u8>>(&documents, &id_key(id))
                .map_err(|error| error.to_string())
        })
    }

    fn get_many(&self, collection: &str, ids: &[u64]) -> Result<Vec<Option<Vec<u8>>>, String> {
        self.with_read_transaction(|transaction| {
            let documents = open_documents_table(transaction, collection)?;
            ids.iter()
                .map(|id| {
                    transaction
                        .get::<Vec<u8>>(&documents, &id_key(*id))
                        .map_err(|error| error.to_string())
                })
                .collect()
        })
    }

    fn document_ids(&self, collection: &str) -> Result<Vec<u64>, String> {
        self.with_read_transaction(|transaction| {
            let documents = open_documents_table(transaction, collection)?;
            let mut cursor = transaction
                .cursor(&documents)
                .map_err(|error| error.to_string())?;
            let mut ids = Vec::new();
            for row in cursor.iter_start::<Cow<'_, [u8]>, Cow<'_, [u8]>>() {
                let (key, _) = row.map_err(|error| error.to_string())?;
                ids.push(decode_u64(&key)?);
            }
            Ok(ids)
        })
    }

    fn put(&mut self, collection: &str, id: u64, bytes: &[u8]) -> Result<(), String> {
        self.put_indexed(collection, id, bytes, &[])
    }

    fn put_indexed(
        &mut self,
        collection: &str,
        id: u64,
        bytes: &[u8],
        indexes: &[IndexEntry],
    ) -> Result<(), String> {
        self.with_write_transaction(|transaction| {
            self.put_document_with_indexes(transaction, collection, id, bytes, indexes)?;
            bump_collection_revision(transaction, collection)
        })
    }

    fn put_many_indexed(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String> {
        self.with_write_transaction(|transaction| {
            for document in documents {
                self.put_document_with_indexes(
                    transaction,
                    collection,
                    document.id,
                    &document.bytes,
                    &document.indexes,
                )?;
            }
            if !documents.is_empty() {
                bump_collection_revision(transaction, collection)?;
            }
            Ok(())
        })
    }

    fn delete(&mut self, collection: &str, id: u64) -> Result<(), String> {
        self.with_write_transaction(|transaction| {
            let documents = create_documents_table(transaction, collection)?;
            let deleted = transaction
                .del(&documents, id_key(id), None)
                .map_err(|error| error.to_string())?;
            self.delete_document_indexes(transaction, collection, id)?;
            if deleted {
                bump_collection_revision(transaction, collection)?;
            }
            Ok(())
        })
    }

    fn delete_many(&mut self, collection: &str, ids: &[u64]) -> Result<(), String> {
        self.with_write_transaction(|transaction| {
            let documents = create_documents_table(transaction, collection)?;
            let mut deleted_any = false;
            for id in ids {
                deleted_any |= transaction
                    .del(&documents, id_key(*id), None)
                    .map_err(|error| error.to_string())?;
                self.delete_document_indexes(transaction, collection, *id)?;
            }
            if deleted_any {
                bump_collection_revision(transaction, collection)?;
            }
            Ok(())
        })
    }

    fn query_index_equal(
        &self,
        collection: &str,
        index: &str,
        value: &IndexValue,
    ) -> Result<Vec<u64>, String> {
        self.with_read_transaction(|transaction| {
            let index_table = open_index_table(transaction, collection, index)?;
            let key = index_value_key(value)?;
            let mut cursor = transaction
                .cursor(&index_table)
                .map_err(|error| error.to_string())?;
            let mut ids = Vec::new();
            for row in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(&key) {
                let (entry_key, value) = row.map_err(|error| error.to_string())?;
                if entry_key.as_ref() != key.as_slice() {
                    break;
                }
                ids.push(decode_u64(&value)?);
            }
            Ok(ids)
        })
    }

    fn query_index_range(
        &self,
        collection: &str,
        index: &str,
        lower: Option<&IndexValue>,
        upper: Option<&IndexValue>,
    ) -> Result<Vec<u64>, String> {
        let range = encode_index_range("", "", lower, upper)?;
        self.with_read_transaction(|transaction| {
            let index_table = open_index_table(transaction, collection, index)?;
            let mut cursor = transaction
                .cursor(&index_table)
                .map_err(|error| error.to_string())?;
            let mut ids = Vec::new();
            for row in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(&range.start) {
                let (key, value) = row.map_err(|error| error.to_string())?;
                if key.as_ref() > range.end_inclusive.as_slice() {
                    break;
                }
                ids.push(decode_u64(&value)?);
            }
            Ok(ids)
        })
    }

    fn collection_revision(&self, collection: &str) -> Result<u64, String> {
        self.with_read_transaction(|transaction| {
            let revisions = open_revisions_table(transaction)?;
            transaction
                .get::<Vec<u8>>(&revisions, &collection_key(collection))
                .map_err(|error| error.to_string())?
                .map(|bytes| decode_u64(&bytes))
                .transpose()
                .map(|value| value.unwrap_or(0))
        })
    }

    fn register_schemas(&mut self, manifest: &SchemaManifest) -> Result<(), String> {
        let mut schemas = HashMap::new();
        self.with_write_transaction(|transaction| {
            let schemas_table = open_schemas_table(transaction)?;
            for collection in &manifest.collections {
                create_documents_table(transaction, &collection.name)?;
                let mut schema = CollectionV2Schema::default();
                for field in &collection.fields {
                    if !field.is_indexed {
                        continue;
                    }
                    schema.indexes.insert(field.name.clone());
                    create_index_table(transaction, &collection.name, &field.name)?;
                    if field.is_index_unique {
                        schema.unique_indexes.insert(field.name.clone());
                        create_unique_table(transaction, &collection.name, &field.name)?;
                    }
                }
                let version = transaction
                    .get::<Vec<u8>>(&schemas_table, &collection_key(&collection.name))
                    .map_err(|error| error.to_string())?
                    .map(|bytes| decode_schema_record(&bytes).map(|record| record.version))
                    .transpose()?
                    .unwrap_or(1);
                let record = LayoutV2SchemaRecord {
                    version,
                    schema: collection.clone(),
                };
                transaction
                    .put(
                        &schemas_table,
                        collection_key(&collection.name),
                        serde_json::to_vec(&record).map_err(|error| error.to_string())?,
                        WriteFlags::UPSERT,
                    )
                    .map_err(|error| error.to_string())?;
                schemas.insert(collection.name.clone(), schema);
            }
            Ok(())
        })?;
        self.schemas = schemas;
        Ok(())
    }

    fn schema_version(&self, collection: &str) -> Result<Option<u64>, String> {
        self.with_read_transaction(|transaction| {
            let schemas = open_schemas_table(transaction)?;
            transaction
                .get::<Vec<u8>>(&schemas, &collection_key(collection))
                .map_err(|error| error.to_string())?
                .map(|bytes| decode_schema_record(&bytes).map(|record| record.version))
                .transpose()
        })
    }

    fn storage_metadata(&self) -> Result<StorageMetadata, String> {
        Ok(StorageMetadata {
            layout: StorageLayoutVersion::MdbxV2,
            document_format: DocumentFormatVersion::JsonV1,
        })
    }

    fn rebuild_indexes(
        &mut self,
        _collection: &str,
        _documents: &[DocumentWrite],
    ) -> Result<(), String> {
        Err("layout v2 spike does not implement native index rebuild".into())
    }
}

fn create_documents_table<'txn>(
    transaction: &'txn Transaction<'_, RW, NoWriteMap>,
    collection: &str,
) -> Result<Table<'txn>, String> {
    transaction
        .create_table(
            Some(&documents_table_name(collection)),
            TableFlags::default(),
        )
        .map_err(|error| error.to_string())
}

fn open_documents_table<'txn, K>(
    transaction: &'txn Transaction<'_, K, NoWriteMap>,
    collection: &str,
) -> Result<Table<'txn>, String>
where
    K: libmdbx::TransactionKind,
{
    transaction
        .open_table(Some(&documents_table_name(collection)))
        .map_err(|error| error.to_string())
}

fn create_index_table<'txn>(
    transaction: &'txn Transaction<'_, RW, NoWriteMap>,
    collection: &str,
    index: &str,
) -> Result<Table<'txn>, String> {
    transaction
        .create_table(
            Some(&index_table_name(collection, index)),
            TableFlags::DUP_SORT,
        )
        .map_err(|error| error.to_string())
}

fn open_index_table<'txn, K>(
    transaction: &'txn Transaction<'_, K, NoWriteMap>,
    collection: &str,
    index: &str,
) -> Result<Table<'txn>, String>
where
    K: libmdbx::TransactionKind,
{
    transaction
        .open_table(Some(&index_table_name(collection, index)))
        .map_err(|error| error.to_string())
}

fn create_unique_table<'txn>(
    transaction: &'txn Transaction<'_, RW, NoWriteMap>,
    collection: &str,
    index: &str,
) -> Result<Table<'txn>, String> {
    transaction
        .create_table(
            Some(&unique_table_name(collection, index)),
            TableFlags::default(),
        )
        .map_err(|error| error.to_string())
}

fn open_counters_table<'txn>(
    transaction: &'txn Transaction<'_, RW, NoWriteMap>,
) -> Result<Table<'txn>, String> {
    transaction
        .open_table(Some(COUNTERS_TABLE))
        .map_err(|error| error.to_string())
}

fn open_document_indexes_table<'txn>(
    transaction: &'txn Transaction<'_, RW, NoWriteMap>,
) -> Result<Table<'txn>, String> {
    transaction
        .open_table(Some(DOCUMENT_INDEXES_TABLE))
        .map_err(|error| error.to_string())
}

fn open_revisions_table<'txn, K>(
    transaction: &'txn Transaction<'_, K, NoWriteMap>,
) -> Result<Table<'txn>, String>
where
    K: libmdbx::TransactionKind,
{
    transaction
        .open_table(Some(REVISIONS_TABLE))
        .map_err(|error| error.to_string())
}

fn open_schemas_table<'txn, K>(
    transaction: &'txn Transaction<'_, K, NoWriteMap>,
) -> Result<Table<'txn>, String>
where
    K: libmdbx::TransactionKind,
{
    transaction
        .open_table(Some(SCHEMAS_TABLE))
        .map_err(|error| error.to_string())
}

fn set_id_counter_at_least(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    collection: &str,
    next_id: u64,
) -> Result<(), String> {
    let counters = open_counters_table(transaction)?;
    let key = collection_key(collection);
    let current = transaction
        .get::<Vec<u8>>(&counters, &key)
        .map_err(|error| error.to_string())?
        .map(|bytes| decode_u64(&bytes))
        .transpose()?
        .unwrap_or(1);
    if current < next_id {
        transaction
            .put(&counters, key, id_key(next_id), WriteFlags::UPSERT)
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn bump_collection_revision(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    collection: &str,
) -> Result<(), String> {
    let revisions = open_revisions_table(transaction)?;
    let key = collection_key(collection);
    let next_revision = transaction
        .get::<Vec<u8>>(&revisions, &key)
        .map_err(|error| error.to_string())?
        .map(|bytes| decode_u64(&bytes))
        .transpose()?
        .unwrap_or(0)
        .saturating_add(1);
    transaction
        .put(&revisions, key, id_key(next_revision), WriteFlags::UPSERT)
        .map_err(|error| error.to_string())?;
    Ok(())
}

fn decode_schema_record(bytes: &[u8]) -> Result<LayoutV2SchemaRecord, String> {
    serde_json::from_slice(bytes).map_err(|error| error.to_string())
}

fn documents_table_name(collection: &str) -> String {
    format!("v2:documents:{collection}")
}

fn index_table_name(collection: &str, index: &str) -> String {
    format!("v2:index:{collection}:{index}")
}

fn unique_table_name(collection: &str, index: &str) -> String {
    format!("v2:unique:{collection}:{index}")
}

fn collection_key(collection: &str) -> Vec<u8> {
    collection.as_bytes().to_vec()
}

fn document_index_key(collection: &str, id: u64) -> Vec<u8> {
    encode_document_key(collection, id)
}

fn index_value_key(value: &IndexValue) -> Result<Vec<u8>, String> {
    encode_index_equal_prefix("", "", value)
}

fn id_key(id: u64) -> [u8; 8] {
    id.to_be_bytes()
}

fn decode_u64(bytes: &[u8]) -> Result<u64, String> {
    let bytes = bytes
        .try_into()
        .map_err(|_| "encoded u64 value must be 8 bytes".to_string())?;
    Ok(u64::from_be_bytes(bytes))
}

#[cfg(test)]
mod tests {
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::*;
    use crate::storage::{FieldSchemaManifest, StorageEngine};

    #[test]
    fn layout_v2_spike_stores_queries_and_deletes_indexed_documents() {
        // Scenario: PERF-03 explores one table per collection and per index.
        // Covers:
        // - Per-collection document tables.
        // - Per-index duplicate-sorted tables.
        // - Reverse index metadata for replacement and deletion.
        // Expected: Core benchmark-style operations work without touching the
        //   production MDBX layout.
        let directory = TemporaryDirectory::new("layout_v2_spike");
        let mut storage = MdbxLayoutV2Storage::open(directory.path()).unwrap();
        storage.register_schemas(&schema_manifest()).unwrap();

        storage
            .put_indexed(
                "users",
                1,
                br#"{"email":"a@example.com","score":10}"#,
                &[
                    index("email", IndexValue::String("a@example.com".into())),
                    index("score", IndexValue::Int(10)),
                ],
            )
            .unwrap();
        storage
            .put_indexed(
                "users",
                2,
                br#"{"email":"a@example.com","score":20}"#,
                &[
                    index("email", IndexValue::String("a@example.com".into())),
                    index("score", IndexValue::Int(20)),
                ],
            )
            .unwrap();

        assert_eq!(storage.document_ids("users").unwrap(), vec![1, 2]);
        assert_eq!(
            storage
                .query_index_equal(
                    "users",
                    "email",
                    &IndexValue::String("a@example.com".into())
                )
                .unwrap(),
            vec![1, 2]
        );
        assert_eq!(
            storage
                .query_index_range(
                    "users",
                    "score",
                    Some(&IndexValue::Int(15)),
                    Some(&IndexValue::Int(30)),
                )
                .unwrap(),
            vec![2]
        );

        storage
            .put_indexed(
                "users",
                1,
                br#"{"email":"b@example.com","score":30}"#,
                &[
                    index("email", IndexValue::String("b@example.com".into())),
                    index("score", IndexValue::Int(30)),
                ],
            )
            .unwrap();
        assert_eq!(
            storage
                .query_index_equal(
                    "users",
                    "email",
                    &IndexValue::String("a@example.com".into())
                )
                .unwrap(),
            vec![2]
        );
        storage.delete("users", 2).unwrap();
        assert_eq!(
            storage
                .query_index_equal(
                    "users",
                    "email",
                    &IndexValue::String("a@example.com".into())
                )
                .unwrap(),
            Vec::<u64>::new()
        );
        assert_eq!(storage.collection_revision("users").unwrap(), 4);
    }

    fn schema_manifest() -> SchemaManifest {
        SchemaManifest {
            collections: vec![CollectionSchemaManifest {
                name: "users".to_string(),
                id_field: "id".to_string(),
                fields: vec![
                    field("id", "int", true, false, false),
                    field("email", "String", false, true, false),
                    field("score", "int", false, true, false),
                ],
                composite_indexes: Vec::new(),
            }],
        }
    }

    fn field(
        name: &str,
        dart_type: &str,
        is_id: bool,
        is_indexed: bool,
        is_index_unique: bool,
    ) -> FieldSchemaManifest {
        FieldSchemaManifest {
            name: name.to_string(),
            dart_type: dart_type.to_string(),
            is_id,
            is_indexed,
            is_index_unique,
            index_case_sensitive: true,
            index_type: "value".to_string(),
        }
    }

    fn index(name: &str, value: IndexValue) -> IndexEntry {
        IndexEntry {
            name: name.to_string(),
            value,
        }
    }

    struct TemporaryDirectory {
        path: PathBuf,
    }

    impl TemporaryDirectory {
        fn new(name: &str) -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "cindel_mdbx_v2_{name}_{}_{}",
                std::process::id(),
                nonce
            ));
            Self { path }
        }

        fn path(&self) -> &str {
            self.path.to_str().expect("temporary path must be UTF-8")
        }
    }

    impl Drop for TemporaryDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }
}
