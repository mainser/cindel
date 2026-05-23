use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::{SystemTime, UNIX_EPOCH};

use libmdbx::{
    Database, DatabaseOptions, NoWriteMap, Table, TableFlags, Transaction, WriteFlags, RO, RW,
};
use serde::{Deserialize, Serialize};

use crate::document_format::read_json_field;
use crate::document_format::{
    index_entries_from_binary_document, read_json_document, write_json_document, BinaryDocument,
};
use crate::native_filter::NativeFilter;

use super::mdbx_key::{
    decode_key_document_id, encode_collection_key, encode_document_key, encode_index_equal_prefix,
    encode_index_key, encode_index_range, encode_unique_index_key, COLLECTION_REVISIONS_TABLE,
    DOCUMENTS_TABLE, INDEXES_TABLE, SCHEMA_COLLECTIONS_TABLE, STORAGE_METADATA_TABLE,
    UNIQUE_INDEXES_TABLE,
};
use super::{
    CollectionSchemaManifest, DocumentWrite, FieldSchemaManifest, IndexEntry, IndexValue,
    SchemaManifest, StorageEngine,
};
use super::{DocumentFormatVersion, StorageLayoutVersion, StorageMetadata};

const IN_MEMORY_DIRECTORY: &str = ":memory:";
const EMPTY_VALUE: &[u8] = &[];

pub struct MdbxStorage {
    state: SharedMdbxState,
    active_transaction: Option<MdbxActiveTransaction>,
    _temporary_directory: Option<TemporaryDirectoryGuard>,
}

struct MdbxSharedState {
    database: Arc<Database<NoWriteMap>>,
    next_ids: Mutex<HashMap<String, u64>>,
}

type SharedMdbxState = Arc<MdbxSharedState>;
type WeakMdbxState = Weak<MdbxSharedState>;

static MDBX_DATABASES: OnceLock<Mutex<HashMap<PathBuf, WeakMdbxState>>> = OnceLock::new();

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

impl MdbxWriteTransaction {
    fn staged_document(&self, collection: &str, id: u64) -> Option<Option<Vec<u8>>> {
        for operation in self.operations.iter().rev() {
            match operation {
                MdbxWriteOperation::PutIndexed {
                    collection: operation_collection,
                    id: operation_id,
                    bytes,
                    ..
                } if operation_collection == collection && *operation_id == id => {
                    return Some(Some(bytes.clone()));
                }
                MdbxWriteOperation::PutManyIndexed {
                    collection: operation_collection,
                    documents,
                } if operation_collection == collection => {
                    if let Some(document) =
                        documents.iter().rev().find(|document| document.id == id)
                    {
                        return Some(Some(document.bytes.clone()));
                    }
                }
                MdbxWriteOperation::Delete {
                    collection: operation_collection,
                    id: operation_id,
                } if operation_collection == collection && *operation_id == id => {
                    return Some(None);
                }
                MdbxWriteOperation::DeleteMany {
                    collection: operation_collection,
                    ids,
                } if operation_collection == collection && ids.contains(&id) => {
                    return Some(None);
                }
                MdbxWriteOperation::RegisterSchemas { .. }
                | MdbxWriteOperation::PutIndexed { .. }
                | MdbxWriteOperation::PutManyIndexed { .. }
                | MdbxWriteOperation::Delete { .. }
                | MdbxWriteOperation::DeleteMany { .. } => {}
            }
        }
        None
    }

    fn staged_document_ids(&self, collection: &str, base_ids: Vec<u64>) -> Vec<u64> {
        let mut ids = base_ids.into_iter().collect::<HashSet<_>>();
        for operation in &self.operations {
            match operation {
                MdbxWriteOperation::PutIndexed {
                    collection: operation_collection,
                    id,
                    ..
                } if operation_collection == collection => {
                    ids.insert(*id);
                }
                MdbxWriteOperation::PutManyIndexed {
                    collection: operation_collection,
                    documents,
                } if operation_collection == collection => {
                    for document in documents {
                        ids.insert(document.id);
                    }
                }
                MdbxWriteOperation::Delete {
                    collection: operation_collection,
                    id,
                } if operation_collection == collection => {
                    ids.remove(id);
                }
                MdbxWriteOperation::DeleteMany {
                    collection: operation_collection,
                    ids: deleted_ids,
                } if operation_collection == collection => {
                    for id in deleted_ids {
                        ids.remove(id);
                    }
                }
                MdbxWriteOperation::RegisterSchemas { .. }
                | MdbxWriteOperation::PutIndexed { .. }
                | MdbxWriteOperation::PutManyIndexed { .. }
                | MdbxWriteOperation::Delete { .. }
                | MdbxWriteOperation::DeleteMany { .. } => {}
            }
        }
        let mut ids = ids.into_iter().collect::<Vec<_>>();
        ids.sort_unstable();
        ids
    }

    fn staged_index_ids(
        &self,
        collection: &str,
        index: &str,
        mut base_entries: Vec<(Vec<u8>, u64)>,
        staged_key: impl Fn(&IndexEntry, u64) -> Result<Option<Vec<u8>>, String>,
    ) -> Result<Vec<u64>, String> {
        let mut changes = HashMap::<u64, Option<Vec<u8>>>::new();
        for operation in &self.operations {
            match operation {
                MdbxWriteOperation::PutIndexed {
                    collection: operation_collection,
                    id,
                    indexes,
                    ..
                } if operation_collection == collection => {
                    changes.insert(*id, staged_index_key(indexes, index, *id, &staged_key)?);
                }
                MdbxWriteOperation::PutManyIndexed {
                    collection: operation_collection,
                    documents,
                } if operation_collection == collection => {
                    for document in documents {
                        changes.insert(
                            document.id,
                            staged_index_key(&document.indexes, index, document.id, &staged_key)?,
                        );
                    }
                }
                MdbxWriteOperation::Delete {
                    collection: operation_collection,
                    id,
                } if operation_collection == collection => {
                    changes.insert(*id, None);
                }
                MdbxWriteOperation::DeleteMany {
                    collection: operation_collection,
                    ids,
                } if operation_collection == collection => {
                    for id in ids {
                        changes.insert(*id, None);
                    }
                }
                MdbxWriteOperation::RegisterSchemas { .. }
                | MdbxWriteOperation::PutIndexed { .. }
                | MdbxWriteOperation::PutManyIndexed { .. }
                | MdbxWriteOperation::Delete { .. }
                | MdbxWriteOperation::DeleteMany { .. } => {}
            }
        }
        if changes.is_empty() {
            return Ok(base_entries
                .into_iter()
                .map(|(_, id)| id)
                .collect::<Vec<_>>());
        }

        base_entries.retain(|(_, id)| !changes.contains_key(id));
        for (id, key) in changes {
            if let Some(key) = key {
                base_entries.push((key, id));
            }
        }
        base_entries.sort_by(|left, right| left.0.cmp(&right.0));
        Ok(base_entries.into_iter().map(|(_, id)| id).collect())
    }
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
        let path = path.canonicalize().map_err(|error| error.to_string())?;
        let state = open_shared_state(&path)?;

        let storage = Self {
            state,
            active_transaction: None,
            _temporary_directory: temporary_directory,
        };
        storage.initialize()?;
        Ok(storage)
    }

    fn initialize(&self) -> Result<(), String> {
        let transaction = self
            .state
            .database
            .begin_rw_txn()
            .map_err(|error| error.to_string())?;
        create_tables(&transaction)?;
        let tables = open_tables(&transaction)?;
        ensure_storage_metadata(
            &transaction,
            &tables,
            StorageLayoutVersion::MdbxV1,
            DocumentFormatVersion::BinaryV1,
        )?;
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
            .state
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
            .state
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

    fn active_write(&self) -> Option<&MdbxWriteTransaction> {
        match &self.active_transaction {
            Some(MdbxActiveTransaction::Write(transaction)) => Some(transaction),
            Some(MdbxActiveTransaction::Read) | None => None,
        }
    }

    fn current_next_id(&self, collection: &str) -> Result<u64, String> {
        self.cached_next_id(collection)
    }

    fn cached_next_id(&self, collection: &str) -> Result<u64, String> {
        let cached = {
            let next_ids = self
                .state
                .next_ids
                .lock()
                .map_err(|error| error.to_string())?;
            next_ids.get(collection).copied()
        };
        if let Some(next_id) = cached {
            return Ok(next_id);
        }

        let next_id = self.next_id_from_documents(collection)?;
        let mut next_ids = self
            .state
            .next_ids
            .lock()
            .map_err(|error| error.to_string())?;
        Ok(*next_ids.entry(collection.to_string()).or_insert(next_id))
    }

    fn allocate_cached_id(&self, collection: &str) -> Result<u64, String> {
        loop {
            let cached = {
                let next_ids = self
                    .state
                    .next_ids
                    .lock()
                    .map_err(|error| error.to_string())?;
                next_ids.get(collection).copied()
            };
            if let Some(next_id) = cached {
                let following = next_id.checked_add(1).ok_or_else(|| {
                    format!("id counter for collection `{collection}` overflowed")
                })?;
                self.set_cached_next_id_at_least(collection, following)?;
                return Ok(next_id);
            }

            let next_id = self.next_id_from_documents(collection)?;
            let mut next_ids = self
                .state
                .next_ids
                .lock()
                .map_err(|error| error.to_string())?;
            if next_ids.contains_key(collection) {
                continue;
            }
            let following = next_id
                .checked_add(1)
                .ok_or_else(|| format!("id counter for collection `{collection}` overflowed"))?;
            next_ids.insert(collection.to_string(), following);
            return Ok(next_id);
        }
    }

    fn next_id_from_documents(&self, collection: &str) -> Result<u64, String> {
        self.with_read_transaction(|transaction, tables| {
            let prefix = encode_collection_key(collection);
            Ok(
                max_id_by_key_range(transaction, &tables.documents, &prefix, None)?
                    .and_then(|id| id.checked_add(1))
                    .unwrap_or(1),
            )
        })
    }

    fn set_cached_next_id_at_least(&self, collection: &str, next_id: u64) -> Result<(), String> {
        let mut next_ids = self
            .state
            .next_ids
            .lock()
            .map_err(|error| error.to_string())?;
        let current = next_ids.entry(collection.to_string()).or_insert(1);
        if *current < next_id {
            *current = next_id;
        }
        Ok(())
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
        let counter_updates = staged.next_ids.clone();
        self.with_write_transaction(|transaction, tables| {
            for operation in staged.operations {
                match operation {
                    MdbxWriteOperation::PutIndexed {
                        collection,
                        id,
                        bytes,
                        indexes,
                    } => {
                        put_document_with_indexes(
                            transaction,
                            &tables,
                            &collection,
                            id,
                            &bytes,
                            &indexes,
                        )?;
                        bump_collection_revision(transaction, &tables, &collection)?;
                    }
                    MdbxWriteOperation::PutManyIndexed {
                        collection,
                        documents,
                    } => {
                        for document in &documents {
                            put_document_with_indexes(
                                transaction,
                                &tables,
                                &collection,
                                document.id,
                                &document.bytes,
                                &document.indexes,
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

            Ok(())
        })?;
        for (collection, next_id) in counter_updates {
            self.set_cached_next_id_at_least(&collection, next_id)?;
        }
        Ok(())
    }
}

fn open_shared_state(path: &PathBuf) -> Result<SharedMdbxState, String> {
    let databases = MDBX_DATABASES.get_or_init(|| Mutex::new(HashMap::new()));
    let mut databases = databases.lock().map_err(|error| error.to_string())?;
    if let Some(state) = databases.get(path).and_then(Weak::upgrade) {
        return Ok(state);
    }

    let database = Arc::new(
        Database::<NoWriteMap>::open_with_options(
            path,
            DatabaseOptions {
                max_tables: Some(16),
                accede: true,
                ..Default::default()
            },
        )
        .map_err(|error| error.to_string())?,
    );
    let state = Arc::new(MdbxSharedState {
        database,
        next_ids: Mutex::new(HashMap::new()),
    });
    databases.insert(path.clone(), Arc::downgrade(&state));
    Ok(state)
}

fn staged_index_key(
    indexes: &[IndexEntry],
    index: &str,
    id: u64,
    staged_key: impl Fn(&IndexEntry, u64) -> Result<Option<Vec<u8>>, String>,
) -> Result<Option<Vec<u8>>, String> {
    for entry in indexes {
        if entry.name != index {
            continue;
        }
        if let Some(key) = staged_key(entry, id)? {
            return Ok(Some(key));
        }
    }
    Ok(None)
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

        self.allocate_cached_id(collection)
    }

    fn get(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String> {
        if let Some(document) = self
            .active_write()
            .and_then(|transaction| transaction.staged_document(collection, id))
        {
            let schema = self.with_read_transaction(|transaction, tables| {
                collection_schema(transaction, &tables, collection)
            })?;
            return document
                .map(|bytes| decode_document_for_read(schema.as_ref(), &bytes))
                .transpose();
        }

        self.with_read_transaction(|transaction, tables| {
            let schema = collection_schema(transaction, &tables, collection)?;
            let Some(bytes) = transaction
                .get::<Vec<u8>>(&tables.documents, &encode_document_key(collection, id))
                .map_err(|error| error.to_string())?
            else {
                return Ok(None);
            };
            decode_document_for_read(schema.as_ref(), &bytes).map(Some)
        })
    }

    fn get_many(&self, collection: &str, ids: &[u64]) -> Result<Vec<Option<Vec<u8>>>, String> {
        if self.active_write().is_some() {
            return ids.iter().map(|id| self.get(collection, *id)).collect();
        }

        self.with_read_transaction(|transaction, tables| {
            let schema = collection_schema(transaction, &tables, collection)?;
            let mut key = encode_collection_key(collection);
            let key_prefix_length = key.len();
            let mut documents = Vec::with_capacity(ids.len());
            for id in ids {
                key.truncate(key_prefix_length);
                key.extend_from_slice(&id.to_be_bytes());
                let bytes = transaction
                    .get::<Vec<u8>>(&tables.documents, &key)
                    .map_err(|error| error.to_string())?;
                documents.push(
                    bytes
                        .map(|bytes| decode_document_for_read(schema.as_ref(), &bytes))
                        .transpose()?,
                );
            }
            Ok(documents)
        })
    }

    fn get_stored(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String> {
        if let Some(document) = self
            .active_write()
            .and_then(|transaction| transaction.staged_document(collection, id))
        {
            return Ok(document);
        }

        self.with_read_transaction(|transaction, tables| {
            transaction
                .get::<Vec<u8>>(&tables.documents, &encode_document_key(collection, id))
                .map_err(|error| error.to_string())
        })
    }

    fn get_many_stored(
        &self,
        collection: &str,
        ids: &[u64],
    ) -> Result<Vec<Option<Vec<u8>>>, String> {
        if self.active_write().is_some() {
            return ids
                .iter()
                .map(|id| self.get_stored(collection, *id))
                .collect();
        }

        self.with_read_transaction(|transaction, tables| {
            let mut key = encode_collection_key(collection);
            let key_prefix_length = key.len();
            let mut documents = Vec::with_capacity(ids.len());
            for id in ids {
                key.truncate(key_prefix_length);
                key.extend_from_slice(&id.to_be_bytes());
                documents.push(
                    transaction
                        .get::<Vec<u8>>(&tables.documents, &key)
                        .map_err(|error| error.to_string())?,
                );
            }
            Ok(documents)
        })
    }

    fn document_ids(&self, collection: &str) -> Result<Vec<u64>, String> {
        let ids = self.with_read_transaction(|transaction, tables| {
            let prefix = encode_collection_key(collection);
            scan_ids_by_key_range(transaction, &tables.documents, &prefix, None)
        })?;
        Ok(match self.active_write() {
            Some(transaction) => transaction.staged_document_ids(collection, ids),
            None => ids,
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
            let schema = self.with_read_transaction(|transaction, tables| {
                collection_schema(transaction, &tables, collection)
            })?;
            let (stored_bytes, effective_indexes) =
                encode_document_for_storage(schema.as_ref(), bytes, indexes)?;
            let fallback_next_id = self.current_next_id(collection)?;
            self.advance_staged_id_counter(collection, id, Some(fallback_next_id))?;
            self.active_write_mut()
                .expect("write transaction must still be active")
                .operations
                .push(MdbxWriteOperation::PutIndexed {
                    collection: collection.to_string(),
                    id,
                    bytes: stored_bytes,
                    indexes: effective_indexes,
                });
            return Ok(());
        }

        self.with_write_transaction(|transaction, tables| {
            put_document_with_indexes(transaction, &tables, collection, id, bytes, indexes)?;
            bump_collection_revision(transaction, &tables, collection)
        })?;
        self.set_cached_next_id_at_least(collection, id.saturating_add(1))
    }

    fn put_many_indexed(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String> {
        self.ensure_can_write()?;
        if self.active_write_mut().is_some() {
            let schema = self.with_read_transaction(|transaction, tables| {
                collection_schema(transaction, &tables, collection)
            })?;
            let staged_documents = documents
                .iter()
                .map(|document| {
                    let (stored_bytes, effective_indexes) = encode_document_for_storage(
                        schema.as_ref(),
                        &document.bytes,
                        &document.indexes,
                    )?;
                    Ok(DocumentWrite {
                        id: document.id,
                        bytes: stored_bytes,
                        indexes: effective_indexes,
                    })
                })
                .collect::<Result<Vec<_>, String>>()?;
            let fallback_next_id = self.current_next_id(collection)?;
            for document in documents {
                self.advance_staged_id_counter(collection, document.id, Some(fallback_next_id))?;
            }
            self.active_write_mut()
                .expect("write transaction must still be active")
                .operations
                .push(MdbxWriteOperation::PutManyIndexed {
                    collection: collection.to_string(),
                    documents: staged_documents,
                });
            return Ok(());
        }

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
        })?;
        if let Some(next_id) = documents
            .iter()
            .map(|document| document.id.saturating_add(1))
            .max()
        {
            self.set_cached_next_id_at_least(collection, next_id)?;
        }
        Ok(())
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
        match self.active_write() {
            Some(transaction) => {
                let entries = self.with_read_transaction(|transaction, tables| {
                    let prefix = encode_index_equal_prefix(collection, index, value)?;
                    scan_entries_by_key_range(transaction, &tables.indexes, &prefix, None)
                })?;
                transaction.staged_index_ids(collection, index, entries, |entry, id| {
                    if entry.value == *value {
                        encode_index_key(collection, index, value, id).map(Some)
                    } else {
                        Ok(None)
                    }
                })
            }
            None => self.with_read_transaction(|transaction, tables| {
                let prefix = encode_index_equal_prefix(collection, index, value)?;
                scan_ids_by_key_range(transaction, &tables.indexes, &prefix, None)
            }),
        }
    }

    fn query_index_range(
        &self,
        collection: &str,
        index: &str,
        lower: Option<&IndexValue>,
        upper: Option<&IndexValue>,
    ) -> Result<Vec<u64>, String> {
        let range = encode_index_range(collection, index, lower, upper)?;
        match self.active_write() {
            Some(transaction) => {
                let entries = self.with_read_transaction(|transaction, tables| {
                    scan_entries_by_key_range(
                        transaction,
                        &tables.indexes,
                        &range.start,
                        Some(&range.end_inclusive),
                    )
                })?;
                transaction.staged_index_ids(collection, index, entries, |entry, id| {
                    let key = encode_index_key(collection, index, &entry.value, id)?;
                    if key >= range.start && key <= range.end_inclusive {
                        Ok(Some(key))
                    } else {
                        Ok(None)
                    }
                })
            }
            None => self.with_read_transaction(|transaction, tables| {
                scan_ids_by_key_range(
                    transaction,
                    &tables.indexes,
                    &range.start,
                    Some(&range.end_inclusive),
                )
            }),
        }
    }

    fn query_filter(
        &self,
        collection: &str,
        candidate_ids: &[u64],
        filter: &[u8],
    ) -> Result<Vec<u64>, String> {
        let filter = NativeFilter::from_json(filter)?;
        let schema = self.with_read_transaction(|transaction, tables| {
            collection_schema(transaction, &tables, collection)
        })?;
        let Some(schema) = schema else {
            return Err(format!(
                "collection `{collection}` has no registered schema"
            ));
        };
        let documents = self.get_many_stored(collection, candidate_ids)?;
        let mut ids = Vec::new();
        for (id, document) in candidate_ids.iter().copied().zip(documents) {
            let Some(document) = document else {
                continue;
            };
            if filter.matches(&schema, &document)? {
                ids.push(id);
            }
        }
        Ok(ids)
    }

    fn query_project(
        &self,
        collection: &str,
        candidate_ids: &[u64],
        field: &str,
    ) -> Result<Vec<u8>, String> {
        let schema = self.with_read_transaction(|transaction, tables| {
            collection_schema(transaction, &tables, collection)
        })?;
        let Some(schema) = schema else {
            return Err(format!(
                "collection `{collection}` has no registered schema"
            ));
        };
        if !schema
            .fields
            .iter()
            .any(|schema_field| schema_field.name == field)
        {
            return Err(format!(
                "field `{field}` is not declared in schema `{collection}`"
            ));
        }
        let documents = self.get_many_stored(collection, candidate_ids)?;
        let mut values = Vec::new();
        for document in documents {
            let Some(document) = document else {
                continue;
            };
            values.push(read_json_field(&schema, &document, field)?);
        }
        serde_json::to_vec(&values).map_err(|error| error.to_string())
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

    fn storage_metadata(&self) -> Result<StorageMetadata, String> {
        self.with_read_transaction(|transaction, tables| {
            read_storage_metadata(transaction, &tables)
        })
    }

    fn rebuild_indexes(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String> {
        self.ensure_can_write()?;
        if self.active_write_mut().is_some() {
            return Err(
                "native index rebuild is not supported inside an active MDBX write transaction yet"
                    .into(),
            );
        }

        self.with_write_transaction(|transaction, tables| {
            rebuild_indexes_in_transaction(transaction, &tables, collection, documents)
        })
    }
}

struct MdbxTables<'txn> {
    documents: Table<'txn>,
    indexes: Table<'txn>,
    unique_indexes: Table<'txn>,
    collection_revisions: Table<'txn>,
    schema_collections: Table<'txn>,
    storage_metadata: Table<'txn>,
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
        .create_table(Some(COLLECTION_REVISIONS_TABLE), TableFlags::default())
        .map_err(|error| error.to_string())?;
    transaction
        .create_table(Some(SCHEMA_COLLECTIONS_TABLE), TableFlags::default())
        .map_err(|error| error.to_string())?;
    transaction
        .create_table(Some(STORAGE_METADATA_TABLE), TableFlags::default())
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
        collection_revisions: transaction
            .open_table(Some(COLLECTION_REVISIONS_TABLE))
            .map_err(|error| error.to_string())?,
        schema_collections: transaction
            .open_table(Some(SCHEMA_COLLECTIONS_TABLE))
            .map_err(|error| error.to_string())?,
        storage_metadata: transaction
            .open_table(Some(STORAGE_METADATA_TABLE))
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

fn collection_schema<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
) -> Result<Option<CollectionSchemaManifest>, String>
where
    K: libmdbx::TransactionKind,
{
    transaction
        .get::<Vec<u8>>(
            &tables.schema_collections,
            &encode_collection_key(collection),
        )
        .map_err(|error| error.to_string())?
        .map(|bytes| decode_schema_record(&bytes).map(|record| record.schema))
        .transpose()
}

fn unique_index_names_from_schema(schema: Option<&CollectionSchemaManifest>) -> HashSet<String> {
    let mut names = HashSet::new();
    if let Some(schema) = schema {
        names.extend(
            schema
                .fields
                .iter()
                .filter(|field| field.is_indexed && field.is_index_unique)
                .map(|field| field.name.clone()),
        );
        names.extend(
            schema
                .composite_indexes
                .iter()
                .filter(|index| index.is_unique)
                .map(|index| index.name.clone()),
        );
    }
    names
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
        if field.index_type != "value"
            && field.index_type != "hash"
            && field.index_type != "words"
            && field.index_type != "multiEntry"
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
        if field.is_indexed
            && !field.index_case_sensitive
            && normalized_dart_type != "String"
            && !(field.index_type == "multiEntry" && normalized_dart_type == "List<String>")
        {
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
        if field.is_indexed
            && field.index_type == "multiEntry"
            && !normalized_dart_type.starts_with("List<")
        {
            return Err(format!(
                "schema field `{}.{}` multi-entry indexes require List fields",
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

    let mut composite_names = HashSet::new();
    for index in &collection.composite_indexes {
        if index.name.trim().is_empty() {
            return Err(format!(
                "schema collection `{}` contains an empty composite index name",
                collection.name
            ));
        }
        if !composite_names.insert(index.name.as_str()) || names.contains(index.name.as_str()) {
            return Err(format!(
                "schema composite index `{}.{}` conflicts with another index",
                collection.name, index.name
            ));
        }
        if index.fields.len() < 2 {
            return Err(format!(
                "schema composite index `{}.{}` must contain at least two fields",
                collection.name, index.name
            ));
        }
        for field_name in &index.fields {
            if !names.contains(field_name.as_str()) {
                return Err(format!(
                    "schema composite index `{}.{}` references missing field `{}`",
                    collection.name, index.name, field_name
                ));
            }
        }
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
    if existing.composite_indexes != next.composite_indexes {
        return Err(format!(
            "schema collection `{}` cannot change composite indexes until public migration tooling exists",
            existing.name
        ));
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
            "schema field `{}.{}` cannot change index status until public migration tooling exists",
            collection.name, existing.name
        ));
    }
    if existing.is_index_unique != next.is_index_unique
        || existing.index_case_sensitive != next.index_case_sensitive
        || existing.index_type != next.index_type
    {
        return Err(format!(
            "schema field `{}.{}` cannot change index options until public migration tooling exists",
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
) -> Result<(), String> {
    let schema = collection_schema(transaction, tables, collection)?;
    let unique_indexes = unique_index_names_from_schema(schema.as_ref());
    let (stored_bytes, effective_indexes) =
        encode_document_for_storage(schema.as_ref(), bytes, indexes)?;
    MdbxIndex::validate_unique(
        transaction,
        tables,
        collection,
        id,
        &effective_indexes,
        &unique_indexes,
    )?;
    let document_key = encode_document_key(collection, id);
    transaction
        .put(
            &tables.documents,
            &document_key,
            &stored_bytes,
            WriteFlags::UPSERT,
        )
        .map_err(|error| error.to_string())?;
    MdbxIndex::replace_document(
        transaction,
        tables,
        collection,
        id,
        &effective_indexes,
        &unique_indexes,
    )
}

fn encode_document_for_storage(
    schema: Option<&CollectionSchemaManifest>,
    bytes: &[u8],
    indexes: &[IndexEntry],
) -> Result<(Vec<u8>, Vec<IndexEntry>), String> {
    let Some(schema) = schema else {
        return Ok((bytes.to_vec(), indexes.to_vec()));
    };
    let stored_bytes = if BinaryDocument::parse(bytes).is_ok() {
        bytes.to_vec()
    } else {
        write_json_document(schema, bytes)?
    };
    let indexes = index_entries_from_binary_document(schema, &stored_bytes)?;
    Ok((stored_bytes, indexes))
}

fn decode_document_for_read(
    schema: Option<&CollectionSchemaManifest>,
    bytes: &[u8],
) -> Result<Vec<u8>, String> {
    let Some(schema) = schema else {
        return Ok(bytes.to_vec());
    };
    if BinaryDocument::parse(bytes).is_ok() {
        read_json_document(schema, bytes)
    } else {
        Ok(bytes.to_vec())
    }
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
    MdbxIndex::delete_document(transaction, tables, collection, id)?;
    Ok(deleted)
}

#[allow(dead_code)]
fn rebuild_indexes_in_transaction(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    documents: &[DocumentWrite],
) -> Result<(), String> {
    MdbxIndex::clear_collection(transaction, tables, collection)?;
    let schema = collection_schema(transaction, tables, collection)?;
    let unique_indexes = unique_index_names_from_schema(schema.as_ref());
    for document in documents {
        ensure_document_exists(transaction, tables, collection, document.id)?;
        let (_, indexes) =
            encode_document_for_storage(schema.as_ref(), &document.bytes, &document.indexes)?;
        MdbxIndex::validate_unique(
            transaction,
            tables,
            collection,
            document.id,
            &indexes,
            &unique_indexes,
        )?;
        MdbxIndex::replace_document(
            transaction,
            tables,
            collection,
            document.id,
            &indexes,
            &unique_indexes,
        )?;
    }
    Ok(())
}

#[allow(dead_code)]
fn ensure_document_exists<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    id: u64,
) -> Result<(), String>
where
    K: libmdbx::TransactionKind,
{
    let exists = transaction
        .get::<Vec<u8>>(&tables.documents, &encode_document_key(collection, id))
        .map_err(|error| error.to_string())?
        .is_some();
    if exists {
        Ok(())
    } else {
        Err(format!(
            "cannot rebuild indexes for missing document `{collection}`.`{id}`"
        ))
    }
}

fn ensure_storage_metadata(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    layout: StorageLayoutVersion,
    document_format: DocumentFormatVersion,
) -> Result<(), String> {
    put_metadata_if_missing(transaction, tables, "storage_layout", layout.as_str())?;
    put_metadata_if_missing(
        transaction,
        tables,
        "document_format",
        document_format.as_str(),
    )
}

fn put_metadata_if_missing(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    key: &str,
    value: &str,
) -> Result<(), String> {
    if transaction
        .get::<Vec<u8>>(&tables.storage_metadata, key.as_bytes())
        .map_err(|error| error.to_string())?
        .is_some()
    {
        return Ok(());
    }
    transaction
        .put(
            &tables.storage_metadata,
            key.as_bytes(),
            value.as_bytes(),
            WriteFlags::UPSERT,
        )
        .map_err(|error| error.to_string())
}

fn read_storage_metadata<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    tables: &MdbxTables<'_>,
) -> Result<StorageMetadata, String>
where
    K: libmdbx::TransactionKind,
{
    let layout = read_metadata_value(transaction, tables, "storage_layout")?
        .unwrap_or_else(|| StorageLayoutVersion::MdbxV1.as_str().to_string());
    let document_format = read_metadata_value(transaction, tables, "document_format")?
        .unwrap_or_else(|| DocumentFormatVersion::JsonV1.as_str().to_string());
    Ok(StorageMetadata {
        layout: parse_storage_layout(&layout)?,
        document_format: parse_document_format(&document_format)?,
    })
}

fn read_metadata_value<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    tables: &MdbxTables<'_>,
    key: &str,
) -> Result<Option<String>, String>
where
    K: libmdbx::TransactionKind,
{
    transaction
        .get::<Vec<u8>>(&tables.storage_metadata, key.as_bytes())
        .map_err(|error| error.to_string())?
        .map(|bytes| String::from_utf8(bytes).map_err(|error| error.to_string()))
        .transpose()
}

fn parse_storage_layout(value: &str) -> Result<StorageLayoutVersion, String> {
    match value {
        "sqlite-v1" => Ok(StorageLayoutVersion::SqliteV1),
        "mdbx-v1" => Ok(StorageLayoutVersion::MdbxV1),
        "mdbx-v2" => Ok(StorageLayoutVersion::MdbxV2),
        _ => Err(format!("unknown storage layout version `{value}`")),
    }
}

fn parse_document_format(value: &str) -> Result<DocumentFormatVersion, String> {
    match value {
        "json-v1" => Ok(DocumentFormatVersion::JsonV1),
        "binary-v1" => Ok(DocumentFormatVersion::BinaryV1),
        _ => Err(format!("unknown document format version `{value}`")),
    }
}

struct MdbxIndex;

#[cfg_attr(not(test), allow(dead_code))]
#[derive(Debug, Eq, PartialEq)]
struct MdbxIndexStats {
    entries: usize,
    unique_entries: usize,
}

impl MdbxIndex {
    fn entry_key(
        collection: &str,
        index_name: &str,
        value: &IndexValue,
        document_id: u64,
    ) -> Result<Vec<u8>, String> {
        encode_index_key(collection, index_name, value, document_id)
    }

    fn unique_key(
        collection: &str,
        index_name: &str,
        value: &IndexValue,
    ) -> Result<Vec<u8>, String> {
        encode_unique_index_key(collection, index_name, value)
    }

    #[cfg_attr(not(test), allow(dead_code))]
    fn equal_prefix(
        collection: &str,
        index_name: &str,
        value: &IndexValue,
    ) -> Result<Vec<u8>, String> {
        encode_index_equal_prefix(collection, index_name, value)
    }

    fn validate_unique(
        transaction: &Transaction<'_, RW, NoWriteMap>,
        tables: &MdbxTables<'_>,
        collection: &str,
        document_id: u64,
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
            let key = Self::unique_key(collection, &index.name, &index.value)?;
            if let Some(existing_id) = transaction
                .get::<Vec<u8>>(&tables.unique_indexes, &key)
                .map_err(|error| error.to_string())?
            {
                let existing_id = decode_u64(&existing_id)?;
                if existing_id != document_id {
                    return Err(format!(
                        "Unique index `{}` already contains this value.",
                        index.name
                    ));
                }
            }
        }
        Ok(())
    }

    fn replace_document(
        transaction: &Transaction<'_, RW, NoWriteMap>,
        tables: &MdbxTables<'_>,
        collection: &str,
        document_id: u64,
        new_indexes: &[IndexEntry],
        unique_indexes: &HashSet<String>,
    ) -> Result<(), String> {
        Self::delete_document(transaction, tables, collection, document_id)?;
        for index in new_indexes {
            Self::insert_entry(
                transaction,
                tables,
                collection,
                document_id,
                index,
                unique_indexes.contains(index.name.as_str()),
            )?;
        }
        Ok(())
    }

    fn insert_entry(
        transaction: &Transaction<'_, RW, NoWriteMap>,
        tables: &MdbxTables<'_>,
        collection: &str,
        document_id: u64,
        index: &IndexEntry,
        is_unique: bool,
    ) -> Result<(), String> {
        let key = Self::entry_key(collection, &index.name, &index.value, document_id)?;
        transaction
            .put(&tables.indexes, key, EMPTY_VALUE, WriteFlags::UPSERT)
            .map_err(|error| error.to_string())?;
        if is_unique {
            let unique_key = Self::unique_key(collection, &index.name, &index.value)?;
            transaction
                .put(
                    &tables.unique_indexes,
                    unique_key,
                    document_id.to_be_bytes(),
                    WriteFlags::UPSERT,
                )
                .map_err(|error| error.to_string())?;
        }
        Ok(())
    }

    fn delete_document(
        transaction: &Transaction<'_, RW, NoWriteMap>,
        tables: &MdbxTables<'_>,
        collection: &str,
        document_id: u64,
    ) -> Result<(), String> {
        let collection_prefix = encode_collection_key(collection);
        let (index_keys, unique_keys) =
            Self::document_keys(transaction, tables, &collection_prefix, document_id)?;

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

    #[cfg_attr(not(test), allow(dead_code))]
    fn clear_collection(
        transaction: &Transaction<'_, RW, NoWriteMap>,
        tables: &MdbxTables<'_>,
        collection: &str,
    ) -> Result<MdbxIndexStats, String> {
        let collection_prefix = encode_collection_key(collection);
        let index_keys = scan_keys_by_prefix(transaction, &tables.indexes, &collection_prefix)?;
        let unique_keys =
            scan_keys_by_prefix(transaction, &tables.unique_indexes, &collection_prefix)?;
        let stats = MdbxIndexStats {
            entries: index_keys.len(),
            unique_entries: unique_keys.len(),
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
        Ok(stats)
    }

    #[cfg_attr(not(test), allow(dead_code))]
    fn stats<K>(
        transaction: &Transaction<'_, K, NoWriteMap>,
        tables: &MdbxTables<'_>,
        collection: &str,
    ) -> Result<MdbxIndexStats, String>
    where
        K: libmdbx::TransactionKind,
    {
        let collection_prefix = encode_collection_key(collection);
        Ok(MdbxIndexStats {
            entries: count_keys_by_prefix(transaction, &tables.indexes, &collection_prefix)?,
            unique_entries: count_keys_by_prefix(
                transaction,
                &tables.unique_indexes,
                &collection_prefix,
            )?,
        })
    }

    fn document_keys(
        transaction: &Transaction<'_, RW, NoWriteMap>,
        tables: &MdbxTables<'_>,
        collection_prefix: &[u8],
        document_id: u64,
    ) -> Result<(Vec<Vec<u8>>, Vec<Vec<u8>>), String> {
        let mut index_keys = Vec::new();
        let mut unique_keys = Vec::new();
        let mut cursor = transaction
            .cursor(&tables.indexes)
            .map_err(|error| error.to_string())?;
        for row in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(collection_prefix) {
            let (key, _) = row.map_err(|error| error.to_string())?;
            if !key.starts_with(collection_prefix) {
                break;
            }
            if decode_key_document_id(&key)? == document_id {
                let key = key.into_owned();
                if key.len() >= 8 {
                    unique_keys.push(key[..key.len() - 8].to_vec());
                }
                index_keys.push(key);
            }
        }
        Ok((index_keys, unique_keys))
    }
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

fn max_id_by_key_range<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    table: &Table<'_>,
    start: &[u8],
    end_inclusive: Option<&[u8]>,
) -> Result<Option<u64>, String>
where
    K: libmdbx::TransactionKind,
{
    let mut cursor = transaction
        .cursor(table)
        .map_err(|error| error.to_string())?;
    let mut max_id: Option<u64> = None;
    for row in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(start) {
        let (key, _) = row.map_err(|error| error.to_string())?;
        if let Some(end_inclusive) = end_inclusive {
            if key.as_ref() > end_inclusive {
                break;
            }
        } else if !key.starts_with(start) {
            break;
        }
        let id = decode_key_document_id(&key)?;
        max_id = Some(max_id.map_or(id, |current| current.max(id)));
    }
    Ok(max_id)
}

fn scan_entries_by_key_range<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    table: &Table<'_>,
    start: &[u8],
    end_inclusive: Option<&[u8]>,
) -> Result<Vec<(Vec<u8>, u64)>, String>
where
    K: libmdbx::TransactionKind,
{
    let mut cursor = transaction
        .cursor(table)
        .map_err(|error| error.to_string())?;
    let mut entries = Vec::new();
    for row in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(start) {
        let (key, _) = row.map_err(|error| error.to_string())?;
        if let Some(end_inclusive) = end_inclusive {
            if key.as_ref() > end_inclusive {
                break;
            }
        } else if !key.starts_with(start) {
            break;
        }
        let id = decode_key_document_id(&key)?;
        entries.push((key.into_owned(), id));
    }
    Ok(entries)
}

#[cfg_attr(not(test), allow(dead_code))]
fn scan_keys_by_prefix<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    table: &Table<'_>,
    prefix: &[u8],
) -> Result<Vec<Vec<u8>>, String>
where
    K: libmdbx::TransactionKind,
{
    let mut keys = Vec::new();
    let mut cursor = transaction
        .cursor(table)
        .map_err(|error| error.to_string())?;
    for row in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(prefix) {
        let (key, _) = row.map_err(|error| error.to_string())?;
        if !key.starts_with(prefix) {
            break;
        }
        keys.push(key.into_owned());
    }
    Ok(keys)
}

#[cfg_attr(not(test), allow(dead_code))]
fn count_keys_by_prefix<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    table: &Table<'_>,
    prefix: &[u8],
) -> Result<usize, String>
where
    K: libmdbx::TransactionKind,
{
    let mut cursor = transaction
        .cursor(table)
        .map_err(|error| error.to_string())?;
    let mut count = 0;
    for row in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(prefix) {
        let (key, _) = row.map_err(|error| error.to_string())?;
        if !key.starts_with(prefix) {
            break;
        }
        count += 1;
    }
    Ok(count)
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
    fn opens_multiple_handles_to_the_same_directory() {
        // Scenario: Dart watchers can use one handle while another handle writes.
        // Covers:
        // - Opening the same MDBX environment twice in one process.
        // - Reading changes from the first handle after the second commits.
        // Expected: MDBX supports the same multi-handle workflow as SQLite.
        let directory = TemporaryDirectory::new("multi_handle");
        let first = MdbxStorage::open(directory.path()).unwrap();
        let mut second = MdbxStorage::open(directory.path()).unwrap();

        second.put("users", 1, br#"{"name":"Ana"}"#).unwrap();

        assert_eq!(
            first.get("users", 1).unwrap(),
            Some(br#"{"name":"Ana"}"#.to_vec())
        );
    }

    #[test]
    fn shares_in_memory_auto_increment_counters_between_handles() {
        // Scenario: Multiple Dart handles point to the same MDBX environment.
        // Covers:
        // - In-process shared auto-increment counters.
        // - Explicit id advancement without persisted counter-table writes.
        // Expected: Handles allocate monotonic ids from the same shared counter.
        let directory = TemporaryDirectory::new("multi_handle_ids");
        let mut first = MdbxStorage::open(directory.path()).unwrap();
        let mut second = MdbxStorage::open(directory.path()).unwrap();

        assert_eq!(first.allocate_id("users").unwrap(), 1);
        assert_eq!(second.allocate_id("users").unwrap(), 2);

        second.put("users", 10, br#"{"name":"Manual"}"#).unwrap();

        assert_eq!(first.allocate_id("users").unwrap(), 11);
    }

    #[test]
    fn initializes_auto_increment_from_existing_document_ids() {
        // Scenario: A database is reopened without relying on persisted counter
        // rows.
        // Covers:
        // - Counter initialization from MDBX document primary keys.
        // - Explicit id max advancement after all handles are dropped.
        // Expected: Reopened storage allocates one greater than the max id.
        let directory = TemporaryDirectory::new("reopen_ids");
        {
            let mut storage = MdbxStorage::open(directory.path()).unwrap();
            storage.put("users", 41, br#"{"name":"Manual"}"#).unwrap();
        }

        let mut reopened = MdbxStorage::open(directory.path()).unwrap();

        assert_eq!(reopened.allocate_id("users").unwrap(), 42);
    }

    #[test]
    fn does_not_persist_allocate_only_ids_without_documents() {
        // Scenario: An app allocates ids but never commits documents before the
        // process exits.
        // Covers:
        // - Counter state being intentionally in-memory for MDBX.
        // - Reopen fallback to primary-key inspection.
        // Expected: Empty collections restart at id 1 because no document exists.
        let directory = TemporaryDirectory::new("allocate_only_ids");
        {
            let mut storage = MdbxStorage::open(directory.path()).unwrap();
            assert_eq!(storage.allocate_id("users").unwrap(), 1);
            assert_eq!(storage.allocate_id("users").unwrap(), 2);
        }

        let mut reopened = MdbxStorage::open(directory.path()).unwrap();

        assert_eq!(reopened.allocate_id("users").unwrap(), 1);
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
                br#"{"id":1,"email":"ana@example.com","name":"Ana","score":10}"#,
                &[
                    IndexEntry {
                        name: "email".into(),
                        value: IndexValue::String("wrong@example.com".into()),
                    },
                    IndexEntry {
                        name: "score".into(),
                        value: IndexValue::Int(999),
                    },
                ],
            )
            .unwrap();
        storage
            .put_indexed(
                "users",
                2,
                br#"{"id":2,"email":"ben@example.com","name":"Ben","score":30}"#,
                &[
                    IndexEntry {
                        name: "email".into(),
                        value: IndexValue::String("ignored@example.com".into()),
                    },
                    IndexEntry {
                        name: "score".into(),
                        value: IndexValue::Int(999),
                    },
                ],
            )
            .unwrap();

        let read = storage.get("users", 1).unwrap().unwrap();
        assert_eq!(
            serde_json::from_slice::<serde_json::Value>(&read).unwrap(),
            serde_json::json!({
                "email": "ana@example.com",
                "id": 1,
                "name": "Ana",
                "score": 10,
            })
        );
        storage
            .with_read_transaction(|transaction, tables| {
                let raw = transaction
                    .get::<Vec<u8>>(&tables.documents, &encode_document_key("users", 1))
                    .map_err(|error| error.to_string())?
                    .expect("document must exist");
                BinaryDocument::parse(&raw).map(|_| ())
            })
            .unwrap();
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
                .query_index_equal(
                    "users",
                    "email",
                    &IndexValue::String("wrong@example.com".into())
                )
                .unwrap(),
            Vec::<u64>::new()
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
    fn mdbx_index_boundary_replaces_deletes_clears_and_counts_entries() {
        // Scenario: PERF-02 moves MDBX index responsibilities behind an
        // internal boundary before changing the table layout.
        // Covers:
        // - Index key creation and equality prefixes.
        // - Unique index validation through the unique index table.
        // - Replacing, deleting, clearing, and counting index entries.
        // Expected: The boundary preserves current global-table behavior while
        //   giving later stages one place to change index maintenance.
        let directory = TemporaryDirectory::new("index_boundary");
        let storage = MdbxStorage::open(directory.path()).unwrap();
        let unique_indexes = HashSet::from(["email".to_string()]);

        storage
            .with_write_transaction(|transaction, tables| {
                let tables = &tables;
                MdbxIndex::replace_document(
                    transaction,
                    tables,
                    "users",
                    1,
                    &[
                        index("email", IndexValue::String("old@example.com".into())),
                        index("score", IndexValue::Int(10)),
                    ],
                    &unique_indexes,
                )?;
                assert_eq!(
                    MdbxIndex::stats(transaction, tables, "users")?,
                    MdbxIndexStats {
                        entries: 2,
                        unique_entries: 1,
                    }
                );

                let old_email_prefix = MdbxIndex::equal_prefix(
                    "users",
                    "email",
                    &IndexValue::String("old@example.com".into()),
                )?;
                assert_eq!(
                    scan_ids_by_key_range(transaction, &tables.indexes, &old_email_prefix, None)?,
                    vec![1]
                );

                MdbxIndex::replace_document(
                    transaction,
                    tables,
                    "users",
                    1,
                    &[
                        index("email", IndexValue::String("new@example.com".into())),
                        index("score", IndexValue::Int(20)),
                    ],
                    &unique_indexes,
                )?;
                assert_eq!(
                    scan_ids_by_key_range(transaction, &tables.indexes, &old_email_prefix, None)?,
                    Vec::<u64>::new()
                );
                let duplicate = MdbxIndex::validate_unique(
                    transaction,
                    tables,
                    "users",
                    2,
                    &[index("email", IndexValue::String("new@example.com".into()))],
                    &unique_indexes,
                );
                assert!(duplicate.unwrap_err().contains("Unique index `email`"));

                MdbxIndex::delete_document(transaction, tables, "users", 1)?;
                assert_eq!(
                    MdbxIndex::stats(transaction, tables, "users")?,
                    MdbxIndexStats {
                        entries: 0,
                        unique_entries: 0,
                    }
                );

                MdbxIndex::replace_document(
                    transaction,
                    tables,
                    "users",
                    1,
                    &[index("email", IndexValue::String("a@example.com".into()))],
                    &unique_indexes,
                )?;
                MdbxIndex::replace_document(
                    transaction,
                    tables,
                    "users",
                    2,
                    &[index("email", IndexValue::String("b@example.com".into()))],
                    &unique_indexes,
                )?;
                assert_eq!(
                    MdbxIndex::clear_collection(transaction, tables, "users")?,
                    MdbxIndexStats {
                        entries: 2,
                        unique_entries: 2,
                    }
                );
                assert_eq!(
                    MdbxIndex::stats(transaction, tables, "users")?,
                    MdbxIndexStats {
                        entries: 0,
                        unique_entries: 0,
                    }
                );
                Ok(())
            })
            .unwrap();
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
                fields: vec![
                    test_field("email", "String", false, true),
                    test_field("id", "int", true, false),
                    test_field("name", "String", false, false),
                    test_field("score", "int", false, true),
                ],
                composite_indexes: Vec::new(),
            }],
        }
    }

    fn test_field(
        name: &str,
        dart_type: &str,
        is_id: bool,
        is_indexed: bool,
    ) -> FieldSchemaManifest {
        FieldSchemaManifest {
            name: name.to_string(),
            dart_type: dart_type.to_string(),
            is_id,
            is_indexed,
            is_index_unique: false,
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
