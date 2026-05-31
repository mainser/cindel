use std::borrow::Cow;
use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::{SystemTime, UNIX_EPOCH};

use libmdbx::{
    Cursor, Database, DatabaseOptions, Mode, NoWriteMap, ReadWriteOptions, SyncMode, Table,
    TableFlags, Transaction, WriteFlags, RO, RW,
};

use crate::document_format::{
    apply_prepared_binary_field_updates, binary_to_wire_value, prepare_binary_field_updates,
    prepare_binary_sort_field, read_binary_field, read_binary_field_at,
    read_prepared_binary_sort_key, read_prepared_binary_string_sort_range,
    PreparedBinaryFieldUpdates, PreparedBinarySortField,
};
use crate::document_format::{
    for_each_index_entry_from_binary_document, index_entries_from_binary_document,
    validate_binary_document, validate_generic_document, BinarySortKey, BinaryValue,
};
use crate::native_filter::NativeFilter;
use crate::wire::{
    encode_projection_rows, encode_scalar, WireIndexValue, WireProjectionRows, WireQueryPlan,
    WireQuerySource, WireScalar, WireValue,
};

use super::mdbx_key::{
    decode_key_document_id, encode_collection_key, encode_document_key, encode_table_index_range,
    encode_table_index_value, encode_table_index_value_into, COLLECTION_REVISIONS_TABLE,
    SCHEMA_COLLECTIONS_TABLE, STORAGE_METADATA_TABLE,
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
const MDBX_DEFAULT_MAX_SIZE: isize = 1 << 30;
const MDBX_GROWTH_STEP: isize = 5 << 20;
const MDBX_SHRINK_THRESHOLD: isize = 20 << 20;
const MDBX_MAX_TABLES: u64 = 512;

pub struct MdbxStorage {
    state: SharedMdbxState,
    active_transaction: Option<MdbxActiveTransaction>,
    last_change_sets: Vec<StorageChangeSet>,
    _temporary_directory: Option<TemporaryDirectoryGuard>,
}

pub(crate) struct MdbxCursorDocumentReader {
    cursor: Cursor<'static, RO>,
    _transaction: Transaction<'static, RO, NoWriteMap>,
    ids: Vec<u64>,
    current_index: Option<usize>,
    current_bytes: Option<Cow<'static, [u8]>>,
}

impl MdbxCursorDocumentReader {
    pub(crate) fn len(&self) -> usize {
        self.ids.len()
    }

    pub(crate) fn is_present(&mut self, document_index: usize) -> Result<bool, String> {
        self.load(document_index)?;
        Ok(self.current_bytes.is_some())
    }

    pub(crate) fn document_bytes(
        &mut self,
        document_index: usize,
    ) -> Result<Option<&[u8]>, String> {
        self.load(document_index)?;
        Ok(self.current_bytes.as_deref())
    }

    pub(crate) fn document_id(&mut self, document_index: usize) -> Result<Option<u64>, String> {
        self.load(document_index)?;
        if self.current_bytes.is_some() {
            Ok(self.ids.get(document_index).copied())
        } else {
            Ok(None)
        }
    }

    fn load(&mut self, document_index: usize) -> Result<(), String> {
        if self.current_index == Some(document_index) {
            return Ok(());
        }
        self.current_index = Some(document_index);
        self.current_bytes = None;
        let Some(id) = self.ids.get(document_index).copied() else {
            return Ok(());
        };
        self.current_bytes = ignore_not_found(
            self.cursor
                .set::<Cow<'static, [u8]>>(&document_table_key(id))
                .map_err(|error| error.to_string()),
        )?;
        Ok(())
    }
}

enum MdbxQueryCursorSource {
    Documents {
        cursor: Cursor<'static, RO>,
        started: bool,
    },
    IndexEqual {
        index_cursor: Cursor<'static, RO>,
        documents_cursor: Cursor<'static, RO>,
        key: Vec<u8>,
        started: bool,
        seen: Option<HashSet<u64>>,
    },
    Sorted {
        documents: Vec<BorrowedPlannedDocument<'static>>,
        current_index: usize,
    },
}

pub(crate) struct MdbxQueryDocumentReader {
    source: MdbxQueryCursorSource,
    _transaction: Transaction<'static, RO, NoWriteMap>,
    schema: CollectionSchemaManifest,
    filter: Option<NativeFilter>,
    offset: usize,
    limit: Option<usize>,
    matched: usize,
    emitted: usize,
    current_id: Option<u64>,
    current_present: bool,
    current_bytes: Option<Cow<'static, [u8]>>,
}

impl MdbxQueryDocumentReader {
    pub(crate) fn next(&mut self) -> Result<bool, String> {
        if self.limit.is_some_and(|limit| self.emitted >= limit) {
            self.current_present = false;
            self.current_bytes = None;
            return Ok(false);
        }

        match &mut self.source {
            MdbxQueryCursorSource::Documents { cursor, started } => loop {
                let row = if *started {
                    cursor
                        .next::<Cow<'static, [u8]>, Cow<'static, [u8]>>()
                        .map_err(|error| error.to_string())?
                } else {
                    *started = true;
                    cursor
                        .first::<Cow<'static, [u8]>, Cow<'static, [u8]>>()
                        .map_err(|error| error.to_string())?
                };
                let Some((key, bytes)) = row else {
                    self.current_present = false;
                    self.current_id = None;
                    self.current_bytes = None;
                    return Ok(false);
                };
                let id = decode_document_table_key(key.as_ref())?;
                if let Some(filter) = &self.filter {
                    if !filter.matches_with_id(&self.schema, bytes.as_ref(), id)? {
                        continue;
                    }
                }
                if self.matched < self.offset {
                    self.matched += 1;
                    continue;
                }
                self.current_bytes = Some(bytes);
                self.current_id = Some(id);
                self.current_present = true;
                self.matched += 1;
                self.emitted += 1;
                return Ok(true);
            },
            MdbxQueryCursorSource::IndexEqual {
                index_cursor,
                documents_cursor,
                key,
                started,
                seen,
            } => loop {
                let row = if *started {
                    index_cursor
                        .next::<Cow<'static, [u8]>, Cow<'static, [u8]>>()
                        .map_err(|error| error.to_string())?
                } else {
                    *started = true;
                    index_cursor
                        .set_range::<Cow<'static, [u8]>, Cow<'static, [u8]>>(key)
                        .map_err(|error| error.to_string())?
                };
                let Some((entry_key, value)) = row else {
                    self.current_present = false;
                    self.current_id = None;
                    self.current_bytes = None;
                    return Ok(false);
                };
                if entry_key.as_ref() != key.as_slice() {
                    self.current_present = false;
                    self.current_id = None;
                    self.current_bytes = None;
                    return Ok(false);
                }
                let id = decode_u64(&value)?;
                if let Some(seen) = seen {
                    if !seen.insert(id) {
                        continue;
                    }
                }
                let Some(bytes) = ignore_not_found(
                    documents_cursor.set::<Cow<'static, [u8]>>(&document_table_key(id)),
                )?
                else {
                    continue;
                };
                if let Some(filter) = &self.filter {
                    if !filter.matches_with_id(&self.schema, bytes.as_ref(), id)? {
                        continue;
                    }
                }
                if self.matched < self.offset {
                    self.matched += 1;
                    continue;
                }
                self.current_bytes = Some(bytes);
                self.current_id = Some(id);
                self.current_present = true;
                self.matched += 1;
                self.emitted += 1;
                return Ok(true);
            },
            MdbxQueryCursorSource::Sorted {
                documents,
                current_index,
            } => {
                if *current_index >= documents.len() {
                    self.current_present = false;
                    self.current_id = None;
                    self.current_bytes = None;
                    return Ok(false);
                }
                self.current_id = documents.get(*current_index).map(|document| document.id);
                *current_index += 1;
                self.current_present = true;
                self.emitted += 1;
                Ok(true)
            }
        }
    }

    pub(crate) fn document_bytes(&self, document_index: usize) -> Result<Option<&[u8]>, String> {
        if document_index != 0 || !self.current_present {
            return Ok(None);
        }
        match &self.source {
            MdbxQueryCursorSource::Sorted {
                documents,
                current_index,
            } => {
                let Some(document) = current_index
                    .checked_sub(1)
                    .and_then(|index| documents.get(index))
                else {
                    return Ok(None);
                };
                Ok(Some(document.bytes.as_ref()))
            }
            MdbxQueryCursorSource::Documents { .. } | MdbxQueryCursorSource::IndexEqual { .. } => {
                Ok(self.current_bytes.as_deref())
            }
        }
    }

    pub(crate) fn document_id(&self, document_index: usize) -> Result<Option<u64>, String> {
        if document_index != 0 || !self.current_present {
            return Ok(None);
        }
        Ok(self.current_id)
    }
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

struct BorrowedPlannedDocument<'a> {
    id: u64,
    bytes: Cow<'a, [u8]>,
    position: usize,
    sort_values: BorrowedSortValues,
}

enum BorrowedSortValues {
    One(BorrowedSortValue),
    OneStringRange(Option<std::ops::Range<usize>>),
    Many(Vec<BorrowedSortValue>),
}

enum BorrowedSortValue {
    Id(u64),
    Field(Option<BinarySortKey>),
}

enum OwnedSortValue {
    Id(u64),
    Field(Option<BinaryValue>),
}

enum QuerySortTarget {
    Id,
    Field(PreparedBinarySortField),
}

struct QuerySortField {
    index: usize,
    ascending: bool,
    target: QuerySortTarget,
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
        Self::open_with_optional_schemas(directory, None)
    }

    pub fn open_with_schemas(directory: &str, manifest: &SchemaManifest) -> Result<Self, String> {
        validate_schema_manifest(manifest)?;
        Self::open_with_optional_schemas(directory, Some(manifest))
    }

    fn open_with_optional_schemas(
        directory: &str,
        manifest: Option<&SchemaManifest>,
    ) -> Result<Self, String> {
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
        storage.initialize(manifest)?;
        Ok(storage)
    }

    fn initialize(&self, manifest: Option<&SchemaManifest>) -> Result<(), String> {
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
            StorageLayoutVersion::MdbxV6,
            DocumentFormatVersion::BinaryV2,
            SchemaMetadataVersion::BinaryV1,
        )?;
        validate_storage_metadata(
            &transaction,
            &tables,
            StorageLayoutVersion::MdbxV6,
            DocumentFormatVersion::BinaryV2,
            SchemaMetadataVersion::BinaryV1,
        )?;
        validate_binary_metadata_records(&transaction, &tables)?;
        if let Some(manifest) = manifest {
            for collection in &manifest.collections {
                register_collection_schema(
                    &transaction,
                    &tables,
                    collection,
                    SchemaRegistrationMode::Compatible,
                )?;
            }
        }
        transaction
            .commit()
            .map(|_| ())
            .map_err(|error| error.to_string())?;
        if let Some(manifest) = manifest {
            self.cache_schema_manifest(manifest)?;
        }
        Ok(())
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

    pub(crate) fn cursor_document_reader(
        &self,
        collection: &str,
        ids: &[u64],
    ) -> Result<MdbxCursorDocumentReader, String> {
        if self.active_write().is_some() {
            return Err("cursor document reader does not support active write transactions".into());
        }
        let transaction = self
            .state
            .database
            .begin_ro_txn()
            .map_err(|error| error.to_string())?;
        let documents_table = open_documents_table(&transaction, collection)?;
        let cursor = transaction
            .cursor(&documents_table)
            .map_err(|error| error.to_string())?;

        // The libmdbx cursor internally owns a cloned transaction handle and
        // only carries the Rust transaction lifetime as a marker. Keep the
        // transaction in the reader and drop the cursor before it.
        let transaction = unsafe {
            std::mem::transmute::<
                Transaction<'_, RO, NoWriteMap>,
                Transaction<'static, RO, NoWriteMap>,
            >(transaction)
        };
        let cursor = unsafe { std::mem::transmute::<Cursor<'_, RO>, Cursor<'static, RO>>(cursor) };

        Ok(MdbxCursorDocumentReader {
            cursor,
            _transaction: transaction,
            ids: ids.to_vec(),
            current_index: None,
            current_bytes: None,
        })
    }

    pub(crate) fn query_document_reader(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Option<MdbxQueryDocumentReader>, String> {
        if self.active_write().is_some() || !plan.distinct_fields.is_empty() {
            return Ok(None);
        }

        let schema = self.required_schema(collection)?;
        let filter = plan
            .filter
            .as_ref()
            .map(|bytes| {
                NativeFilter::decode(bytes).map(|filter| filter.prepare_for_schema(&schema))
            })
            .transpose()?;
        let transaction = self
            .state
            .database
            .begin_ro_txn()
            .map_err(|error| error.to_string())?;

        if !plan.sorts.is_empty() {
            let documents = {
                let sort_fields = query_sort_fields(&schema, &plan.sorts)?;
                let offset = plan.offset as usize;
                let limit = plan.limit.map(|value| value as usize);
                let documents_table = match open_documents_table(&transaction, collection) {
                    Ok(table) => table,
                    Err(_) => return Ok(None),
                };
                let mut documents_cursor = transaction
                    .cursor(&documents_table)
                    .map_err(|error| error.to_string())?;
                let mut planned = Vec::new();
                let mut seen = query_source_dedupes(&plan.source).then(HashSet::new);
                let mut position = 0usize;

                if let Some(bool_query) = direct_bool_index_query(&schema, plan) {
                    for row in documents_cursor.iter_start::<Cow<'_, [u8]>, Cow<'_, [u8]>>() {
                        let (key, bytes) = row.map_err(|error| error.to_string())?;
                        if !direct_bool_index_query_matches(bytes.as_ref(), &bool_query)? {
                            continue;
                        }
                        let id = decode_document_table_key(&key)?;
                        push_borrowed_planned_document(
                            &schema,
                            filter.as_ref(),
                            &sort_fields,
                            &mut planned,
                            id,
                            bytes,
                            position,
                        )?;
                        position += 1;
                    }
                } else {
                    match &plan.source {
                        WireQuerySource::All { .. } => {
                            for row in documents_cursor.iter_start::<Cow<'_, [u8]>, Cow<'_, [u8]>>()
                            {
                                let (key, bytes) = row.map_err(|error| error.to_string())?;
                                let id = decode_document_table_key(&key)?;
                                push_borrowed_planned_document(
                                    &schema,
                                    filter.as_ref(),
                                    &sort_fields,
                                    &mut planned,
                                    id,
                                    bytes,
                                    position,
                                )?;
                                position += 1;
                            }
                        }
                        WireQuerySource::IndexEqual {
                            index_name, value, ..
                        } => {
                            let value = wire_index_value_to_storage(value)?;
                            let key = index_value_key(&value)?;
                            let Ok(index_table) =
                                open_index_table(&transaction, collection, index_name)
                            else {
                                return Ok(None);
                            };
                            let mut index_cursor = transaction
                                .cursor(&index_table)
                                .map_err(|error| error.to_string())?;
                            for row in index_cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(&key)
                            {
                                let (entry_key, value) = row.map_err(|error| error.to_string())?;
                                if entry_key.as_ref() != key {
                                    break;
                                }
                                let id = decode_u64(&value)?;
                                if let Some(seen) = &mut seen {
                                    if !seen.insert(id) {
                                        continue;
                                    }
                                }
                                let Some(bytes) = ignore_not_found(
                                    documents_cursor.set::<Cow<'_, [u8]>>(&document_table_key(id)),
                                )?
                                else {
                                    position += 1;
                                    continue;
                                };
                                push_borrowed_planned_document(
                                    &schema,
                                    filter.as_ref(),
                                    &sort_fields,
                                    &mut planned,
                                    id,
                                    bytes,
                                    position,
                                )?;
                                position += 1;
                            }
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
                            let range = encode_table_index_range(lower.as_ref(), upper.as_ref())?;
                            let Ok(index_table) =
                                open_index_table(&transaction, collection, index_name)
                            else {
                                return Ok(None);
                            };
                            let mut index_cursor = transaction
                                .cursor(&index_table)
                                .map_err(|error| error.to_string())?;
                            for row in
                                index_cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(&range.start)
                            {
                                let (key, value) = row.map_err(|error| error.to_string())?;
                                if key.as_ref() > range.end_inclusive.as_slice() {
                                    break;
                                }
                                let id = decode_u64(&value)?;
                                if let Some(seen) = &mut seen {
                                    if !seen.insert(id) {
                                        continue;
                                    }
                                }
                                let Some(bytes) = ignore_not_found(
                                    documents_cursor.set::<Cow<'_, [u8]>>(&document_table_key(id)),
                                )?
                                else {
                                    position += 1;
                                    continue;
                                };
                                push_borrowed_planned_document(
                                    &schema,
                                    filter.as_ref(),
                                    &sort_fields,
                                    &mut planned,
                                    id,
                                    bytes,
                                    position,
                                )?;
                                position += 1;
                            }
                        }
                    }
                }
                sort_and_window_borrowed_query_documents(planned, &sort_fields, offset, limit)
            };
            let documents = unsafe {
                std::mem::transmute::<
                    Vec<BorrowedPlannedDocument<'_>>,
                    Vec<BorrowedPlannedDocument<'static>>,
                >(documents)
            };
            let transaction = unsafe {
                std::mem::transmute::<
                    Transaction<'_, RO, NoWriteMap>,
                    Transaction<'static, RO, NoWriteMap>,
                >(transaction)
            };
            return Ok(Some(MdbxQueryDocumentReader {
                source: MdbxQueryCursorSource::Sorted {
                    documents,
                    current_index: 0,
                },
                _transaction: transaction,
                schema,
                filter,
                offset: 0,
                limit: None,
                matched: 0,
                emitted: 0,
                current_id: None,
                current_present: false,
                current_bytes: None,
            }));
        }

        let source = match &plan.source {
            WireQuerySource::All { .. } => {
                let documents_table = match open_documents_table(&transaction, collection) {
                    Ok(table) => table,
                    Err(_) => return Ok(None),
                };
                let cursor = transaction
                    .cursor(&documents_table)
                    .map_err(|error| error.to_string())?;
                let cursor =
                    unsafe { std::mem::transmute::<Cursor<'_, RO>, Cursor<'static, RO>>(cursor) };
                MdbxQueryCursorSource::Documents {
                    cursor,
                    started: false,
                }
            }
            WireQuerySource::IndexEqual {
                index_name,
                value,
                dedupe,
            } => {
                let value = wire_index_value_to_storage(value)?;
                let key = index_value_key(&value)?;
                let index_table = match open_index_table(&transaction, collection, index_name) {
                    Ok(table) => table,
                    Err(_) => return Ok(None),
                };
                let documents_table = match open_documents_table(&transaction, collection) {
                    Ok(table) => table,
                    Err(_) => return Ok(None),
                };
                let index_cursor = transaction
                    .cursor(&index_table)
                    .map_err(|error| error.to_string())?;
                let documents_cursor = transaction
                    .cursor(&documents_table)
                    .map_err(|error| error.to_string())?;
                let index_cursor = unsafe {
                    std::mem::transmute::<Cursor<'_, RO>, Cursor<'static, RO>>(index_cursor)
                };
                let documents_cursor = unsafe {
                    std::mem::transmute::<Cursor<'_, RO>, Cursor<'static, RO>>(documents_cursor)
                };
                MdbxQueryCursorSource::IndexEqual {
                    index_cursor,
                    documents_cursor,
                    key,
                    started: false,
                    seen: dedupe.then(HashSet::new),
                }
            }
            WireQuerySource::IndexRange { .. } => return Ok(None),
        };

        // The libmdbx cursor internally owns a cloned transaction handle and
        // only carries the Rust transaction lifetime as a marker. Keep the
        // transaction in the reader and drop the cursor before it.
        let transaction = unsafe {
            std::mem::transmute::<
                Transaction<'_, RO, NoWriteMap>,
                Transaction<'static, RO, NoWriteMap>,
            >(transaction)
        };

        Ok(Some(MdbxQueryDocumentReader {
            source,
            _transaction: transaction,
            schema,
            filter,
            offset: plan.offset as usize,
            limit: plan.limit.map(|value| value as usize),
            matched: 0,
            emitted: 0,
            current_id: None,
            current_present: false,
            current_bytes: None,
        }))
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
        let filter = plan
            .filter
            .as_ref()
            .map(|bytes| {
                NativeFilter::decode(bytes).map(|filter| filter.prepare_for_schema(&schema))
            })
            .transpose()?;

        if let Some(documents) =
            self.execute_query_plan_borrowed_unsorted(collection, plan, &schema, filter.as_ref())?
        {
            return Ok(documents);
        }

        if let Some(documents) =
            self.execute_query_plan_borrowed_sorted(collection, plan, &schema, filter.as_ref())?
        {
            return Ok(documents);
        }

        let mut ids = self.query_plan_source_ids(collection, &plan.source)?;
        if query_source_dedupes(&plan.source) {
            dedupe_ids(&mut ids);
        }
        let documents = self.get_many_stored(collection, &ids)?;
        let mut planned = Vec::new();
        for (position, (id, document)) in ids.into_iter().zip(documents).enumerate() {
            let Some(bytes) = document else {
                continue;
            };
            if let Some(filter) = &filter {
                if !filter.matches_with_id(&schema, &bytes, id)? {
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

    fn execute_query_plan_borrowed_unsorted(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
        schema: &CollectionSchemaManifest,
        filter: Option<&NativeFilter>,
    ) -> Result<Option<Vec<PlannedDocument>>, String> {
        if self.active_write().is_some()
            || !plan.sorts.is_empty()
            || !plan.distinct_fields.is_empty()
            || !matches!(plan.source, WireQuerySource::All { .. })
        {
            return Ok(None);
        }

        let offset = plan.offset as usize;
        let limit = plan.limit.map(|value| value as usize);

        self.with_read_transaction(|transaction, _tables| {
            let documents_table = match open_documents_table(transaction, collection) {
                Ok(table) => table,
                Err(_) => return Ok(Vec::new()),
            };
            let mut documents_cursor = transaction
                .cursor(&documents_table)
                .map_err(|error| error.to_string())?;
            let mut planned = Vec::new();
            let mut matched = 0usize;
            let mut position = 0usize;

            for row in documents_cursor.iter_start::<Cow<'_, [u8]>, Cow<'_, [u8]>>() {
                let (key, bytes) = row.map_err(|error| error.to_string())?;
                let id = decode_document_table_key(&key)?;
                if let Some(filter) = filter {
                    if !filter.matches_with_id(schema, bytes.as_ref(), id)? {
                        position += 1;
                        continue;
                    }
                }
                if matched < offset {
                    matched += 1;
                    position += 1;
                    continue;
                }
                if limit.is_some_and(|limit| planned.len() >= limit) {
                    break;
                }
                planned.push(PlannedDocument {
                    id: decode_document_table_key(&key)?,
                    bytes: bytes.into_owned(),
                    position,
                });
                matched += 1;
                position += 1;
            }
            Ok(planned)
        })
        .map(Some)
    }

    fn execute_query_plan_borrowed_sorted(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
        schema: &CollectionSchemaManifest,
        filter: Option<&NativeFilter>,
    ) -> Result<Option<Vec<PlannedDocument>>, String> {
        if self.active_write().is_some()
            || plan.sorts.is_empty()
            || !plan.distinct_fields.is_empty()
        {
            return Ok(None);
        }

        let sort_fields = query_sort_fields(schema, &plan.sorts)?;
        let offset = plan.offset as usize;
        let limit = plan.limit.map(|value| value as usize);

        self.with_read_transaction(|transaction, tables| {
            let _ = tables;
            let documents_table = match open_documents_table(transaction, collection) {
                Ok(table) => table,
                Err(_) => return Ok(Vec::new()),
            };
            let mut documents_cursor = transaction
                .cursor(&documents_table)
                .map_err(|error| error.to_string())?;
            let mut planned = Vec::new();
            let mut seen = query_source_dedupes(&plan.source).then(HashSet::new);
            let mut position = 0usize;

            if let Some(bool_query) = direct_bool_index_query(schema, plan) {
                for row in documents_cursor.iter_start::<Cow<'_, [u8]>, Cow<'_, [u8]>>() {
                    let (key, bytes) = row.map_err(|error| error.to_string())?;
                    if !direct_bool_index_query_matches(bytes.as_ref(), &bool_query)? {
                        continue;
                    }
                    let id = decode_document_table_key(&key)?;
                    push_borrowed_planned_document(
                        schema,
                        filter,
                        &sort_fields,
                        &mut planned,
                        id,
                        bytes,
                        position,
                    )?;
                    position += 1;
                }
                return Ok(sort_and_window_borrowed_planned_documents(
                    planned,
                    &sort_fields,
                    offset,
                    limit,
                ));
            }

            match &plan.source {
                WireQuerySource::All { .. } => {
                    for row in documents_cursor.iter_start::<Cow<'_, [u8]>, Cow<'_, [u8]>>() {
                        let (key, bytes) = row.map_err(|error| error.to_string())?;
                        let id = decode_document_table_key(&key)?;
                        push_borrowed_planned_document(
                            schema,
                            filter,
                            &sort_fields,
                            &mut planned,
                            id,
                            bytes,
                            position,
                        )?;
                        position += 1;
                    }
                }
                WireQuerySource::IndexEqual {
                    index_name, value, ..
                } => {
                    let value = wire_index_value_to_storage(value)?;
                    let key = index_value_key(&value)?;
                    let Ok(index_table) = open_index_table(transaction, collection, index_name)
                    else {
                        return Ok(Vec::new());
                    };
                    let mut index_cursor = transaction
                        .cursor(&index_table)
                        .map_err(|error| error.to_string())?;
                    for row in index_cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(&key) {
                        let (entry_key, value) = row.map_err(|error| error.to_string())?;
                        if entry_key.as_ref() != key {
                            break;
                        }
                        let id = decode_u64(&value)?;
                        if let Some(seen) = &mut seen {
                            if !seen.insert(id) {
                                continue;
                            }
                        }
                        let Some(bytes) = ignore_not_found(
                            documents_cursor.set::<Cow<'_, [u8]>>(&document_table_key(id)),
                        )?
                        else {
                            position += 1;
                            continue;
                        };
                        push_borrowed_planned_document(
                            schema,
                            filter,
                            &sort_fields,
                            &mut planned,
                            id,
                            bytes,
                            position,
                        )?;
                        position += 1;
                    }
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
                    let range = encode_table_index_range(lower.as_ref(), upper.as_ref())?;
                    let Ok(index_table) = open_index_table(transaction, collection, index_name)
                    else {
                        return Ok(Vec::new());
                    };
                    let mut index_cursor = transaction
                        .cursor(&index_table)
                        .map_err(|error| error.to_string())?;
                    for row in index_cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(&range.start)
                    {
                        let (key, value) = row.map_err(|error| error.to_string())?;
                        if key.as_ref() > range.end_inclusive.as_slice() {
                            break;
                        }
                        let id = decode_u64(&value)?;
                        if let Some(seen) = &mut seen {
                            if !seen.insert(id) {
                                continue;
                            }
                        }
                        let Some(bytes) = ignore_not_found(
                            documents_cursor.set::<Cow<'_, [u8]>>(&document_table_key(id)),
                        )?
                        else {
                            position += 1;
                            continue;
                        };
                        push_borrowed_planned_document(
                            schema,
                            filter,
                            &sort_fields,
                            &mut planned,
                            id,
                            bytes,
                            position,
                        )?;
                        position += 1;
                    }
                }
            }

            Ok(sort_and_window_borrowed_planned_documents(
                planned,
                &sort_fields,
                offset,
                limit,
            ))
        })
        .map(Some)
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

    fn query_plan_update_direct_nonindexed(
        &mut self,
        collection: &str,
        plan: &WireQueryPlan,
        schema: &CollectionSchemaManifest,
        updates: &PreparedBinaryFieldUpdates,
        update_touches_index: bool,
        collect_changes: bool,
    ) -> Result<Option<usize>, String> {
        if self.active_write().is_some()
            || update_touches_index
            || !matches!(plan.source, WireQuerySource::All { .. })
            || !plan.sorts.is_empty()
            || !plan.distinct_fields.is_empty()
        {
            return Ok(None);
        }

        let filter = plan
            .filter
            .as_ref()
            .map(|bytes| {
                NativeFilter::decode(bytes).map(|filter| filter.prepare_for_schema(schema))
            })
            .transpose()?;
        let offset = plan.offset as usize;
        let limit = plan.limit.map(|value| value as usize);
        let mut count = 0usize;
        let mut ids = collect_changes.then(Vec::new);
        let mut change_sets = Vec::new();

        self.with_write_transaction(|transaction, tables| {
            let documents_table = match open_documents_table(transaction, collection) {
                Ok(table) => table,
                Err(_) => return Ok(()),
            };
            let mut cursor = transaction
                .cursor(&documents_table)
                .map_err(|error| error.to_string())?;
            let mut skipped = 0usize;
            let mut current = cursor
                .first::<Vec<u8>, Vec<u8>>()
                .map_err(|error| error.to_string())?;
            while let Some((key, mut bytes)) = current {
                let id = decode_document_table_key(&key)?;
                if let Some(filter) = &filter {
                    if !filter.matches_with_id(schema, &bytes, id)? {
                        current = cursor
                            .next::<Vec<u8>, Vec<u8>>()
                            .map_err(|error| error.to_string())?;
                        continue;
                    }
                }
                if skipped < offset {
                    skipped += 1;
                    current = cursor
                        .next::<Vec<u8>, Vec<u8>>()
                        .map_err(|error| error.to_string())?;
                    continue;
                }
                if limit.is_some_and(|limit| count >= limit) {
                    break;
                }
                apply_prepared_binary_field_updates(&mut bytes, updates)?;
                cursor
                    .put(&key, &bytes, WriteFlags::CURRENT)
                    .map_err(|error| error.to_string())?;
                count += 1;
                if let Some(ids) = ids.as_mut() {
                    ids.push(id);
                }
                current = cursor
                    .next::<Vec<u8>, Vec<u8>>()
                    .map_err(|error| error.to_string())?;
            }
            drop(cursor);

            if count == 0 {
                return Ok(());
            }
            let revision = bump_collection_revision(transaction, &tables, collection)?;
            if let Some(ids) = &ids {
                merge_change_set(&mut change_sets, collection, revision, ids.iter().copied());
            }
            Ok(())
        })?;
        self.last_change_sets = change_sets;
        Ok(Some(count))
    }

    fn query_plan_update_direct_bool_index(
        &mut self,
        collection: &str,
        plan: &WireQueryPlan,
        schema: &CollectionSchemaManifest,
        updates: &[(String, WireValue)],
        collect_changes: bool,
    ) -> Result<Option<usize>, String> {
        if self.active_write().is_some()
            || plan.filter.is_some()
            || !plan.sorts.is_empty()
            || !plan.distinct_fields.is_empty()
            || plan.offset != 0
            || plan.limit.is_some()
        {
            return Ok(None);
        }
        let Some(update) = direct_bool_index_update(schema, plan, updates) else {
            return Ok(None);
        };

        let mut ids = self.query_plan_source_ids(collection, &plan.source)?;
        if query_source_dedupes(&plan.source) {
            dedupe_ids(&mut ids);
        }
        if ids.is_empty() {
            return Ok(Some(0));
        }

        let mut count = 0usize;
        let mut updated_ids = collect_changes.then(|| Vec::with_capacity(ids.len()));
        let mut change_sets = Vec::new();
        self.with_write_transaction(|transaction, tables| {
            let documents_table = match open_documents_table(transaction, collection) {
                Ok(table) => table,
                Err(_) => return Ok(()),
            };
            let index_table = create_index_table(transaction, collection, &update.name)?;
            let mut documents_cursor = transaction
                .cursor(&documents_table)
                .map_err(|error| error.to_string())?;
            let mut index_cursor = transaction
                .cursor(&index_table)
                .map_err(|error| error.to_string())?;

            for id in &ids {
                let document_key = document_table_key(*id);
                let Some(mut bytes) =
                    ignore_not_found(documents_cursor.set::<Vec<u8>>(&document_key))?
                else {
                    continue;
                };
                write_direct_bool_update(&mut bytes, &update)?;
                documents_cursor
                    .put(&document_key, &bytes, WriteFlags::CURRENT)
                    .map_err(|error| error.to_string())?;
                if update.old_key != update.new_key {
                    let document_id_bytes = document_id_key(*id);
                    if index_cursor
                        .get_both::<Vec<u8>>(&update.old_key, &document_id_bytes)
                        .map_err(|error| error.to_string())?
                        .is_some()
                    {
                        index_cursor
                            .del(WriteFlags::empty())
                            .map_err(|error| error.to_string())?;
                    }
                    index_cursor
                        .put(&update.new_key, &document_id_bytes, WriteFlags::UPSERT)
                        .map_err(|error| error.to_string())?;
                }
                count += 1;
                if let Some(updated_ids) = updated_ids.as_mut() {
                    updated_ids.push(*id);
                }
            }
            drop(index_cursor);
            drop(documents_cursor);

            if count == 0 {
                return Ok(());
            }
            let revision = bump_collection_revision(transaction, &tables, collection)?;
            if let Some(updated_ids) = &updated_ids {
                merge_change_set(
                    &mut change_sets,
                    collection,
                    revision,
                    updated_ids.iter().copied(),
                );
            }
            Ok(())
        })?;
        self.last_change_sets = change_sets;
        Ok(Some(count))
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
                        let schema =
                            self.cached_collection_schema(transaction, &tables, &collection)?;
                        put_many_documents_with_indexes(
                            transaction,
                            &tables,
                            &collection,
                            schema.as_ref(),
                            &documents,
                            false,
                        )?;
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
                        let deleted_ids =
                            delete_many_documents(transaction, &tables, &collection, &ids)?;
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
            let mut documents_cursor = transaction
                .cursor(&documents_table)
                .map_err(|error| error.to_string())?;
            let mut documents = Vec::with_capacity(ids.len());
            for id in ids {
                let bytes = documents_cursor.set::<Vec<u8>>(&document_table_key(*id));
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
            let mut documents_cursor = transaction
                .cursor(&documents_table)
                .map_err(|error| error.to_string())?;
            let mut documents = Vec::with_capacity(ids.len());
            for id in ids {
                documents.push(ignore_not_found(
                    documents_cursor.set::<Vec<u8>>(&document_table_key(*id)),
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
            let (stored_bytes, effective_indexes, _) =
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
        self.put_many_indexed_with_change_tracking(collection, documents, true)
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
        self.ensure_can_write()?;
        if self.active_write_mut().is_some() {
            let schema = self.with_read_transaction(|transaction, tables| {
                self.cached_collection_schema(transaction, &tables, collection)
            })?;
            let staged_documents = documents
                .iter()
                .map(|document| {
                    let (stored_bytes, effective_indexes, _) = encode_document_for_storage(
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
            let schema = self.cached_collection_schema(transaction, &tables, collection)?;
            put_many_documents_with_indexes(
                transaction,
                &tables,
                collection,
                schema.as_ref(),
                documents,
                trust_schema_documents,
            )?;
            if !documents.is_empty() {
                let revision = bump_collection_revision(transaction, &tables, collection)?;
                if track_changes {
                    merge_change_set(
                        &mut change_sets,
                        collection,
                        revision,
                        documents.iter().map(|document| document.id),
                    );
                }
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
            let deleted_ids = delete_many_documents(transaction, &tables, collection, ids)?;
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
        let range = encode_table_index_range(lower, upper)?;
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
        let schema = self.with_read_transaction(|transaction, tables| {
            self.cached_collection_schema(transaction, &tables, collection)
        })?;
        let Some(schema) = schema else {
            return Err(format!(
                "collection `{collection}` has no registered schema"
            ));
        };
        let filter = NativeFilter::decode(filter)?.prepare_for_schema(&schema);
        let documents = self.get_many_stored(collection, candidate_ids)?;
        let mut ids = Vec::new();
        for (id, document) in candidate_ids.iter().copied().zip(documents) {
            let Some(document) = document else {
                continue;
            };
            if filter.matches_with_id(&schema, &document, id)? {
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
        ensure_schema_field(&schema, field)?;
        let documents = self.get_many_stored(collection, candidate_ids)?;
        let mut cells = Vec::new();
        for (id, document) in candidate_ids.iter().copied().zip(documents) {
            let Some(document) = document else {
                continue;
            };
            let value = query_binary_field(&schema, &document, id, field)?;
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
        ensure_schema_field(&schema, field)?;

        let documents = self.get_many_stored(collection, candidate_ids)?;
        let mut values = Vec::new();
        for (id, document) in candidate_ids.iter().copied().zip(documents) {
            let Some(document) = document else {
                continue;
            };
            values.push(query_binary_field(&schema, &document, id, field)?);
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
            let value = query_binary_field(&schema, &document.bytes, document.id, field)?;
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
            values.push(query_binary_field(
                &schema,
                &document.bytes,
                document.id,
                field,
            )?);
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

    fn query_plan_update(
        &mut self,
        collection: &str,
        plan: &WireQueryPlan,
        updates: &[(String, WireValue)],
        collect_changes: bool,
    ) -> Result<usize, String> {
        self.ensure_can_write()?;
        if updates.is_empty() {
            return Ok(0);
        }

        let schema = self.required_schema(collection)?;
        let update_touches_index = updates_touch_index(&schema, updates)?;
        let prepared_updates = prepare_binary_field_updates(&schema, updates)?;
        if let Some(count) = self.query_plan_update_direct_bool_index(
            collection,
            plan,
            &schema,
            updates,
            collect_changes,
        )? {
            return Ok(count);
        }
        if let Some(count) = self.query_plan_update_direct_nonindexed(
            collection,
            plan,
            &schema,
            &prepared_updates,
            update_touches_index,
            collect_changes,
        )? {
            return Ok(count);
        }

        let planned = self.execute_query_plan(collection, plan)?;
        if planned.is_empty() {
            return Ok(0);
        }

        let mut documents = Vec::with_capacity(planned.len());
        for mut document in planned {
            apply_prepared_binary_field_updates(&mut document.bytes, &prepared_updates)?;
            documents.push(DocumentWrite {
                id: document.id,
                bytes: document.bytes,
                indexes: Vec::new(),
            });
        }

        if self.active_write_mut().is_some() || update_touches_index {
            self.put_many_indexed_with_options(collection, &documents, true, true)?;
            return Ok(documents.len());
        }

        let count = documents.len();
        let mut change_sets = Vec::new();
        self.with_write_transaction(|transaction, tables| {
            let documents_table = create_documents_table(transaction, collection)?;
            let mut cursor = transaction
                .cursor(&documents_table)
                .map_err(|error| error.to_string())?;
            for document in &documents {
                cursor
                    .put(
                        &document_table_key(document.id),
                        &document.bytes,
                        WriteFlags::UPSERT,
                    )
                    .map_err(|error| error.to_string())?;
            }
            drop(cursor);
            let revision = bump_collection_revision(transaction, &tables, collection)?;
            if collect_changes {
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
        Ok(count)
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
    format!("i:{collection}:{index}")
}

fn unique_table_name(collection: &str, index: &str) -> String {
    format!("u:{collection}:{index}")
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
    encode_table_index_value(value)
}

fn document_id_key(id: u64) -> [u8; 8] {
    id.to_be_bytes()
}

fn document_table_key(id: u64) -> [u8; 8] {
    id.to_le_bytes()
}

fn decode_document_table_key(bytes: &[u8]) -> Result<u64, String> {
    let bytes = bytes
        .try_into()
        .map_err(|_| "MDBX document key must be 8 bytes".to_string())?;
    Ok(u64::from_le_bytes(bytes))
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

fn index_names_from_schema(schema: &CollectionSchemaManifest) -> HashSet<String> {
    let mut names = HashSet::new();
    names.extend(
        schema
            .fields
            .iter()
            .filter(|field| field.is_indexed)
            .map(|field| field.name.clone()),
    );
    names.extend(
        schema
            .composite_indexes
            .iter()
            .map(|index| index.name.clone()),
    );
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

fn schema_field_is_id(schema: &CollectionSchemaManifest, field: &str) -> bool {
    field == schema.id_field
        || schema
            .fields
            .iter()
            .any(|schema_field| schema_field.name == field && schema_field.is_id)
}

fn query_binary_field(
    schema: &CollectionSchemaManifest,
    bytes: &[u8],
    id: u64,
    field: &str,
) -> Result<Option<BinaryValue>, String> {
    if schema_field_is_id(schema, field) {
        return Ok(Some(BinaryValue::Int(id_to_i64(id)?)));
    }
    read_binary_field(schema, bytes, field)
}

fn id_to_i64(id: u64) -> Result<i64, String> {
    i64::try_from(id).map_err(|_| "document id cannot be represented as a signed integer".into())
}

fn updates_touch_index(
    schema: &CollectionSchemaManifest,
    updates: &[(String, WireValue)],
) -> Result<bool, String> {
    for (field, _) in updates {
        let Some(schema_field) = schema
            .fields
            .iter()
            .find(|schema_field| &schema_field.name == field)
        else {
            return Err(format!(
                "field `{field}` is not declared in schema `{}`",
                schema.name
            ));
        };
        if schema_field.is_id {
            return Err(format!("query updates cannot change id field `{field}`"));
        }
        if schema_field.is_indexed
            || schema
                .composite_indexes
                .iter()
                .any(|index| index.fields.iter().any(|index_field| index_field == field))
        {
            return Ok(true);
        }
    }
    Ok(false)
}

struct DirectBoolIndexUpdate {
    name: String,
    static_offset: usize,
    static_size: usize,
    old_key: [u8; 1],
    new_key: [u8; 1],
    new_value: bool,
}

struct DirectBoolIndexQuery {
    static_offset: usize,
    static_size: usize,
    value: bool,
}

fn direct_bool_index_query(
    schema: &CollectionSchemaManifest,
    plan: &WireQueryPlan,
) -> Option<DirectBoolIndexQuery> {
    let WireQuerySource::IndexEqual {
        index_name,
        value: WireIndexValue::Bool(value),
        dedupe: false,
    } = &plan.source
    else {
        return None;
    };
    if schema
        .composite_indexes
        .iter()
        .any(|index| index.fields.iter().any(|field| field == index_name))
    {
        return None;
    }

    let mut static_offset = 0usize;
    let mut static_size = 0usize;
    let mut target = None;
    for field in &schema.fields {
        if field.is_id {
            continue;
        }
        let field_size = compact_field_static_size(&field.binary_type)?;
        if field.name == *index_name {
            if !field.is_indexed
                || field.is_index_unique
                || field.index_type != "value"
                || normalized_binary_type(&field.binary_type) != "bool"
            {
                return None;
            }
            target = Some(static_offset);
        }
        static_offset = static_offset.checked_add(field_size)?;
        static_size = static_size.checked_add(field_size)?;
    }
    target.map(|static_offset| DirectBoolIndexQuery {
        static_offset,
        static_size,
        value: *value,
    })
}

fn direct_bool_index_query_matches(
    bytes: &[u8],
    query: &DirectBoolIndexQuery,
) -> Result<bool, String> {
    if bytes.len() < 3 {
        return Err("compact binary document is shorter than the header".into());
    }
    let static_size = read_compact_u24(bytes, 0)? as usize;
    if static_size != query.static_size {
        return Err("compact binary document static size does not match schema".into());
    }
    if bytes.len() < 3 + static_size {
        return Err("compact binary document static section is truncated".into());
    }
    let Some(value) = bytes.get(3 + query.static_offset) else {
        return Err("compact bool field is outside the static section".into());
    };
    Ok(matches!((*value, query.value), (0, false) | (1, true)))
}

fn direct_bool_index_update(
    schema: &CollectionSchemaManifest,
    plan: &WireQueryPlan,
    updates: &[(String, WireValue)],
) -> Option<DirectBoolIndexUpdate> {
    let WireQuerySource::IndexEqual {
        index_name,
        value: WireIndexValue::Bool(old_value),
        dedupe: false,
    } = &plan.source
    else {
        return None;
    };
    let [(field_name, WireValue::Bool(new_value))] = updates else {
        return None;
    };
    if field_name != index_name
        || schema
            .composite_indexes
            .iter()
            .any(|index| index.fields.iter().any(|field| field == field_name))
    {
        return None;
    }

    let mut static_offset = 0usize;
    let mut static_size = 0usize;
    let mut target_offset = None;
    for field in &schema.fields {
        if field.is_id {
            continue;
        }
        let field_size = compact_field_static_size(&field.binary_type)?;
        if field.name == *field_name {
            if !field.is_indexed
                || field.is_index_unique
                || field.index_type != "value"
                || normalized_binary_type(&field.binary_type) != "bool"
            {
                return None;
            }
            target_offset = Some(static_offset);
        }
        static_offset = static_offset.checked_add(field_size)?;
        static_size = static_size.checked_add(field_size)?;
    }
    target_offset.map(|static_offset| DirectBoolIndexUpdate {
        name: field_name.clone(),
        static_offset,
        static_size,
        old_key: [if *old_value { 2 } else { 1 }],
        new_key: [if *new_value { 2 } else { 1 }],
        new_value: *new_value,
    })
}

fn write_direct_bool_update(
    bytes: &mut [u8],
    update: &DirectBoolIndexUpdate,
) -> Result<(), String> {
    if bytes.len() < 3 {
        return Err("compact binary document is shorter than the header".into());
    }
    let static_size = read_compact_u24(bytes, 0)? as usize;
    if static_size != update.static_size {
        return Err("compact binary document static size does not match schema".into());
    }
    if bytes.len() < 3 + static_size {
        return Err("compact binary document static section is truncated".into());
    }
    let slot = bytes
        .get_mut(3 + update.static_offset)
        .ok_or_else(|| "compact bool update is outside the static section".to_string())?;
    *slot = u8::from(update.new_value);
    Ok(())
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
    let sort_fields = query_sort_fields(schema, sorts)?;
    let mut keyed = documents
        .iter()
        .map(|document| {
            let values = sort_fields
                .iter()
                .map(|sort_field| match &sort_field.target {
                    QuerySortTarget::Id => Ok(OwnedSortValue::Id(document.id)),
                    QuerySortTarget::Field(_) => {
                        read_binary_field_at(schema, &document.bytes, sort_field.index)
                            .map(OwnedSortValue::Field)
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

    keyed.sort_unstable_by(|left, right| {
        for (index, sort_field) in sort_fields.iter().enumerate() {
            let ordering = compare_owned_sort_values(&left.3[index], &right.3[index]);
            if ordering != Ordering::Equal {
                return if sort_field.ascending {
                    ordering
                } else {
                    ordering.reverse()
                };
            }
        }
        Ordering::Equal
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

fn query_sort_fields(
    schema: &CollectionSchemaManifest,
    sorts: &[crate::wire::WireQuerySort],
) -> Result<Vec<QuerySortField>, String> {
    sorts
        .iter()
        .map(|sort| {
            let index = schema
                .fields
                .iter()
                .position(|field| field.name == sort.field)
                .ok_or_else(|| {
                    format!(
                        "field `{}` is not declared in schema `{}`",
                        sort.field, schema.name
                    )
                })?;
            Ok(QuerySortField {
                index,
                ascending: sort.ascending,
                target: if schema.fields[index].is_id {
                    QuerySortTarget::Id
                } else {
                    QuerySortTarget::Field(prepare_binary_sort_field(schema, index)?)
                },
            })
        })
        .collect::<Result<Vec<_>, String>>()
}

fn push_borrowed_planned_document<'a>(
    schema: &CollectionSchemaManifest,
    filter: Option<&NativeFilter>,
    sort_fields: &[QuerySortField],
    planned: &mut Vec<BorrowedPlannedDocument<'a>>,
    id: u64,
    bytes: Cow<'a, [u8]>,
    position: usize,
) -> Result<(), String> {
    if let Some(filter) = filter {
        if !filter.matches_with_id(schema, bytes.as_ref(), id)? {
            return Ok(());
        }
    }
    let sort_values = if let [sort_field] = sort_fields {
        match &sort_field.target {
            QuerySortTarget::Id => BorrowedSortValues::One(BorrowedSortValue::Id(id)),
            QuerySortTarget::Field(prepared) => {
                if let Some(range) =
                    read_prepared_binary_string_sort_range(bytes.as_ref(), prepared)?
                {
                    BorrowedSortValues::OneStringRange(range)
                } else {
                    BorrowedSortValues::One(BorrowedSortValue::Field(
                        read_prepared_binary_sort_key(schema, bytes.as_ref(), prepared)?,
                    ))
                }
            }
        }
    } else {
        BorrowedSortValues::Many(
            sort_fields
                .iter()
                .map(|sort_field| read_borrowed_sort_value(schema, bytes.as_ref(), id, sort_field))
                .collect::<Result<Vec<_>, String>>()?,
        )
    };
    planned.push(BorrowedPlannedDocument {
        id,
        bytes,
        position,
        sort_values,
    });
    Ok(())
}

fn sort_borrowed_planned_documents(
    documents: &mut [BorrowedPlannedDocument<'_>],
    sort_fields: &[QuerySortField],
) {
    documents.sort_unstable_by(|left, right| {
        for (index, sort_field) in sort_fields.iter().enumerate() {
            let ordering = compare_borrowed_sort_values(left, right, index);
            if ordering != Ordering::Equal {
                return if sort_field.ascending {
                    ordering
                } else {
                    ordering.reverse()
                };
            }
        }
        Ordering::Equal
    });
}

fn borrowed_sort_value<'a>(
    document: &'a BorrowedPlannedDocument<'_>,
    index: usize,
) -> Option<&'a BorrowedSortValue> {
    match &document.sort_values {
        BorrowedSortValues::One(value) => Some(value),
        BorrowedSortValues::OneStringRange(_) => None,
        BorrowedSortValues::Many(values) => Some(&values[index]),
    }
}

fn read_borrowed_sort_value(
    schema: &CollectionSchemaManifest,
    bytes: &[u8],
    id: u64,
    sort_field: &QuerySortField,
) -> Result<BorrowedSortValue, String> {
    match &sort_field.target {
        QuerySortTarget::Id => Ok(BorrowedSortValue::Id(id)),
        QuerySortTarget::Field(prepared) => Ok(BorrowedSortValue::Field(
            read_prepared_binary_sort_key(schema, bytes, prepared)?,
        )),
    }
}

fn compare_borrowed_sort_values(
    left: &BorrowedPlannedDocument<'_>,
    right: &BorrowedPlannedDocument<'_>,
    index: usize,
) -> Ordering {
    match (&left.sort_values, &right.sort_values, index) {
        (
            BorrowedSortValues::OneStringRange(left_range),
            BorrowedSortValues::OneStringRange(right_range),
            0,
        ) => compare_optional_bytes(
            left_range
                .as_ref()
                .map(|range| &left.bytes.as_ref()[range.clone()]),
            right_range
                .as_ref()
                .map(|range| &right.bytes.as_ref()[range.clone()]),
        ),
        _ => compare_borrowed_sort_value(
            borrowed_sort_value(left, index),
            left.bytes.as_ref(),
            borrowed_sort_value(right, index),
            right.bytes.as_ref(),
        ),
    }
}

fn compare_borrowed_sort_value(
    left: Option<&BorrowedSortValue>,
    left_bytes: &[u8],
    right: Option<&BorrowedSortValue>,
    right_bytes: &[u8],
) -> Ordering {
    match (left, right) {
        (Some(BorrowedSortValue::Id(left)), Some(BorrowedSortValue::Id(right))) => left.cmp(right),
        (Some(BorrowedSortValue::Field(left)), Some(BorrowedSortValue::Field(right))) => {
            compare_binary_sort_keys(left.as_ref(), left_bytes, right.as_ref(), right_bytes)
        }
        (None, None) => Ordering::Equal,
        (None, Some(_)) => Ordering::Less,
        (Some(_), None) => Ordering::Greater,
        (Some(BorrowedSortValue::Id(_)), Some(BorrowedSortValue::Field(_))) => Ordering::Greater,
        (Some(BorrowedSortValue::Field(_)), Some(BorrowedSortValue::Id(_))) => Ordering::Less,
    }
}

fn compare_optional_bytes(left: Option<&[u8]>, right: Option<&[u8]>) -> Ordering {
    match (left, right) {
        (None, None) => Ordering::Equal,
        (None, Some(_)) => Ordering::Less,
        (Some(_), None) => Ordering::Greater,
        (Some(left), Some(right)) => left.cmp(right),
    }
}

fn compare_binary_sort_keys(
    left: Option<&BinarySortKey>,
    left_bytes: &[u8],
    right: Option<&BinarySortKey>,
    right_bytes: &[u8],
) -> Ordering {
    match (left, right) {
        (None, None) => Ordering::Equal,
        (None, Some(_)) => Ordering::Less,
        (Some(_), None) => Ordering::Greater,
        (Some(left), Some(right)) => {
            if let (Some(left), Some(right)) =
                (binary_sort_key_number(left), binary_sort_key_number(right))
            {
                return left.total_cmp(&right);
            }
            match (
                binary_sort_key_string_bytes(left, left_bytes),
                binary_sort_key_string_bytes(right, right_bytes),
            ) {
                (Some(left), Some(right)) => return left.cmp(right),
                _ => {}
            }
            match (binary_sort_key_bool(left), binary_sort_key_bool(right)) {
                (Some(left), Some(right)) => return left.cmp(&right),
                _ => {}
            }
            binary_sort_key_distinct_key(left, left_bytes)
                .cmp(&binary_sort_key_distinct_key(right, right_bytes))
        }
    }
}

fn compare_owned_sort_values(left: &OwnedSortValue, right: &OwnedSortValue) -> Ordering {
    match (left, right) {
        (OwnedSortValue::Id(left), OwnedSortValue::Id(right)) => left.cmp(right),
        (OwnedSortValue::Field(left), OwnedSortValue::Field(right)) => {
            compare_binary_values(left.as_ref(), right.as_ref())
        }
        (OwnedSortValue::Id(_), OwnedSortValue::Field(_)) => Ordering::Greater,
        (OwnedSortValue::Field(_), OwnedSortValue::Id(_)) => Ordering::Less,
    }
}

fn binary_sort_key_number(value: &BinarySortKey) -> Option<f64> {
    match value {
        BinarySortKey::Int(value) => Some(*value as f64),
        BinarySortKey::Double(value) if value.is_finite() => Some(*value),
        BinarySortKey::Owned(value) => binary_number(value),
        BinarySortKey::Bool(_) | BinarySortKey::Double(_) | BinarySortKey::StringRange(_) => None,
    }
}

fn binary_sort_key_string_bytes<'a>(value: &'a BinarySortKey, bytes: &'a [u8]) -> Option<&'a [u8]> {
    match value {
        BinarySortKey::StringRange(range) => Some(&bytes[range.clone()]),
        BinarySortKey::Owned(BinaryValue::String(value))
        | BinarySortKey::Owned(BinaryValue::Enum(value)) => Some(value.as_bytes()),
        BinarySortKey::Bool(_)
        | BinarySortKey::Int(_)
        | BinarySortKey::Double(_)
        | BinarySortKey::Owned(_) => None,
    }
}

fn binary_sort_key_bool(value: &BinarySortKey) -> Option<bool> {
    match value {
        BinarySortKey::Bool(value) => Some(*value),
        BinarySortKey::Owned(BinaryValue::Bool(value)) => Some(*value),
        BinarySortKey::Int(_)
        | BinarySortKey::Double(_)
        | BinarySortKey::StringRange(_)
        | BinarySortKey::Owned(_) => None,
    }
}

fn binary_sort_key_distinct_key(value: &BinarySortKey, bytes: &[u8]) -> String {
    match value {
        BinarySortKey::StringRange(range) => {
            format!("String:{}", String::from_utf8_lossy(&bytes[range.clone()]))
        }
        BinarySortKey::Bool(value) => format!("bool:{value}"),
        BinarySortKey::Int(value) => format!("int:{value}"),
        BinarySortKey::Double(value) => format!("double:{value}"),
        BinarySortKey::Owned(value) => binary_distinct_key(Some(value)),
    }
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

fn sort_and_window_borrowed_planned_documents(
    mut documents: Vec<BorrowedPlannedDocument<'_>>,
    sort_fields: &[QuerySortField],
    offset: usize,
    limit: Option<usize>,
) -> Vec<PlannedDocument> {
    sort_borrowed_planned_documents(&mut documents, sort_fields);
    if offset >= documents.len() {
        return Vec::new();
    }
    let end = limit
        .map(|limit| offset.saturating_add(limit).min(documents.len()))
        .unwrap_or(documents.len());
    documents
        .drain(offset..end)
        .map(|document| PlannedDocument {
            id: document.id,
            bytes: document.bytes.into_owned(),
            position: document.position,
        })
        .collect()
}

fn sort_and_window_borrowed_query_documents<'a>(
    mut documents: Vec<BorrowedPlannedDocument<'a>>,
    sort_fields: &[QuerySortField],
    offset: usize,
    limit: Option<usize>,
) -> Vec<BorrowedPlannedDocument<'a>> {
    sort_borrowed_planned_documents(&mut documents, sort_fields);
    if offset >= documents.len() {
        return Vec::new();
    }
    let end = limit
        .map(|limit| offset.saturating_add(limit).min(documents.len()))
        .unwrap_or(documents.len());
    documents.drain(offset..end).collect()
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
                query_binary_field(schema, &document.bytes, document.id, field)
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
    let (stored_bytes, effective_indexes, can_derive_new_indexes) =
        encode_document_for_storage(schema.as_ref(), bytes, indexes)?;
    let documents_table = create_documents_table(transaction, collection)?;
    let previous_bytes =
        ignore_not_found(transaction.get::<Vec<u8>>(&documents_table, &document_table_key(id)))?;
    let old_indexes = previous_index_state(schema.as_ref(), previous_bytes.as_deref())?;
    let persist_reverse_metadata = !can_derive_new_indexes;
    let indexes_unchanged = can_derive_new_indexes
        && matches!(
            &old_indexes,
            PreviousIndexState::Derived(indexes) if indexes == &effective_indexes
        );
    if !indexes_unchanged {
        MdbxIndex::validate_unique(
            transaction,
            tables,
            collection,
            id,
            &effective_indexes,
            &unique_indexes,
        )?;
    }
    transaction
        .put(
            &documents_table,
            document_table_key(id),
            &stored_bytes,
            WriteFlags::UPSERT,
        )
        .map_err(|error| error.to_string())?;
    if !indexes_unchanged {
        let remove_reverse_metadata = matches!(old_indexes, PreviousIndexState::ReverseMetadata);
        match old_indexes {
            PreviousIndexState::Missing => {}
            PreviousIndexState::Derived(indexes) => {
                MdbxIndex::delete_entries(transaction, collection, id, &indexes)?;
            }
            PreviousIndexState::ReverseMetadata => {
                MdbxIndex::delete_document(transaction, tables, collection, id, None)?;
            }
        }
        for index in &effective_indexes {
            MdbxIndex::insert_entry(
                transaction,
                tables,
                collection,
                id,
                index,
                unique_indexes.contains(index.name.as_str()),
            )?;
        }
        MdbxIndex::write_reverse_metadata(
            transaction,
            tables,
            collection,
            id,
            &effective_indexes,
            persist_reverse_metadata,
            remove_reverse_metadata,
        )?;
    }
    Ok(())
}

enum PreviousIndexState {
    Missing,
    Derived(Vec<IndexEntry>),
    ReverseMetadata,
}

fn previous_index_state(
    schema: Option<&CollectionSchemaManifest>,
    previous_bytes: Option<&[u8]>,
) -> Result<PreviousIndexState, String> {
    let Some(previous_bytes) = previous_bytes else {
        return Ok(PreviousIndexState::Missing);
    };
    match derive_indexes_from_stored_document(schema, previous_bytes)? {
        Some(indexes) => Ok(PreviousIndexState::Derived(indexes)),
        None => Ok(PreviousIndexState::ReverseMetadata),
    }
}

fn put_many_documents_with_indexes(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    schema: Option<&CollectionSchemaManifest>,
    documents: &[DocumentWrite],
    trust_schema_documents: bool,
) -> Result<(), String> {
    if documents.is_empty() {
        return Ok(());
    }

    if schema.is_none() {
        if documents.iter().all(|document| document.indexes.is_empty()) {
            let documents_table = create_documents_table(transaction, collection)?;
            let mut documents_cursor = transaction
                .cursor(&documents_table)
                .map_err(|error| error.to_string())?;
            for document in documents {
                documents_cursor
                    .put(
                        &document_table_key(document.id),
                        &document.bytes,
                        WriteFlags::UPSERT,
                    )
                    .map_err(|error| error.to_string())?;
            }
            drop(documents_cursor);
            return Ok(());
        }
        for document in documents {
            put_document_with_indexes(
                transaction,
                tables,
                collection,
                document.id,
                &document.bytes,
                &document.indexes,
            )?;
        }
        return Ok(());
    }

    let schema = schema.expect("schema checked above");
    let unique_indexes = unique_index_names_from_schema(Some(schema));
    let documents_table = create_documents_table(transaction, collection)?;
    let mut documents_cursor = transaction
        .cursor(&documents_table)
        .map_err(|error| error.to_string())?;
    let index_names = index_names_from_schema(schema);
    if trust_schema_documents
        && index_names.is_empty()
        && unique_indexes.is_empty()
        && documents.iter().all(|document| document.indexes.is_empty())
    {
        for document in documents {
            documents_cursor
                .put(
                    &document_table_key(document.id),
                    &document.bytes,
                    WriteFlags::UPSERT,
                )
                .map_err(|error| error.to_string())?;
        }
        drop(documents_cursor);
        return Ok(());
    }
    let index_tables = open_index_tables_for_names(transaction, collection, &index_names)?;
    let mut index_cursors = index_tables
        .tables
        .iter()
        .map(|(_, table)| transaction.cursor(table).map_err(|error| error.to_string()))
        .collect::<Result<Vec<_>, _>>()?;
    let mut index_key_buffer = Vec::with_capacity(64);

    for document in documents {
        if document.indexes.is_empty()
            && unique_indexes.is_empty()
            && (trust_schema_documents || validate_binary_document(schema, &document.bytes).is_ok())
        {
            let previous_bytes = ignore_not_found(
                documents_cursor.set::<Vec<u8>>(&document_table_key(document.id)),
            )?;
            let old_indexes = previous_index_state(Some(schema), previous_bytes.as_deref())?;
            let mut derived_new_indexes = None;
            let indexes_unchanged = match &old_indexes {
                PreviousIndexState::Derived(indexes) => {
                    let next_indexes = index_entries_from_binary_document(schema, &document.bytes)?;
                    let unchanged = indexes == &next_indexes;
                    derived_new_indexes = Some(next_indexes);
                    unchanged
                }
                PreviousIndexState::Missing | PreviousIndexState::ReverseMetadata => false,
            };
            if !indexes_unchanged {
                match old_indexes {
                    PreviousIndexState::Missing => {}
                    PreviousIndexState::Derived(indexes) => {
                        MdbxIndex::delete_entries_with_index_cursors(
                            transaction,
                            collection,
                            document.id,
                            &indexes,
                            &unique_indexes,
                            &index_tables,
                            &mut index_cursors,
                        )?;
                    }
                    PreviousIndexState::ReverseMetadata => MdbxIndex::delete_document(
                        transaction,
                        tables,
                        collection,
                        document.id,
                        None,
                    )?,
                }
            }
            documents_cursor
                .put(
                    &document_table_key(document.id),
                    &document.bytes,
                    WriteFlags::UPSERT,
                )
                .map_err(|error| error.to_string())?;
            if !indexes_unchanged {
                if let Some(indexes) = derived_new_indexes {
                    for index in indexes {
                        encode_table_index_value_into(&index.value, &mut index_key_buffer)?;
                        let cursor_index = index_tables.position(&index.name).ok_or_else(|| {
                            format!("missing prepared MDBX index table `{}`", index.name)
                        })?;
                        let document_id_bytes = document_id_key(document.id);
                        index_cursors[cursor_index]
                            .put(
                                index_key_buffer.as_slice(),
                                &document_id_bytes,
                                WriteFlags::UPSERT,
                            )
                            .map_err(|error| error.to_string())?;
                    }
                } else {
                    for_each_index_entry_from_binary_document(
                        schema,
                        &document.bytes,
                        |name, value| {
                            encode_table_index_value_into(&value, &mut index_key_buffer)?;
                            let cursor_index = index_tables.position(name).ok_or_else(|| {
                                format!("missing prepared MDBX index table `{name}`")
                            })?;
                            let document_id_bytes = document_id_key(document.id);
                            index_cursors[cursor_index]
                                .put(
                                    index_key_buffer.as_slice(),
                                    &document_id_bytes,
                                    WriteFlags::UPSERT,
                                )
                                .map_err(|error| error.to_string())
                        },
                    )?;
                }
            }
            continue;
        }

        let (stored_bytes, effective_indexes, can_derive_new_indexes) =
            encode_document_for_storage(Some(schema), &document.bytes, &document.indexes)?;
        let previous_bytes =
            ignore_not_found(documents_cursor.set::<Vec<u8>>(&document_table_key(document.id)))?;
        let old_indexes = previous_index_state(Some(schema), previous_bytes.as_deref())?;
        let persist_reverse_metadata = !can_derive_new_indexes;
        let indexes_unchanged = can_derive_new_indexes
            && matches!(
                &old_indexes,
                PreviousIndexState::Derived(indexes) if indexes == &effective_indexes
            );

        if !indexes_unchanged {
            MdbxIndex::validate_unique(
                transaction,
                tables,
                collection,
                document.id,
                &effective_indexes,
                &unique_indexes,
            )?;
        }
        documents_cursor
            .put(
                &document_table_key(document.id),
                &stored_bytes,
                WriteFlags::UPSERT,
            )
            .map_err(|error| error.to_string())?;
        if !indexes_unchanged {
            let remove_reverse_metadata =
                matches!(old_indexes, PreviousIndexState::ReverseMetadata);
            match old_indexes {
                PreviousIndexState::Missing => {}
                PreviousIndexState::Derived(indexes) => {
                    MdbxIndex::delete_entries_with_index_cursors(
                        transaction,
                        collection,
                        document.id,
                        &indexes,
                        &unique_indexes,
                        &index_tables,
                        &mut index_cursors,
                    )?;
                }
                PreviousIndexState::ReverseMetadata => {
                    MdbxIndex::delete_document(transaction, tables, collection, document.id, None)?;
                }
            }
            for index in &effective_indexes {
                let key = MdbxIndex::entry_key(collection, &index.name, &index.value)?;
                let cursor_index = index_tables
                    .position(&index.name)
                    .ok_or_else(|| format!("missing prepared MDBX index table `{}`", index.name))?;
                let document_id_bytes = document_id_key(document.id);
                index_cursors[cursor_index]
                    .put(&key, &document_id_bytes, WriteFlags::UPSERT)
                    .map_err(|error| error.to_string())?;
                if unique_indexes.contains(index.name.as_str()) {
                    let unique_key = MdbxIndex::unique_key(collection, &index.name, &index.value)?;
                    let unique_table = create_unique_table(transaction, collection, &index.name)?;
                    transaction
                        .put(
                            &unique_table,
                            unique_key,
                            document.id.to_be_bytes(),
                            WriteFlags::UPSERT,
                        )
                        .map_err(|error| error.to_string())?;
                }
            }
            MdbxIndex::write_reverse_metadata(
                transaction,
                tables,
                collection,
                document.id,
                &effective_indexes,
                persist_reverse_metadata,
                remove_reverse_metadata,
            )?;
        }
    }

    drop(index_cursors);
    drop(documents_cursor);
    Ok(())
}

struct PreparedIndexTables<'txn> {
    tables: Vec<(String, Table<'txn>)>,
}

impl<'txn> PreparedIndexTables<'txn> {
    fn position(&self, name: &str) -> Option<usize> {
        self.tables
            .iter()
            .position(|(table_name, _)| table_name == name)
    }
}

fn open_index_tables_for_names<'txn>(
    transaction: &'txn Transaction<'_, RW, NoWriteMap>,
    collection: &str,
    index_names: &HashSet<String>,
) -> Result<PreparedIndexTables<'txn>, String> {
    let mut tables = Vec::with_capacity(index_names.len());
    for name in index_names {
        tables.push((
            name.clone(),
            create_index_table(transaction, collection, name)?,
        ));
    }
    Ok(PreparedIndexTables { tables })
}

fn encode_document_for_storage(
    schema: Option<&CollectionSchemaManifest>,
    bytes: &[u8],
    indexes: &[IndexEntry],
) -> Result<(Vec<u8>, Vec<IndexEntry>, bool), String> {
    let Some(schema) = schema else {
        return Ok((bytes.to_vec(), indexes.to_vec(), false));
    };
    if let Ok(indexes) = index_entries_from_binary_document(schema, bytes) {
        return Ok((bytes.to_vec(), indexes, true));
    }
    if validate_generic_document(bytes).is_ok() {
        return Ok((bytes.to_vec(), indexes.to_vec(), false));
    }
    Err("document storage requires GenericDocumentV1 or Cindel binary document bytes".into())
}

fn derive_indexes_from_stored_document(
    schema: Option<&CollectionSchemaManifest>,
    bytes: &[u8],
) -> Result<Option<Vec<IndexEntry>>, String> {
    let Some(schema) = schema else {
        return Ok(None);
    };
    if validate_binary_document(schema, bytes).is_ok() {
        return index_entries_from_binary_document(schema, bytes).map(Some);
    }
    Ok(None)
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
    let schema = collection_schema(transaction, tables, collection)?;
    let documents_table = create_documents_table(transaction, collection)?;
    let previous_bytes =
        ignore_not_found(transaction.get::<Vec<u8>>(&documents_table, &document_table_key(id)))?;
    let Some(previous_bytes) = previous_bytes else {
        return Ok(false);
    };
    let old_indexes = derive_indexes_from_stored_document(schema.as_ref(), &previous_bytes)?;
    let deleted = transaction
        .del(&documents_table, document_table_key(id), None)
        .map_err(|error| error.to_string())?;
    if deleted {
        MdbxIndex::delete_document(transaction, tables, collection, id, old_indexes.as_deref())?;
    }
    Ok(deleted)
}

fn delete_many_documents(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    ids: &[u64],
) -> Result<Vec<u64>, String> {
    if ids.is_empty() {
        return Ok(Vec::new());
    }

    let Some(schema) = collection_schema(transaction, tables, collection)? else {
        let mut deleted_ids = Vec::new();
        for id in ids {
            if delete_document(transaction, tables, collection, *id)? {
                deleted_ids.push(*id);
            }
        }
        return Ok(deleted_ids);
    };

    let documents_table = create_documents_table(transaction, collection)?;
    let mut documents_cursor = transaction
        .cursor(&documents_table)
        .map_err(|error| error.to_string())?;
    let index_names = index_names_from_schema(&schema);
    if index_names.is_empty() {
        let mut deleted_ids = Vec::with_capacity(ids.len());
        for id in ids {
            if documents_cursor
                .set::<Vec<u8>>(&document_table_key(*id))
                .map_err(|error| error.to_string())?
                .is_none()
            {
                continue;
            }
            documents_cursor
                .del(WriteFlags::empty())
                .map_err(|error| error.to_string())?;
            deleted_ids.push(*id);
        }
        drop(documents_cursor);
        return Ok(deleted_ids);
    }

    if let Some(index) = direct_bool_delete_index(&schema) {
        return delete_many_documents_with_bool_index(
            transaction,
            collection,
            ids,
            documents_cursor,
            &index,
        );
    }

    let unique_indexes = unique_index_names_from_schema(Some(&schema));
    let index_tables = open_index_tables_for_names(transaction, collection, &index_names)?;
    let mut index_cursors = index_tables
        .tables
        .iter()
        .map(|(_, table)| transaction.cursor(table).map_err(|error| error.to_string()))
        .collect::<Result<Vec<_>, _>>()?;
    let mut deleted_ids = Vec::with_capacity(ids.len());

    for id in ids {
        let previous_bytes =
            ignore_not_found(documents_cursor.set::<Vec<u8>>(&document_table_key(*id)))?;
        let Some(previous_bytes) = previous_bytes else {
            continue;
        };
        match derive_indexes_from_stored_document(Some(&schema), &previous_bytes)? {
            Some(indexes) => MdbxIndex::delete_entries_with_index_cursors(
                transaction,
                collection,
                *id,
                &indexes,
                &unique_indexes,
                &index_tables,
                &mut index_cursors,
            )?,
            None => MdbxIndex::delete_document(transaction, tables, collection, *id, None)?,
        }
        documents_cursor
            .del(WriteFlags::empty())
            .map_err(|error| error.to_string())?;
        deleted_ids.push(*id);
    }

    drop(index_cursors);
    drop(documents_cursor);
    Ok(deleted_ids)
}

struct DirectBoolDeleteIndex {
    name: String,
    static_offset: usize,
    static_size: usize,
}

fn direct_bool_delete_index(schema: &CollectionSchemaManifest) -> Option<DirectBoolDeleteIndex> {
    if !schema.composite_indexes.is_empty() {
        return None;
    }
    let mut indexed_field = None;
    let mut static_offset = 0usize;
    let mut static_size = 0usize;
    for field in &schema.fields {
        if field.is_id {
            continue;
        }
        let field_size = compact_field_static_size(&field.binary_type)?;
        if field.is_indexed {
            if indexed_field.is_some()
                || field.is_index_unique
                || field.index_type != "value"
                || normalized_binary_type(&field.binary_type) != "bool"
            {
                return None;
            }
            indexed_field = Some((field.name.clone(), static_offset));
        }
        static_offset = static_offset.checked_add(field_size)?;
        static_size = static_size.checked_add(field_size)?;
    }
    indexed_field.map(|(name, static_offset)| DirectBoolDeleteIndex {
        name,
        static_offset,
        static_size,
    })
}

fn delete_many_documents_with_bool_index(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    collection: &str,
    ids: &[u64],
    mut documents_cursor: libmdbx::Cursor<'_, RW>,
    index: &DirectBoolDeleteIndex,
) -> Result<Vec<u64>, String> {
    let index_table = create_index_table(transaction, collection, &index.name)?;
    let mut index_cursor = transaction
        .cursor(&index_table)
        .map_err(|error| error.to_string())?;
    let mut deleted_ids = Vec::with_capacity(ids.len());

    for id in ids {
        let previous_bytes =
            ignore_not_found(documents_cursor.set::<Vec<u8>>(&document_table_key(*id)))?;
        let Some(previous_bytes) = previous_bytes else {
            continue;
        };
        let key = direct_bool_index_key(&previous_bytes, index)?;
        let document_id_bytes = document_id_key(*id);
        if let Some(key) = key {
            if index_cursor
                .get_both::<Vec<u8>>(&key, &document_id_bytes)
                .map_err(|error| error.to_string())?
                .is_some()
            {
                index_cursor
                    .del(WriteFlags::empty())
                    .map_err(|error| error.to_string())?;
            }
        }
        documents_cursor
            .del(WriteFlags::empty())
            .map_err(|error| error.to_string())?;
        deleted_ids.push(*id);
    }

    drop(index_cursor);
    drop(documents_cursor);
    Ok(deleted_ids)
}

fn direct_bool_index_key(
    bytes: &[u8],
    index: &DirectBoolDeleteIndex,
) -> Result<Option<[u8; 1]>, String> {
    if bytes.len() < 3 {
        return Err("compact binary document is shorter than the header".into());
    }
    let static_size = read_compact_u24(bytes, 0)? as usize;
    if static_size != index.static_size {
        return Err("compact binary document static size does not match schema".into());
    }
    if bytes.len() < 3 + static_size {
        return Err("compact binary document static section is truncated".into());
    }
    let value = *bytes
        .get(3 + index.static_offset)
        .ok_or_else(|| "compact bool index is outside the static section".to_string())?;
    match value {
        0 => Ok(Some([1])),
        1 => Ok(Some([2])),
        0xff => Ok(None),
        value => Err(format!("invalid compact bool byte `{value}`")),
    }
}

fn compact_field_static_size(binary_type: &str) -> Option<usize> {
    match normalized_binary_type(binary_type) {
        "bool" => Some(1),
        "int" | "double" => Some(8),
        "string" | "String" | "list" | "object" => Some(3),
        _ => None,
    }
}

fn read_compact_u24(bytes: &[u8], offset: usize) -> Result<u32, String> {
    let slice = bytes
        .get(offset..offset + 3)
        .ok_or_else(|| "u24 read is out of bounds".to_string())?;
    Ok(u32::from(slice[0]) | (u32::from(slice[1]) << 8) | (u32::from(slice[2]) << 16))
}

fn normalized_binary_type(binary_type: &str) -> &str {
    binary_type.strip_suffix('?').unwrap_or(binary_type)
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
        let (_, indexes, _) =
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
            None,
            &indexes,
            &unique_indexes,
            true,
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
        .unwrap_or_else(|| DocumentFormatVersion::BinaryV2.as_str().to_string());
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
        "mdbx-v5" => Ok(StorageLayoutVersion::MdbxV5),
        "mdbx-v6" => Ok(StorageLayoutVersion::MdbxV6),
        _ => Err(format!("unknown storage layout version `{value}`")),
    }
}

fn parse_document_format(value: &str) -> Result<DocumentFormatVersion, String> {
    match value {
        "json-v1" => Ok(DocumentFormatVersion::JsonV1),
        "binary-v1" => Ok(DocumentFormatVersion::BinaryV1),
        "binary-v2" => Ok(DocumentFormatVersion::BinaryV2),
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
        old_indexes: Option<&[IndexEntry]>,
        new_indexes: &[IndexEntry],
        unique_indexes: &HashSet<String>,
        persist_reverse_metadata: bool,
    ) -> Result<(), String> {
        Self::delete_document(transaction, tables, collection, document_id, old_indexes)?;
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
        if !persist_reverse_metadata || new_indexes.is_empty() {
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

    fn write_reverse_metadata(
        transaction: &Transaction<'_, RW, NoWriteMap>,
        tables: &MdbxTables<'_>,
        collection: &str,
        document_id: u64,
        new_indexes: &[IndexEntry],
        persist_reverse_metadata: bool,
        remove_existing_metadata: bool,
    ) -> Result<(), String> {
        let key = encode_document_key(collection, document_id);
        if persist_reverse_metadata && !new_indexes.is_empty() {
            transaction
                .put(
                    &tables.document_indexes,
                    key,
                    encode_index_entry_metadata(document_id, new_indexes)?,
                    WriteFlags::UPSERT,
                )
                .map_err(|error| error.to_string())?;
        } else if remove_existing_metadata {
            ignore_not_found(transaction.del(&tables.document_indexes, key, None))?;
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
        known_indexes: Option<&[IndexEntry]>,
    ) -> Result<(), String> {
        if let Some(indexes) = known_indexes {
            Self::delete_entries(transaction, collection, document_id, indexes)?;
            let document_index_key = encode_document_key(collection, document_id);
            ignore_not_found(transaction.del(&tables.document_indexes, document_index_key, None))?;
            return Ok(());
        }

        let document_index_key = encode_document_key(collection, document_id);
        let Some(indexes) = ignore_not_found(
            transaction.get::<Vec<u8>>(&tables.document_indexes, &document_index_key),
        )?
        else {
            return Ok(());
        };
        let indexes = decode_index_entry_metadata(&indexes)?;
        Self::delete_entries(transaction, collection, document_id, &indexes)?;
        ignore_not_found(transaction.del(&tables.document_indexes, document_index_key, None))?;
        Ok(())
    }

    fn delete_entries(
        transaction: &Transaction<'_, RW, NoWriteMap>,
        collection: &str,
        document_id: u64,
        indexes: &[IndexEntry],
    ) -> Result<(), String> {
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
        Ok(())
    }

    fn delete_entries_with_index_cursors(
        transaction: &Transaction<'_, RW, NoWriteMap>,
        collection: &str,
        document_id: u64,
        indexes: &[IndexEntry],
        unique_indexes: &HashSet<String>,
        index_tables: &PreparedIndexTables<'_>,
        index_cursors: &mut [libmdbx::Cursor<'_, RW>],
    ) -> Result<(), String> {
        for index in indexes {
            let key = Self::entry_key(collection, &index.name, &index.value)?;
            let cursor_index = index_tables
                .position(&index.name)
                .ok_or_else(|| format!("missing prepared MDBX index table `{}`", index.name))?;
            let document_id_bytes = document_id_key(document_id);
            if index_cursors[cursor_index]
                .get_both::<Vec<u8>>(&key, &document_id_bytes)
                .map_err(|error| error.to_string())?
                .is_some()
            {
                index_cursors[cursor_index]
                    .del(WriteFlags::empty())
                    .map_err(|error| error.to_string())?;
            }
            if unique_indexes.contains(index.name.as_str()) {
                let unique_key = Self::unique_key(collection, &index.name, &index.value)?;
                if let Ok(unique_table) = open_unique_table(transaction, collection, &index.name) {
                    ignore_not_found(transaction.del(&unique_table, unique_key, None))?;
                }
            }
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
        let document_keys =
            scan_keys_by_prefix(transaction, &tables.document_indexes, &collection_prefix)?;
        let stats = Self::stats(transaction, tables, collection)?;
        let ids = document_keys
            .iter()
            .map(|key| decode_key_document_id(key))
            .collect::<Result<Vec<_>, _>>()?;
        for id in ids {
            Self::delete_document(transaction, tables, collection, id, None)?;
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
    use crate::document_format::{read_binary_field, write_compact_document_for_test, BinaryValue};
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
    fn document_table_keys_match_mdbx_integer_key_ordering() {
        // Scenario: MDBX document tables use INTEGER_KEY ordering.
        // Covers:
        // - Little-endian integer id bytes for positive Cindel ids.
        // - Round-trip decoding used by collection scans.
        // Expected: The encoded integer keys preserve document id order.
        let first = u64::from_le_bytes(document_table_key(1));
        let second = u64::from_le_bytes(document_table_key(2));
        let tenth = u64::from_le_bytes(document_table_key(10));

        assert!(first < second);
        assert!(second < tenth);
        assert_eq!(
            decode_document_table_key(&document_table_key(10)).unwrap(),
            10
        );
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
                validate_binary_document(&schema_manifest().collections[0], &raw)
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
    fn streams_index_equal_query_documents() {
        // Scenario: MDBX streams documents from an index equality query.
        // Covers:
        // - Query reader creation for indexed equality plans.
        // - Document order and payload access from streamed rows.
        // Expected: Only documents matching the index value are streamed.
        let directory = TemporaryDirectory::new("index_equal_query_reader");
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        storage.register_schemas(&schema_manifest()).unwrap();

        for (id, email, name, score) in [
            (1, "ana@example.com", "Ana", 10),
            (2, "ben@example.com", "Ben", 20),
            (3, "cid@example.com", "Cid", 10),
        ] {
            storage
                .put_indexed(
                    "users",
                    id,
                    &user_document(email, id as i64, name, score),
                    &[],
                )
                .unwrap();
        }

        let plan = WireQueryPlan {
            source: WireQuerySource::IndexEqual {
                index_name: "score".to_string(),
                value: WireIndexValue::Int(10),
                dedupe: false,
            },
            filter: None,
            sorts: Vec::new(),
            distinct_fields: Vec::new(),
            offset: 0,
            limit: None,
        };

        let mut reader = storage
            .query_document_reader("users", &plan)
            .unwrap()
            .expect("index equality queries should stream through MDBX");

        assert!(reader.next().unwrap());
        assert_eq!(
            reader.document_bytes(0).unwrap().unwrap(),
            user_document("ana@example.com", 1, "Ana", 10).as_slice()
        );
        assert!(reader.next().unwrap());
        assert_eq!(
            reader.document_bytes(0).unwrap().unwrap(),
            user_document("cid@example.com", 3, "Cid", 10).as_slice()
        );
        assert!(!reader.next().unwrap());
    }

    #[test]
    fn cursor_document_reader_handles_hits_misses_and_reloads() {
        // Scenario: The MDBX point-read cursor reader keeps the current
        // document borrowed from the read transaction.
        // Covers:
        // - Hits and misses in an ordered getAll-style id list.
        // - Re-reading a previous document after visiting a missing id.
        // - Document id and byte access using the same loaded row.
        // Expected: Missing rows do not leak stale bytes, and existing rows
        //   remain readable while the reader is alive.
        let directory = TemporaryDirectory::new("cursor_document_reader_borrowed");
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        storage.register_schemas(&schema_manifest()).unwrap();

        storage
            .put_indexed(
                "users",
                1,
                &user_document("ana@example.com", 1, "Ana", 10),
                &[],
            )
            .unwrap();
        storage
            .put_indexed(
                "users",
                2,
                &user_document("ben@example.com", 2, "Ben", 20),
                &[],
            )
            .unwrap();

        let mut reader = storage
            .cursor_document_reader("users", &[2, 404, 1, 2])
            .unwrap();

        assert_eq!(reader.len(), 4);
        assert!(reader.is_present(0).unwrap());
        assert_eq!(reader.document_id(0).unwrap(), Some(2));
        assert_eq!(
            reader.document_bytes(0).unwrap().unwrap(),
            user_document("ben@example.com", 2, "Ben", 20).as_slice()
        );

        assert!(!reader.is_present(1).unwrap());
        assert_eq!(reader.document_id(1).unwrap(), None);
        assert_eq!(reader.document_bytes(1).unwrap(), None);

        assert!(reader.is_present(2).unwrap());
        assert_eq!(reader.document_id(2).unwrap(), Some(1));
        assert_eq!(
            reader.document_bytes(2).unwrap().unwrap(),
            user_document("ana@example.com", 1, "Ana", 10).as_slice()
        );

        assert!(reader.is_present(3).unwrap());
        assert_eq!(reader.document_id(3).unwrap(), Some(2));
        assert_eq!(
            reader.document_bytes(3).unwrap().unwrap(),
            user_document("ben@example.com", 2, "Ben", 20).as_slice()
        );
    }

    #[test]
    fn streams_all_query_documents_from_borrowed_rows() {
        // Scenario: MDBX streams an unsorted all-documents query directly from
        // cursor rows.
        // Covers:
        // - The non-sorted `Documents` query-reader source.
        // - Current-row bytes becoming unavailable after the stream ends.
        // Expected: Each row is readable exactly while it is current.
        let directory = TemporaryDirectory::new("all_query_reader_borrowed");
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        storage.register_schemas(&schema_manifest()).unwrap();

        for (id, email, name, score) in [
            (1, "ana@example.com", "Ana", 10),
            (2, "ben@example.com", "Ben", 20),
        ] {
            storage
                .put_indexed(
                    "users",
                    id,
                    &user_document(email, id as i64, name, score),
                    &[],
                )
                .unwrap();
        }

        let plan = WireQueryPlan {
            source: WireQuerySource::All { dedupe: false },
            filter: None,
            sorts: Vec::new(),
            distinct_fields: Vec::new(),
            offset: 0,
            limit: None,
        };

        let mut reader = storage
            .query_document_reader("users", &plan)
            .unwrap()
            .expect("all-documents queries should stream through MDBX");

        assert!(reader.next().unwrap());
        assert_eq!(reader.document_id(0).unwrap(), Some(1));
        assert_eq!(
            reader.document_bytes(0).unwrap().unwrap(),
            user_document("ana@example.com", 1, "Ana", 10).as_slice()
        );
        assert!(reader.next().unwrap());
        assert_eq!(reader.document_id(0).unwrap(), Some(2));
        assert_eq!(
            reader.document_bytes(0).unwrap().unwrap(),
            user_document("ben@example.com", 2, "Ben", 20).as_slice()
        );
        assert!(!reader.next().unwrap());
        assert_eq!(reader.document_bytes(0).unwrap(), None);
        assert_eq!(reader.document_id(0).unwrap(), None);
    }

    #[test]
    fn sorts_bool_index_equal_query_documents() {
        // Scenario: MDBX filters by a bool index and sorts by a secondary field.
        // Covers:
        // - Bool index equality query planning.
        // - Native sort over compact task documents.
        // Expected: Matching documents are returned sorted by title.
        let directory = TemporaryDirectory::new("bool_index_equal_sort");
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        storage.register_schemas(&task_schema_manifest()).unwrap();

        for (id, completed, title) in [(1, true, "Cid"), (2, false, "Ben"), (3, true, "Ana")] {
            storage
                .put_indexed(
                    "tasks",
                    id,
                    &task_document(completed, id as i64, title),
                    &[],
                )
                .unwrap();
        }

        let plan = WireQueryPlan {
            source: WireQuerySource::IndexEqual {
                index_name: "completed".to_string(),
                value: WireIndexValue::Bool(true),
                dedupe: false,
            },
            filter: None,
            sorts: vec![crate::wire::WireQuerySort {
                field: "title".to_string(),
                ascending: true,
            }],
            distinct_fields: Vec::new(),
            offset: 0,
            limit: None,
        };

        assert_eq!(
            storage.query_plan_documents("tasks", &plan).unwrap(),
            vec![task_document(true, 3, "Ana"), task_document(true, 1, "Cid"),]
        );
    }

    #[test]
    fn updates_compact_bool_index_documents_without_embedded_id() {
        // Scenario: MDBX updates compact documents whose id is only in the key.
        // Covers:
        // - Query-plan updates over compact bool-indexed documents.
        // - Index replacement after field mutation.
        // Expected: Matching rows move from the true index to the false index.
        let directory = TemporaryDirectory::new("bool_index_update_compact_without_id");
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        storage.register_schemas(&task_schema_manifest()).unwrap();

        for (id, completed, title) in [(1, true, "Cid"), (2, false, "Ben"), (3, true, "Ana")] {
            storage
                .put_indexed("tasks", id, &task_compact_document(completed, title), &[])
                .unwrap();
        }

        let true_plan = WireQueryPlan {
            source: WireQuerySource::IndexEqual {
                index_name: "completed".to_string(),
                value: WireIndexValue::Bool(true),
                dedupe: false,
            },
            filter: None,
            sorts: vec![crate::wire::WireQuerySort {
                field: "title".to_string(),
                ascending: true,
            }],
            distinct_fields: Vec::new(),
            offset: 0,
            limit: None,
        };

        assert_eq!(
            storage.query_plan_documents("tasks", &true_plan).unwrap(),
            vec![
                task_compact_document(true, "Ana"),
                task_compact_document(true, "Cid"),
            ]
        );

        let updated = storage
            .query_plan_update(
                "tasks",
                &WireQueryPlan {
                    sorts: Vec::new(),
                    ..true_plan.clone()
                },
                &[("completed".to_string(), WireValue::Bool(false))],
                true,
            )
            .unwrap();

        assert_eq!(updated, 2);
        assert_eq!(
            storage
                .query_index_equal("tasks", "completed", &IndexValue::Bool(true))
                .unwrap(),
            Vec::<u64>::new()
        );
        assert_eq!(
            storage
                .query_index_equal("tasks", "completed", &IndexValue::Bool(false))
                .unwrap(),
            vec![1, 2, 3]
        );
    }

    #[test]
    fn skips_change_set_ids_for_unwatched_unindexed_query_updates() {
        // Scenario: MDBX updates unindexed query matches without requested ids.
        // Covers:
        // - Filter-only query-plan updates.
        // - Optional watcher change-set id collection.
        // Expected: Documents are updated while no change-set ids are emitted.
        let directory = TemporaryDirectory::new("update_without_change_ids");
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        storage
            .register_schemas(&task_unindexed_schema_manifest())
            .unwrap();

        for (id, completed, title) in [(1, true, "Cid"), (2, false, "Ben"), (3, true, "Ana")] {
            storage
                .put_indexed("tasks", id, &task_compact_document(completed, title), &[])
                .unwrap();
        }

        let filter = crate::wire::WireFilter::Field {
            field: "completed".to_string(),
            operation: crate::wire::WireFilterOperation::Equal,
            value: WireValue::Bool(true),
        };
        let all_tasks_plan = WireQueryPlan {
            source: WireQuerySource::All { dedupe: false },
            filter: None,
            sorts: Vec::new(),
            distinct_fields: Vec::new(),
            offset: 0,
            limit: None,
        };

        let updated = storage
            .query_plan_update(
                "tasks",
                &WireQueryPlan {
                    filter: Some(crate::wire::encode_filter(&filter).unwrap()),
                    ..all_tasks_plan.clone()
                },
                &[("completed".to_string(), WireValue::Bool(false))],
                false,
            )
            .unwrap();

        assert_eq!(updated, 2);
        assert!(storage.take_change_sets().unwrap().is_empty());
        assert_eq!(
            storage
                .query_plan_documents("tasks", &all_tasks_plan)
                .unwrap(),
            vec![
                task_compact_document(false, "Cid"),
                task_compact_document(false, "Ben"),
                task_compact_document(false, "Ana"),
            ]
        );
    }

    #[test]
    fn updates_compact_string_list_fields() {
        // Scenario: MDBX updates a generated compact List<String> field.
        // Covers:
        // - Query-plan updates that change dynamic compact payload length.
        // - The same compact string-list representation used by generated inserts.
        // Expected: Matching documents receive the new string-list value.
        let directory = TemporaryDirectory::new("update_compact_string_list");
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        storage
            .register_schemas(&task_tags_schema_manifest())
            .unwrap();

        for (id, completed, title, tags) in [
            (1, true, "Cid", vec!["old"]),
            (2, false, "Ben", vec!["skip"]),
            (3, true, "Ana", vec!["stale", "tag"]),
        ] {
            storage
                .put_indexed(
                    "tasks",
                    id,
                    &task_tags_document(completed, title, tags),
                    &[],
                )
                .unwrap();
        }

        let updated = storage
            .query_plan_update(
                "tasks",
                &WireQueryPlan {
                    source: WireQuerySource::All { dedupe: false },
                    filter: Some(
                        crate::wire::encode_filter(&crate::wire::WireFilter::Field {
                            field: "completed".to_string(),
                            operation: crate::wire::WireFilterOperation::Equal,
                            value: WireValue::Bool(true),
                        })
                        .unwrap(),
                    ),
                    sorts: Vec::new(),
                    distinct_fields: Vec::new(),
                    offset: 0,
                    limit: None,
                },
                &[(
                    "tags".to_string(),
                    WireValue::List(vec![
                        WireValue::String("fresh".to_string()),
                        WireValue::String("fast".to_string()),
                    ]),
                )],
                true,
            )
            .unwrap();

        let documents = storage
            .query_plan_documents(
                "tasks",
                &WireQueryPlan {
                    source: WireQuerySource::All { dedupe: false },
                    filter: None,
                    sorts: vec![crate::wire::WireQuerySort {
                        field: "title".to_string(),
                        ascending: true,
                    }],
                    distinct_fields: Vec::new(),
                    offset: 0,
                    limit: None,
                },
            )
            .unwrap();
        let schema = &task_tags_schema_manifest().collections[0];
        let tags = documents
            .iter()
            .map(|bytes| read_binary_field(schema, bytes, "tags").unwrap())
            .collect::<Vec<_>>();

        assert_eq!(updated, 2);
        assert_eq!(
            tags,
            vec![
                Some(BinaryValue::List(vec![
                    Some(BinaryValue::String("fresh".to_string())),
                    Some(BinaryValue::String("fast".to_string())),
                ])),
                Some(BinaryValue::List(vec![Some(BinaryValue::String(
                    "skip".to_string()
                ))])),
                Some(BinaryValue::List(vec![
                    Some(BinaryValue::String("fresh".to_string())),
                    Some(BinaryValue::String("fast".to_string())),
                ])),
            ]
        );
    }

    #[test]
    fn sorts_compact_documents_by_external_id() {
        // Scenario: MDBX sorts compact documents by their external document id.
        // Covers:
        // - Id-field sorting when id is stored in the MDBX key.
        // - Compact document payloads without embedded id fields.
        // Expected: Results are ordered by document id, not insertion order.
        let directory = TemporaryDirectory::new("sort_compact_by_external_id");
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        storage.register_schemas(&task_schema_manifest()).unwrap();

        for (id, completed, title) in [(3, false, "Cid"), (1, true, "Ana"), (2, false, "Ben")] {
            storage
                .put_indexed("tasks", id, &task_compact_document(completed, title), &[])
                .unwrap();
        }

        let plan = WireQueryPlan {
            source: WireQuerySource::All { dedupe: false },
            filter: None,
            sorts: vec![crate::wire::WireQuerySort {
                field: "id".to_string(),
                ascending: true,
            }],
            distinct_fields: Vec::new(),
            offset: 0,
            limit: None,
        };

        assert_eq!(
            storage.query_plan_documents("tasks", &plan).unwrap(),
            vec![
                task_compact_document(true, "Ana"),
                task_compact_document(false, "Ben"),
                task_compact_document(false, "Cid"),
            ]
        );
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
    fn schema_binary_documents_delete_old_indexes_without_reverse_metadata() {
        // Scenario: Schema-backed binary documents can derive old index entries
        // from the previously stored document bytes.
        // Covers:
        // - No document_indexes write for the optimized typed binary path.
        // - Update deletes old index keys before inserting new keys.
        // - Delete cleans indexes without reverse metadata.
        // Expected: Index queries stay correct and the reverse metadata table
        // remains empty for the typed binary document.
        let directory = TemporaryDirectory::new("binary_indexes_no_reverse");
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        storage.register_schemas(&schema_manifest()).unwrap();

        storage
            .put_indexed(
                "users",
                1,
                &user_document("old@example.com", 1, "Ana", 10),
                &[],
            )
            .unwrap();

        storage
            .with_read_transaction(|transaction, tables| {
                assert!(
                    ignore_not_found(transaction.get::<Vec<u8>>(
                        &tables.document_indexes,
                        &encode_document_key("users", 1),
                    ))?
                    .is_none()
                );
                Ok(())
            })
            .unwrap();

        storage
            .put_indexed(
                "users",
                1,
                &user_document("new@example.com", 1, "Ana", 20),
                &[],
            )
            .unwrap();

        assert_eq!(
            storage
                .query_index_equal(
                    "users",
                    "email",
                    &IndexValue::String("old@example.com".into())
                )
                .unwrap(),
            Vec::<u64>::new()
        );
        assert_eq!(
            storage
                .query_index_equal(
                    "users",
                    "email",
                    &IndexValue::String("new@example.com".into())
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
                    Some(&IndexValue::Int(10))
                )
                .unwrap(),
            Vec::<u64>::new()
        );

        storage.delete("users", 1).unwrap();

        assert_eq!(
            storage
                .query_index_equal(
                    "users",
                    "email",
                    &IndexValue::String("new@example.com".into())
                )
                .unwrap(),
            Vec::<u64>::new()
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
                    None,
                    &[
                        index("email", IndexValue::String("old@example.com".into())),
                        index("score", IndexValue::Int(10)),
                    ],
                    &unique_indexes,
                    true,
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
                    None,
                    &[
                        index("email", IndexValue::String("new@example.com".into())),
                        index("score", IndexValue::Int(20)),
                    ],
                    &unique_indexes,
                    true,
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
                MdbxIndex::delete_document(transaction, tables, "users", 1, None)?;
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
                    None,
                    &[index("email", IndexValue::String("a@example.com".into()))],
                    &unique_indexes,
                    true,
                )?;
                MdbxIndex::replace_document(
                    transaction,
                    tables,
                    "users",
                    2,
                    None,
                    &[index("email", IndexValue::String("b@example.com".into()))],
                    &unique_indexes,
                    true,
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

    fn task_schema_manifest() -> SchemaManifest {
        SchemaManifest {
            collections: vec![CollectionSchemaManifest {
                name: "tasks".to_string(),
                id_field: "id".to_string(),
                fields: vec![
                    test_field("completed", "bool", false, true),
                    test_field("id", "int", true, false),
                    test_field("title", "String", false, false),
                ],
                composite_indexes: Vec::new(),
            }],
        }
    }

    fn task_unindexed_schema_manifest() -> SchemaManifest {
        SchemaManifest {
            collections: vec![CollectionSchemaManifest {
                name: "tasks".to_string(),
                id_field: "id".to_string(),
                fields: vec![
                    test_field("completed", "bool", false, false),
                    test_field("id", "int", true, false),
                    test_field("title", "String", false, false),
                ],
                composite_indexes: Vec::new(),
            }],
        }
    }

    fn task_tags_schema_manifest() -> SchemaManifest {
        SchemaManifest {
            collections: vec![CollectionSchemaManifest {
                name: "tasks".to_string(),
                id_field: "id".to_string(),
                fields: vec![
                    test_field("completed", "bool", false, false),
                    test_field("id", "int", true, false),
                    list_field("tags", "List<String>", false),
                    test_field("title", "String", false, false),
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
            binary_type: dart_type.to_string(),
            is_id,
            is_indexed,
            is_index_unique: false,
            index_case_sensitive: true,
            index_type: "value".to_string(),
        }
    }

    fn list_field(name: &str, dart_type: &str, is_indexed: bool) -> FieldSchemaManifest {
        FieldSchemaManifest {
            name: name.to_string(),
            dart_type: dart_type.to_string(),
            binary_type: "list".to_string(),
            is_id: false,
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
        write_compact_document_for_test(
            &schema_manifest().collections[0],
            &[
                Some(BinaryValue::String(email.to_string())),
                Some(BinaryValue::Int(id)),
                Some(BinaryValue::String(name.to_string())),
                Some(BinaryValue::Int(score)),
            ],
        )
        .unwrap()
    }

    fn task_document(completed: bool, id: i64, title: &str) -> Vec<u8> {
        write_compact_document_for_test(
            &task_schema_manifest().collections[0],
            &[
                Some(BinaryValue::Bool(completed)),
                Some(BinaryValue::Int(id)),
                Some(BinaryValue::String(title.to_string())),
            ],
        )
        .unwrap()
    }

    fn task_compact_document(completed: bool, title: &str) -> Vec<u8> {
        let title = title.as_bytes();
        let mut bytes = Vec::with_capacity(10 + title.len());
        bytes.extend_from_slice(&[4, 0, 0]);
        bytes.push(u8::from(completed));
        bytes.extend_from_slice(&[4, 0, 0]);
        bytes.push(title.len() as u8);
        bytes.push((title.len() >> 8) as u8);
        bytes.push((title.len() >> 16) as u8);
        bytes.extend_from_slice(title);
        bytes
    }

    fn task_tags_document(completed: bool, title: &str, tags: Vec<&str>) -> Vec<u8> {
        write_compact_document_for_test(
            &task_tags_schema_manifest().collections[0],
            &[
                Some(BinaryValue::Bool(completed)),
                Some(BinaryValue::Int(0)),
                Some(BinaryValue::List(
                    tags.into_iter()
                        .map(|value| Some(BinaryValue::String(value.to_string())))
                        .collect(),
                )),
                Some(BinaryValue::String(title.to_string())),
            ],
        )
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
