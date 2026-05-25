use std::borrow::Cow;
use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::{SystemTime, UNIX_EPOCH};

use libmdbx::{
    Database, DatabaseOptions, Mode, NoWriteMap, ReadWriteOptions, SyncMode, Table, TableFlags,
    Transaction, WriteFlags, RO, RW,
};

use crate::document_format::{binary_to_wire_value, read_binary_field};
use crate::document_format::{
    index_entries_from_binary_document, validate_generic_document, BinaryDocument, BinaryValue,
};
use crate::native_filter::NativeFilter;
use crate::wire::{
    encode_projection_rows, encode_scalar, WireIndexValue, WireProjectionRows, WireQueryPlan,
    WireQuerySource, WireScalar,
};

use super::mdbx_key::{
    decode_key_document_id, encode_collection_key, encode_document_key, encode_index_equal_prefix,
    encode_index_range, COLLECTION_REVISIONS_TABLE, SCHEMA_COLLECTIONS_TABLE,
    STORAGE_METADATA_TABLE,
};
use super::{
    decode_index_entry_metadata, decode_schema_record, encode_index_entry_metadata,
    encode_schema_record, CollectionSchemaManifest, DocumentWrite, FieldSchemaManifest, IndexEntry,
    IndexValue, SchemaManifest, StorageChangeSet, StorageEngine,
};
use super::{DocumentFormatVersion, SchemaMetadataVersion, StorageLayoutVersion, StorageMetadata};

const IN_MEMORY_DIRECTORY: &str = ":memory:";
const MDBX_FILE_NAME: &str = "cindel.mdbx";
const DOCUMENT_INDEXES_TABLE: &str = "__v2_document_indexes";
const MDBX_MIN_SIZE: isize = 1 << 20;
const MDBX_DEFAULT_MAX_SIZE: isize = 128 << 20;
const MDBX_GROWTH_STEP: isize = 5 << 20;
const MDBX_SHRINK_THRESHOLD: isize = 20 << 20;
const MDBX_MAX_TABLES: u64 = 512;

pub struct MdbxStorage {
    state: SharedMdbxState,
    active_transaction: Option<MdbxActiveTransaction>,
    last_change_sets: Vec<StorageChangeSet>,
    _temporary_directory: Option<TemporaryDirectoryGuard>,
}

struct MdbxSharedState {
    database: Arc<Database<NoWriteMap>>,
    next_ids: Mutex<HashMap<String, u64>>,
    schemas: Mutex<HashMap<String, CollectionSchemaManifest>>,
}

struct PlannedDocument {
    id: u64,
    bytes: Vec<u8>,
    position: usize,
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
        mut base_ids: Vec<u64>,
        staged_matches: impl Fn(&IndexEntry) -> Result<bool, String>,
    ) -> Result<Vec<u64>, String> {
        let mut changes = HashMap::<u64, bool>::new();
        for operation in &self.operations {
            match operation {
                MdbxWriteOperation::PutIndexed {
                    collection: operation_collection,
                    id,
                    indexes,
                    ..
                } if operation_collection == collection => {
                    changes.insert(*id, staged_index_match(indexes, index, &staged_matches)?);
                }
                MdbxWriteOperation::PutManyIndexed {
                    collection: operation_collection,
                    documents,
                } if operation_collection == collection => {
                    for document in documents {
                        changes.insert(
                            document.id,
                            staged_index_match(&document.indexes, index, &staged_matches)?,
                        );
                    }
                }
                MdbxWriteOperation::Delete {
                    collection: operation_collection,
                    id,
                } if operation_collection == collection => {
                    changes.insert(*id, false);
                }
                MdbxWriteOperation::DeleteMany {
                    collection: operation_collection,
                    ids,
                } if operation_collection == collection => {
                    for id in ids {
                        changes.insert(*id, false);
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
            return Ok(base_ids);
        }

        base_ids.retain(|id| !changes.contains_key(id));
        for (id, matches) in changes {
            if matches {
                base_ids.push(id);
            }
        }
        base_ids.sort_unstable();
        Ok(base_ids)
    }
}

impl MdbxStorage {
    pub fn open(directory: &str) -> Result<Self, String> {
        let (directory_path, temporary_directory) = if directory == IN_MEMORY_DIRECTORY {
            let directory_path = temporary_mdbx_directory()?;
            (
                directory_path.clone(),
                Some(TemporaryDirectoryGuard {
                    path: directory_path,
                }),
            )
        } else {
            (PathBuf::from(directory), None)
        };

        fs::create_dir_all(&directory_path).map_err(|error| error.to_string())?;
        let directory_path = directory_path
            .canonicalize()
            .map_err(|error| error.to_string())?;
        let database_path = directory_path.join(MDBX_FILE_NAME);
        let state = open_shared_state(&database_path)?;

        let storage = Self {
            state,
            active_transaction: None,
            last_change_sets: Vec::new(),
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
            StorageLayoutVersion::MdbxV4,
            DocumentFormatVersion::BinaryV1,
            SchemaMetadataVersion::BinaryV1,
        )?;
        validate_storage_metadata(
            &transaction,
            &tables,
            StorageLayoutVersion::MdbxV4,
            DocumentFormatVersion::BinaryV1,
            SchemaMetadataVersion::BinaryV1,
        )?;
        validate_binary_metadata_records(&transaction, &tables)?;
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

    fn cached_collection_schema<K>(
        &self,
        transaction: &Transaction<'_, K, NoWriteMap>,
        tables: &MdbxTables<'_>,
        collection: &str,
    ) -> Result<Option<CollectionSchemaManifest>, String>
    where
        K: libmdbx::TransactionKind,
    {
        if let Some(schema) = self
            .state
            .schemas
            .lock()
            .map_err(|error| error.to_string())?
            .get(collection)
            .cloned()
        {
            return Ok(Some(schema));
        }

        let record = schema_record(transaction, tables, collection)?;
        if let Some(record) = record {
            let schema = record.1.clone();
            self.state
                .schemas
                .lock()
                .map_err(|error| error.to_string())?
                .insert(collection.to_string(), schema.clone());
            Ok(Some(schema))
        } else {
            Ok(None)
        }
    }

    fn cache_schema_manifest(&self, manifest: &SchemaManifest) -> Result<(), String> {
        let mut schemas = self
            .state
            .schemas
            .lock()
            .map_err(|error| error.to_string())?;
        for collection in &manifest.collections {
            schemas.insert(collection.name.clone(), collection.clone());
        }
        Ok(())
    }

    fn required_schema(&self, collection: &str) -> Result<CollectionSchemaManifest, String> {
        let schema = self.with_read_transaction(|transaction, tables| {
            self.cached_collection_schema(transaction, &tables, collection)
        })?;
        schema.ok_or_else(|| format!("collection `{collection}` has no registered schema"))
    }

    fn execute_query_plan(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Vec<PlannedDocument>, String> {
        let schema = self.required_schema(collection)?;
        let mut ids = self.query_plan_source_ids(collection, &plan.source)?;
        if query_source_dedupes(&plan.source) {
            dedupe_ids(&mut ids);
        }

        let filter = plan
            .filter
            .as_ref()
            .map(|bytes| NativeFilter::decode(bytes))
            .transpose()?;
        let documents = self.get_many_stored(collection, &ids)?;
        let mut planned = Vec::new();
        for (position, (id, document)) in ids.into_iter().zip(documents).enumerate() {
            let Some(bytes) = document else {
                continue;
            };
            if let Some(filter) = &filter {
                if !filter.matches(&schema, &bytes)? {
                    continue;
                }
            }
            planned.push(PlannedDocument {
                id,
                bytes,
                position,
            });
        }

        if !plan.sorts.is_empty() {
            sort_planned_documents(&schema, &mut planned, &plan.sorts)?;
        }
        if !plan.distinct_fields.is_empty() {
            planned = distinct_planned_documents(&schema, planned, &plan.distinct_fields)?;
        }
        Ok(window_planned_documents(
            planned,
            plan.offset as usize,
            plan.limit.map(|value| value as usize),
        ))
    }

    fn query_plan_source_ids(
        &self,
        collection: &str,
        source: &WireQuerySource,
    ) -> Result<Vec<u64>, String> {
        match source {
            WireQuerySource::All { .. } => <Self as StorageEngine>::document_ids(self, collection),
            WireQuerySource::IndexEqual {
                index_name, value, ..
            } => {
                let value = wire_index_value_to_storage(value)?;
                <Self as StorageEngine>::query_index_equal(self, collection, index_name, &value)
            }
            WireQuerySource::IndexRange {
                index_name,
                lower,
                upper,
                ..
            } => {
                let lower = lower
                    .as_ref()
                    .map(wire_index_value_to_storage)
                    .transpose()?;
                let upper = upper
                    .as_ref()
                    .map(wire_index_value_to_storage)
                    .transpose()?;
                <Self as StorageEngine>::query_index_range(
                    self,
                    collection,
                    index_name,
                    lower.as_ref(),
                    upper.as_ref(),
                )
            }
        }
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
            let _ = tables;
            let Ok(documents) = open_documents_table(transaction, collection) else {
                return Ok(1);
            };
            Ok(max_document_id(transaction, &documents)?
                .and_then(|id| id.checked_add(1))
                .unwrap_or(1))
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

    fn commit_staged_write(&mut self, staged: MdbxWriteTransaction) -> Result<(), String> {
        let counter_updates = staged.next_ids.clone();
        let mut registered_manifests = Vec::new();
        let mut change_sets = Vec::new();
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
                        let revision = bump_collection_revision(transaction, &tables, &collection)?;
                        merge_change_set(&mut change_sets, &collection, revision, [id]);
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
                            let revision =
                                bump_collection_revision(transaction, &tables, &collection)?;
                            merge_change_set(
                                &mut change_sets,
                                &collection,
                                revision,
                                documents.iter().map(|document| document.id),
                            );
                        }
                    }
                    MdbxWriteOperation::Delete { collection, id } => {
                        let deleted = delete_document(transaction, &tables, &collection, id)?;
                        if deleted {
                            let revision =
                                bump_collection_revision(transaction, &tables, &collection)?;
                            merge_change_set(&mut change_sets, &collection, revision, [id]);
                        }
                    }
                    MdbxWriteOperation::DeleteMany { collection, ids } => {
                        let mut deleted_ids = Vec::new();
                        for id in ids {
                            if delete_document(transaction, &tables, &collection, id)? {
                                deleted_ids.push(id);
                            }
                        }
                        if !deleted_ids.is_empty() {
                            let revision =
                                bump_collection_revision(transaction, &tables, &collection)?;
                            merge_change_set(&mut change_sets, &collection, revision, deleted_ids);
                        }
                    }
                    MdbxWriteOperation::RegisterSchemas { manifest, mode } => {
                        for collection in &manifest.collections {
                            register_collection_schema(transaction, &tables, collection, mode)?;
                        }
                        registered_manifests.push(manifest);
                    }
                }
            }

            Ok(())
        })?;
        self.last_change_sets = change_sets;
        for manifest in &registered_manifests {
            self.cache_schema_manifest(manifest)?;
        }
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
                permissions: Some(0o600),
                max_tables: Some(MDBX_MAX_TABLES),
                no_sub_dir: true,
                accede: false,
                coalesce: true,
                mode: Mode::ReadWrite(ReadWriteOptions {
                    sync_mode: SyncMode::NoMetaSync,
                    min_size: Some(MDBX_MIN_SIZE),
                    max_size: Some(MDBX_DEFAULT_MAX_SIZE),
                    growth_step: Some(MDBX_GROWTH_STEP),
                    shrink_threshold: Some(MDBX_SHRINK_THRESHOLD),
                }),
                ..Default::default()
            },
        )
        .map_err(|error| error.to_string())?,
    );
    let state = Arc::new(MdbxSharedState {
        database,
        next_ids: Mutex::new(HashMap::new()),
        schemas: Mutex::new(HashMap::new()),
    });
    databases.insert(path.clone(), Arc::downgrade(&state));
    Ok(state)
}

fn staged_index_match(
    indexes: &[IndexEntry],
    index: &str,
    staged_matches: impl Fn(&IndexEntry) -> Result<bool, String>,
) -> Result<bool, String> {
    for entry in indexes {
        if entry.name != index {
            continue;
        }
        if staged_matches(entry)? {
            return Ok(true);
        }
    }
    Ok(false)
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
                self.cached_collection_schema(transaction, &tables, collection)
            })?;
            return document
                .map(|bytes| decode_document_for_read(schema.as_ref(), &bytes))
                .transpose();
        }

        self.with_read_transaction(|transaction, tables| {
            let schema = self.cached_collection_schema(transaction, &tables, collection)?;
            let Ok(documents_table) = open_documents_table(transaction, collection) else {
                return Ok(None);
            };
            let Some(bytes) = ignore_not_found(
                transaction.get::<Vec<u8>>(&documents_table, &document_table_key(id)),
            )?
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
            let schema = self.cached_collection_schema(transaction, &tables, collection)?;
            let documents_table = match open_documents_table(transaction, collection) {
                Ok(table) => table,
                Err(_) => return Ok(vec![None; ids.len()]),
            };
            let mut documents = Vec::with_capacity(ids.len());
            for id in ids {
                let bytes = transaction.get::<Vec<u8>>(&documents_table, &document_table_key(*id));
                documents.push(
                    ignore_not_found(bytes)?
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
            let _ = tables;
            let Ok(documents_table) = open_documents_table(transaction, collection) else {
                return Ok(None);
            };
            ignore_not_found(transaction.get::<Vec<u8>>(&documents_table, &document_table_key(id)))
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
            let _ = tables;
            let documents_table = match open_documents_table(transaction, collection) {
                Ok(table) => table,
                Err(_) => return Ok(vec![None; ids.len()]),
            };
            let mut documents = Vec::with_capacity(ids.len());
            for id in ids {
                documents.push(ignore_not_found(
                    transaction.get::<Vec<u8>>(&documents_table, &document_table_key(*id)),
                )?);
            }
            Ok(documents)
        })
    }

    fn document_ids(&self, collection: &str) -> Result<Vec<u64>, String> {
        let ids = self.with_read_transaction(|transaction, tables| {
            let _ = tables;
            let Ok(documents_table) = open_documents_table(transaction, collection) else {
                return Ok(Vec::new());
            };
            scan_document_ids(transaction, &documents_table)
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
                self.cached_collection_schema(transaction, &tables, collection)
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

        let mut change_sets = Vec::new();
        self.with_write_transaction(|transaction, tables| {
            put_document_with_indexes(transaction, &tables, collection, id, bytes, indexes)?;
            let revision = bump_collection_revision(transaction, &tables, collection)?;
            merge_change_set(&mut change_sets, collection, revision, [id]);
            Ok(())
        })?;
        self.last_change_sets = change_sets;
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
                self.cached_collection_schema(transaction, &tables, collection)
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

        let mut change_sets = Vec::new();
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
                let revision = bump_collection_revision(transaction, &tables, collection)?;
                merge_change_set(
                    &mut change_sets,
                    collection,
                    revision,
                    documents.iter().map(|document| document.id),
                );
            }
            Ok(())
        })?;
        self.last_change_sets = change_sets;
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

        let mut change_sets = Vec::new();
        self.with_write_transaction(|transaction, tables| {
            let deleted = delete_document(transaction, &tables, collection, id)?;
            if deleted {
                let revision = bump_collection_revision(transaction, &tables, collection)?;
                merge_change_set(&mut change_sets, collection, revision, [id]);
            }
            Ok(())
        })?;
        self.last_change_sets = change_sets;
        Ok(())
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

        let mut change_sets = Vec::new();
        self.with_write_transaction(|transaction, tables| {
            let mut deleted_ids = Vec::new();
            for id in ids {
                if delete_document(transaction, &tables, collection, *id)? {
                    deleted_ids.push(*id);
                }
            }
            if !deleted_ids.is_empty() {
                let revision = bump_collection_revision(transaction, &tables, collection)?;
                merge_change_set(&mut change_sets, collection, revision, deleted_ids);
            }
            Ok(())
        })?;
        self.last_change_sets = change_sets;
        Ok(())
    }

    fn query_index_equal(
        &self,
        collection: &str,
        index: &str,
        value: &IndexValue,
    ) -> Result<Vec<u64>, String> {
        match self.active_write() {
            Some(transaction) => {
                let ids = self.with_read_transaction(|transaction, tables| {
                    let _ = tables;
                    let key = index_value_key(value)?;
                    scan_index_equal_ids(transaction, collection, index, &key)
                })?;
                transaction
                    .staged_index_ids(collection, index, ids, |entry| Ok(entry.value == *value))
            }
            None => self.with_read_transaction(|transaction, tables| {
                let _ = tables;
                let key = index_value_key(value)?;
                scan_index_equal_ids(transaction, collection, index, &key)
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
        let range = encode_index_range("", "", lower, upper)?;
        match self.active_write() {
            Some(transaction) => {
                let ids = self.with_read_transaction(|transaction, tables| {
                    let _ = tables;
                    scan_index_range_ids(
                        transaction,
                        collection,
                        index,
                        &range.start,
                        &range.end_inclusive,
                    )
                })?;
                transaction.staged_index_ids(collection, index, ids, |entry| {
                    let key = index_value_key(&entry.value)?;
                    if key >= range.start && key <= range.end_inclusive {
                        Ok(true)
                    } else {
                        Ok(false)
                    }
                })
            }
            None => self.with_read_transaction(|transaction, tables| {
                let _ = tables;
                scan_index_range_ids(
                    transaction,
                    collection,
                    index,
                    &range.start,
                    &range.end_inclusive,
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
        let filter = NativeFilter::decode(filter)?;
        let schema = self.with_read_transaction(|transaction, tables| {
            self.cached_collection_schema(transaction, &tables, collection)
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
            self.cached_collection_schema(transaction, &tables, collection)
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
        let mut cells = Vec::new();
        for document in documents {
            let Some(document) = document else {
                continue;
            };
            let value = read_binary_field(&schema, &document, field)?;
            cells.push(binary_to_wire_value(value.as_ref())?);
        }
        encode_projection_rows(&WireProjectionRows {
            row_count: cells.len() as u32,
            column_count: 1,
            cells,
        })
    }

    fn query_aggregate(
        &self,
        collection: &str,
        candidate_ids: &[u64],
        field: &str,
        operation: &str,
    ) -> Result<Vec<u8>, String> {
        let schema = self.with_read_transaction(|transaction, tables| {
            self.cached_collection_schema(transaction, &tables, collection)
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
            values.push(read_binary_field(&schema, &document, field)?);
        }
        encode_scalar(&aggregate_binary_values(&values, operation)?)
    }

    fn query_plan_ids(&self, collection: &str, plan: &WireQueryPlan) -> Result<Vec<u64>, String> {
        Ok(self
            .execute_query_plan(collection, plan)?
            .into_iter()
            .map(|document| document.id)
            .collect())
    }

    fn query_plan_documents(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Vec<Vec<u8>>, String> {
        Ok(self
            .execute_query_plan(collection, plan)?
            .into_iter()
            .map(|document| document.bytes)
            .collect())
    }

    fn query_plan_count(&self, collection: &str, plan: &WireQueryPlan) -> Result<u64, String> {
        Ok(self.execute_query_plan(collection, plan)?.len() as u64)
    }

    fn query_plan_project(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
        field: &str,
    ) -> Result<Vec<u8>, String> {
        let schema = self.required_schema(collection)?;
        ensure_schema_field(&schema, field)?;
        let documents = self.execute_query_plan(collection, plan)?;
        let mut cells = Vec::with_capacity(documents.len());
        for document in documents {
            let value = read_binary_field(&schema, &document.bytes, field)?;
            cells.push(binary_to_wire_value(value.as_ref())?);
        }
        encode_projection_rows(&WireProjectionRows {
            row_count: cells.len() as u32,
            column_count: 1,
            cells,
        })
    }

    fn query_plan_aggregate(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
        field: &str,
        operation: &str,
    ) -> Result<Vec<u8>, String> {
        let schema = self.required_schema(collection)?;
        ensure_schema_field(&schema, field)?;
        let documents = self.execute_query_plan(collection, plan)?;
        let mut values = Vec::new();
        for document in documents {
            values.push(read_binary_field(&schema, &document.bytes, field)?);
        }
        encode_scalar(&aggregate_binary_values(&values, operation)?)
    }

    fn query_plan_delete(
        &mut self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Vec<u64>, String> {
        self.ensure_can_write()?;
        let ids = self.query_plan_ids(collection, plan)?;
        if !ids.is_empty() {
            self.delete_many(collection, &ids)?;
        }
        Ok(ids)
    }

    fn collection_revision(&self, collection: &str) -> Result<u64, String> {
        self.with_read_transaction(|transaction, tables| {
            transaction
                .get::<Vec<u8>>(
                    &tables.collection_revisions,
                    &encode_collection_key(collection),
                )
                .or_else(|error| {
                    let message = error.to_string();
                    if message.contains("NOTFOUND") || message.contains("No matching key/data pair")
                    {
                        Ok(None)
                    } else {
                        Err(message)
                    }
                })?
                .map(|bytes| decode_u64(&bytes))
                .transpose()
                .map(Option::unwrap_or_default)
        })
    }

    fn take_change_sets(&mut self) -> Result<Vec<StorageChangeSet>, String> {
        Ok(std::mem::take(&mut self.last_change_sets))
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
        })?;
        self.cache_schema_manifest(manifest)
    }

    fn schema_version(&self, collection: &str) -> Result<Option<u64>, String> {
        self.with_read_transaction(|transaction, tables| {
            transaction
                .get::<Vec<u8>>(
                    &tables.schema_collections,
                    &encode_collection_key(collection),
                )
                .map_err(|error| error.to_string())?
                .map(|bytes| decode_schema_record(&bytes).map(|record| record.0))
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
    document_indexes: Table<'txn>,
    collection_revisions: Table<'txn>,
    schema_collections: Table<'txn>,
    storage_metadata: Table<'txn>,
}

fn create_tables<'txn>(transaction: &'txn Transaction<'_, RW, NoWriteMap>) -> Result<(), String> {
    transaction
        .create_table(Some(DOCUMENT_INDEXES_TABLE), TableFlags::default())
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
        document_indexes: transaction
            .open_table(Some(DOCUMENT_INDEXES_TABLE))
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

fn validate_binary_metadata_records<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    tables: &MdbxTables<'_>,
) -> Result<(), String>
where
    K: libmdbx::TransactionKind,
{
    validate_schema_records(transaction, &tables.schema_collections)?;
    validate_document_index_records(transaction, &tables.document_indexes)
}

fn validate_schema_records<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    table: &Table<'_>,
) -> Result<(), String>
where
    K: libmdbx::TransactionKind,
{
    let mut cursor = transaction
        .cursor(table)
        .map_err(|error| error.to_string())?;
    for row in cursor.iter_start::<Cow<'_, [u8]>, Cow<'_, [u8]>>() {
        let (_, value) = row.map_err(|error| error.to_string())?;
        decode_schema_record(&value)?;
    }
    Ok(())
}

fn validate_document_index_records<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    table: &Table<'_>,
) -> Result<(), String>
where
    K: libmdbx::TransactionKind,
{
    let mut cursor = transaction
        .cursor(table)
        .map_err(|error| error.to_string())?;
    for row in cursor.iter_start::<Cow<'_, [u8]>, Cow<'_, [u8]>>() {
        let (_, value) = row.map_err(|error| error.to_string())?;
        decode_index_entry_metadata(&value)?;
    }
    Ok(())
}

fn validate_storage_metadata<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    tables: &MdbxTables<'_>,
    layout: StorageLayoutVersion,
    document_format: DocumentFormatVersion,
    schema_metadata_format: SchemaMetadataVersion,
) -> Result<(), String>
where
    K: libmdbx::TransactionKind,
{
    let metadata = read_storage_metadata(transaction, tables)?;
    if metadata.layout != layout {
        return Err(format!(
            "unsupported MDBX storage layout `{}`",
            metadata.layout.as_str()
        ));
    }
    if metadata.document_format != document_format {
        return Err(
            "JSON-era preview document storage is incompatible with Cindel binary storage; recreate the database"
                .into(),
        );
    }
    if metadata.schema_metadata_format != schema_metadata_format {
        return Err("unsupported MDBX schema metadata format; recreate the database".into());
    }
    Ok(())
}

fn create_documents_table<'txn>(
    transaction: &'txn Transaction<'_, RW, NoWriteMap>,
    collection: &str,
) -> Result<Table<'txn>, String> {
    open_or_create_table(
        transaction,
        &documents_table_name(collection),
        TableFlags::INTEGER_KEY,
    )
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
    open_or_create_table(
        transaction,
        &index_table_name(collection, index),
        TableFlags::DUP_SORT,
    )
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
    open_or_create_table(
        transaction,
        &unique_table_name(collection, index),
        TableFlags::default(),
    )
}

fn open_unique_table<'txn, K>(
    transaction: &'txn Transaction<'_, K, NoWriteMap>,
    collection: &str,
    index: &str,
) -> Result<Table<'txn>, String>
where
    K: libmdbx::TransactionKind,
{
    transaction
        .open_table(Some(&unique_table_name(collection, index)))
        .map_err(|error| error.to_string())
}

fn documents_table_name(collection: &str) -> String {
    format!("d:{collection}")
}

fn index_table_name(collection: &str, index: &str) -> String {
    format!("v2:index:{collection}:{index}")
}

fn unique_table_name(collection: &str, index: &str) -> String {
    format!("v2:unique:{collection}:{index}")
}

fn open_or_create_table<'txn>(
    transaction: &'txn Transaction<'_, RW, NoWriteMap>,
    name: &str,
    flags: TableFlags,
) -> Result<Table<'txn>, String> {
    match transaction.open_table(Some(name)) {
        Ok(table) => Ok(table),
        Err(_) => transaction
            .create_table(Some(name), flags)
            .map_err(|error| error.to_string()),
    }
}

fn index_value_key(value: &IndexValue) -> Result<Vec<u8>, String> {
    encode_index_equal_prefix("", "", value)
}

fn document_id_key(id: u64) -> [u8; 8] {
    id.to_be_bytes()
}

fn document_table_key(id: u64) -> [u8; 8] {
    id.to_ne_bytes()
}

fn decode_document_table_key(bytes: &[u8]) -> Result<u64, String> {
    let bytes = bytes
        .try_into()
        .map_err(|_| "MDBX document key must be 8 bytes".to_string())?;
    Ok(u64::from_ne_bytes(bytes))
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
        create_documents_table(transaction, &collection.name)?;
        for field in &collection.fields {
            if field.is_indexed {
                create_index_table(transaction, &collection.name, &field.name)?;
                if field.is_index_unique {
                    create_unique_table(transaction, &collection.name, &field.name)?;
                }
            }
        }
        for index in &collection.composite_indexes {
            create_index_table(transaction, &collection.name, &index.name)?;
            if index.is_unique {
                create_unique_table(transaction, &collection.name, &index.name)?;
            }
        }
        return put_schema_record(transaction, tables, &key, 1, collection);
    };

    if existing.1 == *collection {
        return Ok(());
    }
    if mode == SchemaRegistrationMode::Compatible {
        validate_compatible_schema_change(&existing.1, collection)?;
    }
    create_documents_table(transaction, &collection.name)?;
    for field in &collection.fields {
        if field.is_indexed {
            create_index_table(transaction, &collection.name, &field.name)?;
            if field.is_index_unique {
                create_unique_table(transaction, &collection.name, &field.name)?;
            }
        }
    }
    for index in &collection.composite_indexes {
        create_index_table(transaction, &collection.name, &index.name)?;
        if index.is_unique {
            create_unique_table(transaction, &collection.name, &index.name)?;
        }
    }

    let next_version = existing
        .0
        .checked_add(1)
        .ok_or_else(|| format!("schema version for `{}` overflowed", collection.name))?;
    put_schema_record(transaction, tables, &key, next_version, collection)
}

fn put_schema_record(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    key: &[u8],
    version: u64,
    schema: &CollectionSchemaManifest,
) -> Result<(), String> {
    let bytes = encode_schema_record(version, schema)?;
    transaction
        .put(&tables.schema_collections, key, bytes, WriteFlags::UPSERT)
        .map_err(|error| error.to_string())
}

fn schema_record<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
) -> Result<Option<(u64, CollectionSchemaManifest)>, String>
where
    K: libmdbx::TransactionKind,
{
    transaction
        .get::<Vec<u8>>(
            &tables.schema_collections,
            &encode_collection_key(collection),
        )
        .map_err(|error| error.to_string())?
        .map(|bytes| decode_schema_record(&bytes))
        .transpose()
}

fn collection_schema<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
) -> Result<Option<CollectionSchemaManifest>, String>
where
    K: libmdbx::TransactionKind,
{
    schema_record(transaction, tables, collection).map(|record| record.map(|record| record.1))
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

fn ensure_schema_field(schema: &CollectionSchemaManifest, field: &str) -> Result<(), String> {
    if schema
        .fields
        .iter()
        .any(|schema_field| schema_field.name == field)
    {
        Ok(())
    } else {
        Err(format!(
            "field `{field}` is not declared in schema `{}`",
            schema.name
        ))
    }
}

fn query_source_dedupes(source: &WireQuerySource) -> bool {
    match source {
        WireQuerySource::All { dedupe }
        | WireQuerySource::IndexEqual { dedupe, .. }
        | WireQuerySource::IndexRange { dedupe, .. } => *dedupe,
    }
}

fn dedupe_ids(ids: &mut Vec<u64>) {
    let mut seen = HashSet::new();
    ids.retain(|id| seen.insert(*id));
}

fn wire_index_value_to_storage(value: &WireIndexValue) -> Result<IndexValue, String> {
    match value {
        WireIndexValue::Null => Err("query plan index values cannot be null".into()),
        WireIndexValue::Bool(value) => Ok(IndexValue::Bool(*value)),
        WireIndexValue::Int(value) => Ok(IndexValue::Int(*value)),
        WireIndexValue::Double(value) if value.is_finite() => Ok(IndexValue::Double(*value)),
        WireIndexValue::Double(_) => Err("query plan double values must be finite".into()),
        WireIndexValue::String(value) => Ok(IndexValue::String(value.clone())),
        WireIndexValue::List(values) => values
            .iter()
            .map(wire_index_value_to_storage)
            .collect::<Result<Vec<_>, _>>()
            .map(IndexValue::List),
    }
}

fn sort_planned_documents(
    schema: &CollectionSchemaManifest,
    documents: &mut [PlannedDocument],
    sorts: &[crate::wire::WireQuerySort],
) -> Result<(), String> {
    let sort_fields = sorts
        .iter()
        .map(|sort| {
            schema
                .fields
                .iter()
                .position(|field| field.name == sort.field)
                .map(|index| (index, sort.ascending))
                .ok_or_else(|| {
                    format!(
                        "field `{}` is not declared in schema `{}`",
                        sort.field, schema.name
                    )
                })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let mut keyed = documents
        .iter()
        .map(|document| {
            let binary = BinaryDocument::parse(&document.bytes)?;
            let values = sort_fields
                .iter()
                .map(|(index, _)| {
                    if *index >= binary.field_count() {
                        Ok(None)
                    } else {
                        binary.field_value(*index)
                    }
                })
                .collect::<Result<Vec<_>, String>>()?;
            Ok((
                document.id,
                document.bytes.clone(),
                document.position,
                values,
            ))
        })
        .collect::<Result<Vec<_>, String>>()?;

    keyed.sort_by(|left, right| {
        for (index, (_, ascending)) in sort_fields.iter().enumerate() {
            let ordering = compare_binary_values(left.3[index].as_ref(), right.3[index].as_ref());
            if ordering != Ordering::Equal {
                return if *ascending {
                    ordering
                } else {
                    ordering.reverse()
                };
            }
        }
        left.2.cmp(&right.2)
    });

    for (target, (id, bytes, position, _)) in documents.iter_mut().zip(keyed) {
        *target = PlannedDocument {
            id,
            bytes,
            position,
        };
    }
    Ok(())
}

fn compare_binary_values(left: Option<&BinaryValue>, right: Option<&BinaryValue>) -> Ordering {
    match (left, right) {
        (None, None) => Ordering::Equal,
        (None, Some(_)) => Ordering::Less,
        (Some(_), None) => Ordering::Greater,
        (Some(left), Some(right)) => {
            if let (Some(left), Some(right)) = (binary_number(left), binary_number(right)) {
                return left.total_cmp(&right);
            }
            match (left, right) {
                (BinaryValue::String(left), BinaryValue::String(right))
                | (BinaryValue::Enum(left), BinaryValue::Enum(right))
                | (BinaryValue::String(left), BinaryValue::Enum(right))
                | (BinaryValue::Enum(left), BinaryValue::String(right)) => left.cmp(right),
                (BinaryValue::Bool(left), BinaryValue::Bool(right)) => left.cmp(right),
                _ => binary_distinct_key(Some(left)).cmp(&binary_distinct_key(Some(right))),
            }
        }
    }
}

fn distinct_planned_documents(
    schema: &CollectionSchemaManifest,
    documents: Vec<PlannedDocument>,
    fields: &[String],
) -> Result<Vec<PlannedDocument>, String> {
    for field in fields {
        ensure_schema_field(schema, field)?;
    }
    let mut seen = HashSet::new();
    let mut distinct = Vec::new();
    for document in documents {
        let key = fields
            .iter()
            .map(|field| {
                read_binary_field(schema, &document.bytes, field)
                    .map(|value| binary_distinct_key(value.as_ref()))
            })
            .collect::<Result<Vec<_>, String>>()?
            .join("\u{1}");
        if seen.insert(key) {
            distinct.push(document);
        }
    }
    Ok(distinct)
}

fn binary_distinct_key(value: Option<&BinaryValue>) -> String {
    match value {
        None => "Null:null".to_string(),
        Some(BinaryValue::Bool(value)) => format!("bool:{value}"),
        Some(BinaryValue::Int(value)) => format!("int:{value}"),
        Some(BinaryValue::DateTimeMicros(value)) => format!("DateTime:{value}"),
        Some(BinaryValue::DurationMicros(value)) => format!("Duration:{value}"),
        Some(BinaryValue::Double(value)) => format!("double:{value}"),
        Some(BinaryValue::String(value)) => format!("String:{value}"),
        Some(BinaryValue::Enum(value)) => format!("String:{value}"),
        Some(BinaryValue::List(values)) => format!(
            "List:[{}]",
            values
                .iter()
                .map(|value| binary_distinct_key(value.as_ref()))
                .collect::<Vec<_>>()
                .join(",")
        ),
        Some(BinaryValue::Embedded(values)) => format!(
            "Embedded:[{}]",
            values
                .iter()
                .map(|value| binary_distinct_key(value.as_ref()))
                .collect::<Vec<_>>()
                .join(",")
        ),
        Some(BinaryValue::Object(entries)) => format!(
            "Object:{{{}}}",
            entries
                .iter()
                .map(|(name, value)| format!("{name}:{}", binary_distinct_key(value.as_ref())))
                .collect::<Vec<_>>()
                .join(",")
        ),
    }
}

fn window_planned_documents(
    documents: Vec<PlannedDocument>,
    offset: usize,
    limit: Option<usize>,
) -> Vec<PlannedDocument> {
    if offset >= documents.len() {
        return Vec::new();
    }
    let end = limit
        .map(|limit| offset.saturating_add(limit).min(documents.len()))
        .unwrap_or(documents.len());
    documents
        .into_iter()
        .skip(offset)
        .take(end - offset)
        .collect()
}

fn aggregate_binary_values(
    values: &[Option<BinaryValue>],
    operation: &str,
) -> Result<WireScalar, String> {
    match operation {
        "count" => Ok(WireScalar::Int(
            values.iter().filter(|value| value.is_some()).count() as i64,
        )),
        "min" => aggregate_binary_min_max(values, AggregateOrder::Min),
        "max" => aggregate_binary_min_max(values, AggregateOrder::Max),
        "sum" => aggregate_binary_sum(values),
        "average" => aggregate_binary_average(values),
        _ => Err(format!("unknown aggregate operation `{operation}`")),
    }
}

fn aggregate_binary_min_max(
    values: &[Option<BinaryValue>],
    order: AggregateOrder,
) -> Result<WireScalar, String> {
    let mut best: Option<BinaryValue> = None;
    for value in values.iter().flatten() {
        match value {
            BinaryValue::Int(_)
            | BinaryValue::DateTimeMicros(_)
            | BinaryValue::DurationMicros(_)
            | BinaryValue::Double(_)
            | BinaryValue::String(_)
            | BinaryValue::Enum(_) => {}
            _ => return Err("min/max aggregates require number, string, or null values".into()),
        }
        if let Some(best_value) = &best {
            let comparison = compare_binary_values(Some(value), Some(best_value));
            let replace = match order {
                AggregateOrder::Min => comparison.is_lt(),
                AggregateOrder::Max => comparison.is_gt(),
            };
            if replace {
                best = Some(value.clone());
            }
        } else {
            best = Some(value.clone());
        }
    }
    binary_value_to_scalar(best.as_ref())
}

fn aggregate_binary_sum(values: &[Option<BinaryValue>]) -> Result<WireScalar, String> {
    let mut sum = 0.0;
    let mut count = 0_u64;
    for value in values.iter().flatten() {
        let Some(number) = binary_number(value) else {
            return Err("sum aggregate requires number or null values".into());
        };
        sum += number;
        count += 1;
    }
    if count == 0 {
        Ok(WireScalar::Null)
    } else {
        Ok(WireScalar::Double(sum))
    }
}

fn aggregate_binary_average(values: &[Option<BinaryValue>]) -> Result<WireScalar, String> {
    let mut sum = 0.0;
    let mut count = 0_u64;
    for value in values.iter().flatten() {
        let Some(number) = binary_number(value) else {
            return Err("average aggregate requires number or null values".into());
        };
        sum += number;
        count += 1;
    }
    if count == 0 {
        Ok(WireScalar::Null)
    } else {
        Ok(WireScalar::Double(sum / count as f64))
    }
}

#[derive(Clone, Copy)]
enum AggregateOrder {
    Min,
    Max,
}

fn binary_number(value: &BinaryValue) -> Option<f64> {
    match value {
        BinaryValue::Int(value)
        | BinaryValue::DateTimeMicros(value)
        | BinaryValue::DurationMicros(value) => Some(*value as f64),
        BinaryValue::Double(value) if value.is_finite() => Some(*value),
        _ => None,
    }
}

fn binary_value_to_scalar(value: Option<&BinaryValue>) -> Result<WireScalar, String> {
    Ok(match value {
        None => WireScalar::Null,
        Some(BinaryValue::Bool(value)) => WireScalar::Bool(*value),
        Some(BinaryValue::Int(value))
        | Some(BinaryValue::DateTimeMicros(value))
        | Some(BinaryValue::DurationMicros(value)) => WireScalar::Int(*value),
        Some(BinaryValue::Double(value)) if value.is_finite() => WireScalar::Double(*value),
        Some(BinaryValue::Double(_)) => return Err("aggregate double must be finite".into()),
        Some(BinaryValue::String(value)) | Some(BinaryValue::Enum(value)) => {
            WireScalar::String(value.clone())
        }
        Some(_) => return Err("aggregate value cannot be represented as a scalar".into()),
    })
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
    let documents_table = create_documents_table(transaction, collection)?;
    transaction
        .put(
            &documents_table,
            document_table_key(id),
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
    )?;
    Ok(())
}

fn encode_document_for_storage(
    schema: Option<&CollectionSchemaManifest>,
    bytes: &[u8],
    indexes: &[IndexEntry],
) -> Result<(Vec<u8>, Vec<IndexEntry>), String> {
    let Some(schema) = schema else {
        return Ok((bytes.to_vec(), indexes.to_vec()));
    };
    if BinaryDocument::parse(bytes).is_ok() {
        let indexes = index_entries_from_binary_document(schema, bytes)?;
        return Ok((bytes.to_vec(), indexes));
    }
    if validate_generic_document(bytes).is_ok() {
        return Ok((bytes.to_vec(), indexes.to_vec()));
    }
    Err("document storage requires GenericDocumentV1 or Cindel binary document bytes".into())
}

fn decode_document_for_read(
    _schema: Option<&CollectionSchemaManifest>,
    bytes: &[u8],
) -> Result<Vec<u8>, String> {
    Ok(bytes.to_vec())
}

fn delete_document(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    id: u64,
) -> Result<bool, String> {
    let deleted = transaction
        .del(
            &create_documents_table(transaction, collection)?,
            document_table_key(id),
            None,
        )
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
    _tables: &MdbxTables<'_>,
    collection: &str,
    id: u64,
) -> Result<(), String>
where
    K: libmdbx::TransactionKind,
{
    let exists = transaction
        .get::<Vec<u8>>(
            &open_documents_table(transaction, collection)?,
            &document_table_key(id),
        )
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
    schema_metadata_format: SchemaMetadataVersion,
) -> Result<(), String> {
    put_metadata_if_missing(transaction, tables, "storage_layout", layout.as_str())?;
    put_metadata_if_missing(
        transaction,
        tables,
        "document_format",
        document_format.as_str(),
    )?;
    put_metadata_if_missing(
        transaction,
        tables,
        "schema_metadata_format",
        schema_metadata_format.as_str(),
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
        .unwrap_or_else(|| DocumentFormatVersion::BinaryV1.as_str().to_string());
    let schema_metadata_format =
        read_metadata_value(transaction, tables, "schema_metadata_format")?
            .unwrap_or_else(|| SchemaMetadataVersion::BinaryV1.as_str().to_string());
    Ok(StorageMetadata {
        layout: parse_storage_layout(&layout)?,
        document_format: parse_document_format(&document_format)?,
        schema_metadata_format: super::metadata::parse_schema_metadata_format(
            &schema_metadata_format,
        )?,
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
        "mdbx-v3" => Ok(StorageLayoutVersion::MdbxV3),
        "mdbx-v4" => Ok(StorageLayoutVersion::MdbxV4),
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
        _collection: &str,
        _index_name: &str,
        value: &IndexValue,
    ) -> Result<Vec<u8>, String> {
        index_value_key(value)
    }

    fn unique_key(
        _collection: &str,
        _index_name: &str,
        value: &IndexValue,
    ) -> Result<Vec<u8>, String> {
        index_value_key(value)
    }

    #[cfg_attr(not(test), allow(dead_code))]
    fn equal_prefix(
        _collection: &str,
        _index_name: &str,
        value: &IndexValue,
    ) -> Result<Vec<u8>, String> {
        index_value_key(value)
    }

    fn validate_unique(
        transaction: &Transaction<'_, RW, NoWriteMap>,
        _tables: &MdbxTables<'_>,
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
            let unique_table = create_unique_table(transaction, collection, &index.name)?;
            if let Some(existing_id) =
                ignore_not_found(transaction.get::<Vec<u8>>(&unique_table, &key))?
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
        let document_indexes = &tables.document_indexes;
        let key = encode_document_key(collection, document_id);
        if new_indexes.is_empty() {
            ignore_not_found(transaction.del(document_indexes, key, None))?;
        } else {
            transaction
                .put(
                    document_indexes,
                    key,
                    encode_index_entry_metadata(document_id, new_indexes)?,
                    WriteFlags::UPSERT,
                )
                .map_err(|error| error.to_string())?;
        }
        Ok(())
    }

    fn insert_entry(
        transaction: &Transaction<'_, RW, NoWriteMap>,
        _tables: &MdbxTables<'_>,
        collection: &str,
        document_id: u64,
        index: &IndexEntry,
        is_unique: bool,
    ) -> Result<(), String> {
        let key = Self::entry_key(collection, &index.name, &index.value)?;
        let index_table = create_index_table(transaction, collection, &index.name)?;
        let document_id_bytes = document_id_key(document_id);
        transaction
            .put(&index_table, key, document_id_bytes, WriteFlags::UPSERT)
            .map_err(|error| error.to_string())?;
        if is_unique {
            let unique_key = Self::unique_key(collection, &index.name, &index.value)?;
            let unique_table = create_unique_table(transaction, collection, &index.name)?;
            transaction
                .put(
                    &unique_table,
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
        let document_index_key = encode_document_key(collection, document_id);
        let Some(indexes) = ignore_not_found(
            transaction.get::<Vec<u8>>(&tables.document_indexes, &document_index_key),
        )?
        else {
            return Ok(());
        };
        let indexes = decode_index_entry_metadata(&indexes)?;
        for index in indexes {
            let key = Self::entry_key(collection, &index.name, &index.value)?;
            let index_table = create_index_table(transaction, collection, &index.name)?;
            let document_id_bytes = document_id_key(document_id);
            ignore_not_found(transaction.del(&index_table, key, Some(&document_id_bytes)))?;
            let unique_key = Self::unique_key(collection, &index.name, &index.value)?;
            if let Ok(unique_table) = open_unique_table(transaction, collection, &index.name) {
                ignore_not_found(transaction.del(&unique_table, unique_key, None))?;
            }
        }
        ignore_not_found(transaction.del(&tables.document_indexes, document_index_key, None))?;
        Ok(())
    }

    #[cfg_attr(not(test), allow(dead_code))]
    fn clear_collection(
        transaction: &Transaction<'_, RW, NoWriteMap>,
        tables: &MdbxTables<'_>,
        collection: &str,
    ) -> Result<MdbxIndexStats, String> {
        let collection_prefix = encode_collection_key(collection);
        let document_keys =
            scan_keys_by_prefix(transaction, &tables.document_indexes, &collection_prefix)?;
        let stats = Self::stats(transaction, tables, collection)?;
        let ids = document_keys
            .iter()
            .map(|key| decode_key_document_id(key))
            .collect::<Result<Vec<_>, _>>()?;
        for id in ids {
            Self::delete_document(transaction, tables, collection, id)?;
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
        let document_keys =
            scan_keys_by_prefix(transaction, &tables.document_indexes, &collection_prefix)?;
        let mut entries = 0;
        let mut unique_entries = 0;
        for key in document_keys {
            let Some(indexes) =
                ignore_not_found(transaction.get::<Vec<u8>>(&tables.document_indexes, &key))?
            else {
                continue;
            };
            let indexes = decode_index_entry_metadata(&indexes)?;
            entries += indexes.len();
            for index in indexes {
                let Ok(unique_table) = open_unique_table(transaction, collection, &index.name)
                else {
                    continue;
                };
                let key = Self::unique_key(collection, &index.name, &index.value)?;
                if ignore_not_found(transaction.get::<Vec<u8>>(&unique_table, &key))?.is_some() {
                    unique_entries += 1;
                }
            }
        }
        let stats = MdbxIndexStats {
            entries,
            unique_entries,
        };
        Ok(stats)
    }
}

fn scan_document_ids<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    table: &Table<'_>,
) -> Result<Vec<u64>, String>
where
    K: libmdbx::TransactionKind,
{
    let mut cursor = transaction
        .cursor(table)
        .map_err(|error| error.to_string())?;
    let mut ids = Vec::new();
    for row in cursor.iter_start::<Cow<'_, [u8]>, Cow<'_, [u8]>>() {
        let (key, _) = row.map_err(|error| error.to_string())?;
        ids.push(decode_document_table_key(&key)?);
    }
    Ok(ids)
}

fn max_document_id<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    table: &Table<'_>,
) -> Result<Option<u64>, String>
where
    K: libmdbx::TransactionKind,
{
    let ids = scan_document_ids(transaction, table)?;
    Ok(ids.into_iter().max())
}

fn scan_index_equal_ids<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    collection: &str,
    index: &str,
    key: &[u8],
) -> Result<Vec<u64>, String>
where
    K: libmdbx::TransactionKind,
{
    let Ok(index_table) = open_index_table(transaction, collection, index) else {
        return Ok(Vec::new());
    };
    let mut cursor = transaction
        .cursor(&index_table)
        .map_err(|error| error.to_string())?;
    let mut ids = Vec::new();
    for row in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(key) {
        let (entry_key, value) = row.map_err(|error| error.to_string())?;
        if entry_key.as_ref() != key {
            break;
        }
        ids.push(decode_u64(&value)?);
    }
    Ok(ids)
}

fn scan_index_range_ids<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    collection: &str,
    index: &str,
    start: &[u8],
    end_inclusive: &[u8],
) -> Result<Vec<u64>, String>
where
    K: libmdbx::TransactionKind,
{
    let Ok(index_table) = open_index_table(transaction, collection, index) else {
        return Ok(Vec::new());
    };
    let mut cursor = transaction
        .cursor(&index_table)
        .map_err(|error| error.to_string())?;
    let mut ids = Vec::new();
    for row in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(start) {
        let (key, value) = row.map_err(|error| error.to_string())?;
        if key.as_ref() > end_inclusive {
            break;
        }
        ids.push(decode_u64(&value)?);
    }
    Ok(ids)
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

fn bump_collection_revision(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
) -> Result<u64, String> {
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
        .map_err(|error| error.to_string())?;
    Ok(next)
}

fn merge_change_set(
    changes: &mut Vec<StorageChangeSet>,
    collection: &str,
    revision: u64,
    ids: impl IntoIterator<Item = u64>,
) {
    let ids = ids.into_iter().collect::<Vec<_>>();
    if ids.is_empty() {
        return;
    }
    if let Some(change) = changes
        .iter_mut()
        .find(|change| change.collection == collection)
    {
        change.revision = change.revision.max(revision);
        for id in ids {
            if !change.document_ids.contains(&id) {
                change.document_ids.push(id);
            }
        }
        return;
    }
    changes.push(StorageChangeSet {
        collection: collection.to_string(),
        revision,
        document_ids: ids,
    });
}

fn decode_u64(bytes: &[u8]) -> Result<u64, String> {
    let bytes = bytes
        .try_into()
        .map_err(|_| "MDBX stored integer must be 8 bytes".to_string())?;
    Ok(u64::from_be_bytes(bytes))
}

fn ignore_not_found<T: Default, E: std::fmt::Display>(result: Result<T, E>) -> Result<T, String> {
    match result {
        Ok(value) => Ok(value),
        Err(error) => {
            let message = error.to_string();
            if message.contains("NOTFOUND") || message.contains("No matching key/data pair") {
                Ok(T::default())
            } else {
                Err(message)
            }
        }
    }
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
    use crate::document_format::{write_document, BinaryValue};
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
    fn rejects_json_era_schema_metadata_on_open() {
        // Scenario: A preview MDBX database has JSON schema metadata rows.
        // Covers:
        // - Fail-closed behavior during MDBX initialization.
        // - JSON-era schema_collections records.
        // Expected: Opening the database asks the user to recreate it.
        let directory = TemporaryDirectory::new("json_schema_metadata");
        {
            let storage = MdbxStorage::open(directory.path()).unwrap();
            storage
                .with_write_transaction(|transaction, tables| {
                    transaction
                        .put(
                            &tables.schema_collections,
                            encode_collection_key("users"),
                            br#"{"version":1}"#,
                            WriteFlags::UPSERT,
                        )
                        .map_err(|error| error.to_string())
                })
                .unwrap();
        }

        let error = MdbxStorage::open(directory.path())
            .err()
            .expect("JSON metadata should reject MDBX open");

        assert!(error.contains("JSON-era preview metadata"));
    }

    #[test]
    fn rejects_json_era_reverse_index_metadata_on_open() {
        // Scenario: A preview MDBX database has JSON document-index metadata.
        // Covers:
        // - Fail-closed behavior for reverse index metadata.
        // - The document_indexes table used to clean old index entries.
        // Expected: Opening the database rejects the JSON-era reverse metadata.
        let directory = TemporaryDirectory::new("json_reverse_index_metadata");
        {
            let storage = MdbxStorage::open(directory.path()).unwrap();
            storage
                .with_write_transaction(|transaction, tables| {
                    transaction
                        .put(
                            &tables.document_indexes,
                            encode_document_key("users", 1),
                            br#"[{"name":"email"}]"#,
                            WriteFlags::UPSERT,
                        )
                        .map_err(|error| error.to_string())
                })
                .unwrap();
        }

        let error = MdbxStorage::open(directory.path())
            .err()
            .expect("JSON reverse metadata should reject MDBX open");

        assert!(error.contains("JSON-era preview metadata"));
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
                &user_document("ana@example.com", 1, "Ana", 10),
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
                &user_document("ben@example.com", 2, "Ben", 30),
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
        assert_eq!(read, user_document("ana@example.com", 1, "Ana", 10));
        storage
            .with_read_transaction(|transaction, tables| {
                let _ = tables;
                let raw = transaction
                    .get::<Vec<u8>>(
                        &open_documents_table(transaction, "users")?,
                        &document_table_key(1),
                    )
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
    fn aggregates_binary_document_fields() {
        // Scenario: PERF-15 keeps aggregate queries inside MDBX instead of
        // hydrating full Dart objects.
        // Covers:
        // - Native count, min, max, sum, and average over binary documents.
        // - String min/max ordering.
        // - Missing candidate ids being ignored.
        // Expected: Aggregates are returned as compact CindelWireV1 scalars.
        let directory = TemporaryDirectory::new("aggregates");
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        storage.register_schemas(&schema_manifest()).unwrap();

        for (id, name, score) in [(1, "Cid", 30), (2, "Ana", 10), (3, "Ben", 20)] {
            storage
                .put_indexed(
                    "users",
                    id,
                    &user_document(&format!("user-{id}@example.com"), id as i64, name, score),
                    &[],
                )
                .unwrap();
        }

        assert_eq!(
            storage
                .query_aggregate("users", &[1, 2, 3, 999], "score", "count")
                .unwrap(),
            encode_scalar(&WireScalar::Int(3)).unwrap()
        );
        assert_eq!(
            storage
                .query_aggregate("users", &[1, 2, 3], "score", "min")
                .unwrap(),
            encode_scalar(&WireScalar::Int(10)).unwrap()
        );
        assert_eq!(
            storage
                .query_aggregate("users", &[1, 2, 3], "score", "max")
                .unwrap(),
            encode_scalar(&WireScalar::Int(30)).unwrap()
        );
        assert_eq!(
            storage
                .query_aggregate("users", &[1, 2, 3], "score", "sum")
                .unwrap(),
            encode_scalar(&WireScalar::Double(60.0)).unwrap()
        );
        assert_eq!(
            storage
                .query_aggregate("users", &[1, 2, 3], "score", "average")
                .unwrap(),
            encode_scalar(&WireScalar::Double(20.0)).unwrap()
        );
        assert_eq!(
            storage
                .query_aggregate("users", &[1, 2, 3], "name", "min")
                .unwrap(),
            encode_scalar(&WireScalar::String("Ana".to_string())).unwrap()
        );
        assert_eq!(
            storage
                .query_aggregate("users", &[1, 2, 3], "name", "max")
                .unwrap(),
            encode_scalar(&WireScalar::String("Cid".to_string())).unwrap()
        );
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
            .with_write_transaction(|transaction, _tables| {
                create_index_table(transaction, "users", "email")?;
                create_index_table(transaction, "users", "score")?;
                create_unique_table(transaction, "users", "email")?;
                Ok(())
            })
            .unwrap();

        let old_email_prefix = MdbxIndex::equal_prefix(
            "users",
            "email",
            &IndexValue::String("old@example.com".into()),
        )
        .unwrap();

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
                assert_eq!(
                    scan_index_equal_ids(transaction, "users", "email", &old_email_prefix,)?,
                    vec![1]
                );
                Ok(())
            })
            .unwrap();

        storage
            .with_write_transaction(|transaction, tables| {
                let tables = &tables;
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
                    scan_index_equal_ids(transaction, "users", "email", &old_email_prefix,)?,
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
                Ok(())
            })
            .unwrap();

        storage
            .with_write_transaction(|transaction, tables| {
                let tables = &tables;
                MdbxIndex::delete_document(transaction, tables, "users", 1)?;
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

        storage
            .with_write_transaction(|transaction, tables| {
                let tables = &tables;
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
                Ok(())
            })
            .unwrap();

        storage
            .with_write_transaction(|transaction, tables| {
                let tables = &tables;
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

    fn user_document(email: &str, id: i64, name: &str, score: i64) -> Vec<u8> {
        write_document(&[
            Some(BinaryValue::String(email.to_string())),
            Some(BinaryValue::Int(id)),
            Some(BinaryValue::String(name.to_string())),
            Some(BinaryValue::Int(score)),
        ])
        .unwrap()
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
