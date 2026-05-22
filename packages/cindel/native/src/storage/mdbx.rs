use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use libmdbx::{
    Database, DatabaseOptions, NoWriteMap, Table, TableFlags, Transaction, WriteFlags, RO, RW,
};
use serde::{Deserialize, Serialize};

use super::mdbx_key::{
    decode_key_document_id, encode_collection_key, encode_document_key, encode_index_equal_prefix,
    encode_index_key, encode_index_range, encode_unique_index_key, COLLECTION_REVISIONS_TABLE,
    DOCUMENTS_TABLE, ID_COUNTERS_TABLE, INDEXES_TABLE, SCHEMA_COLLECTIONS_TABLE,
    SCHEMA_MIGRATIONS_TABLE, UNIQUE_INDEXES_TABLE,
};
use super::{
    CollectionSchemaManifest, DocumentWrite, FieldSchemaManifest, IndexEntry, IndexValue,
    SchemaManifest, StorageEngine,
};

const IN_MEMORY_DIRECTORY: &str = ":memory:";
const EMPTY_VALUE: &[u8] = &[];

pub struct MdbxStorage {
    database: Database<NoWriteMap>,
    active_transaction: Option<MdbxActiveTransaction>,
    _temporary_directory: Option<TemporaryDirectoryGuard>,
}

enum MdbxActiveTransaction {
    Read,
    Write(MdbxWriteTransaction),
}

#[derive(Default)]
struct MdbxWriteTransaction {
    operations: Vec<MdbxWriteOperation>,
    next_ids: HashMap<String, u64>,
}

enum MdbxWriteOperation {
    PutIndexed {
        collection: String,
        id: u64,
        bytes: Vec<u8>,
        indexes: Vec<IndexEntry>,
    },
    PutManyIndexed {
        collection: String,
        documents: Vec<DocumentWrite>,
    },
    Delete {
        collection: String,
        id: u64,
    },
    DeleteMany {
        collection: String,
        ids: Vec<u64>,
    },
    RegisterSchemas {
        manifest: SchemaManifest,
        mode: SchemaRegistrationMode,
    },
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
            active_transaction: None,
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

    fn ensure_can_write(&self) -> Result<(), String> {
        match self.active_transaction {
            Some(MdbxActiveTransaction::Read) => {
                Err("write attempted inside read transaction".into())
            }
            Some(MdbxActiveTransaction::Write(_)) | None => Ok(()),
        }
    }

    fn active_write_mut(&mut self) -> Option<&mut MdbxWriteTransaction> {
        match &mut self.active_transaction {
            Some(MdbxActiveTransaction::Write(transaction)) => Some(transaction),
            Some(MdbxActiveTransaction::Read) | None => None,
        }
    }

    fn current_next_id(&self, collection: &str) -> Result<u64, String> {
        self.with_read_transaction(|transaction, tables| {
            transaction
                .get::<Vec<u8>>(&tables.id_counters, &encode_collection_key(collection))
                .map_err(|error| error.to_string())?
                .map(|bytes| decode_u64(&bytes))
                .transpose()
                .map(|value| value.unwrap_or(1))
        })
    }

    fn advance_staged_id_counter(
        &mut self,
        collection: &str,
        id: u64,
        fallback_next_id: Option<u64>,
    ) -> Result<(), String> {
        let Some(transaction) = self.active_write_mut() else {
            return Ok(());
        };
        let next_id = id.saturating_add(1);
        let current = match transaction.next_ids.get(collection).copied() {
            Some(current) => current,
            None => fallback_next_id.unwrap_or(1),
        };
        if current < next_id {
            transaction.next_ids.insert(collection.to_string(), next_id);
        } else {
            transaction.next_ids.insert(collection.to_string(), current);
        }
        Ok(())
    }

    fn commit_staged_write(&self, staged: MdbxWriteTransaction) -> Result<(), String> {
        self.with_write_transaction(|transaction, tables| {
            for operation in staged.operations {
                match operation {
                    MdbxWriteOperation::PutIndexed {
                        collection,
                        id,
                        bytes,
                        indexes,
                    } => {
                        let unique_indexes = unique_index_names(transaction, &tables, &collection)?;
                        put_document_with_indexes(
                            transaction,
                            &tables,
                            &collection,
                            id,
                            &bytes,
                            &indexes,
                            &unique_indexes,
                        )?;
                        bump_collection_revision(transaction, &tables, &collection)?;
                    }
                    MdbxWriteOperation::PutManyIndexed {
                        collection,
                        documents,
                    } => {
                        let unique_indexes = unique_index_names(transaction, &tables, &collection)?;
                        for document in &documents {
                            put_document_with_indexes(
                                transaction,
                                &tables,
                                &collection,
                                document.id,
                                &document.bytes,
                                &document.indexes,
                                &unique_indexes,
                            )?;
                        }
                        if !documents.is_empty() {
                            bump_collection_revision(transaction, &tables, &collection)?;
                        }
                    }
                    MdbxWriteOperation::Delete { collection, id } => {
                        let deleted = delete_document(transaction, &tables, &collection, id)?;
                        if deleted {
                            bump_collection_revision(transaction, &tables, &collection)?;
                        }
                    }
                    MdbxWriteOperation::DeleteMany { collection, ids } => {
                        let mut deleted_any = false;
                        for id in ids {
                            deleted_any |= delete_document(transaction, &tables, &collection, id)?;
                        }
                        if deleted_any {
                            bump_collection_revision(transaction, &tables, &collection)?;
                        }
                    }
                    MdbxWriteOperation::RegisterSchemas { manifest, mode } => {
                        for collection in &manifest.collections {
                            register_collection_schema(transaction, &tables, collection, mode)?;
                        }
                    }
                }
            }

            for (collection, next_id) in staged.next_ids {
                set_id_counter_at_least(transaction, &tables, &collection, next_id)?;
            }
            Ok(())
        })
    }
}

impl StorageEngine for MdbxStorage {
    fn begin_read_transaction(&mut self) -> Result<(), String> {
        if self.active_transaction.is_some() {
            return Err("a transaction is already active".into());
        }
        self.active_transaction = Some(MdbxActiveTransaction::Read);
        Ok(())
    }

    fn begin_write_transaction(&mut self) -> Result<(), String> {
        if self.active_transaction.is_some() {
            return Err("a transaction is already active".into());
        }
        self.active_transaction =
            Some(MdbxActiveTransaction::Write(MdbxWriteTransaction::default()));
        Ok(())
    }

    fn commit_transaction(&mut self) -> Result<(), String> {
        let Some(active_transaction) = self.active_transaction.take() else {
            return Err("no active transaction to commit".into());
        };

        match active_transaction {
            MdbxActiveTransaction::Read => Ok(()),
            MdbxActiveTransaction::Write(staged) => match self.commit_staged_write(staged) {
                Ok(()) => Ok(()),
                Err(error) => {
                    self.active_transaction =
                        Some(MdbxActiveTransaction::Write(MdbxWriteTransaction::default()));
                    Err(error)
                }
            },
        }
    }

    fn rollback_transaction(&mut self) -> Result<(), String> {
        if self.active_transaction.is_none() {
            return Err("no active transaction to rollback".into());
        }
        self.active_transaction = None;
        Ok(())
    }

    fn allocate_id(&mut self, collection: &str) -> Result<u64, String> {
        self.ensure_can_write()?;
        if let Some(MdbxActiveTransaction::Write(transaction)) = &self.active_transaction {
            if let Some(next_id) = transaction.next_ids.get(collection).copied() {
                let following = next_id.checked_add(1).ok_or_else(|| {
                    format!("id counter for collection `{collection}` overflowed")
                })?;
                self.active_write_mut()
                    .expect("write transaction must still be active")
                    .next_ids
                    .insert(collection.to_string(), following);
                return Ok(next_id);
            }
        }
        if self.active_write_mut().is_some() {
            let next_id = self.current_next_id(collection)?;
            let following = next_id
                .checked_add(1)
                .ok_or_else(|| format!("id counter for collection `{collection}` overflowed"))?;
            self.active_write_mut()
                .expect("write transaction must still be active")
                .next_ids
                .insert(collection.to_string(), following);
            return Ok(next_id);
        }

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
        self.ensure_can_write()?;
        if self.active_write_mut().is_some() {
            let fallback_next_id = self.current_next_id(collection)?;
            self.advance_staged_id_counter(collection, id, Some(fallback_next_id))?;
            self.active_write_mut()
                .expect("write transaction must still be active")
                .operations
                .push(MdbxWriteOperation::PutIndexed {
                    collection: collection.to_string(),
                    id,
                    bytes: bytes.to_vec(),
                    indexes: indexes.to_vec(),
                });
            return Ok(());
        }

        self.with_write_transaction(|transaction, tables| {
            let unique_indexes = unique_index_names(transaction, &tables, collection)?;
            put_document_with_indexes(
                transaction,
                &tables,
                collection,
                id,
                bytes,
                indexes,
                &unique_indexes,
            )?;
            bump_collection_revision(transaction, &tables, collection)
        })
    }

    fn put_many_indexed(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String> {
        self.ensure_can_write()?;
        if self.active_write_mut().is_some() {
            let fallback_next_id = self.current_next_id(collection)?;
            for document in documents {
                self.advance_staged_id_counter(collection, document.id, Some(fallback_next_id))?;
            }
            self.active_write_mut()
                .expect("write transaction must still be active")
                .operations
                .push(MdbxWriteOperation::PutManyIndexed {
                    collection: collection.to_string(),
                    documents: documents.to_vec(),
                });
            return Ok(());
        }

        self.with_write_transaction(|transaction, tables| {
            let unique_indexes = unique_index_names(transaction, &tables, collection)?;
            for document in documents {
                put_document_with_indexes(
                    transaction,
                    &tables,
                    collection,
                    document.id,
                    &document.bytes,
                    &document.indexes,
                    &unique_indexes,
                )?;
            }
            if !documents.is_empty() {
                bump_collection_revision(transaction, &tables, collection)?;
            }
            Ok(())
        })
    }

    fn delete(&mut self, collection: &str, id: u64) -> Result<(), String> {
        self.ensure_can_write()?;
        if self.active_write_mut().is_some() {
            self.active_write_mut()
                .expect("write transaction must still be active")
                .operations
                .push(MdbxWriteOperation::Delete {
                    collection: collection.to_string(),
                    id,
                });
            return Ok(());
        }

        self.with_write_transaction(|transaction, tables| {
            let deleted = delete_document(transaction, &tables, collection, id)?;
            if deleted {
                bump_collection_revision(transaction, &tables, collection)?;
            }
            Ok(())
        })
    }

    fn delete_many(&mut self, collection: &str, ids: &[u64]) -> Result<(), String> {
        self.ensure_can_write()?;
        if self.active_write_mut().is_some() {
            self.active_write_mut()
                .expect("write transaction must still be active")
                .operations
                .push(MdbxWriteOperation::DeleteMany {
                    collection: collection.to_string(),
                    ids: ids.to_vec(),
                });
            return Ok(());
        }

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
        validate_schema_manifest(manifest)?;
        self.ensure_can_write()?;
        if self.active_write_mut().is_some() {
            self.active_write_mut()
                .expect("write transaction must still be active")
                .operations
                .push(MdbxWriteOperation::RegisterSchemas {
                    manifest: manifest.clone(),
                    mode: SchemaRegistrationMode::Compatible,
                });
            return Ok(());
        }

        self.with_write_transaction(|transaction, tables| {
            for collection in &manifest.collections {
                register_collection_schema(
                    transaction,
                    &tables,
                    collection,
                    SchemaRegistrationMode::Compatible,
                )?;
            }
            Ok(())
        })
    }

    fn register_schemas_after_migration(
        &mut self,
        manifest: &SchemaManifest,
    ) -> Result<(), String> {
        validate_schema_manifest(manifest)?;
        self.ensure_can_write()?;
        if self.active_write_mut().is_some() {
            self.active_write_mut()
                .expect("write transaction must still be active")
                .operations
                .push(MdbxWriteOperation::RegisterSchemas {
                    manifest: manifest.clone(),
                    mode: SchemaRegistrationMode::ExplicitMigration,
                });
            return Ok(());
        }

        self.with_write_transaction(|transaction, tables| {
            for collection in &manifest.collections {
                register_collection_schema(
                    transaction,
                    &tables,
                    collection,
                    SchemaRegistrationMode::ExplicitMigration,
                )?;
            }
            Ok(())
        })
    }

    fn schema_version(&self, collection: &str) -> Result<Option<u64>, String> {
        self.with_read_transaction(|transaction, tables| {
            transaction
                .get::<Vec<u8>>(
                    &tables.schema_collections,
                    &encode_collection_key(collection),
                )
                .map_err(|error| error.to_string())?
                .map(|bytes| decode_schema_record(&bytes).map(|record| record.version))
                .transpose()
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

#[derive(Debug, Deserialize, Serialize)]
struct MdbxSchemaRecord {
    version: u64,
    schema: CollectionSchemaManifest,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum SchemaRegistrationMode {
    Compatible,
    ExplicitMigration,
}

fn register_collection_schema(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &CollectionSchemaManifest,
    mode: SchemaRegistrationMode,
) -> Result<(), String> {
    let key = encode_collection_key(&collection.name);
    let existing = transaction
        .get::<Vec<u8>>(&tables.schema_collections, &key)
        .map_err(|error| error.to_string())?
        .map(|bytes| decode_schema_record(&bytes))
        .transpose()?;

    let Some(existing) = existing else {
        let record = MdbxSchemaRecord {
            version: 1,
            schema: collection.clone(),
        };
        return put_schema_record(transaction, tables, &key, &record);
    };

    if existing.schema == *collection {
        return Ok(());
    }
    if mode == SchemaRegistrationMode::Compatible {
        validate_compatible_schema_change(&existing.schema, collection)?;
    }

    let next_version = existing
        .version
        .checked_add(1)
        .ok_or_else(|| format!("schema version for `{}` overflowed", collection.name))?;
    let record = MdbxSchemaRecord {
        version: next_version,
        schema: collection.clone(),
    };
    put_schema_record(transaction, tables, &key, &record)
}

fn put_schema_record(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    key: &[u8],
    record: &MdbxSchemaRecord,
) -> Result<(), String> {
    let bytes = serde_json::to_vec(record).map_err(|error| error.to_string())?;
    transaction
        .put(&tables.schema_collections, key, bytes, WriteFlags::UPSERT)
        .map_err(|error| error.to_string())
}

fn decode_schema_record(bytes: &[u8]) -> Result<MdbxSchemaRecord, String> {
    serde_json::from_slice(bytes).map_err(|error| error.to_string())
}

fn unique_index_names<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
) -> Result<HashSet<String>, String>
where
    K: libmdbx::TransactionKind,
{
    let Some(bytes) = transaction
        .get::<Vec<u8>>(
            &tables.schema_collections,
            &encode_collection_key(collection),
        )
        .map_err(|error| error.to_string())?
    else {
        return Ok(HashSet::new());
    };
    let record = decode_schema_record(&bytes)?;
    Ok(record
        .schema
        .fields
        .into_iter()
        .filter(|field| field.is_indexed && field.is_index_unique)
        .map(|field| field.name)
        .collect())
}

fn validate_schema_manifest(manifest: &SchemaManifest) -> Result<(), String> {
    let mut names = HashSet::new();
    for collection in &manifest.collections {
        if collection.name.trim().is_empty() {
            return Err("schema collection name must not be empty".into());
        }
        if !names.insert(collection.name.as_str()) {
            return Err(format!(
                "schema collection `{}` is duplicated",
                collection.name
            ));
        }
        validate_collection_schema(collection)?;
    }
    Ok(())
}

fn validate_collection_schema(collection: &CollectionSchemaManifest) -> Result<(), String> {
    if collection.id_field.trim().is_empty() {
        return Err(format!(
            "schema collection `{}` must declare an id field",
            collection.name
        ));
    }

    let mut names = HashSet::new();
    let mut id_fields = 0;
    for field in &collection.fields {
        if field.name.trim().is_empty() {
            return Err(format!(
                "schema collection `{}` contains an empty field name",
                collection.name
            ));
        }
        if field.dart_type.trim().is_empty() {
            return Err(format!(
                "schema field `{}.{}` must declare a Dart type",
                collection.name, field.name
            ));
        }
        if field.index_type != "value" && field.index_type != "hash" && field.index_type != "words"
        {
            return Err(format!(
                "schema field `{}.{}` uses unsupported index type `{}`",
                collection.name, field.name, field.index_type
            ));
        }
        if !field.is_indexed
            && (field.is_index_unique || !field.index_case_sensitive || field.index_type != "value")
        {
            return Err(format!(
                "schema field `{}.{}` declares index options without an index",
                collection.name, field.name
            ));
        }
        let normalized_dart_type = field
            .dart_type
            .strip_suffix('?')
            .unwrap_or(&field.dart_type);
        if field.is_indexed && !field.index_case_sensitive && normalized_dart_type != "String" {
            return Err(format!(
                "schema field `{}.{}` case-insensitive indexes require String fields",
                collection.name, field.name
            ));
        }
        if field.is_indexed && field.index_type == "words" && normalized_dart_type != "String" {
            return Err(format!(
                "schema field `{}.{}` word indexes require String fields",
                collection.name, field.name
            ));
        }
        if !names.insert(field.name.as_str()) {
            return Err(format!(
                "schema field `{}.{}` is duplicated",
                collection.name, field.name
            ));
        }
        if field.is_id {
            id_fields += 1;
            if field.name != collection.id_field {
                return Err(format!(
                    "schema field `{}.{}` is marked as id but id_field is `{}`",
                    collection.name, field.name, collection.id_field
                ));
            }
        }
    }

    if id_fields != 1 {
        return Err(format!(
            "schema collection `{}` must declare exactly one id field",
            collection.name
        ));
    }

    Ok(())
}

fn validate_compatible_schema_change(
    existing: &CollectionSchemaManifest,
    next: &CollectionSchemaManifest,
) -> Result<(), String> {
    if existing.name != next.name {
        return Err("schema collection names cannot change".into());
    }
    if existing.id_field != next.id_field {
        return Err(format!(
            "schema collection `{}` cannot change id field",
            existing.name
        ));
    }

    let next_fields = next
        .fields
        .iter()
        .map(|field| (field.name.as_str(), field))
        .collect::<std::collections::HashMap<_, _>>();

    for existing_field in &existing.fields {
        let Some(next_field) = next_fields.get(existing_field.name.as_str()) else {
            return Err(format!(
                "schema field `{}.{}` cannot be removed",
                existing.name, existing_field.name
            ));
        };
        validate_compatible_field(existing, existing_field, next_field)?;
    }

    Ok(())
}

fn validate_compatible_field(
    collection: &CollectionSchemaManifest,
    existing: &FieldSchemaManifest,
    next: &FieldSchemaManifest,
) -> Result<(), String> {
    if existing.dart_type != next.dart_type {
        return Err(format!(
            "schema field `{}.{}` cannot change type from `{}` to `{}`",
            collection.name, existing.name, existing.dart_type, next.dart_type
        ));
    }
    if existing.is_id != next.is_id {
        return Err(format!(
            "schema field `{}.{}` cannot change id status",
            collection.name, existing.name
        ));
    }
    if existing.is_indexed != next.is_indexed {
        return Err(format!(
            "schema field `{}.{}` cannot change index status without an explicit migration",
            collection.name, existing.name
        ));
    }
    if existing.is_index_unique != next.is_index_unique
        || existing.index_case_sensitive != next.index_case_sensitive
        || existing.index_type != next.index_type
    {
        return Err(format!(
            "schema field `{}.{}` cannot change index options without an explicit migration",
            collection.name, existing.name
        ));
    }
    Ok(())
}

fn put_document_with_indexes(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    id: u64,
    bytes: &[u8],
    indexes: &[IndexEntry],
    unique_indexes: &HashSet<String>,
) -> Result<(), String> {
    enforce_unique_indexes(transaction, tables, collection, id, indexes, unique_indexes)?;
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
        if unique_indexes.contains(index.name.as_str()) {
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
    let (index_keys, unique_keys) = {
        let mut cursor = transaction
            .cursor(&tables.indexes)
            .map_err(|error| error.to_string())?;
        let mut index_keys = Vec::new();
        let mut unique_keys = Vec::new();
        for row in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(&collection_prefix) {
            let (key, _) = row.map_err(|error| error.to_string())?;
            if !key.starts_with(&collection_prefix) {
                break;
            }
            if decode_key_document_id(&key)? == id {
                let key = key.into_owned();
                if key.len() >= 8 {
                    unique_keys.push(key[..key.len() - 8].to_vec());
                }
                index_keys.push(key);
            }
        }
        (index_keys, unique_keys)
    };

    for key in index_keys {
        transaction
            .del(&tables.indexes, key, None)
            .map_err(|error| error.to_string())?;
    }
    for key in unique_keys {
        transaction
            .del(&tables.unique_indexes, key, None)
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn enforce_unique_indexes(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    id: u64,
    indexes: &[IndexEntry],
    unique_indexes: &HashSet<String>,
) -> Result<(), String> {
    if unique_indexes.is_empty() {
        return Ok(());
    }

    for index in indexes {
        if !unique_indexes.contains(index.name.as_str()) {
            continue;
        }
        let prefix = encode_index_equal_prefix(collection, &index.name, &index.value)?;
        let existing_ids = scan_ids_by_key_range(transaction, &tables.indexes, &prefix, None)?;
        for existing_id in existing_ids {
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

fn scan_ids_by_key_range<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    table: &Table<'_>,
    start: &[u8],
    end_inclusive: Option<&[u8]>,
) -> Result<Vec<u64>, String>
where
    K: libmdbx::TransactionKind,
{
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

fn set_id_counter_at_least(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    next_id: u64,
) -> Result<(), String> {
    let key = encode_collection_key(collection);
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
    use crate::storage::{contract_tests, CollectionSchemaManifest, FieldSchemaManifest};

    #[test]
    fn passes_the_shared_storage_engine_contract() {
        // Scenario: MDBX-06 promotes the prototype to a StorageEngine peer.
        // Covers:
        // - The shared [StorageEngine] behavioral contract used by SQLite.
        // - CRUD, ids, indexes, unique indexes, schemas, revisions, and batch
        //   rollback behavior without enabling explicit transactions yet.
        // Expected: MDBX matches SQLite for the non-explicit-transaction
        //   storage surface before MDBX-07.
        contract_tests::run_storage_engine_contract("mdbx", MdbxStorage::open);
    }

    #[test]
    fn passes_the_shared_storage_transaction_contract() {
        // Scenario: MDBX-07 integrates Cindel's explicit transaction model.
        // Covers:
        // - The shared [StorageEngine] explicit transaction contract.
        // - Commit, rollback, read transaction write rejection, nested
        //   transaction rejection, and id allocation rollback.
        // Expected: MDBX matches SQLite's transaction behavior without storing
        //   self-referential MDBX transaction handles.
        contract_tests::run_storage_transaction_contract("mdbx", MdbxStorage::open);
    }

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
