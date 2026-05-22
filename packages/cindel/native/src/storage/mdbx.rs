use std::borrow::Cow;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use libmdbx::{
    Database, DatabaseOptions, NoWriteMap, Table, TableFlags, Transaction, WriteFlags, RO, RW,
};

use super::mdbx_key::{
    decode_key_document_id, encode_collection_key, encode_document_key, encode_index_equal_prefix,
    encode_index_key, encode_index_range, encode_unique_index_key, COLLECTION_REVISIONS_TABLE,
    DOCUMENTS_TABLE, ID_COUNTERS_TABLE, INDEXES_TABLE, SCHEMA_COLLECTIONS_TABLE,
    SCHEMA_MIGRATIONS_TABLE, UNIQUE_INDEXES_TABLE,
};
use super::{DocumentWrite, IndexEntry, IndexValue, SchemaManifest, StorageEngine};

const IN_MEMORY_DIRECTORY: &str = ":memory:";
const EMPTY_VALUE: &[u8] = &[];

pub struct MdbxStorage {
    database: Database<NoWriteMap>,
    _temporary_directory: Option<TemporaryDirectoryGuard>,
}

impl MdbxStorage {
    pub fn open(directory: &str) -> Result<Self, String> {
        let (path, temporary_directory) = if directory == IN_MEMORY_DIRECTORY {
            let path = temporary_mdbx_directory()?;
            (path.clone(), Some(TemporaryDirectoryGuard { path }))
        } else {
            (PathBuf::from(directory), None)
        };

        fs::create_dir_all(&path).map_err(|error| error.to_string())?;
        let database = Database::<NoWriteMap>::open_with_options(
            &path,
            DatabaseOptions {
                max_tables: Some(16),
                ..Default::default()
            },
        )
        .map_err(|error| error.to_string())?;

        let storage = Self {
            database,
            _temporary_directory: temporary_directory,
        };
        storage.initialize()?;
        Ok(storage)
    }

    fn initialize(&self) -> Result<(), String> {
        let transaction = self
            .database
            .begin_rw_txn()
            .map_err(|error| error.to_string())?;
        create_tables(&transaction)?;
        transaction
            .commit()
            .map(|_| ())
            .map_err(|error| error.to_string())
    }

    fn with_read_transaction<T>(
        &self,
        action: impl for<'txn> FnOnce(
            &'txn Transaction<'_, RO, NoWriteMap>,
            MdbxTables<'txn>,
        ) -> Result<T, String>,
    ) -> Result<T, String> {
        let transaction = self
            .database
            .begin_ro_txn()
            .map_err(|error| error.to_string())?;
        let tables = open_tables(&transaction)?;
        let result = action(&transaction, tables)?;
        transaction.commit().map_err(|error| error.to_string())?;
        Ok(result)
    }

    fn with_write_transaction<T>(
        &self,
        action: impl for<'txn> FnOnce(
            &'txn Transaction<'_, RW, NoWriteMap>,
            MdbxTables<'txn>,
        ) -> Result<T, String>,
    ) -> Result<T, String> {
        let transaction = self
            .database
            .begin_rw_txn()
            .map_err(|error| error.to_string())?;
        let tables = open_tables(&transaction)?;
        let result = action(&transaction, tables)?;
        transaction.commit().map_err(|error| error.to_string())?;
        Ok(result)
    }
}

impl StorageEngine for MdbxStorage {
    fn begin_read_transaction(&mut self) -> Result<(), String> {
        Err("MDBX explicit transactions are not implemented yet.".into())
    }

    fn begin_write_transaction(&mut self) -> Result<(), String> {
        Err("MDBX explicit transactions are not implemented yet.".into())
    }

    fn commit_transaction(&mut self) -> Result<(), String> {
        Err("MDBX explicit transactions are not implemented yet.".into())
    }

    fn rollback_transaction(&mut self) -> Result<(), String> {
        Err("MDBX explicit transactions are not implemented yet.".into())
    }

    fn allocate_id(&mut self, collection: &str) -> Result<u64, String> {
        self.with_write_transaction(|transaction, tables| {
            let key = encode_collection_key(collection);
            let next_id = transaction
                .get::<Vec<u8>>(&tables.id_counters, &key)
                .map_err(|error| error.to_string())?
                .map(|bytes| decode_u64(&bytes))
                .transpose()?
                .unwrap_or(1);
            let following = next_id
                .checked_add(1)
                .ok_or_else(|| format!("id counter for collection `{collection}` overflowed"))?;
            transaction
                .put(
                    &tables.id_counters,
                    &key,
                    following.to_be_bytes(),
                    WriteFlags::UPSERT,
                )
                .map_err(|error| error.to_string())?;
            Ok(next_id)
        })
    }

    fn get(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String> {
        self.with_read_transaction(|transaction, tables| {
            transaction
                .get::<Vec<u8>>(&tables.documents, &encode_document_key(collection, id))
                .map_err(|error| error.to_string())
        })
    }

    fn get_many(&self, collection: &str, ids: &[u64]) -> Result<Vec<Option<Vec<u8>>>, String> {
        self.with_read_transaction(|transaction, tables| {
            ids.iter()
                .map(|id| {
                    transaction
                        .get::<Vec<u8>>(&tables.documents, &encode_document_key(collection, *id))
                        .map_err(|error| error.to_string())
                })
                .collect()
        })
    }

    fn document_ids(&self, collection: &str) -> Result<Vec<u64>, String> {
        self.with_read_transaction(|transaction, tables| {
            let prefix = encode_collection_key(collection);
            scan_ids_by_key_range(transaction, &tables.documents, &prefix, None)
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
        self.with_write_transaction(|transaction, tables| {
            put_document_with_indexes(transaction, &tables, collection, id, bytes, indexes)?;
            bump_collection_revision(transaction, &tables, collection)
        })
    }

    fn put_many_indexed(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String> {
        self.with_write_transaction(|transaction, tables| {
            for document in documents {
                put_document_with_indexes(
                    transaction,
                    &tables,
                    collection,
                    document.id,
                    &document.bytes,
                    &document.indexes,
                )?;
            }
            if !documents.is_empty() {
                bump_collection_revision(transaction, &tables, collection)?;
            }
            Ok(())
        })
    }

    fn delete(&mut self, collection: &str, id: u64) -> Result<(), String> {
        self.with_write_transaction(|transaction, tables| {
            let deleted = delete_document(transaction, &tables, collection, id)?;
            if deleted {
                bump_collection_revision(transaction, &tables, collection)?;
            }
            Ok(())
        })
    }

    fn delete_many(&mut self, collection: &str, ids: &[u64]) -> Result<(), String> {
        self.with_write_transaction(|transaction, tables| {
            let mut deleted_any = false;
            for id in ids {
                deleted_any |= delete_document(transaction, &tables, collection, *id)?;
            }
            if deleted_any {
                bump_collection_revision(transaction, &tables, collection)?;
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
        self.with_read_transaction(|transaction, tables| {
            let prefix = encode_index_equal_prefix(collection, index, value)?;
            scan_ids_by_key_range(transaction, &tables.indexes, &prefix, None)
        })
    }

    fn query_index_range(
        &self,
        collection: &str,
        index: &str,
        lower: Option<&IndexValue>,
        upper: Option<&IndexValue>,
    ) -> Result<Vec<u64>, String> {
        self.with_read_transaction(|transaction, tables| {
            let range = encode_index_range(collection, index, lower, upper)?;
            scan_ids_by_key_range(
                transaction,
                &tables.indexes,
                &range.start,
                Some(&range.end_inclusive),
            )
        })
    }

    fn collection_revision(&self, collection: &str) -> Result<u64, String> {
        self.with_read_transaction(|transaction, tables| {
            transaction
                .get::<Vec<u8>>(
                    &tables.collection_revisions,
                    &encode_collection_key(collection),
                )
                .map_err(|error| error.to_string())?
                .map(|bytes| decode_u64(&bytes))
                .transpose()
                .map(Option::unwrap_or_default)
        })
    }

    fn register_schemas(&mut self, manifest: &SchemaManifest) -> Result<(), String> {
        self.with_write_transaction(|transaction, tables| {
            for collection in &manifest.collections {
                let schema_json =
                    serde_json::to_vec(collection).map_err(|error| error.to_string())?;
                transaction
                    .put(
                        &tables.schema_collections,
                        encode_collection_key(&collection.name),
                        schema_json,
                        WriteFlags::UPSERT,
                    )
                    .map_err(|error| error.to_string())?;
            }
            Ok(())
        })
    }

    fn register_schemas_after_migration(
        &mut self,
        manifest: &SchemaManifest,
    ) -> Result<(), String> {
        self.register_schemas(manifest)
    }

    fn schema_version(&self, collection: &str) -> Result<Option<u64>, String> {
        self.with_read_transaction(|transaction, tables| {
            transaction
                .get::<Vec<u8>>(
                    &tables.schema_collections,
                    &encode_collection_key(collection),
                )
                .map_err(|error| error.to_string())
                .map(|schema| schema.map(|_| 1))
        })
    }
}

struct MdbxTables<'txn> {
    documents: Table<'txn>,
    indexes: Table<'txn>,
    unique_indexes: Table<'txn>,
    id_counters: Table<'txn>,
    collection_revisions: Table<'txn>,
    schema_collections: Table<'txn>,
    _schema_migrations: Table<'txn>,
}

fn create_tables<'txn>(transaction: &'txn Transaction<'_, RW, NoWriteMap>) -> Result<(), String> {
    transaction
        .create_table(Some(DOCUMENTS_TABLE), TableFlags::default())
        .map_err(|error| error.to_string())?;
    transaction
        .create_table(Some(INDEXES_TABLE), TableFlags::default())
        .map_err(|error| error.to_string())?;
    transaction
        .create_table(Some(UNIQUE_INDEXES_TABLE), TableFlags::default())
        .map_err(|error| error.to_string())?;
    transaction
        .create_table(Some(ID_COUNTERS_TABLE), TableFlags::default())
        .map_err(|error| error.to_string())?;
    transaction
        .create_table(Some(COLLECTION_REVISIONS_TABLE), TableFlags::default())
        .map_err(|error| error.to_string())?;
    transaction
        .create_table(Some(SCHEMA_COLLECTIONS_TABLE), TableFlags::default())
        .map_err(|error| error.to_string())?;
    transaction
        .create_table(Some(SCHEMA_MIGRATIONS_TABLE), TableFlags::default())
        .map_err(|error| error.to_string())?;
    Ok(())
}

fn open_tables<'txn, K>(
    transaction: &'txn Transaction<'_, K, NoWriteMap>,
) -> Result<MdbxTables<'txn>, String>
where
    K: libmdbx::TransactionKind,
{
    Ok(MdbxTables {
        documents: transaction
            .open_table(Some(DOCUMENTS_TABLE))
            .map_err(|error| error.to_string())?,
        indexes: transaction
            .open_table(Some(INDEXES_TABLE))
            .map_err(|error| error.to_string())?,
        unique_indexes: transaction
            .open_table(Some(UNIQUE_INDEXES_TABLE))
            .map_err(|error| error.to_string())?,
        id_counters: transaction
            .open_table(Some(ID_COUNTERS_TABLE))
            .map_err(|error| error.to_string())?,
        collection_revisions: transaction
            .open_table(Some(COLLECTION_REVISIONS_TABLE))
            .map_err(|error| error.to_string())?,
        schema_collections: transaction
            .open_table(Some(SCHEMA_COLLECTIONS_TABLE))
            .map_err(|error| error.to_string())?,
        _schema_migrations: transaction
            .open_table(Some(SCHEMA_MIGRATIONS_TABLE))
            .map_err(|error| error.to_string())?,
    })
}

fn put_document_with_indexes(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    id: u64,
    bytes: &[u8],
    indexes: &[IndexEntry],
) -> Result<(), String> {
    let document_key = encode_document_key(collection, id);
    transaction
        .put(&tables.documents, &document_key, bytes, WriteFlags::UPSERT)
        .map_err(|error| error.to_string())?;
    delete_index_entries(transaction, tables, collection, id)?;
    for index in indexes {
        let key = encode_index_key(collection, &index.name, &index.value, id)?;
        transaction
            .put(&tables.indexes, key, EMPTY_VALUE, WriteFlags::UPSERT)
            .map_err(|error| error.to_string())?;
        let unique_key = encode_unique_index_key(collection, &index.name, &index.value)?;
        transaction
            .put(
                &tables.unique_indexes,
                unique_key,
                id.to_be_bytes(),
                WriteFlags::UPSERT,
            )
            .map_err(|error| error.to_string())?;
    }
    advance_id_counter(transaction, tables, collection, id)
}

fn delete_document(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    id: u64,
) -> Result<bool, String> {
    let deleted = transaction
        .del(&tables.documents, encode_document_key(collection, id), None)
        .map_err(|error| error.to_string())?;
    delete_index_entries(transaction, tables, collection, id)?;
    Ok(deleted)
}

fn delete_index_entries(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    id: u64,
) -> Result<(), String> {
    let collection_prefix = encode_collection_key(collection);
    let keys = {
        let mut cursor = transaction
            .cursor(&tables.indexes)
            .map_err(|error| error.to_string())?;
        let mut keys = Vec::new();
        for row in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(&collection_prefix) {
            let (key, _) = row.map_err(|error| error.to_string())?;
            if !key.starts_with(&collection_prefix) {
                break;
            }
            if decode_key_document_id(&key)? == id {
                keys.push(key.into_owned());
            }
        }
        keys
    };

    for key in keys {
        transaction
            .del(&tables.indexes, key, None)
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn scan_ids_by_key_range(
    transaction: &Transaction<'_, RO, NoWriteMap>,
    table: &Table<'_>,
    start: &[u8],
    end_inclusive: Option<&[u8]>,
) -> Result<Vec<u64>, String> {
    let mut cursor = transaction
        .cursor(table)
        .map_err(|error| error.to_string())?;
    let mut ids = Vec::new();
    for row in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(start) {
        let (key, _) = row.map_err(|error| error.to_string())?;
        if let Some(end_inclusive) = end_inclusive {
            if key.as_ref() > end_inclusive {
                break;
            }
        } else if !key.starts_with(start) {
            break;
        }
        ids.push(decode_key_document_id(&key)?);
    }
    Ok(ids)
}

fn bump_collection_revision(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
) -> Result<(), String> {
    let key = encode_collection_key(collection);
    let current = transaction
        .get::<Vec<u8>>(&tables.collection_revisions, &key)
        .map_err(|error| error.to_string())?
        .map(|bytes| decode_u64(&bytes))
        .transpose()?
        .unwrap_or_default();
    let next = current
        .checked_add(1)
        .ok_or_else(|| format!("collection `{collection}` revision overflowed"))?;
    transaction
        .put(
            &tables.collection_revisions,
            &key,
            next.to_be_bytes(),
            WriteFlags::UPSERT,
        )
        .map_err(|error| error.to_string())
}

fn advance_id_counter(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    id: u64,
) -> Result<(), String> {
    let key = encode_collection_key(collection);
    let next_id = id.saturating_add(1);
    let current = transaction
        .get::<Vec<u8>>(&tables.id_counters, &key)
        .map_err(|error| error.to_string())?
        .map(|bytes| decode_u64(&bytes))
        .transpose()?
        .unwrap_or(1);
    if current >= next_id {
        return Ok(());
    }
    transaction
        .put(
            &tables.id_counters,
            &key,
            next_id.to_be_bytes(),
            WriteFlags::UPSERT,
        )
        .map_err(|error| error.to_string())
}

fn decode_u64(bytes: &[u8]) -> Result<u64, String> {
    let bytes = bytes
        .try_into()
        .map_err(|_| "MDBX stored integer must be 8 bytes".to_string())?;
    Ok(u64::from_be_bytes(bytes))
}

fn temporary_mdbx_directory() -> Result<PathBuf, String> {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_nanos();
    Ok(std::env::temp_dir().join(format!(
        "cindel_mdbx_memory_{}_{}",
        std::process::id(),
        nonce
    )))
}

struct TemporaryDirectoryGuard {
    path: PathBuf,
}

impl Drop for TemporaryDirectoryGuard {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

#[cfg(test)]
mod tests {
    use std::path::Path;
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::*;
    use crate::storage::{CollectionSchemaManifest, FieldSchemaManifest};

    #[test]
    fn opens_mdbx_database_directory() {
        // Scenario: The optional MDBX dependency is enabled for a native build.
        // Covers:
        // - Compiling the `libmdbx` crate behind Cindel's `mdbx` feature.
        // - Opening an MDBX environment with the Windows-compatible default mode.
        // Expected: The prototype opens the database directory without becoming
        //   the default Cindel backend.
        let directory = TemporaryDirectory::new("probe");

        let result = MdbxStorage::open(directory.path());

        assert!(result.is_ok(), "{:?}", result.err());
        assert!(Path::new(directory.path()).exists());
    }

    #[test]
    fn stores_reads_and_queries_indexed_documents() {
        // Scenario: MDBX-04 implements the benchmark's core indexed workload.
        // Covers:
        // - Persistent directory open.
        // - Schema registration.
        // - Indexed writes and point reads.
        // - Equality and range index scans.
        // - Collection revision updates.
        // Expected: Documents round-trip and index queries return deterministic
        //   document ids.
        let directory = TemporaryDirectory::new("prototype");
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        storage.register_schemas(&schema_manifest()).unwrap();

        storage
            .put_indexed(
                "users",
                1,
                br#"{"name":"Ana"}"#,
                &[
                    IndexEntry {
                        name: "email".into(),
                        value: IndexValue::String("ana@example.com".into()),
                    },
                    IndexEntry {
                        name: "score".into(),
                        value: IndexValue::Int(10),
                    },
                ],
            )
            .unwrap();
        storage
            .put_indexed(
                "users",
                2,
                br#"{"name":"Ben"}"#,
                &[
                    IndexEntry {
                        name: "email".into(),
                        value: IndexValue::String("ben@example.com".into()),
                    },
                    IndexEntry {
                        name: "score".into(),
                        value: IndexValue::Int(30),
                    },
                ],
            )
            .unwrap();

        assert_eq!(
            storage.get("users", 1).unwrap(),
            Some(br#"{"name":"Ana"}"#.to_vec())
        );
        assert_eq!(storage.document_ids("users").unwrap(), vec![1, 2]);
        assert_eq!(
            storage
                .query_index_equal(
                    "users",
                    "email",
                    &IndexValue::String("ana@example.com".into())
                )
                .unwrap(),
            vec![1]
        );
        assert_eq!(
            storage
                .query_index_range(
                    "users",
                    "score",
                    Some(&IndexValue::Int(0)),
                    Some(&IndexValue::Int(20))
                )
                .unwrap(),
            vec![1]
        );
        assert_eq!(storage.collection_revision("users").unwrap(), 2);
        assert_eq!(storage.schema_version("users").unwrap(), Some(1));
    }

    #[test]
    fn opens_test_only_in_memory_directory() {
        // Scenario: The storage trait supports an in-memory directory sentinel.
        // Covers:
        // - MDBX-04's documented test-only temporary-directory fallback.
        // - Basic write/read behavior on that fallback.
        // Expected: The temporary environment behaves like a short-lived
        //   database and is removed when dropped.
        let mut storage = MdbxStorage::open(IN_MEMORY_DIRECTORY).unwrap();
        let directory = storage._temporary_directory.as_ref().unwrap().path.clone();

        storage.put("items", 1, b"hello").unwrap();

        assert_eq!(storage.get("items", 1).unwrap(), Some(b"hello".to_vec()));
        assert!(directory.exists());

        drop(storage);

        assert!(!directory.exists());
    }

    fn schema_manifest() -> SchemaManifest {
        SchemaManifest {
            collections: vec![CollectionSchemaManifest {
                name: "users".to_string(),
                id_field: "id".to_string(),
                fields: vec![FieldSchemaManifest {
                    name: "id".to_string(),
                    dart_type: "int".to_string(),
                    is_id: true,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                }],
            }],
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
                "cindel_mdbx_{name}_{}_{}",
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
