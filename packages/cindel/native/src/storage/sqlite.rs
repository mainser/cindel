use std::collections::{HashMap, HashSet};
use std::ffi::{c_void, CStr, CString};
use std::fmt::Write as _;
#[cfg(not(all(target_family = "wasm", target_os = "unknown")))]
use std::fs;
#[cfg(any(not(all(target_family = "wasm", target_os = "unknown")), test))]
use std::path::Path;
use std::ptr;
use std::slice;

use rusqlite::types::{Null, Value, ValueRef};
#[cfg(all(feature = "web", target_family = "wasm", target_os = "unknown"))]
use rusqlite::OpenFlags;
use rusqlite::{
    ffi, params, params_from_iter, Connection, OptionalExtension, Row, TransactionBehavior,
};

use crate::document_format::{decode_list, BinaryValue};
use crate::wire::{
    decode_filter, encode_index_value, encode_projection_rows, encode_scalar, WireFilter,
    WireFilterOperation, WireIndexValue, WireProjectionRows, WireQueryPlan, WireQuerySource,
    WireScalar, WireValue,
};

use super::{
    decode_schema_record, encode_schema_record, CollectionSchemaManifest, DocumentWrite,
    FieldSchemaManifest, IndexEntry, IndexValue, LinkSave, NativeDocumentValue,
    NativeDocumentWrite, SchemaManifest, StorageChangeSet, StorageEngine,
};
use super::{DocumentFormatVersion, SchemaMetadataVersion, StorageLayoutVersion, StorageMetadata};

pub struct SqliteStorage {
    connection: Connection,
    schemas: HashMap<String, RegisteredCollectionSchema>,
    collection_revisions: HashMap<String, u64>,
    persist_schema_metadata: bool,
    active_transaction: Option<TransactionMode>,
    active_change_sets: Vec<StorageChangeSet>,
    last_change_sets: Vec<StorageChangeSet>,
}

#[derive(Clone)]
struct RegisteredCollectionSchema {
    version: u64,
    schema: CollectionSchemaManifest,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum TransactionMode {
    Read,
    Write,
}

pub(crate) struct SqliteNativeDocumentCursor {
    database: *mut ffi::sqlite3,
    statement: *mut ffi::sqlite3_stmt,
    ids: Vec<i64>,
    current_index: Option<usize>,
    current_present: bool,
    owns_transaction: bool,
}

pub(crate) struct SqliteNativeQueryCursor {
    database: *mut ffi::sqlite3,
    statement: *mut ffi::sqlite3_stmt,
    current_present: bool,
    owns_transaction: bool,
}

impl SqliteNativeDocumentCursor {
    fn new(
        connection: &Connection,
        schema: &CollectionSchemaManifest,
        ids: &[u64],
        owns_transaction: bool,
    ) -> Result<Self, String> {
        let ids = ids
            .iter()
            .copied()
            .map(sqlite_id)
            .collect::<Result<Vec<_>, _>>()?;
        let fields = native_fields(schema);
        let mut select = String::from("SELECT ");
        select.push_str(SQLITE_ROW_ID_COLUMN);
        for field in &fields {
            select.push_str(", ");
            select.push_str(&field.name);
        }
        select.push_str(" FROM ");
        select.push_str(&schema.name);
        select.push_str(" WHERE ");
        select.push_str(SQLITE_ROW_ID_COLUMN);
        select.push_str(" = ?");

        let sql = CString::new(select).map_err(|error| error.to_string())?;
        let mut statement = ptr::null_mut();
        let database = unsafe { connection.handle() };
        if owns_transaction {
            sqlite_exec(database, "BEGIN")?;
        }
        let status = unsafe {
            ffi::sqlite3_prepare_v2(database, sql.as_ptr(), -1, &mut statement, ptr::null_mut())
        };
        if status != ffi::SQLITE_OK {
            if owns_transaction {
                let _ = sqlite_exec(database, "ROLLBACK");
            }
            return Err(sqlite_error(database));
        }
        Ok(Self {
            database,
            statement,
            ids,
            current_index: None,
            current_present: false,
            owns_transaction,
        })
    }

    pub(crate) fn len(&self) -> usize {
        self.ids.len()
    }

    pub(crate) fn is_present(&mut self, document_index: usize) -> Result<bool, String> {
        self.seek(document_index)
    }

    pub(crate) fn document_id(&mut self, document_index: usize) -> Option<u64> {
        if !self.seek(document_index).ok()? {
            return None;
        }
        let id = unsafe { ffi::sqlite3_column_int64(self.statement, 0) };
        u64::try_from(id).ok()
    }

    pub(crate) fn read_bool(&mut self, document_index: usize, field_index: usize) -> Option<bool> {
        if !self.seek(document_index).ok()? {
            return None;
        }
        let column = Self::field_column(field_index)?;
        if self.is_null_column(column) {
            None
        } else {
            Some(unsafe { ffi::sqlite3_column_int(self.statement, column) } != 0)
        }
    }

    pub(crate) fn read_int(&mut self, document_index: usize, field_index: usize) -> Option<i64> {
        if !self.seek(document_index).ok()? {
            return None;
        }
        let column = Self::field_column(field_index)?;
        if self.is_null_column(column) {
            None
        } else {
            Some(unsafe { ffi::sqlite3_column_int64(self.statement, column) })
        }
    }

    pub(crate) fn read_double(&mut self, document_index: usize, field_index: usize) -> Option<f64> {
        if !self.seek(document_index).ok()? {
            return None;
        }
        let column = Self::field_column(field_index)?;
        if self.is_null_column(column) {
            None
        } else {
            Some(unsafe { ffi::sqlite3_column_double(self.statement, column) })
        }
    }

    pub(crate) fn read_bytes(
        &mut self,
        document_index: usize,
        field_index: usize,
    ) -> Option<&[u8]> {
        if !self.seek(document_index).ok()? {
            return None;
        }
        let column = Self::field_column(field_index)?;
        if self.is_null_column(column) {
            return None;
        }
        let length = unsafe { ffi::sqlite3_column_bytes(self.statement, column) };
        if length < 0 {
            return None;
        }
        let ptr = match unsafe { ffi::sqlite3_column_type(self.statement, column) } {
            ffi::SQLITE_TEXT => unsafe {
                ffi::sqlite3_column_text(self.statement, column) as *const u8
            },
            ffi::SQLITE_BLOB => unsafe {
                ffi::sqlite3_column_blob(self.statement, column) as *const u8
            },
            _ => return None,
        };
        if ptr.is_null() && length != 0 {
            return None;
        }
        Some(unsafe { slice::from_raw_parts(ptr, length as usize) })
    }

    fn seek(&mut self, document_index: usize) -> Result<bool, String> {
        if self.current_index == Some(document_index) {
            return Ok(self.current_present);
        }
        let Some(id) = self.ids.get(document_index).copied() else {
            self.current_index = Some(document_index);
            self.current_present = false;
            return Ok(false);
        };
        sqlite_status(self.database, unsafe { ffi::sqlite3_reset(self.statement) })?;
        sqlite_status(self.database, unsafe {
            ffi::sqlite3_clear_bindings(self.statement)
        })?;
        sqlite_status(self.database, unsafe {
            ffi::sqlite3_bind_int64(self.statement, 1, id)
        })?;
        let status = unsafe { ffi::sqlite3_step(self.statement) };
        self.current_index = Some(document_index);
        self.current_present = match status {
            ffi::SQLITE_ROW => true,
            ffi::SQLITE_DONE => false,
            _ => return Err(sqlite_error(self.database)),
        };
        Ok(self.current_present)
    }

    fn field_column(field_index: usize) -> Option<i32> {
        i32::try_from(field_index.checked_add(1)?).ok()
    }

    fn is_null_column(&self, column: i32) -> bool {
        unsafe { ffi::sqlite3_column_type(self.statement, column) == ffi::SQLITE_NULL }
    }
}

impl SqliteNativeQueryCursor {
    fn new(
        connection: &Connection,
        schema: &CollectionSchemaManifest,
        plan: &WireQueryPlan,
        owns_transaction: bool,
    ) -> Result<Self, String> {
        let (sql, params) = sqlite_query_plan_sql(schema, plan, SqliteQuerySelect::Documents)?;
        let sql = CString::new(sql).map_err(|error| error.to_string())?;
        let mut statement = ptr::null_mut();
        let database = unsafe { connection.handle() };
        if owns_transaction {
            sqlite_exec(database, "BEGIN")?;
        }
        let status = unsafe {
            ffi::sqlite3_prepare_v2(database, sql.as_ptr(), -1, &mut statement, ptr::null_mut())
        };
        if status != ffi::SQLITE_OK {
            if owns_transaction {
                let _ = sqlite_exec(database, "ROLLBACK");
            }
            return Err(sqlite_error(database));
        }
        for (index, value) in params.iter().enumerate() {
            bind_sqlite_value(database, statement, index + 1, value)?;
        }
        Ok(Self {
            database,
            statement,
            current_present: false,
            owns_transaction,
        })
    }

    pub(crate) fn next(&mut self) -> Result<bool, String> {
        let status = unsafe { ffi::sqlite3_step(self.statement) };
        self.current_present = match status {
            ffi::SQLITE_ROW => true,
            ffi::SQLITE_DONE => false,
            _ => return Err(sqlite_error(self.database)),
        };
        Ok(self.current_present)
    }

    pub(crate) fn document_id(&self, _document_index: usize) -> Option<u64> {
        if !self.current_present {
            return None;
        }
        let id = unsafe { ffi::sqlite3_column_int64(self.statement, 0) };
        u64::try_from(id).ok()
    }

    pub(crate) fn read_bool(&self, _document_index: usize, field_index: usize) -> Option<bool> {
        if !self.current_present {
            return None;
        }
        let column = Self::field_column(field_index)?;
        if self.is_null_column(column) {
            None
        } else {
            Some(unsafe { ffi::sqlite3_column_int(self.statement, column) } != 0)
        }
    }

    pub(crate) fn read_int(&self, _document_index: usize, field_index: usize) -> Option<i64> {
        if !self.current_present {
            return None;
        }
        let column = Self::field_column(field_index)?;
        if self.is_null_column(column) {
            None
        } else {
            Some(unsafe { ffi::sqlite3_column_int64(self.statement, column) })
        }
    }

    pub(crate) fn read_double(&self, _document_index: usize, field_index: usize) -> Option<f64> {
        if !self.current_present {
            return None;
        }
        let column = Self::field_column(field_index)?;
        if self.is_null_column(column) {
            None
        } else {
            Some(unsafe { ffi::sqlite3_column_double(self.statement, column) })
        }
    }

    pub(crate) fn read_bytes(&self, _document_index: usize, field_index: usize) -> Option<&[u8]> {
        if !self.current_present {
            return None;
        }
        let column = Self::field_column(field_index)?;
        if self.is_null_column(column) {
            return None;
        }
        let length = unsafe { ffi::sqlite3_column_bytes(self.statement, column) };
        if length < 0 {
            return None;
        }
        let ptr = match unsafe { ffi::sqlite3_column_type(self.statement, column) } {
            ffi::SQLITE_TEXT => unsafe {
                ffi::sqlite3_column_text(self.statement, column) as *const u8
            },
            ffi::SQLITE_BLOB => unsafe {
                ffi::sqlite3_column_blob(self.statement, column) as *const u8
            },
            _ => return None,
        };
        if ptr.is_null() && length != 0 {
            return None;
        }
        Some(unsafe { slice::from_raw_parts(ptr, length as usize) })
    }

    fn field_column(field_index: usize) -> Option<i32> {
        i32::try_from(field_index.checked_add(1)?).ok()
    }

    fn is_null_column(&self, column: i32) -> bool {
        unsafe { ffi::sqlite3_column_type(self.statement, column) == ffi::SQLITE_NULL }
    }
}

impl Drop for SqliteNativeQueryCursor {
    fn drop(&mut self) {
        if !self.statement.is_null() {
            unsafe {
                ffi::sqlite3_finalize(self.statement);
            }
            self.statement = ptr::null_mut();
        }
        if self.owns_transaction {
            let _ = sqlite_exec(self.database, "COMMIT");
            self.owns_transaction = false;
        }
    }
}

impl Drop for SqliteNativeDocumentCursor {
    fn drop(&mut self) {
        if !self.statement.is_null() {
            unsafe {
                ffi::sqlite3_finalize(self.statement);
            }
            self.statement = ptr::null_mut();
        }
        if self.owns_transaction {
            let _ = sqlite_exec(self.database, "COMMIT");
            self.owns_transaction = false;
        }
    }
}

fn bind_sqlite_value(
    database: *mut ffi::sqlite3,
    statement: *mut ffi::sqlite3_stmt,
    index: usize,
    value: &Value,
) -> Result<(), String> {
    let index = i32::try_from(index).map_err(|error| error.to_string())?;
    let status = match value {
        Value::Null => unsafe { ffi::sqlite3_bind_null(statement, index) },
        Value::Integer(value) => unsafe { ffi::sqlite3_bind_int64(statement, index, *value) },
        Value::Real(value) => unsafe { ffi::sqlite3_bind_double(statement, index, *value) },
        Value::Text(value) => unsafe {
            ffi::sqlite3_bind_text(
                statement,
                index,
                value.as_ptr().cast(),
                i32::try_from(value.len()).map_err(|error| error.to_string())?,
                ffi::SQLITE_TRANSIENT(),
            )
        },
        Value::Blob(value) => unsafe {
            ffi::sqlite3_bind_blob(
                statement,
                index,
                value.as_ptr().cast::<c_void>(),
                i32::try_from(value.len()).map_err(|error| error.to_string())?,
                ffi::SQLITE_TRANSIENT(),
            )
        },
    };
    sqlite_status(database, status)
}

fn sqlite_exec(database: *mut ffi::sqlite3, sql: &str) -> Result<(), String> {
    let sql = CString::new(sql).map_err(|error| error.to_string())?;
    let mut error_message = ptr::null_mut();
    let status = unsafe {
        ffi::sqlite3_exec(
            database,
            sql.as_ptr(),
            None,
            ptr::null_mut(),
            &mut error_message,
        )
    };
    if status == ffi::SQLITE_OK {
        return Ok(());
    }
    if error_message.is_null() {
        return Err(sqlite_error(database));
    }
    let message = unsafe { CStr::from_ptr(error_message) }
        .to_string_lossy()
        .into_owned();
    unsafe {
        ffi::sqlite3_free(error_message.cast());
    }
    Err(message)
}

fn sqlite_status(database: *mut ffi::sqlite3, status: i32) -> Result<(), String> {
    if status == ffi::SQLITE_OK {
        Ok(())
    } else {
        Err(sqlite_error(database))
    }
}

fn sqlite_error(database: *mut ffi::sqlite3) -> String {
    if database.is_null() {
        return "SQLite operation failed".into();
    }
    let message = unsafe { ffi::sqlite3_errmsg(database) };
    if message.is_null() {
        "SQLite operation failed".into()
    } else {
        unsafe { CStr::from_ptr(message) }
            .to_string_lossy()
            .into_owned()
    }
}

impl SqliteStorage {
    pub fn open(directory: &str) -> Result<Self, String> {
        let mut storage = Self::open_uninitialized(directory, true)?;
        storage.initialize(None)?;

        Ok(storage)
    }

    pub fn open_with_schemas(directory: &str, manifest: &SchemaManifest) -> Result<Self, String> {
        validate_schema_manifest(manifest)?;
        let mut storage = Self::open_uninitialized(directory, false)?;
        storage.initialize(Some(manifest))?;

        Ok(storage)
    }

    pub fn open_with_persisted_schemas(
        directory: &str,
        manifest: &SchemaManifest,
    ) -> Result<Self, String> {
        validate_schema_manifest(manifest)?;
        let mut storage = Self::open_uninitialized(directory, true)?;
        storage.initialize(None)?;
        storage.register_schemas(manifest)?;
        for collection in &manifest.collections {
            storage.register_collection_schema(collection)?;
        }

        Ok(storage)
    }

    pub(crate) fn native_document_cursor(
        &self,
        collection: &str,
        ids: &[u64],
    ) -> Result<Option<SqliteNativeDocumentCursor>, String> {
        let Some(schema) = self.collection_schema(collection) else {
            return Ok(None);
        };
        SqliteNativeDocumentCursor::new(
            &self.connection,
            schema,
            ids,
            self.active_transaction.is_none(),
        )
        .map(Some)
    }

    pub(crate) fn query_plan_native_cursor(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Option<SqliteNativeQueryCursor>, String> {
        let Some(schema) = self.collection_schema(collection) else {
            return Ok(None);
        };
        SqliteNativeQueryCursor::new(
            &self.connection,
            schema,
            plan,
            self.active_transaction.is_none(),
        )
        .map(Some)
    }

    fn open_uninitialized(directory: &str, persist_schema_metadata: bool) -> Result<Self, String> {
        let connection = open_sqlite_connection(directory)?;
        let storage = Self {
            connection,
            schemas: HashMap::new(),
            collection_revisions: HashMap::new(),
            persist_schema_metadata,
            active_transaction: None,
            active_change_sets: Vec::new(),
            last_change_sets: Vec::new(),
        };

        Ok(storage)
    }

    fn initialize(&mut self, manifest: Option<&SchemaManifest>) -> Result<(), String> {
        self.connection
            .execute_batch(
                r#"
                PRAGMA mmap_size = 1073741824;
                PRAGMA journal_mode = WAL;
                PRAGMA case_sensitive_like = true;
                "#,
            )
            .map_err(|error| error.to_string())?;
        self.connection
            .execute_batch("BEGIN")
            .map_err(|error| error.to_string())?;
        let result = self.initialize_transaction(manifest);
        match result {
            Ok(()) => self
                .connection
                .execute_batch("COMMIT")
                .map_err(|error| error.to_string()),
            Err(error) => {
                let _ = self.connection.execute_batch("ROLLBACK");
                Err(error)
            }
        }
    }

    fn initialize_transaction(&mut self, manifest: Option<&SchemaManifest>) -> Result<(), String> {
        ensure_id_counters_table(&self.connection)?;
        if self.persist_schema_metadata {
            ensure_base_tables(&self.connection)?;
            ensure_binary_schema_collections_table(&self.connection)?;
            ensure_storage_metadata(
                &self.connection,
                StorageLayoutVersion::SqliteV1,
                DocumentFormatVersion::BinaryV2,
                SchemaMetadataVersion::BinaryV1,
            )?;
            validate_storage_metadata(
                &self.connection,
                StorageLayoutVersion::SqliteV1,
                DocumentFormatVersion::BinaryV2,
                SchemaMetadataVersion::BinaryV1,
            )?;
            validate_schema_metadata_records(&self.connection)?;
        } else if table_exists(&self.connection, "storage_metadata")? {
            validate_storage_metadata(
                &self.connection,
                StorageLayoutVersion::SqliteV1,
                DocumentFormatVersion::BinaryV2,
                SchemaMetadataVersion::BinaryV1,
            )?;
        }
        ensure_relation_tables(&self.connection)?;

        if let Some(manifest) = manifest {
            for collection in &manifest.collections {
                self.register_collection_schema(collection)?;
            }
            return Ok(());
        }

        Ok(())
    }

    fn record_change(
        &mut self,
        collection: &str,
        revision: u64,
        ids: impl IntoIterator<Item = u64>,
    ) {
        let target = if self.active_transaction == Some(TransactionMode::Write) {
            &mut self.active_change_sets
        } else {
            self.last_change_sets.clear();
            &mut self.last_change_sets
        };
        merge_change_set(target, collection, revision, ids);
    }

    fn collection_schema(&self, collection: &str) -> Option<&CollectionSchemaManifest> {
        self.schemas.get(collection).map(|schema| &schema.schema)
    }

    fn register_collection_schema(
        &mut self,
        collection: &CollectionSchemaManifest,
    ) -> Result<(), String> {
        let version = match self.schemas.get(&collection.name) {
            None => 1,
            Some(existing) if existing.schema == *collection => existing.version,
            Some(existing) => {
                validate_compatible_schema_change(&existing.schema, collection)?;
                existing.version + 1
            }
        };
        create_collection_table(&self.connection, collection)?;
        self.schemas.insert(
            collection.name.clone(),
            RegisteredCollectionSchema {
                version,
                schema: collection.clone(),
            },
        );
        Ok(())
    }

    fn bump_collection_revision_in_memory(&mut self, collection: &str) -> u64 {
        let revision = self
            .collection_revisions
            .entry(collection.to_string())
            .or_default();
        *revision += 1;
        *revision
    }
}

const IN_MEMORY_DIRECTORY: &str = ":memory:";
const SQLITE_ROW_ID_COLUMN: &str = "_rowid_";
const SQLITE_MAX_PARAM_COUNT: usize = 32766;

impl StorageEngine for SqliteStorage {
    fn begin_read_transaction(&mut self) -> Result<(), String> {
        self.begin_transaction(TransactionMode::Read, "BEGIN DEFERRED TRANSACTION")
    }

    fn begin_write_transaction(&mut self) -> Result<(), String> {
        self.begin_transaction(TransactionMode::Write, "BEGIN IMMEDIATE TRANSACTION")
    }

    fn commit_transaction(&mut self) -> Result<(), String> {
        let Some(mode) = self.active_transaction else {
            return Err("no active transaction to commit".into());
        };
        self.connection
            .execute_batch("COMMIT")
            .map_err(|error| error.to_string())?;
        self.active_transaction = None;
        self.last_change_sets = if mode == TransactionMode::Write {
            std::mem::take(&mut self.active_change_sets)
        } else {
            Vec::new()
        };
        Ok(())
    }

    fn rollback_transaction(&mut self) -> Result<(), String> {
        if self.active_transaction.is_none() {
            return Err("no active transaction to rollback".into());
        }
        self.connection
            .execute_batch("ROLLBACK")
            .map_err(|error| error.to_string())?;
        self.active_transaction = None;
        self.active_change_sets.clear();
        Ok(())
    }

    fn allocate_id(&mut self, collection: &str) -> Result<u64, String> {
        self.reserve_ids(collection, 1)
    }

    fn reserve_ids(&mut self, collection: &str, count: u32) -> Result<u64, String> {
        self.ensure_can_write()?;
        if count == 0 {
            return Ok(0);
        }
        let is_native = self.collection_schema(collection).is_some();
        if self.active_transaction.is_some() {
            if !is_native {
                ensure_generic_document_tables(&self.connection)?;
            }
            let id = reserve_ids(&self.connection, collection, count)?;
            return u64::try_from(id).map_err(|error| error.to_string());
        }

        // Acquire the write lock before reading the shared counter. A deferred
        // read/update could race another connection or fail while upgrading.
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(|error| error.to_string())?;

        if !is_native {
            ensure_generic_document_tables(&transaction)?;
        }
        let id = reserve_ids(&transaction, collection, count)?;

        transaction.commit().map_err(|error| error.to_string())?;
        u64::try_from(id).map_err(|error| error.to_string())
    }

    fn get(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String> {
        let id = sqlite_id(id)?;
        if !table_exists(&self.connection, "documents")? {
            return Ok(None);
        }

        self.connection
            .query_row(
                "SELECT bytes FROM documents WHERE collection = ?1 AND id = ?2",
                params![collection, id],
                |row| row.get(0),
            )
            .optional()
            .map_err(|error| error.to_string())
    }

    fn get_many(&self, collection: &str, ids: &[u64]) -> Result<Vec<Option<Vec<u8>>>, String> {
        if ids.is_empty() {
            return Ok(Vec::new());
        }
        if !table_exists(&self.connection, "documents")? {
            return Ok(vec![None; ids.len()]);
        }
        get_many_generic_documents(&self.connection, collection, ids)
    }

    fn get_many_stored(
        &self,
        collection: &str,
        ids: &[u64],
    ) -> Result<Vec<Option<Vec<u8>>>, String> {
        let Some(schema) = self.collection_schema(collection) else {
            return self.get_many(collection, ids);
        };
        get_many_native_documents(&self.connection, schema, ids)
    }

    fn document_ids(&self, collection: &str) -> Result<Vec<u64>, String> {
        if self.collection_schema(collection).is_some() {
            if table_exists(&self.connection, "documents")? {
                let sql = format!(
                    "SELECT {SQLITE_ROW_ID_COLUMN} AS id FROM {collection}
                     UNION
                     SELECT id FROM documents WHERE collection = ?1
                     ORDER BY id"
                );
                return query_ids(&self.connection, &sql, params![collection]);
            }
            let sql = format!(
                "SELECT {SQLITE_ROW_ID_COLUMN} FROM {collection} ORDER BY {SQLITE_ROW_ID_COLUMN}"
            );
            return query_ids(&self.connection, &sql, []);
        }
        if !table_exists(&self.connection, "documents")? {
            return Ok(Vec::new());
        }
        query_ids(
            &self.connection,
            r#"
            SELECT id
            FROM documents
            WHERE collection = ?1
            ORDER BY id
            "#,
            params![collection],
        )
    }

    fn document_ids_page(
        &self,
        collection: &str,
        after_id: Option<u64>,
        limit: usize,
    ) -> Result<Vec<u64>, String> {
        let after_id = optional_sql_id(after_id)?;
        let limit = i64::try_from(limit).map_err(|error| error.to_string())?;
        if self.collection_schema(collection).is_some() {
            if table_exists(&self.connection, "documents")? {
                let sql = format!(
                    "SELECT id FROM (
                         SELECT {SQLITE_ROW_ID_COLUMN} AS id
                         FROM {collection}
                         WHERE (?2 IS NULL OR {SQLITE_ROW_ID_COLUMN} > ?2)
                         UNION
                         SELECT id
                         FROM documents
                         WHERE collection = ?1 AND (?2 IS NULL OR id > ?2)
                     )
                     ORDER BY id
                     LIMIT ?3"
                );
                return query_ids(&self.connection, &sql, params![collection, after_id, limit]);
            }
            let sql = format!(
                "SELECT {SQLITE_ROW_ID_COLUMN}
                 FROM {collection}
                 WHERE (?1 IS NULL OR {SQLITE_ROW_ID_COLUMN} > ?1)
                 ORDER BY {SQLITE_ROW_ID_COLUMN}
                 LIMIT ?2"
            );
            return query_ids(&self.connection, &sql, params![after_id, limit]);
        }
        if !table_exists(&self.connection, "documents")? {
            return Ok(Vec::new());
        }
        query_ids(
            &self.connection,
            r#"
            SELECT id
            FROM documents
            WHERE collection = ?1 AND (?2 IS NULL OR id > ?2)
            ORDER BY id
            LIMIT ?3
            "#,
            params![collection, after_id, limit],
        )
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
        if self.active_transaction.is_some() {
            put_document_with_indexes(&self.connection, collection, id, bytes, indexes)?;
            let revision = bump_collection_revision(&self.connection, collection)?;
            self.record_change(collection, revision, [id]);
            return Ok(());
        }

        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;

        put_document_with_indexes(&transaction, collection, id, bytes, indexes)?;
        let revision = bump_collection_revision(&transaction, collection)?;

        transaction.commit().map_err(|error| error.to_string())?;
        self.record_change(collection, revision, [id]);
        Ok(())
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
        _trust_schema_documents: bool,
    ) -> Result<(), String> {
        if documents.is_empty() {
            if self.active_transaction.is_none() {
                self.last_change_sets.clear();
            }
            return Ok(());
        }
        self.ensure_can_write()?;
        if self.active_transaction.is_some() {
            for document in documents {
                put_document_with_indexes(
                    &self.connection,
                    collection,
                    document.id,
                    &document.bytes,
                    &document.indexes,
                )?;
            }
            let revision = bump_collection_revision(&self.connection, collection)?;
            if track_changes {
                self.record_change(
                    collection,
                    revision,
                    documents.iter().map(|document| document.id),
                );
            }
            return Ok(());
        }

        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;

        for document in documents {
            put_document_with_indexes(
                &transaction,
                collection,
                document.id,
                &document.bytes,
                &document.indexes,
            )?;
        }
        let revision = bump_collection_revision(&transaction, collection)?;

        transaction.commit().map_err(|error| error.to_string())?;
        if track_changes {
            self.record_change(
                collection,
                revision,
                documents.iter().map(|document| document.id),
            );
        } else {
            self.last_change_sets.clear();
        }
        Ok(())
    }

    fn put_many_native_documents(
        &mut self,
        collection: &str,
        documents: &[NativeDocumentWrite],
        track_changes: bool,
    ) -> Result<bool, String> {
        let Some(schema) = self.collection_schema(collection).cloned() else {
            return Ok(false);
        };
        if documents.is_empty() {
            if self.active_transaction.is_none() {
                self.last_change_sets.clear();
            }
            return Ok(true);
        }
        self.ensure_can_write()?;
        if self.active_transaction.is_some() {
            let max_id = put_native_documents(&self.connection, &schema, documents)?;
            if let Some(max_id) = max_id {
                advance_id_counter(&self.connection, collection, max_id)?;
            }
            let revision = self.bump_collection_revision_in_memory(collection);
            if track_changes {
                self.record_change(
                    collection,
                    revision,
                    documents.iter().map(|document| document.id),
                );
            }
            return Ok(true);
        }

        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;
        let max_id = put_native_documents(&transaction, &schema, documents)?;
        if let Some(max_id) = max_id {
            advance_id_counter(&transaction, collection, max_id)?;
        }
        transaction.commit().map_err(|error| error.to_string())?;
        let revision = self.bump_collection_revision_in_memory(collection);
        if track_changes {
            self.record_change(
                collection,
                revision,
                documents.iter().map(|document| document.id),
            );
        } else {
            self.last_change_sets.clear();
        }
        Ok(true)
    }

    fn delete(&mut self, collection: &str, id: u64) -> Result<(), String> {
        self.ensure_can_write()?;
        let id = sqlite_id(id)?;
        let has_collection_table = self.collection_schema(collection).is_some();
        if self.active_transaction.is_some() {
            let deleted = delete_document_with_layout(
                &self.connection,
                collection,
                id,
                has_collection_table,
            )?;
            if deleted {
                let revision = if has_collection_table {
                    self.bump_collection_revision_in_memory(collection)
                } else {
                    bump_collection_revision(&self.connection, collection)?
                };
                self.record_change(collection, revision, [id as u64]);
            }
            return Ok(());
        }

        self.last_change_sets.clear();
        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;

        let deleted =
            delete_document_with_layout(&transaction, collection, id, has_collection_table)?;
        let mut revision = None;
        if deleted && !has_collection_table {
            revision = Some(bump_collection_revision(&transaction, collection)?);
        }

        transaction.commit().map_err(|error| error.to_string())?;
        if deleted && has_collection_table {
            revision = Some(self.bump_collection_revision_in_memory(collection));
        }
        if let Some(revision) = revision {
            self.record_change(collection, revision, [id as u64]);
        }
        Ok(())
    }

    fn delete_many(&mut self, collection: &str, ids: &[u64]) -> Result<(), String> {
        if ids.is_empty() {
            if self.active_transaction.is_none() {
                self.last_change_sets.clear();
            }
            return Ok(());
        }
        self.ensure_can_write()?;
        let has_collection_table = self.collection_schema(collection).is_some();
        if self.active_transaction.is_some() {
            let mut deleted_ids = Vec::new();
            for id in ids {
                let id = sqlite_id(*id)?;
                let deleted = delete_document_with_layout(
                    &self.connection,
                    collection,
                    id,
                    has_collection_table,
                )?;
                if deleted {
                    deleted_ids.push(id as u64);
                }
            }
            if !deleted_ids.is_empty() {
                let revision = if has_collection_table {
                    self.bump_collection_revision_in_memory(collection)
                } else {
                    bump_collection_revision(&self.connection, collection)?
                };
                self.record_change(collection, revision, deleted_ids);
            }
            return Ok(());
        }

        self.last_change_sets.clear();
        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;

        let mut deleted_ids = Vec::new();
        for id in ids {
            let id = sqlite_id(*id)?;
            let deleted =
                delete_document_with_layout(&transaction, collection, id, has_collection_table)?;
            if deleted {
                deleted_ids.push(id as u64);
            }
        }
        let revision = if deleted_ids.is_empty() {
            None
        } else if has_collection_table {
            None
        } else {
            Some(bump_collection_revision(&transaction, collection)?)
        };

        transaction.commit().map_err(|error| error.to_string())?;
        let revision = if !deleted_ids.is_empty() && has_collection_table {
            Some(self.bump_collection_revision_in_memory(collection))
        } else {
            revision
        };
        if let Some(revision) = revision {
            self.record_change(collection, revision, deleted_ids);
        }
        Ok(())
    }

    fn delete_many_native_documents(
        &mut self,
        collection: &str,
        ids: &[u64],
    ) -> Result<bool, String> {
        let Some(schema) = self.collection_schema(collection).cloned() else {
            return Ok(false);
        };
        if ids.is_empty() {
            if self.active_transaction.is_none() {
                self.last_change_sets.clear();
            }
            return Ok(true);
        }
        self.ensure_can_write()?;

        if self.active_transaction.is_some() {
            let deleted_ids = delete_native_documents(&self.connection, &schema.name, ids)?;
            if !deleted_ids.is_empty() {
                let revision = self.bump_collection_revision_in_memory(collection);
                self.record_change(collection, revision, deleted_ids);
            }
            return Ok(true);
        }

        self.last_change_sets.clear();
        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;
        let deleted_ids = delete_native_documents(&transaction, &schema.name, ids)?;
        let has_deleted_ids = !deleted_ids.is_empty();

        transaction.commit().map_err(|error| error.to_string())?;
        if has_deleted_ids {
            let revision = self.bump_collection_revision_in_memory(collection);
            self.record_change(collection, revision, deleted_ids);
        }
        Ok(true)
    }

    fn replace_links(&mut self, links: &LinkSave) -> Result<(), String> {
        self.ensure_can_write()?;
        let target_ids = dedupe_sorted_ids(&links.target_ids);
        if self.active_transaction.is_some() {
            replace_links_sqlite(&self.connection, links, &target_ids)?;
            let revision = if self.collection_schema(&links.source_collection).is_some() {
                self.bump_collection_revision_in_memory(&links.source_collection)
            } else {
                bump_collection_revision(&self.connection, &links.source_collection)?
            };
            self.record_change(&links.source_collection, revision, [links.source_id]);
            return Ok(());
        }

        self.last_change_sets.clear();
        let has_source_schema = self.collection_schema(&links.source_collection).is_some();
        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;
        replace_links_sqlite(&transaction, links, &target_ids)?;
        let revision = if has_source_schema {
            None
        } else {
            Some(bump_collection_revision(
                &transaction,
                &links.source_collection,
            )?)
        };
        transaction.commit().map_err(|error| error.to_string())?;
        let revision = revision
            .unwrap_or_else(|| self.bump_collection_revision_in_memory(&links.source_collection));
        self.record_change(&links.source_collection, revision, [links.source_id]);
        Ok(())
    }

    fn forward_link_ids(
        &self,
        source_collection: &str,
        source_id: u64,
        link_name: &str,
        target_collection: &str,
    ) -> Result<Vec<u64>, String> {
        ensure_relation_tables(&self.connection)?;
        query_ids(
            &self.connection,
            r#"
            SELECT target_id
            FROM cindel_relations
            WHERE source_collection = ?1
              AND source_id = ?2
              AND link_name = ?3
              AND target_collection = ?4
            ORDER BY target_id
            "#,
            params![
                source_collection,
                sqlite_id(source_id)?,
                link_name,
                target_collection
            ],
        )
    }

    fn backlink_source_ids(
        &self,
        target_collection: &str,
        target_id: u64,
        source_collection: &str,
        link_name: &str,
    ) -> Result<Vec<u64>, String> {
        ensure_relation_tables(&self.connection)?;
        query_ids(
            &self.connection,
            r#"
            SELECT source_id
            FROM cindel_relations
            WHERE target_collection = ?1
              AND target_id = ?2
              AND source_collection = ?3
              AND link_name = ?4
            ORDER BY source_id
            "#,
            params![
                target_collection,
                sqlite_id(target_id)?,
                source_collection,
                link_name
            ],
        )
    }

    fn query_index_equal(
        &self,
        collection: &str,
        index: &str,
        value: &IndexValue,
    ) -> Result<Vec<u64>, String> {
        query_index(
            &self.connection,
            collection,
            index,
            Some(value),
            Some(value),
        )
    }

    fn query_index_range(
        &self,
        collection: &str,
        index: &str,
        lower: Option<&IndexValue>,
        upper: Option<&IndexValue>,
    ) -> Result<Vec<u64>, String> {
        query_index(&self.connection, collection, index, lower, upper)
    }

    fn collection_revision(&self, collection: &str) -> Result<u64, String> {
        if self.collection_schema(collection).is_some() {
            let native_revision = *self.collection_revisions.get(collection).unwrap_or(&0);
            if !table_exists(&self.connection, "collection_revisions")? {
                return Ok(native_revision);
            }
            let generic_revision = self
                .connection
                .query_row(
                    "SELECT revision FROM collection_revisions WHERE collection = ?1",
                    params![collection],
                    |row| row.get::<_, i64>(0),
                )
                .optional()
                .map_err(|error| error.to_string())?
                .map(u64::try_from)
                .transpose()
                .map_err(|error| error.to_string())?
                .unwrap_or_default();
            return Ok(native_revision.max(generic_revision));
        }
        if !table_exists(&self.connection, "collection_revisions")? {
            return Ok(0);
        }
        self.connection
            .query_row(
                "SELECT revision FROM collection_revisions WHERE collection = ?1",
                params![collection],
                |row| row.get::<_, i64>(0),
            )
            .optional()
            .map_err(|error| error.to_string())?
            .map(u64::try_from)
            .transpose()
            .map_err(|error| error.to_string())
            .map(Option::unwrap_or_default)
    }

    fn take_change_sets(&mut self) -> Result<Vec<StorageChangeSet>, String> {
        Ok(std::mem::take(&mut self.last_change_sets))
    }

    fn register_schemas(&mut self, manifest: &SchemaManifest) -> Result<(), String> {
        validate_schema_manifest(manifest)?;
        self.ensure_can_write()?;
        if self.persist_schema_metadata {
            if self.active_transaction.is_some() {
                for collection in &manifest.collections {
                    register_persisted_collection_schema(&self.connection, collection)?;
                    let version =
                        persisted_schema_version(&self.connection, &collection.name)?.unwrap_or(1);
                    self.schemas.insert(
                        collection.name.clone(),
                        RegisteredCollectionSchema {
                            version,
                            schema: collection.clone(),
                        },
                    );
                }
                return Ok(());
            }

            let transaction = self
                .connection
                .transaction()
                .map_err(|error| error.to_string())?;
            for collection in &manifest.collections {
                register_persisted_collection_schema(&transaction, collection)?;
            }
            transaction.commit().map_err(|error| error.to_string())?;
            for collection in &manifest.collections {
                let version =
                    persisted_schema_version(&self.connection, &collection.name)?.unwrap_or(1);
                self.schemas.insert(
                    collection.name.clone(),
                    RegisteredCollectionSchema {
                        version,
                        schema: collection.clone(),
                    },
                );
            }
            return Ok(());
        }

        if self.active_transaction.is_some() {
            for collection in &manifest.collections {
                self.register_collection_schema(collection)?;
            }
            return Ok(());
        }

        self.connection
            .execute_batch("BEGIN")
            .map_err(|error| error.to_string())?;
        for collection in &manifest.collections {
            if let Err(error) = self.register_collection_schema(collection) {
                let _ = self.connection.execute_batch("ROLLBACK");
                return Err(error);
            }
        }

        self.connection
            .execute_batch("COMMIT")
            .map_err(|error| error.to_string())
    }

    fn register_migrated_schemas(&mut self, manifest: &SchemaManifest) -> Result<(), String> {
        validate_schema_manifest(manifest)?;
        self.ensure_can_write()?;
        if !self.persist_schema_metadata {
            return self.register_schemas(manifest);
        }
        if self.active_transaction.is_some() {
            for collection in &manifest.collections {
                register_migrated_collection_schema(&self.connection, collection)?;
                let version =
                    persisted_schema_version(&self.connection, &collection.name)?.unwrap_or(1);
                self.schemas.insert(
                    collection.name.clone(),
                    RegisteredCollectionSchema {
                        version,
                        schema: collection.clone(),
                    },
                );
            }
            return Ok(());
        }

        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;
        for collection in &manifest.collections {
            register_migrated_collection_schema(&transaction, collection)?;
        }
        transaction.commit().map_err(|error| error.to_string())?;
        for collection in &manifest.collections {
            let version =
                persisted_schema_version(&self.connection, &collection.name)?.unwrap_or(1);
            self.schemas.insert(
                collection.name.clone(),
                RegisteredCollectionSchema {
                    version,
                    schema: collection.clone(),
                },
            );
        }
        Ok(())
    }

    fn schema_version(&self, collection: &str) -> Result<Option<u64>, String> {
        if self.persist_schema_metadata {
            return self
                .connection
                .query_row(
                    "SELECT version FROM schema_collections WHERE collection = ?1",
                    params![collection],
                    |row| row.get::<_, i64>(0),
                )
                .optional()
                .map_err(|error| error.to_string())?
                .map(u64::try_from)
                .transpose()
                .map_err(|error| error.to_string());
        }
        Ok(self.schemas.get(collection).map(|schema| schema.version))
    }

    fn migration_version(&self) -> Result<Option<u64>, String> {
        read_migration_version(&self.connection)
    }

    fn set_migration_version(&mut self, version: u64) -> Result<(), String> {
        self.ensure_can_write()?;
        write_migration_version(&self.connection, version)
    }

    fn storage_metadata(&self) -> Result<StorageMetadata, String> {
        Ok(StorageMetadata {
            layout: StorageLayoutVersion::SqliteV1,
            document_format: DocumentFormatVersion::BinaryV2,
            schema_metadata_format: SchemaMetadataVersion::BinaryV1,
        })
    }

    fn compact(&mut self) -> Result<(), String> {
        self.ensure_can_write()?;
        if self.active_transaction.is_some() {
            return Err("SQLite compact cannot run inside an active transaction".into());
        }
        self.connection
            .execute_batch("VACUUM")
            .map_err(|error| error.to_string())
    }

    fn rebuild_indexes(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String> {
        self.ensure_can_write()?;
        if self.active_transaction.is_some() {
            return rebuild_indexes_on_connection(&self.connection, collection, documents);
        }

        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;
        rebuild_indexes_on_connection(&transaction, collection, documents)?;
        transaction.commit().map_err(|error| error.to_string())
    }

    fn query_plan_ids(&self, collection: &str, plan: &WireQueryPlan) -> Result<Vec<u64>, String> {
        let schema = self.required_collection_schema(collection)?;
        let (sql, params) = sqlite_query_plan_sql(&schema, plan, SqliteQuerySelect::Ids)?;
        query_ids(&self.connection, &sql, params_from_iter(params.iter()))
    }

    fn query_plan_documents(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Vec<Vec<u8>>, String> {
        Ok(self
            .query_plan_native_document_rows(collection, plan)?
            .into_iter()
            .map(|(_, document)| document)
            .collect())
    }

    fn query_plan_count(&self, collection: &str, plan: &WireQueryPlan) -> Result<u64, String> {
        if !plan.distinct_fields.is_empty() {
            return Ok(self.query_plan_ids(collection, plan)?.len() as u64);
        }
        let schema = self.required_collection_schema(collection)?;
        let (sql, params) = sqlite_query_plan_sql(&schema, plan, SqliteQuerySelect::Count)?;
        let count = self
            .connection
            .query_row(&sql, params_from_iter(params.iter()), |row| {
                row.get::<_, i64>(0)
            })
            .map_err(|error| error.to_string())?;
        u64::try_from(count).map_err(|error| error.to_string())
    }

    fn query_project(
        &self,
        collection: &str,
        candidate_ids: &[u64],
        field: &str,
    ) -> Result<Vec<u8>, String> {
        let schema = self.required_collection_schema(collection)?;
        self.query_native_projection(&schema, candidate_ids, field)
    }

    fn query_aggregate(
        &self,
        collection: &str,
        candidate_ids: &[u64],
        field: &str,
        operation: &str,
    ) -> Result<Vec<u8>, String> {
        let schema = self.required_collection_schema(collection)?;
        let values = self.query_native_values(&schema, candidate_ids, field)?;
        encode_scalar(&aggregate_wire_values(&values, operation)?)
    }

    fn query_plan_project(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
        field: &str,
    ) -> Result<Vec<u8>, String> {
        let schema = self.required_collection_schema(collection)?;
        let cells = self.query_plan_native_values(&schema, plan, field)?;
        let row_count =
            u32::try_from(cells.len()).map_err(|_| "projection row count overflow".to_string())?;
        encode_projection_rows(&WireProjectionRows {
            row_count,
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
        let schema = self.required_collection_schema(collection)?;
        if !plan.distinct_fields.is_empty() {
            let values = self.query_plan_native_values(&schema, plan, field)?;
            return encode_scalar(&aggregate_wire_values(&values, operation)?);
        }

        let schema_field = sqlite_schema_field(&schema, field)?;
        let (sql, params) =
            sqlite_query_plan_sql(&schema, plan, SqliteQuerySelect::Field(schema_field))?;
        let mut statement = self
            .connection
            .prepare(&sql)
            .map_err(|error| error.to_string())?;
        let rows = statement
            .query_map(params_from_iter(params.iter()), |row| {
                sqlite_row_wire_value(row, 0, schema_field)
            })
            .map_err(|error| error.to_string())?;
        let mut aggregate = StreamingWireAggregate::new(operation);
        for row in rows {
            let value = row.map_err(|error| error.to_string())?;
            // Materializing the values used to report read errors before aggregate
            // errors. Keep decoding after a calculation error to preserve that order.
            aggregate = aggregate.and_then(|mut aggregate| {
                aggregate.push(value)?;
                Ok(aggregate)
            });
        }
        encode_scalar(&aggregate?.finish()?)
    }

    fn query_plan_delete(
        &mut self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Vec<u64>, String> {
        self.ensure_can_write()?;
        let ids = self.query_plan_ids(collection, plan)?;
        if !ids.is_empty() {
            self.delete_many_native_documents(collection, &ids)?;
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
        let schema = self.required_collection_schema(collection)?;
        let count = update_native_query_plan(&self.connection, &schema, plan, updates)?;
        if count > 0 {
            let revision = self.bump_collection_revision_in_memory(collection);
            if collect_changes {
                self.record_change(collection, revision, std::iter::empty::<u64>());
            }
        }
        Ok(count)
    }
}

impl SqliteStorage {
    fn required_collection_schema(
        &self,
        collection: &str,
    ) -> Result<CollectionSchemaManifest, String> {
        self.collection_schema(collection)
            .cloned()
            .ok_or_else(|| format!("collection `{collection}` has no registered schema"))
    }

    fn query_plan_native_document_rows(
        &self,
        collection: &str,
        plan: &WireQueryPlan,
    ) -> Result<Vec<(u64, Vec<u8>)>, String> {
        let schema = self.required_collection_schema(collection)?;
        let fields = native_fields(&schema);
        let (sql, params) = sqlite_query_plan_sql(&schema, plan, SqliteQuerySelect::Documents)?;
        let mut statement = self
            .connection
            .prepare(&sql)
            .map_err(|error| error.to_string())?;
        let rows = statement
            .query_map(params_from_iter(params.iter()), |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    native_document_from_row(row, &fields)?,
                ))
            })
            .map_err(|error| error.to_string())?;
        let mut documents = Vec::new();
        for row in rows {
            let (id, document) = row.map_err(|error| error.to_string())?;
            documents.push((
                u64::try_from(id).map_err(|error| error.to_string())?,
                document,
            ));
        }
        Ok(documents)
    }

    fn query_plan_native_values(
        &self,
        schema: &CollectionSchemaManifest,
        plan: &WireQueryPlan,
        field: &str,
    ) -> Result<Vec<WireValue>, String> {
        if !plan.distinct_fields.is_empty() {
            // Keep the same representative row selected by the ID query's GROUP BY.
            let ids = self.query_plan_ids(&schema.name, plan)?;
            return self.query_native_values(schema, &ids, field);
        }

        let schema_field = sqlite_schema_field(schema, field)?;
        let (sql, params) =
            sqlite_query_plan_sql(schema, plan, SqliteQuerySelect::Field(schema_field))?;
        let mut statement = self
            .connection
            .prepare(&sql)
            .map_err(|error| error.to_string())?;
        let rows = statement
            .query_map(params_from_iter(params.iter()), |row| {
                sqlite_row_wire_value(row, 0, schema_field)
            })
            .map_err(|error| error.to_string())?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|error| error.to_string())
    }

    fn query_native_projection(
        &self,
        schema: &CollectionSchemaManifest,
        ids: &[u64],
        field: &str,
    ) -> Result<Vec<u8>, String> {
        let cells = self.query_native_values(schema, ids, field)?;
        let row_count =
            u32::try_from(cells.len()).map_err(|_| "projection row count overflow".to_string())?;
        encode_projection_rows(&WireProjectionRows {
            row_count,
            column_count: 1,
            cells,
        })
    }

    fn query_native_values(
        &self,
        schema: &CollectionSchemaManifest,
        ids: &[u64],
        field: &str,
    ) -> Result<Vec<WireValue>, String> {
        let schema_field = sqlite_schema_field(schema, field)?;
        if schema_field.is_id {
            let mut values = Vec::new();
            for id in ids {
                if native_document_exists(&self.connection, schema, *id)? {
                    values.push(WireValue::Int(
                        i64::try_from(*id).map_err(|error| error.to_string())?,
                    ));
                }
            }
            return Ok(values);
        }

        let column = sqlite_column_for_schema_field(schema_field);
        let sql = format!(
            "SELECT {column} FROM {} WHERE {SQLITE_ROW_ID_COLUMN} = ?1",
            schema.name
        );
        let mut statement = self
            .connection
            .prepare(&sql)
            .map_err(|error| error.to_string())?;
        let mut values = Vec::new();
        for id in ids {
            let id = sqlite_id(*id)?;
            let value = statement
                .query_row(params![id], |row| {
                    sqlite_row_wire_value(row, 0, schema_field)
                })
                .optional()
                .map_err(|error| error.to_string())?;
            if let Some(value) = value {
                values.push(value);
            }
        }
        Ok(values)
    }

    fn begin_transaction(&mut self, mode: TransactionMode, sql: &str) -> Result<(), String> {
        if self.active_transaction.is_some() {
            return Err("a transaction is already active".into());
        }
        self.connection
            .execute_batch(sql)
            .map_err(|error| error.to_string())?;
        self.active_transaction = Some(mode);
        Ok(())
    }

    fn ensure_can_write(&self) -> Result<(), String> {
        match self.active_transaction {
            Some(TransactionMode::Read) => Err("write attempted inside read transaction".into()),
            Some(TransactionMode::Write) | None => Ok(()),
        }
    }
}

#[cfg(all(feature = "web", target_family = "wasm", target_os = "unknown"))]
fn open_sqlite_connection(directory: &str) -> Result<Connection, String> {
    let flags = OpenFlags::SQLITE_OPEN_READ_WRITE
        | OpenFlags::SQLITE_OPEN_CREATE
        | OpenFlags::SQLITE_OPEN_URI
        | OpenFlags::SQLITE_OPEN_NO_MUTEX;
    if directory == IN_MEMORY_DIRECTORY {
        Connection::open_in_memory_with_flags(flags).map_err(|error| error.to_string())
    } else {
        Connection::open_with_flags_and_vfs(directory, flags, "opfs-sahpool")
            .map_err(|error| error.to_string())
    }
}

#[cfg(all(not(feature = "web"), target_family = "wasm", target_os = "unknown"))]
fn open_sqlite_connection(directory: &str) -> Result<Connection, String> {
    if directory == IN_MEMORY_DIRECTORY {
        Connection::open_in_memory().map_err(|error| error.to_string())
    } else {
        Err(
            "persistent SQLite storage on Web requires the `web` feature and OPFS SAHPool setup"
                .into(),
        )
    }
}

#[cfg(not(all(target_family = "wasm", target_os = "unknown")))]
fn open_sqlite_connection(directory: &str) -> Result<Connection, String> {
    if directory == IN_MEMORY_DIRECTORY {
        Connection::open_in_memory().map_err(|error| error.to_string())
    } else {
        fs::create_dir_all(directory).map_err(|error| error.to_string())?;
        let database_path = Path::new(directory).join("cindel.sqlite");
        Connection::open(database_path).map_err(|error| error.to_string())
    }
}

fn sqlite_id(id: u64) -> Result<i64, String> {
    i64::try_from(id).map_err(|_| format!("id {id} exceeds SQLite INTEGER range"))
}

#[derive(Clone, Copy)]
enum SqliteQuerySelect<'a> {
    Ids,
    Documents,
    Count,
    Field(&'a FieldSchemaManifest),
}

fn sqlite_query_plan_sql(
    schema: &CollectionSchemaManifest,
    plan: &WireQueryPlan,
    select: SqliteQuerySelect<'_>,
) -> Result<(String, Vec<Value>), String> {
    let fields = native_fields(schema);
    let (predicates, params) = sqlite_query_plan_predicates(schema, plan)?;

    let mut sql = String::new();
    match select {
        SqliteQuerySelect::Count => sql.push_str("SELECT COUNT(*) FROM (SELECT 1"),
        SqliteQuerySelect::Ids => {
            sql.push_str("SELECT ");
            sql.push_str(SQLITE_ROW_ID_COLUMN);
        }
        SqliteQuerySelect::Field(field) => {
            sql.push_str("SELECT ");
            sql.push_str(&sqlite_column_for_schema_field(field));
        }
        SqliteQuerySelect::Documents => {
            sql.push_str("SELECT ");
            sql.push_str(SQLITE_ROW_ID_COLUMN);
            for field in &fields {
                sql.push_str(", ");
                sql.push_str(&field.name);
            }
        }
    }
    sql.push_str(" FROM ");
    sql.push_str(&schema.name);
    if !predicates.is_empty() {
        sql.push_str(" WHERE ");
        sql.push_str(&predicates.join(" AND "));
    }
    if !plan.distinct_fields.is_empty() {
        sql.push_str(" GROUP BY ");
        let distinct = plan
            .distinct_fields
            .iter()
            .map(|field| sqlite_column_for_field(schema, field))
            .collect::<Result<Vec<_>, String>>()?;
        sql.push_str(&distinct.join(", "));
    }
    if matches!(select, SqliteQuerySelect::Count) {
        // Sorting cannot change the size of a non-distinct result window,
        // but invalid sort fields must still be rejected.
        for sort in &plan.sorts {
            sqlite_column_for_field(schema, &sort.field)?;
        }
    } else if !plan.sorts.is_empty() {
        sql.push_str(" ORDER BY ");
        for (index, sort) in plan.sorts.iter().enumerate() {
            if index > 0 {
                sql.push_str(", ");
            }
            sql.push_str(&sqlite_column_for_field(schema, &sort.field)?);
            sql.push_str(" COLLATE NOCASE");
            if !sort.ascending {
                sql.push_str(" DESC");
            }
        }
    }
    if plan.offset > 0 {
        sql.push_str(&format!(
            " LIMIT {}, {}",
            plan.offset,
            plan.limit.unwrap_or(u32::MAX)
        ));
    } else if let Some(limit) = plan.limit {
        sql.push_str(&format!(" LIMIT {limit}"));
    }
    if matches!(select, SqliteQuerySelect::Count) {
        sql.push(')');
    }

    Ok((sql, params))
}

fn sqlite_query_plan_predicates(
    schema: &CollectionSchemaManifest,
    plan: &WireQueryPlan,
) -> Result<(Vec<String>, Vec<Value>), String> {
    let mut params = Vec::new();
    let mut predicates = Vec::new();

    if let Some((source_sql, source_params)) = sqlite_query_source_sql(schema, &plan.source)? {
        predicates.push(source_sql);
        params.extend(source_params);
    }
    if let Some(filter) = &plan.filter {
        let filter = decode_filter(filter)?;
        let (filter_sql, filter_params) = sqlite_filter_sql(schema, filter)?;
        predicates.push(filter_sql);
        params.extend(filter_params);
    }

    Ok((predicates, params))
}

fn update_native_query_plan(
    connection: &Connection,
    schema: &CollectionSchemaManifest,
    plan: &WireQueryPlan,
    updates: &[(String, WireValue)],
) -> Result<usize, String> {
    if updates.is_empty() {
        return Ok(0);
    }
    let (update_sql, mut params) = sqlite_update_sql(schema, updates)?;
    let requires_subquery = plan.offset > 0
        || plan.limit.is_some()
        || !plan.sorts.is_empty()
        || !plan.distinct_fields.is_empty();

    let sql = if requires_subquery {
        let (select_sql, select_params) =
            sqlite_query_plan_sql(schema, plan, SqliteQuerySelect::Ids)?;
        params.extend(select_params);
        format!(
            "UPDATE {} SET {} WHERE {} IN ({})",
            schema.name, update_sql, SQLITE_ROW_ID_COLUMN, select_sql
        )
    } else {
        let (predicates, predicate_params) = sqlite_query_plan_predicates(schema, plan)?;
        params.extend(predicate_params);
        let mut sql = format!("UPDATE {} SET {}", schema.name, update_sql);
        if !predicates.is_empty() {
            sql.push_str(" WHERE ");
            sql.push_str(&predicates.join(" AND "));
        }
        sql
    };

    connection
        .execute(&sql, params_from_iter(params.iter()))
        .map_err(|error| error.to_string())
}

fn sqlite_update_sql(
    schema: &CollectionSchemaManifest,
    updates: &[(String, WireValue)],
) -> Result<(String, Vec<Value>), String> {
    let mut sql = String::new();
    let mut params = Vec::new();
    for (field_name, value) in updates {
        let field = schema
            .fields
            .iter()
            .find(|field| field.name == *field_name)
            .ok_or_else(|| {
                format!(
                    "field `{field_name}` is not declared in schema `{}`",
                    schema.name
                )
            })?;
        if field.is_id {
            return Err(format!(
                "query updates cannot change id field `{field_name}`"
            ));
        }
        if !sql.is_empty() {
            sql.push(',');
        }
        sql.push_str(&field.name);
        if matches!(value, WireValue::Null) {
            sql.push_str("=NULL");
        } else {
            sql.push_str("=?");
            params.push(sqlite_update_value(field, value)?);
        }
    }
    Ok((sql, params))
}

fn sqlite_update_value(field: &FieldSchemaManifest, value: &WireValue) -> Result<Value, String> {
    match (field.binary_type.as_str(), value) {
        (_, WireValue::Null) => Ok(Value::Null),
        ("bool", WireValue::Bool(value)) => Ok(Value::Integer(i64::from(*value))),
        ("int", WireValue::Int(value)) => Ok(Value::Integer(*value)),
        ("double", WireValue::Double(value)) if value.is_finite() => Ok(Value::Real(*value)),
        ("double", WireValue::Double(_)) => {
            Err("SQLite update double values must be finite".into())
        }
        ("string", WireValue::String(value)) => Ok(Value::Text(value.clone())),
        ("list", WireValue::List(_)) | ("object", WireValue::Object(_)) => {
            let mut json = String::new();
            push_wire_json_value(&mut json, value)?;
            Ok(Value::Text(json))
        }
        _ => Err(format!(
            "SQLite update value does not match field `{}` type `{}`",
            field.name, field.binary_type
        )),
    }
}

fn push_wire_json_value(json: &mut String, value: &WireValue) -> Result<(), String> {
    match value {
        WireValue::Null => json.push_str("null"),
        WireValue::Bool(value) => json.push_str(if *value { "true" } else { "false" }),
        WireValue::Int(value) => json.push_str(&value.to_string()),
        WireValue::Double(value) if value.is_finite() => json.push_str(&value.to_string()),
        WireValue::Double(_) => return Err("SQLite JSON double values must be finite".into()),
        WireValue::String(value) => push_json_string(json, value)?,
        WireValue::List(values) => {
            json.push('[');
            for (index, value) in values.iter().enumerate() {
                if index > 0 {
                    json.push(',');
                }
                push_wire_json_value(json, value)?;
            }
            json.push(']');
        }
        WireValue::Object(fields) => {
            json.push('{');
            for (index, (name, value)) in fields.iter().enumerate() {
                if index > 0 {
                    json.push(',');
                }
                push_json_string(json, name)?;
                json.push(':');
                push_wire_json_value(json, value)?;
            }
            json.push('}');
        }
    }
    Ok(())
}

fn sqlite_query_source_sql(
    schema: &CollectionSchemaManifest,
    source: &WireQuerySource,
) -> Result<Option<(String, Vec<Value>)>, String> {
    match source {
        WireQuerySource::All { .. } => Ok(None),
        WireQuerySource::IndexEqual {
            index_name, value, ..
        } => {
            let column = sqlite_column_for_field(schema, index_name)?;
            if matches!(value, WireIndexValue::Null) {
                Ok(Some((format!("{column} IS NULL"), Vec::new())))
            } else {
                Ok(Some((
                    format!("{column} = ?"),
                    vec![sqlite_index_value(value)?],
                )))
            }
        }
        WireQuerySource::IndexRange {
            index_name,
            lower,
            upper,
            ..
        } => {
            let column = sqlite_column_for_field(schema, index_name)?;
            let mut sql = Vec::new();
            let mut params = Vec::new();
            if let Some(lower) = lower {
                sql.push(format!("{column} >= ?"));
                params.push(sqlite_index_value(lower)?);
            }
            if let Some(upper) = upper {
                sql.push(format!("{column} <= ?"));
                params.push(sqlite_index_value(upper)?);
            }
            Ok(Some((sql.join(" AND "), params)))
        }
    }
}

fn sqlite_filter_sql(
    schema: &CollectionSchemaManifest,
    filter: WireFilter,
) -> Result<(String, Vec<Value>), String> {
    match filter {
        WireFilter::Field {
            field,
            operation,
            value,
        } => sqlite_field_filter_sql(schema, &field, operation, &value),
        WireFilter::All { predicates } => {
            if predicates.is_empty() {
                return Ok(("TRUE".to_string(), Vec::new()));
            }
            let mut sql = Vec::new();
            let mut params = Vec::new();
            for predicate in predicates {
                let (predicate_sql, predicate_params) = sqlite_filter_sql(schema, predicate)?;
                sql.push(predicate_sql);
                params.extend(predicate_params);
            }
            Ok((format!("({})", sql.join(" AND ")), params))
        }
        WireFilter::Any { predicates } => {
            if predicates.is_empty() {
                return Ok(("FALSE".to_string(), Vec::new()));
            }
            let mut sql = Vec::new();
            let mut params = Vec::new();
            for predicate in predicates {
                let (predicate_sql, predicate_params) = sqlite_filter_sql(schema, predicate)?;
                sql.push(predicate_sql);
                params.extend(predicate_params);
            }
            Ok((format!("({})", sql.join(" OR ")), params))
        }
        WireFilter::Not { predicate } => {
            let (sql, params) = sqlite_filter_sql(schema, *predicate)?;
            Ok((format!("NOT {sql}"), params))
        }
    }
}

fn sqlite_field_filter_sql(
    schema: &CollectionSchemaManifest,
    field: &str,
    operation: WireFilterOperation,
    value: &WireValue,
) -> Result<(String, Vec<Value>), String> {
    let schema_field = sqlite_schema_field(schema, field)?;
    let column = sqlite_column_for_schema_field(schema_field);
    if !schema_field.is_id
        && sqlite_binary_type(&schema_field.binary_type) == "list"
        && operation == WireFilterOperation::Contains
    {
        return sqlite_list_contains_sql(&column, value);
    }
    if !schema_field.is_id
        && sqlite_binary_type(&schema_field.binary_type) == "list"
        && matches!(
            operation,
            WireFilterOperation::LengthEqual
                | WireFilterOperation::LengthLessThan
                | WireFilterOperation::LengthLessThanOrEqual
                | WireFilterOperation::LengthGreaterThan
                | WireFilterOperation::LengthGreaterThanOrEqual
        )
    {
        return sqlite_list_length_sql(&column, operation, value);
    }
    let sql = match operation {
        WireFilterOperation::IsNull => (format!("{column} IS NULL"), Vec::new()),
        WireFilterOperation::Equal => match value {
            WireValue::Null => (format!("{column} IS NULL"), Vec::new()),
            value => (format!("{column} = ?"), vec![sqlite_wire_value(value)?]),
        },
        WireFilterOperation::GreaterThan => match value {
            WireValue::Null => (format!("{column} IS NOT NULL"), Vec::new()),
            value => (format!("{column} > ?"), vec![sqlite_wire_value(value)?]),
        },
        WireFilterOperation::GreaterThanOrEqual => match value {
            WireValue::Null => ("TRUE".to_string(), Vec::new()),
            value => (format!("{column} >= ?"), vec![sqlite_wire_value(value)?]),
        },
        WireFilterOperation::LessThan => match value {
            WireValue::Null => ("FALSE".to_string(), Vec::new()),
            value => (
                format!("({column} < ? OR {column} IS NULL)"),
                vec![sqlite_wire_value(value)?],
            ),
        },
        WireFilterOperation::LessThanOrEqual => match value {
            WireValue::Null => (format!("{column} IS NULL"), Vec::new()),
            value => (
                format!("({column} <= ? OR {column} IS NULL)"),
                vec![sqlite_wire_value(value)?],
            ),
        },
        WireFilterOperation::Contains => sqlite_string_like_sql(&column, value, "%", "%")?,
        WireFilterOperation::StartsWith => sqlite_string_like_sql(&column, value, "", "%")?,
        WireFilterOperation::EndsWith => sqlite_string_like_sql(&column, value, "%", "")?,
        WireFilterOperation::LengthEqual
        | WireFilterOperation::LengthLessThan
        | WireFilterOperation::LengthLessThanOrEqual
        | WireFilterOperation::LengthGreaterThan
        | WireFilterOperation::LengthGreaterThanOrEqual => ("FALSE".to_string(), Vec::new()),
    };
    Ok(sql)
}

fn sqlite_list_contains_sql(
    column: &str,
    value: &WireValue,
) -> Result<(String, Vec<Value>), String> {
    let value = sqlite_wire_value(value)?;
    let predicate = match value {
        Value::Null => format!(
            "{column} IS NOT NULL AND EXISTS (SELECT 1 FROM json_each({column}) AS cindel_list WHERE cindel_list.value IS NULL)"
        ),
        value => {
            return Ok((
                format!(
                    "{column} IS NOT NULL AND EXISTS (SELECT 1 FROM json_each({column}) AS cindel_list WHERE cindel_list.value = ?)"
                ),
                vec![value],
            ))
        }
    };
    Ok((predicate, Vec::new()))
}

fn sqlite_list_length_sql(
    column: &str,
    operation: WireFilterOperation,
    value: &WireValue,
) -> Result<(String, Vec<Value>), String> {
    let WireValue::Int(length) = value else {
        return Ok(("FALSE".to_string(), Vec::new()));
    };
    let operator = match operation {
        WireFilterOperation::LengthEqual => "=",
        WireFilterOperation::LengthLessThan => "<",
        WireFilterOperation::LengthLessThanOrEqual => "<=",
        WireFilterOperation::LengthGreaterThan => ">",
        WireFilterOperation::LengthGreaterThanOrEqual => ">=",
        _ => return Err("not a SQLite native list length filter".into()),
    };
    Ok((
        format!("{column} IS NOT NULL AND json_array_length({column}) {operator} ?"),
        vec![Value::Integer(*length)],
    ))
}

fn sqlite_string_like_sql(
    column: &str,
    value: &WireValue,
    prefix: &str,
    suffix: &str,
) -> Result<(String, Vec<Value>), String> {
    let WireValue::String(value) = value else {
        return Ok(("FALSE".to_string(), Vec::new()));
    };
    Ok((
        format!("{column} LIKE ? ESCAPE '\\'"),
        vec![Value::Text(format!(
            "{prefix}{}{suffix}",
            sqlite_escape_like(value)
        ))],
    ))
}

fn sqlite_escape_like(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_")
}

fn sqlite_column_for_field(
    schema: &CollectionSchemaManifest,
    field: &str,
) -> Result<String, String> {
    Ok(sqlite_column_for_schema_field(sqlite_schema_field(
        schema, field,
    )?))
}

fn sqlite_schema_field<'a>(
    schema: &'a CollectionSchemaManifest,
    field: &str,
) -> Result<&'a FieldSchemaManifest, String> {
    schema
        .fields
        .iter()
        .find(|schema_field| schema_field.name == field)
        .ok_or_else(|| {
            format!(
                "field `{field}` is not declared in schema `{}`",
                schema.name
            )
        })
}

fn sqlite_column_for_schema_field(field: &FieldSchemaManifest) -> String {
    if field.is_id {
        SQLITE_ROW_ID_COLUMN.to_string()
    } else {
        field.name.clone()
    }
}

fn sqlite_binary_type(binary_type: &str) -> &str {
    binary_type.strip_suffix('?').unwrap_or(binary_type)
}

fn sqlite_wire_value(value: &WireValue) -> Result<Value, String> {
    match value {
        WireValue::Null => Ok(Value::Null),
        WireValue::Bool(value) => Ok(Value::Integer(i64::from(*value))),
        WireValue::Int(value) => Ok(Value::Integer(*value)),
        WireValue::Double(value) if value.is_finite() => Ok(Value::Real(*value)),
        WireValue::Double(_) => Err("SQLite query double values must be finite".into()),
        WireValue::String(value) => Ok(Value::Text(value.clone())),
        WireValue::List(_) | WireValue::Object(_) => {
            Err("SQLite native SQL filters do not support list or object values yet".into())
        }
    }
}

fn native_document_exists(
    connection: &Connection,
    schema: &CollectionSchemaManifest,
    id: u64,
) -> Result<bool, String> {
    let id = sqlite_id(id)?;
    let sql = format!(
        "SELECT 1 FROM {} WHERE {SQLITE_ROW_ID_COLUMN} = ?1",
        schema.name
    );
    connection
        .query_row(&sql, params![id], |_| Ok(()))
        .optional()
        .map(|value| value.is_some())
        .map_err(|error| error.to_string())
}

fn sqlite_row_wire_value(
    row: &Row<'_>,
    index: usize,
    field: &FieldSchemaManifest,
) -> Result<WireValue, rusqlite::Error> {
    let value = row.get_ref(index)?;
    match (sqlite_binary_type(&field.binary_type), value) {
        (_, ValueRef::Null) => Ok(WireValue::Null),
        ("bool", ValueRef::Integer(value)) => Ok(WireValue::Bool(value != 0)),
        ("int", ValueRef::Integer(value)) => Ok(WireValue::Int(value)),
        ("double", ValueRef::Real(value)) => Ok(WireValue::Double(value)),
        ("double", ValueRef::Integer(value)) => Ok(WireValue::Double(value as f64)),
        ("string", ValueRef::Text(value)) => Ok(WireValue::String(
            std::str::from_utf8(value)
                .map_err(|error| {
                    rusqlite::Error::FromSqlConversionFailure(
                        index,
                        rusqlite::types::Type::Text,
                        Box::new(error),
                    )
                })?
                .to_string(),
        )),
        _ => Err(rusqlite::Error::InvalidColumnType(
            index,
            field.name.clone(),
            value.data_type(),
        )),
    }
}

enum StreamingWireAggregate {
    Count {
        count: u64,
    },
    MinMax {
        order: AggregateOrder,
        best: Option<WireValue>,
    },
    Sum {
        sum: f64,
        count: u64,
        average: bool,
    },
}

impl StreamingWireAggregate {
    fn new(operation: &str) -> Result<Self, String> {
        match operation {
            "count" => Ok(Self::Count { count: 0 }),
            "min" => Ok(Self::MinMax {
                order: AggregateOrder::Min,
                best: None,
            }),
            "max" => Ok(Self::MinMax {
                order: AggregateOrder::Max,
                best: None,
            }),
            "sum" | "average" => Ok(Self::Sum {
                sum: 0.0,
                count: 0,
                average: operation == "average",
            }),
            _ => Err(format!("unknown aggregate operation `{operation}`")),
        }
    }

    fn push(&mut self, value: WireValue) -> Result<(), String> {
        if matches!(value, WireValue::Null) {
            return Ok(());
        }
        match self {
            Self::Count { count } => *count += 1,
            Self::MinMax { order, best } => {
                if !matches!(
                    value,
                    WireValue::Int(_) | WireValue::Double(_) | WireValue::String(_)
                ) {
                    return Err("min/max aggregates require number, string, or null values".into());
                }
                let replace = match best.as_ref() {
                    Some(current) => match order {
                        AggregateOrder::Min => compare_wire_values(&value, current)?.is_lt(),
                        AggregateOrder::Max => compare_wire_values(&value, current)?.is_gt(),
                    },
                    None => true,
                };
                if replace {
                    *best = Some(value);
                }
            }
            Self::Sum {
                sum,
                count,
                average,
            } => {
                let number = wire_number(&value).ok_or_else(|| {
                    let operation = if *average { "average" } else { "sum" };
                    format!("{operation} aggregate requires number or null values")
                })?;
                *sum += number;
                *count += 1;
            }
        }
        Ok(())
    }

    fn finish(self) -> Result<WireScalar, String> {
        match self {
            Self::Count { count } => Ok(WireScalar::Int(count as i64)),
            Self::MinMax { best, .. } => best
                .as_ref()
                .map(wire_value_to_scalar)
                .transpose()?
                .map_or(Ok(WireScalar::Null), Ok),
            Self::Sum {
                sum,
                count,
                average,
            } => {
                if count == 0 {
                    Ok(WireScalar::Null)
                } else {
                    Ok(WireScalar::Double(if average {
                        sum / count as f64
                    } else {
                        sum
                    }))
                }
            }
        }
    }
}

fn aggregate_wire_values(values: &[WireValue], operation: &str) -> Result<WireScalar, String> {
    match operation {
        "count" => Ok(WireScalar::Int(
            values
                .iter()
                .filter(|value| !matches!(value, WireValue::Null))
                .count() as i64,
        )),
        "min" => aggregate_wire_min_max(values, AggregateOrder::Min),
        "max" => aggregate_wire_min_max(values, AggregateOrder::Max),
        "sum" => aggregate_wire_sum(values),
        "average" => aggregate_wire_average(values),
        _ => Err(format!("unknown aggregate operation `{operation}`")),
    }
}

fn aggregate_wire_min_max(
    values: &[WireValue],
    order: AggregateOrder,
) -> Result<WireScalar, String> {
    let mut best: Option<&WireValue> = None;
    for value in values {
        if matches!(value, WireValue::Null) {
            continue;
        }
        if !matches!(
            value,
            WireValue::Int(_) | WireValue::Double(_) | WireValue::String(_)
        ) {
            return Err("min/max aggregates require number, string, or null values".into());
        }
        let replace = match best {
            Some(current) => match order {
                AggregateOrder::Min => compare_wire_values(value, current)?.is_lt(),
                AggregateOrder::Max => compare_wire_values(value, current)?.is_gt(),
            },
            None => true,
        };
        if replace {
            best = Some(value);
        }
    }
    best.map(wire_value_to_scalar)
        .transpose()?
        .map_or(Ok(WireScalar::Null), Ok)
}

fn aggregate_wire_sum(values: &[WireValue]) -> Result<WireScalar, String> {
    let mut sum = 0.0;
    let mut count = 0_u64;
    for value in values {
        if matches!(value, WireValue::Null) {
            continue;
        }
        sum += wire_number(value)
            .ok_or_else(|| "sum aggregate requires number or null values".to_string())?;
        count += 1;
    }
    if count == 0 {
        Ok(WireScalar::Null)
    } else {
        Ok(WireScalar::Double(sum))
    }
}

fn aggregate_wire_average(values: &[WireValue]) -> Result<WireScalar, String> {
    let mut sum = 0.0;
    let mut count = 0_u64;
    for value in values {
        if matches!(value, WireValue::Null) {
            continue;
        }
        sum += wire_number(value)
            .ok_or_else(|| "average aggregate requires number or null values".to_string())?;
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

fn compare_wire_values(left: &WireValue, right: &WireValue) -> Result<std::cmp::Ordering, String> {
    match (left, right) {
        (WireValue::Int(left), WireValue::Int(right)) => Ok(left.cmp(right)),
        (WireValue::Double(left), WireValue::Double(right)) => left
            .partial_cmp(right)
            .ok_or_else(|| "cannot compare NaN aggregate values".to_string()),
        (WireValue::Int(left), WireValue::Double(right)) => (*left as f64)
            .partial_cmp(right)
            .ok_or_else(|| "cannot compare NaN aggregate values".to_string()),
        (WireValue::Double(left), WireValue::Int(right)) => left
            .partial_cmp(&(*right as f64))
            .ok_or_else(|| "cannot compare NaN aggregate values".to_string()),
        (WireValue::String(left), WireValue::String(right)) => Ok(left.cmp(right)),
        _ => Err("min/max aggregates require comparable value types".into()),
    }
}

fn wire_number(value: &WireValue) -> Option<f64> {
    match value {
        WireValue::Int(value) => Some(*value as f64),
        WireValue::Double(value) if value.is_finite() => Some(*value),
        _ => None,
    }
}

fn wire_value_to_scalar(value: &WireValue) -> Result<WireScalar, String> {
    match value {
        WireValue::Null => Ok(WireScalar::Null),
        WireValue::Bool(value) => Ok(WireScalar::Bool(*value)),
        WireValue::Int(value) => Ok(WireScalar::Int(*value)),
        WireValue::Double(value) if value.is_finite() => Ok(WireScalar::Double(*value)),
        WireValue::Double(_) => Err("aggregate double values must be finite".into()),
        WireValue::String(value) => Ok(WireScalar::String(value.clone())),
        WireValue::List(_) | WireValue::Object(_) => {
            Err("aggregates do not support list or object values".into())
        }
    }
}

fn sqlite_index_value(value: &WireIndexValue) -> Result<Value, String> {
    match value {
        WireIndexValue::Null => Ok(Value::Null),
        WireIndexValue::Bool(value) => Ok(Value::Integer(i64::from(*value))),
        WireIndexValue::Int(value) => Ok(Value::Integer(*value)),
        WireIndexValue::Double(value) if value.is_finite() => Ok(Value::Real(*value)),
        WireIndexValue::Double(_) => Err("SQLite query double values must be finite".into()),
        WireIndexValue::String(value) => Ok(Value::Text(value.clone())),
        WireIndexValue::List(_) => {
            Err("SQLite native SQL query sources do not support composite values yet".into())
        }
    }
}

fn reserve_ids(connection: &Connection, collection: &str, count: u32) -> Result<i64, String> {
    let existing = connection
        .query_row(
            "SELECT next_id FROM id_counters WHERE collection = ?1",
            params![collection],
            |row| row.get::<_, i64>(0),
        )
        .optional()
        .map_err(|error| error.to_string())?;

    let Some(next_id) = existing else {
        connection
            .execute(
                "INSERT INTO id_counters (collection, next_id) VALUES (?1, ?2)",
                params![collection, 1 + i64::from(count)],
            )
            .map_err(|error| error.to_string())?;
        return Ok(1);
    };

    if next_id < 1 {
        return Err(format!(
            "id counter for collection `{collection}` is not positive"
        ));
    }
    let following_id = next_id.checked_add(i64::from(count)).ok_or_else(|| {
        format!("id counter for collection `{collection}` exceeds SQLite INTEGER range")
    })?;
    connection
        .execute(
            "UPDATE id_counters SET next_id = ?2 WHERE collection = ?1",
            params![collection, following_id],
        )
        .map_err(|error| error.to_string())?;
    Ok(next_id)
}

fn advance_id_counter(connection: &Connection, collection: &str, id: i64) -> Result<(), String> {
    let next_id = id.checked_add(1).unwrap_or(i64::MAX);
    connection
        .execute(
            r#"
            INSERT INTO id_counters (collection, next_id)
            VALUES (?1, ?2)
            ON CONFLICT(collection) DO UPDATE SET
                next_id = CASE
                    WHEN id_counters.next_id < excluded.next_id
                    THEN excluded.next_id
                    ELSE id_counters.next_id
                END
            "#,
            params![collection, next_id],
        )
        .map(|_| ())
        .map_err(|error| error.to_string())
}

fn put_document_with_indexes(
    connection: &Connection,
    collection: &str,
    id: u64,
    bytes: &[u8],
    indexes: &[IndexEntry],
) -> Result<(), String> {
    ensure_generic_document_tables(connection)?;
    let id = sqlite_id(id)?;
    enforce_unique_indexes(connection, collection, id, indexes)?;
    put_document(connection, collection, id, bytes)?;
    delete_index_entries(connection, collection, id)?;
    insert_index_entries(connection, collection, id, indexes)?;
    advance_id_counter(connection, collection, id)
}

fn put_document(
    connection: &Connection,
    collection: &str,
    id: i64,
    bytes: &[u8],
) -> Result<(), String> {
    connection
        .execute(
            r#"
            INSERT INTO documents (collection, id, bytes)
            VALUES (?1, ?2, ?3)
            ON CONFLICT(collection, id) DO UPDATE SET bytes = excluded.bytes
            "#,
            params![collection, id, bytes],
        )
        .map(|_| ())
        .map_err(|error| error.to_string())
}

fn put_native_documents(
    connection: &Connection,
    schema: &CollectionSchemaManifest,
    documents: &[NativeDocumentWrite],
) -> Result<Option<i64>, String> {
    if documents.is_empty() {
        return Ok(None);
    }
    let fields = native_fields(schema);
    for document in documents {
        enforce_native_unique_indexes(connection, schema, &fields, document)?;
    }
    let values_per_document = fields.len() + 1;
    let batch_limit = SQLITE_MAX_PARAM_COUNT / values_per_document;
    let batch_limit = batch_limit.max(1);
    put_native_documents_cached_chunk_statement(connection, schema, &fields, documents, batch_limit)
}

fn put_native_documents_cached_chunk_statement(
    connection: &Connection,
    schema: &CollectionSchemaManifest,
    fields: &[&FieldSchemaManifest],
    documents: &[NativeDocumentWrite],
    batch_limit: usize,
) -> Result<Option<i64>, String> {
    let mut max_seen_id = None;
    let mut chunks = documents.chunks_exact(batch_limit);
    if documents.len() >= batch_limit {
        let full_chunk_sql = native_insert_sql(&schema.name, fields, batch_limit);
        let mut full_statement = connection
            .prepare(&full_chunk_sql)
            .map_err(|error| error.to_string())?;
        for chunk in &mut chunks {
            execute_native_insert_chunk(
                &mut full_statement,
                schema,
                fields,
                chunk,
                &mut max_seen_id,
            )?;
        }
        drop(full_statement);
    }

    let remainder = chunks.remainder();
    if !remainder.is_empty() {
        let sql = native_insert_sql(&schema.name, fields, remainder.len());
        let mut statement = connection
            .prepare(&sql)
            .map_err(|error| error.to_string())?;
        execute_native_insert_chunk(&mut statement, schema, fields, remainder, &mut max_seen_id)?;
    }

    Ok(max_seen_id)
}

fn execute_native_insert_chunk(
    statement: &mut rusqlite::Statement<'_>,
    schema: &CollectionSchemaManifest,
    fields: &[&FieldSchemaManifest],
    chunk: &[NativeDocumentWrite],
    max_seen_id: &mut Option<i64>,
) -> Result<(), String> {
    let mut parameter_index = 1;
    for document in chunk {
        if document.values.len() != fields.len() {
            return Err(format!(
                "native document field count mismatch for collection `{}`",
                schema.name
            ));
        }
        let id = sqlite_id(document.id)?;
        *max_seen_id = Some((*max_seen_id).map_or(id, |current: i64| current.max(id)));
        statement
            .raw_bind_parameter(parameter_index, id)
            .map_err(|error| error.to_string())?;
        parameter_index += 1;
        for (field, value) in fields.iter().zip(document.values.iter()) {
            bind_native_sql_value(statement, parameter_index, field, value)?;
            parameter_index += 1;
        }
    }
    statement.raw_execute().map_err(|error| error.to_string())?;
    Ok(())
}

enum NativeSqlValueRef<'a> {
    Id(i64),
    Field(&'a FieldSchemaManifest, &'a NativeDocumentValue),
}

fn enforce_native_unique_indexes(
    connection: &Connection,
    schema: &CollectionSchemaManifest,
    fields: &[&FieldSchemaManifest],
    document: &NativeDocumentWrite,
) -> Result<(), String> {
    if document.values.len() != fields.len() {
        return Err(format!(
            "native document field count mismatch for collection `{}`",
            schema.name
        ));
    }
    let id = sqlite_id(document.id)?;
    for field in schema
        .fields
        .iter()
        .filter(|field| field.is_indexed && field.is_index_unique)
    {
        let value = native_document_field_value(schema, fields, document, id, &field.name)?;
        if native_sql_value_is_null(&value) {
            continue;
        }
        enforce_native_unique_index(
            connection,
            schema,
            id,
            &field.name,
            field.is_index_replace,
            &[(field.name.as_str(), value)],
        )?;
    }
    for index in schema
        .composite_indexes
        .iter()
        .filter(|index| index.is_unique)
    {
        let mut values = Vec::with_capacity(index.fields.len());
        let mut has_null = false;
        for field_name in &index.fields {
            let value = native_document_field_value(schema, fields, document, id, field_name)?;
            has_null |= native_sql_value_is_null(&value);
            values.push((field_name.as_str(), value));
        }
        if has_null {
            continue;
        }
        enforce_native_unique_index(
            connection,
            schema,
            id,
            &index.name,
            index.is_replace,
            &values,
        )?;
    }
    Ok(())
}

fn native_document_field_value<'a>(
    schema: &CollectionSchemaManifest,
    fields: &[&'a FieldSchemaManifest],
    document: &'a NativeDocumentWrite,
    id: i64,
    field_name: &str,
) -> Result<NativeSqlValueRef<'a>, String> {
    if field_name == schema.id_field
        || schema
            .fields
            .iter()
            .any(|field| field.name == field_name && field.is_id)
    {
        return Ok(NativeSqlValueRef::Id(id));
    }
    let Some(index) = fields.iter().position(|field| field.name == field_name) else {
        return Err(format!(
            "schema composite index references missing native field `{field_name}`"
        ));
    };
    Ok(NativeSqlValueRef::Field(
        fields[index],
        &document.values[index],
    ))
}

fn native_sql_value_is_null(value: &NativeSqlValueRef<'_>) -> bool {
    matches!(
        value,
        NativeSqlValueRef::Field(_, NativeDocumentValue::Null)
    )
}

fn enforce_native_unique_index(
    connection: &Connection,
    schema: &CollectionSchemaManifest,
    id: i64,
    index_name: &str,
    is_replace: bool,
    values: &[(&str, NativeSqlValueRef<'_>)],
) -> Result<(), String> {
    let mut sql = format!("SELECT {SQLITE_ROW_ID_COLUMN} FROM {} WHERE ", schema.name);
    for (index, (field_name, _)) in values.iter().enumerate() {
        if index > 0 {
            sql.push_str(" AND ");
        }
        if sqlite_schema_field_is_id(schema, field_name) {
            sql.push_str(SQLITE_ROW_ID_COLUMN);
        } else {
            sql.push_str(field_name);
        }
        sql.push_str(" = ?");
        sql.push_str(&(index + 1).to_string());
    }
    let mut statement = connection
        .prepare(&sql)
        .map_err(|error| error.to_string())?;
    for (index, (_, value)) in values.iter().enumerate() {
        bind_native_unique_value(&mut statement, index + 1, value)?;
    }
    let mut rows = statement.raw_query();
    while let Some(row) = rows.next().map_err(|error| error.to_string())? {
        let existing_id = row.get::<_, i64>(0).map_err(|error| error.to_string())?;
        if existing_id == id {
            continue;
        }
        if is_replace {
            delete_document_with_layout(connection, &schema.name, existing_id, true)?;
            continue;
        }
        return Err(format!(
            "Unique index `{}` already contains this value.",
            index_name
        ));
    }
    Ok(())
}

fn bind_native_unique_value(
    statement: &mut rusqlite::Statement<'_>,
    parameter_index: usize,
    value: &NativeSqlValueRef<'_>,
) -> Result<(), String> {
    match value {
        NativeSqlValueRef::Id(id) => statement
            .raw_bind_parameter(parameter_index, id)
            .map_err(|error| error.to_string()),
        NativeSqlValueRef::Field(field, value) => {
            bind_native_sql_value(statement, parameter_index, field, value)
        }
    }
}

fn sqlite_schema_field_is_id(schema: &CollectionSchemaManifest, field: &str) -> bool {
    field == schema.id_field
        || schema
            .fields
            .iter()
            .any(|schema_field| schema_field.name == field && schema_field.is_id)
}

fn native_insert_sql(collection: &str, fields: &[&FieldSchemaManifest], count: usize) -> String {
    let mut sql = String::new();
    sql.push_str("INSERT OR REPLACE INTO ");
    sql.push_str(collection);
    sql.push_str(" (");
    sql.push_str(SQLITE_ROW_ID_COLUMN);
    for field in fields {
        sql.push_str(", ");
        sql.push_str(&field.name);
    }
    sql.push_str(") VALUES ");
    let mut batch = String::from("(?");
    for _ in fields {
        batch.push_str(",?");
    }
    batch.push(')');
    sql.push_str(&batch);
    for _ in 1..count {
        sql.push(',');
        sql.push_str(&batch);
    }
    sql
}

fn delete_native_documents(
    connection: &Connection,
    collection: &str,
    ids: &[u64],
) -> Result<Vec<u64>, String> {
    let sql = format!("DELETE FROM {collection} WHERE {SQLITE_ROW_ID_COLUMN} = ?1");
    let mut statement = connection
        .prepare(&sql)
        .map_err(|error| error.to_string())?;
    let mut deleted_ids = Vec::new();
    for id in ids {
        let id = sqlite_id(*id)?;
        let deleted = statement
            .execute(params![id])
            .map_err(|error| error.to_string())?;
        if deleted > 0 {
            deleted_ids.push(id as u64);
        }
    }
    Ok(deleted_ids)
}

fn bind_native_sql_value(
    statement: &mut rusqlite::Statement<'_>,
    parameter_index: usize,
    field: &FieldSchemaManifest,
    value: &NativeDocumentValue,
) -> Result<(), String> {
    match (field.binary_type.as_str(), value) {
        (_, NativeDocumentValue::Null) => statement.raw_bind_parameter(parameter_index, Null),
        ("bool", NativeDocumentValue::Bool(value)) => {
            statement.raw_bind_parameter(parameter_index, i64::from(*value))
        }
        ("int", NativeDocumentValue::Int(value)) => {
            statement.raw_bind_parameter(parameter_index, *value)
        }
        ("double", NativeDocumentValue::Double(value)) => {
            statement.raw_bind_parameter(parameter_index, *value)
        }
        ("string", NativeDocumentValue::Bytes(value)) => {
            let text = std::str::from_utf8(value).map_err(|error| error.to_string())?;
            statement.raw_bind_parameter(parameter_index, text)
        }
        ("list", NativeDocumentValue::Bytes(value)) => {
            if value.first() == Some(&b'[') {
                let text = std::str::from_utf8(value).map_err(|error| error.to_string())?;
                statement.raw_bind_parameter(parameter_index, text)
            } else if let Ok(text) = native_string_list_json(value) {
                statement.raw_bind_parameter(parameter_index, text.as_str())
            } else {
                statement.raw_bind_parameter(parameter_index, value.as_slice())
            }
        }
        ("object", NativeDocumentValue::Bytes(value)) => {
            statement.raw_bind_parameter(parameter_index, value.as_slice())
        }
        _ => {
            return Err(format!(
                "native value does not match schema field `{}` type `{}`",
                field.name, field.binary_type
            ))
        }
    }
    .map_err(|error| error.to_string())
}

fn native_string_list_json(bytes: &[u8]) -> Result<String, String> {
    let values = decode_list(bytes)?;
    let mut json = String::new();
    json.push('[');
    for (index, value) in values.iter().enumerate() {
        if index > 0 {
            json.push(',');
        }
        match value {
            Some(BinaryValue::String(value)) => push_json_string(&mut json, value)?,
            None => json.push_str("null"),
            _ => return Err("SQLite native string list contains a non-string value".into()),
        }
    }
    json.push(']');
    Ok(json)
}

fn push_json_string(json: &mut String, value: &str) -> Result<(), String> {
    json.push('"');
    for character in value.chars() {
        match character {
            '"' => json.push_str("\\\""),
            '\\' => json.push_str("\\\\"),
            '\n' => json.push_str("\\n"),
            '\r' => json.push_str("\\r"),
            '\t' => json.push_str("\\t"),
            '\u{08}' => json.push_str("\\b"),
            '\u{0c}' => json.push_str("\\f"),
            character if character <= '\u{1f}' => {
                write!(json, "\\u{:04x}", character as u32).map_err(|error| error.to_string())?;
            }
            character => json.push(character),
        }
    }
    json.push('"');
    Ok(())
}

fn get_many_generic_documents(
    connection: &Connection,
    collection: &str,
    ids: &[u64],
) -> Result<Vec<Option<Vec<u8>>>, String> {
    let sqlite_ids = ids
        .iter()
        .map(|id| sqlite_id(*id))
        .collect::<Result<Vec<_>, _>>()?;
    let batch_limit = SQLITE_MAX_PARAM_COUNT.saturating_sub(1).max(1);
    let mut found = HashMap::<i64, Vec<u8>>::with_capacity(sqlite_ids.len());
    for chunk in sqlite_ids.chunks(batch_limit) {
        let sql = format!(
            "SELECT id, bytes FROM documents WHERE collection = ?1 AND id IN {}",
            sqlite_placeholders_from(2, chunk.len())
        );
        let mut params = Vec::with_capacity(chunk.len() + 1);
        params.push(Value::Text(collection.to_string()));
        params.extend(chunk.iter().copied().map(Value::Integer));
        let mut statement = connection
            .prepare(&sql)
            .map_err(|error| error.to_string())?;
        let mut rows = statement
            .query(params_from_iter(params.iter()))
            .map_err(|error| error.to_string())?;
        while let Some(row) = rows.next().map_err(|error| error.to_string())? {
            let id = row.get::<_, i64>(0).map_err(|error| error.to_string())?;
            let document = row
                .get::<_, Vec<u8>>(1)
                .map_err(|error| error.to_string())?;
            found.insert(id, document);
        }
    }
    Ok(sqlite_ids.iter().map(|id| found.get(id).cloned()).collect())
}

fn sqlite_placeholders(count: usize) -> String {
    sqlite_placeholders_from(1, count)
}

fn sqlite_placeholders_from(start: usize, count: usize) -> String {
    let mut sql = String::from("(");
    for index in 0..count {
        if index > 0 {
            sql.push_str(", ");
        }
        sql.push('?');
        sql.push_str(&(start + index).to_string());
    }
    sql.push(')');
    sql
}

fn get_many_native_documents(
    connection: &Connection,
    schema: &CollectionSchemaManifest,
    ids: &[u64],
) -> Result<Vec<Option<Vec<u8>>>, String> {
    if ids.is_empty() {
        return Ok(Vec::new());
    }
    let fields = native_fields(schema);
    let mut select = String::from("SELECT ");
    select.push_str(SQLITE_ROW_ID_COLUMN);
    for field in &fields {
        select.push_str(", ");
        select.push_str(&field.name);
    }
    select.push_str(" FROM ");
    select.push_str(&schema.name);
    select.push_str(" WHERE ");
    select.push_str(SQLITE_ROW_ID_COLUMN);
    select.push_str(" IN ");

    let sqlite_ids = ids
        .iter()
        .map(|id| sqlite_id(*id))
        .collect::<Result<Vec<_>, _>>()?;
    let batch_limit = SQLITE_MAX_PARAM_COUNT.max(1);
    let mut found = HashMap::<i64, Vec<u8>>::with_capacity(sqlite_ids.len());
    for chunk in sqlite_ids.chunks(batch_limit) {
        let sql = format!("{select}{}", sqlite_placeholders(chunk.len()));
        let mut statement = connection
            .prepare(&sql)
            .map_err(|error| error.to_string())?;
        let mut rows = statement
            .query(params_from_iter(chunk.iter()))
            .map_err(|error| error.to_string())?;
        while let Some(row) = rows.next().map_err(|error| error.to_string())? {
            let id = row.get::<_, i64>(0).map_err(|error| error.to_string())?;
            let document =
                native_document_from_row(row, &fields).map_err(|error| error.to_string())?;
            found.insert(id, document);
        }
    }
    Ok(sqlite_ids.iter().map(|id| found.get(id).cloned()).collect())
}

fn native_document_from_row(
    row: &Row<'_>,
    fields: &[&FieldSchemaManifest],
) -> rusqlite::Result<Vec<u8>> {
    let mut layout = NativeDocumentLayout::new(fields);
    let mut bytes = Vec::with_capacity(3 + layout.static_size);
    bytes.resize(3 + layout.static_size, 0);
    write_u24_le(&mut bytes, 0, layout.static_size)
        .map_err(|error| rusqlite::Error::ToSqlConversionFailure(error.into()))?;
    for (index, field) in fields.iter().enumerate() {
        let value = row.get_ref(index + 1)?;
        write_native_row_value(&mut bytes, &mut layout, index, field, value)
            .map_err(|error| rusqlite::Error::ToSqlConversionFailure(error.into()))?;
    }
    Ok(bytes)
}

struct NativeDocumentLayout {
    offsets: Vec<usize>,
    static_size: usize,
}

impl NativeDocumentLayout {
    fn new(fields: &[&FieldSchemaManifest]) -> Self {
        let mut offsets = Vec::with_capacity(fields.len());
        let mut static_size = 0usize;
        for field in fields {
            offsets.push(static_size);
            static_size += native_field_static_size(field);
        }
        Self {
            offsets,
            static_size,
        }
    }
}

fn native_field_static_size(field: &FieldSchemaManifest) -> usize {
    match field.binary_type.as_str() {
        "bool" => 1,
        "int" | "double" => 8,
        "string" | "list" | "object" => 3,
        _ => 3,
    }
}

fn write_native_row_value(
    bytes: &mut Vec<u8>,
    layout: &mut NativeDocumentLayout,
    index: usize,
    field: &FieldSchemaManifest,
    value: ValueRef<'_>,
) -> Result<(), String> {
    let offset = 3 + layout
        .offsets
        .get(index)
        .copied()
        .ok_or_else(|| format!("native field index `{index}` is out of range"))?;
    match (field.binary_type.as_str(), value) {
        ("bool", ValueRef::Integer(value)) => {
            bytes[offset] = if value == 0 { 0 } else { 1 };
        }
        ("bool", ValueRef::Null) => bytes[offset] = 0xff,
        ("int", ValueRef::Integer(value)) => {
            bytes[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
        }
        ("int", ValueRef::Null) => {
            bytes[offset..offset + 8].copy_from_slice(&i64::MIN.to_le_bytes());
        }
        ("double", ValueRef::Real(value)) => {
            bytes[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
        }
        ("double", ValueRef::Integer(value)) => {
            let value = value as f64;
            bytes[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
        }
        ("double", ValueRef::Null) => {
            bytes[offset..offset + 8].copy_from_slice(&0x7ff8_0000_0000_0001u64.to_le_bytes());
        }
        ("string", ValueRef::Text(value)) => write_native_dynamic(bytes, layout, offset, value)?,
        ("list", ValueRef::Text(value)) => write_native_dynamic(bytes, layout, offset, value)?,
        ("list" | "object", ValueRef::Blob(value)) => {
            write_native_dynamic(bytes, layout, offset, value)?
        }
        ("string" | "list" | "object", ValueRef::Null) => write_u24_le(bytes, offset, 0)?,
        _ => {
            return Err(format!(
                "SQLite value does not match native field `{}` type `{}`",
                field.name, field.binary_type
            ));
        }
    }
    Ok(())
}

fn write_native_dynamic(
    bytes: &mut Vec<u8>,
    layout: &NativeDocumentLayout,
    offset: usize,
    payload: &[u8],
) -> Result<(), String> {
    if payload.len() > 0x00ff_ffff {
        return Err("native dynamic payload is too large".into());
    }
    let relative = layout
        .static_size
        .checked_add(bytes.len().saturating_sub(3 + layout.static_size))
        .ok_or_else(|| "native dynamic offset overflow".to_string())?;
    write_u24_le(bytes, offset, relative)?;
    let mut header = [0u8; 3];
    write_u24_le(&mut header, 0, payload.len())?;
    bytes.extend_from_slice(&header);
    bytes.extend_from_slice(payload);
    Ok(())
}

fn write_u24_le(bytes: &mut [u8], offset: usize, value: usize) -> Result<(), String> {
    if value > 0x00ff_ffff || offset + 3 > bytes.len() {
        return Err("native uint24 write is out of range".into());
    }
    bytes[offset] = (value & 0xff) as u8;
    bytes[offset + 1] = ((value >> 8) & 0xff) as u8;
    bytes[offset + 2] = ((value >> 16) & 0xff) as u8;
    Ok(())
}

fn delete_document_with_layout(
    connection: &Connection,
    collection: &str,
    id: i64,
    has_collection_table: bool,
) -> Result<bool, String> {
    let mut deleted = 0usize;
    if has_collection_table {
        let sql = format!("DELETE FROM {collection} WHERE {SQLITE_ROW_ID_COLUMN} = ?1");
        deleted += connection
            .execute(&sql, params![id])
            .map_err(|error| error.to_string())?;
    }
    if table_exists(connection, "documents")? {
        deleted += connection
            .execute(
                "DELETE FROM documents WHERE collection = ?1 AND id = ?2",
                params![collection, id],
            )
            .map_err(|error| error.to_string())?;
    }
    if table_exists(connection, "index_entries")? {
        delete_index_entries(connection, collection, id)?;
    }
    Ok(deleted > 0)
}

fn delete_index_entries(connection: &Connection, collection: &str, id: i64) -> Result<(), String> {
    connection
        .execute(
            "DELETE FROM index_entries WHERE collection = ?1 AND document_id = ?2",
            params![collection, id],
        )
        .map(|_| ())
        .map_err(|error| error.to_string())
}

#[allow(dead_code)]
fn rebuild_indexes_on_connection(
    connection: &Connection,
    collection: &str,
    documents: &[DocumentWrite],
) -> Result<(), String> {
    connection
        .execute(
            "DELETE FROM index_entries WHERE collection = ?1",
            params![collection],
        )
        .map_err(|error| error.to_string())?;
    for document in documents {
        let id = sqlite_id(document.id)?;
        ensure_document_exists(connection, collection, id)?;
        enforce_unique_indexes(connection, collection, id, &document.indexes)?;
        insert_index_entries(connection, collection, id, &document.indexes)?;
    }
    Ok(())
}

#[allow(dead_code)]
fn ensure_document_exists(
    connection: &Connection,
    collection: &str,
    id: i64,
) -> Result<(), String> {
    let exists = if collection_schema(connection, collection)?.is_some() {
        let sql = format!(
            "SELECT 1 FROM (
                SELECT {SQLITE_ROW_ID_COLUMN} AS id FROM {collection}
                UNION
                SELECT id FROM documents WHERE collection = ?2
            ) WHERE id = ?1"
        );
        connection
            .query_row(&sql, params![id, collection], |_| Ok(()))
            .optional()
            .map_err(|error| error.to_string())?
            .is_some()
    } else {
        connection
            .query_row(
                "SELECT 1 FROM documents WHERE collection = ?1 AND id = ?2",
                params![collection, id],
                |_| Ok(()),
            )
            .optional()
            .map_err(|error| error.to_string())?
            .is_some()
    };
    if exists {
        Ok(())
    } else {
        Err(format!(
            "cannot rebuild indexes for missing document `{collection}`.`{id}`"
        ))
    }
}

fn enforce_unique_indexes(
    connection: &Connection,
    collection: &str,
    id: i64,
    indexes: &[IndexEntry],
) -> Result<(), String> {
    let unique_indexes = unique_index_options(connection, collection)?;
    if unique_indexes.is_empty() {
        return Ok(());
    }

    for index in indexes {
        let Some(is_replace) = unique_indexes.get(index.name.as_str()).copied() else {
            continue;
        };
        let existing_ids = query_index(
            connection,
            collection,
            &index.name,
            Some(&index.value),
            Some(&index.value),
        )?;
        for existing_id in existing_ids {
            let existing_id = sqlite_id(existing_id)?;
            if existing_id != id {
                if is_replace {
                    let has_collection_table = collection_schema(connection, collection)?.is_some();
                    delete_document_with_layout(
                        connection,
                        collection,
                        existing_id,
                        has_collection_table,
                    )?;
                    continue;
                }
                return Err(format!(
                    "Unique index `{}` already contains this value.",
                    index.name
                ));
            }
        }
    }
    Ok(())
}

fn unique_index_options(
    connection: &Connection,
    collection: &str,
) -> Result<std::collections::HashMap<String, bool>, String> {
    if !table_exists(connection, "schema_collections")? {
        return Ok(std::collections::HashMap::new());
    }
    let schema_bytes = connection
        .query_row(
            "SELECT schema_bytes FROM schema_collections WHERE collection = ?1",
            params![collection],
            |row| row.get::<_, Vec<u8>>(0),
        )
        .optional()
        .map_err(|error| error.to_string())?;
    let Some(schema_bytes) = schema_bytes else {
        return Ok(std::collections::HashMap::new());
    };
    let (_, schema) = decode_schema_record(&schema_bytes)?;
    let mut indexes = std::collections::HashMap::new();
    for field in schema
        .fields
        .into_iter()
        .filter(|field| field.is_indexed && field.is_index_unique)
    {
        indexes.insert(field.name, field.is_index_replace);
    }
    for index in schema
        .composite_indexes
        .into_iter()
        .filter(|index| index.is_unique)
    {
        indexes.insert(index.name, index.is_replace);
    }
    Ok(indexes)
}

fn insert_index_entries(
    connection: &Connection,
    collection: &str,
    id: i64,
    indexes: &[IndexEntry],
) -> Result<(), String> {
    for index in indexes {
        let key = SqliteIndexKey::from(&index.value)?;
        connection
            .execute(
                r#"
                INSERT INTO index_entries (
                    collection,
                    index_name,
                    value_kind,
                    int_value,
                    real_value,
                    text_value,
                    document_id
                )
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                "#,
                params![
                    collection,
                    index.name,
                    key.kind,
                    key.int_value,
                    key.real_value,
                    key.text_value,
                    id,
                ],
            )
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn ensure_storage_metadata(
    connection: &Connection,
    layout: StorageLayoutVersion,
    document_format: DocumentFormatVersion,
    schema_metadata_format: SchemaMetadataVersion,
) -> Result<(), String> {
    connection
        .execute(
            "INSERT OR IGNORE INTO storage_metadata (key, value) VALUES (?1, ?2)",
            params!["storage_layout", layout.as_str()],
        )
        .map_err(|error| error.to_string())?;
    connection
        .execute(
            "INSERT OR IGNORE INTO storage_metadata (key, value) VALUES (?1, ?2)",
            params!["document_format", document_format.as_str()],
        )
        .map_err(|error| error.to_string())?;
    connection
        .execute(
            "INSERT OR IGNORE INTO storage_metadata (key, value) VALUES (?1, ?2)",
            params!["schema_metadata_format", schema_metadata_format.as_str()],
        )
        .map_err(|error| error.to_string())?;
    Ok(())
}

fn ensure_binary_schema_collections_table(connection: &Connection) -> Result<(), String> {
    let columns = schema_collection_columns(connection)?;
    if columns.iter().any(|column| column == "schema_json")
        || !columns.iter().any(|column| column == "schema_bytes")
    {
        let row_count = connection
            .query_row("SELECT COUNT(*) FROM schema_collections", [], |row| {
                row.get::<_, i64>(0)
            })
            .map_err(|error| error.to_string())?;
        if row_count > 0 {
            return Err(
                "JSON-era preview schema metadata is incompatible with Cindel binary metadata; recreate the database"
                    .into(),
            );
        }
        connection
            .execute("DROP TABLE schema_collections", [])
            .map_err(|error| error.to_string())?;
        connection
            .execute(
                r#"
                CREATE TABLE schema_collections (
                    collection TEXT PRIMARY KEY NOT NULL,
                    version INTEGER NOT NULL,
                    schema_bytes BLOB NOT NULL
                )
                "#,
                [],
            )
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn schema_collection_columns(connection: &Connection) -> Result<Vec<String>, String> {
    let mut statement = connection
        .prepare("PRAGMA table_info(schema_collections)")
        .map_err(|error| error.to_string())?;
    let rows = statement
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(|error| error.to_string())?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| error.to_string())
}

fn validate_schema_metadata_records(connection: &Connection) -> Result<(), String> {
    let mut statement = connection
        .prepare("SELECT schema_bytes FROM schema_collections")
        .map_err(|error| error.to_string())?;
    let rows = statement
        .query_map([], |row| row.get::<_, Vec<u8>>(0))
        .map_err(|error| error.to_string())?;
    for row in rows {
        let bytes = row.map_err(|error| error.to_string())?;
        decode_schema_record(&bytes)?;
    }
    Ok(())
}

fn validate_storage_metadata(
    connection: &Connection,
    layout: StorageLayoutVersion,
    document_format: DocumentFormatVersion,
    schema_metadata_format: SchemaMetadataVersion,
) -> Result<(), String> {
    let metadata = read_storage_metadata(connection)?;
    if metadata.layout != layout {
        return Err(format!(
            "unsupported SQLite storage layout `{}`",
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
        return Err("unsupported SQLite schema metadata format; recreate the database".into());
    }
    Ok(())
}

#[allow(dead_code)]
fn read_storage_metadata(connection: &Connection) -> Result<StorageMetadata, String> {
    let layout = connection
        .query_row(
            "SELECT value FROM storage_metadata WHERE key = 'storage_layout'",
            [],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|error| error.to_string())?
        .unwrap_or_else(|| StorageLayoutVersion::SqliteV1.as_str().to_string());
    let document_format = connection
        .query_row(
            "SELECT value FROM storage_metadata WHERE key = 'document_format'",
            [],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|error| error.to_string())?
        .unwrap_or_else(|| DocumentFormatVersion::BinaryV2.as_str().to_string());
    let schema_metadata_format = connection
        .query_row(
            "SELECT value FROM storage_metadata WHERE key = 'schema_metadata_format'",
            [],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|error| error.to_string())?
        .unwrap_or_else(|| SchemaMetadataVersion::BinaryV1.as_str().to_string());
    Ok(StorageMetadata {
        layout: parse_storage_layout(&layout)?,
        document_format: parse_document_format(&document_format)?,
        schema_metadata_format: super::metadata::parse_schema_metadata_format(
            &schema_metadata_format,
        )?,
    })
}

fn read_migration_version(connection: &Connection) -> Result<Option<u64>, String> {
    if !table_exists(connection, "storage_metadata")? {
        return Ok(None);
    }
    connection
        .query_row(
            "SELECT value FROM storage_metadata WHERE key = 'data_migration_version'",
            [],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|error| error.to_string())?
        .map(|value| value.parse::<u64>().map_err(|error| error.to_string()))
        .transpose()
}

fn write_migration_version(connection: &Connection, version: u64) -> Result<(), String> {
    connection
        .execute(
            r#"
            CREATE TABLE IF NOT EXISTS storage_metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            )
            "#,
            [],
        )
        .map_err(|error| error.to_string())?;
    connection
        .execute(
            r#"
            INSERT INTO storage_metadata (key, value)
            VALUES ('data_migration_version', ?1)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            "#,
            params![version.to_string()],
        )
        .map(|_| ())
        .map_err(|error| error.to_string())
}

#[allow(dead_code)]
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

#[allow(dead_code)]
fn parse_document_format(value: &str) -> Result<DocumentFormatVersion, String> {
    match value {
        "json-v1" => Ok(DocumentFormatVersion::JsonV1),
        "binary-v1" => Ok(DocumentFormatVersion::BinaryV1),
        "binary-v2" => Ok(DocumentFormatVersion::BinaryV2),
        _ => Err(format!("unknown document format version `{value}`")),
    }
}

fn bump_collection_revision(connection: &Connection, collection: &str) -> Result<u64, String> {
    connection
        .execute(
            r#"
            INSERT INTO collection_revisions (collection, revision)
            VALUES (?1, 1)
            ON CONFLICT(collection) DO UPDATE SET
                revision = collection_revisions.revision + 1
            "#,
            params![collection],
        )
        .map_err(|error| error.to_string())?;
    connection
        .query_row(
            "SELECT revision FROM collection_revisions WHERE collection = ?1",
            params![collection],
            |row| row.get::<_, i64>(0),
        )
        .map_err(|error| error.to_string())
        .and_then(|revision| u64::try_from(revision).map_err(|error| error.to_string()))
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

fn ensure_id_counters_table(connection: &Connection) -> Result<(), String> {
    connection
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS id_counters (
            collection TEXT PRIMARY KEY NOT NULL,
            next_id INTEGER NOT NULL
        )",
        )
        .map_err(|error| error.to_string())
}

fn ensure_base_tables(connection: &Connection) -> Result<(), String> {
    connection
        .execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS documents (
                collection TEXT NOT NULL,
                id INTEGER NOT NULL,
                bytes BLOB NOT NULL,
                PRIMARY KEY (collection, id)
            );

            CREATE TABLE IF NOT EXISTS index_entries (
                collection TEXT NOT NULL,
                index_name TEXT NOT NULL,
                value_kind INTEGER NOT NULL,
                int_value INTEGER,
                real_value REAL,
                text_value TEXT,
                document_id INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS collection_revisions (
                collection TEXT PRIMARY KEY NOT NULL,
                revision INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS id_counters (
                collection TEXT PRIMARY KEY NOT NULL,
                next_id INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS schema_collections (
                collection TEXT PRIMARY KEY NOT NULL,
                version INTEGER NOT NULL,
                schema_bytes BLOB NOT NULL
            );

            CREATE TABLE IF NOT EXISTS storage_metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS cindel_index_entries_lookup
            ON index_entries (
                collection,
                index_name,
                value_kind,
                int_value,
                real_value,
                text_value,
                document_id
            );
            "#,
        )
        .map_err(|error| error.to_string())
}

fn ensure_relation_tables(connection: &Connection) -> Result<(), String> {
    connection
        .execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS cindel_relations (
                source_collection TEXT NOT NULL,
                source_id INTEGER NOT NULL,
                link_name TEXT NOT NULL,
                target_collection TEXT NOT NULL,
                target_id INTEGER NOT NULL,
                PRIMARY KEY (
                    source_collection,
                    source_id,
                    link_name,
                    target_collection,
                    target_id
                )
            );

            CREATE INDEX IF NOT EXISTS cindel_relations_backlink_idx
            ON cindel_relations (
                target_collection,
                target_id,
                source_collection,
                link_name,
                source_id
            );
            "#,
        )
        .map_err(|error| error.to_string())
}

fn replace_links_sqlite(
    connection: &Connection,
    links: &LinkSave,
    target_ids: &[u64],
) -> Result<(), String> {
    ensure_relation_tables(connection)?;
    ensure_sqlite_document_exists(connection, &links.source_collection, links.source_id).map_err(
        |_| {
            format!(
                "cannot save link `{}`: source `{}.{}` does not exist",
                links.link_name, links.source_collection, links.source_id
            )
        },
    )?;
    for target_id in target_ids {
        ensure_sqlite_document_exists(connection, &links.target_collection, *target_id).map_err(
            |_| {
                format!(
                    "cannot save link `{}`: target `{}.{}` does not exist",
                    links.link_name, links.target_collection, target_id
                )
            },
        )?;
    }

    connection
        .execute(
            r#"
            DELETE FROM cindel_relations
            WHERE source_collection = ?1
              AND source_id = ?2
              AND link_name = ?3
              AND target_collection = ?4
            "#,
            params![
                links.source_collection,
                sqlite_id(links.source_id)?,
                links.link_name,
                links.target_collection
            ],
        )
        .map_err(|error| error.to_string())?;
    let mut statement = connection
        .prepare(
            r#"
            INSERT INTO cindel_relations (
                source_collection,
                source_id,
                link_name,
                target_collection,
                target_id
            )
            VALUES (?1, ?2, ?3, ?4, ?5)
            "#,
        )
        .map_err(|error| error.to_string())?;
    for target_id in target_ids {
        statement
            .execute(params![
                links.source_collection,
                sqlite_id(links.source_id)?,
                links.link_name,
                links.target_collection,
                sqlite_id(*target_id)?
            ])
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn ensure_sqlite_document_exists(
    connection: &Connection,
    collection: &str,
    id: u64,
) -> Result<(), String> {
    let id = sqlite_id(id)?;
    let generic_exists = table_exists(connection, "documents")?
        && connection
            .query_row(
                "SELECT 1 FROM documents WHERE collection = ?1 AND id = ?2",
                params![collection, id],
                |_| Ok(()),
            )
            .optional()
            .map_err(|error| error.to_string())?
            .is_some();
    if generic_exists {
        return Ok(());
    }
    if table_exists(connection, collection)? {
        let sql = format!("SELECT 1 FROM {collection} WHERE {SQLITE_ROW_ID_COLUMN} = ?1");
        if connection
            .query_row(&sql, params![id], |_| Ok(()))
            .optional()
            .map_err(|error| error.to_string())?
            .is_some()
        {
            return Ok(());
        }
    }
    Err("missing document".into())
}

fn dedupe_sorted_ids(ids: &[u64]) -> Vec<u64> {
    let mut ids = ids.to_vec();
    ids.sort_unstable();
    ids.dedup();
    ids
}

fn ensure_generic_document_tables(connection: &Connection) -> Result<(), String> {
    connection
        .execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS documents (
                collection TEXT NOT NULL,
                id INTEGER NOT NULL,
                bytes BLOB NOT NULL,
                PRIMARY KEY (collection, id)
            );

            CREATE TABLE IF NOT EXISTS index_entries (
                collection TEXT NOT NULL,
                index_name TEXT NOT NULL,
                value_kind INTEGER NOT NULL,
                int_value INTEGER,
                real_value REAL,
                text_value TEXT,
                document_id INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS collection_revisions (
                collection TEXT PRIMARY KEY NOT NULL,
                revision INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS id_counters (
                collection TEXT PRIMARY KEY NOT NULL,
                next_id INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS cindel_index_entries_lookup
            ON index_entries (
                collection,
                index_name,
                value_kind,
                int_value,
                real_value,
                text_value,
                document_id
            );
            "#,
        )
        .map_err(|error| error.to_string())
}

fn table_exists(connection: &Connection, table: &str) -> Result<bool, String> {
    connection
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            params![table],
            |_| Ok(()),
        )
        .optional()
        .map(|value| value.is_some())
        .map_err(|error| error.to_string())
}

fn validate_schema_manifest(manifest: &SchemaManifest) -> Result<(), String> {
    let mut names = std::collections::HashSet::new();
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

fn register_persisted_collection_schema(
    connection: &Connection,
    collection: &CollectionSchemaManifest,
) -> Result<(), String> {
    let existing = connection
        .query_row(
            "SELECT version, schema_bytes FROM schema_collections WHERE collection = ?1",
            params![collection.name],
            |row| Ok((row.get::<_, i64>(0)?, row.get::<_, Vec<u8>>(1)?)),
        )
        .optional()
        .map_err(|error| error.to_string())?;

    let Some((version, schema_bytes)) = existing else {
        let schema_bytes = encode_schema_record(1, collection)?;
        connection
            .execute(
                r#"
                INSERT INTO schema_collections (collection, version, schema_bytes)
                VALUES (?1, 1, ?2)
                "#,
                params![collection.name, schema_bytes],
            )
            .map_err(|error| error.to_string())?;
        create_collection_table(connection, collection)?;
        return Ok(());
    };

    let (stored_version, existing_schema) = decode_schema_record(&schema_bytes)?;
    let stored_version = i64::try_from(stored_version).map_err(|error| error.to_string())?;
    if stored_version != version {
        return Err(format!(
            "schema metadata version mismatch for `{}`",
            collection.name
        ));
    }
    if existing_schema == *collection {
        create_collection_table(connection, collection)?;
        return Ok(());
    }

    validate_compatible_schema_change(&existing_schema, collection)?;

    let next_version = version + 1;
    let schema_bytes = encode_schema_record(
        u64::try_from(next_version).map_err(|error| error.to_string())?,
        collection,
    )?;
    connection
        .execute(
            r#"
            UPDATE schema_collections
            SET version = ?2, schema_bytes = ?3
            WHERE collection = ?1
            "#,
            params![collection.name, next_version, schema_bytes],
        )
        .map_err(|error| error.to_string())?;
    create_collection_table(connection, collection)?;
    Ok(())
}

fn register_migrated_collection_schema(
    connection: &Connection,
    collection: &CollectionSchemaManifest,
) -> Result<(), String> {
    let existing = connection
        .query_row(
            "SELECT version FROM schema_collections WHERE collection = ?1",
            params![collection.name],
            |row| row.get::<_, i64>(0),
        )
        .optional()
        .map_err(|error| error.to_string())?;
    let next_version = match existing {
        Some(version) => version
            .checked_add(1)
            .ok_or_else(|| format!("schema version for `{}` overflowed", collection.name))?,
        None => 1,
    };
    let schema_bytes = encode_schema_record(
        u64::try_from(next_version).map_err(|error| error.to_string())?,
        collection,
    )?;

    if table_exists(connection, &collection.name)? {
        let sql = format!("DROP TABLE {}", collection.name);
        connection
            .execute(&sql, [])
            .map_err(|error| error.to_string())?;
    }
    connection
        .execute(
            "DELETE FROM documents WHERE collection = ?1",
            params![collection.name],
        )
        .map_err(|error| error.to_string())?;
    connection
        .execute(
            "DELETE FROM index_entries WHERE collection = ?1",
            params![collection.name],
        )
        .map_err(|error| error.to_string())?;
    connection
        .execute(
            r#"
            INSERT INTO schema_collections (collection, version, schema_bytes)
            VALUES (?1, ?2, ?3)
            ON CONFLICT(collection) DO UPDATE
            SET version = excluded.version,
                schema_bytes = excluded.schema_bytes
            "#,
            params![collection.name, next_version, schema_bytes],
        )
        .map_err(|error| error.to_string())?;
    create_collection_table(connection, collection)
}

fn persisted_schema_version(
    connection: &Connection,
    collection: &str,
) -> Result<Option<u64>, String> {
    connection
        .query_row(
            "SELECT version FROM schema_collections WHERE collection = ?1",
            params![collection],
            |row| row.get::<_, i64>(0),
        )
        .optional()
        .map_err(|error| error.to_string())?
        .map(u64::try_from)
        .transpose()
        .map_err(|error| error.to_string())
}

fn validate_collection_schema(collection: &CollectionSchemaManifest) -> Result<(), String> {
    if collection.id_field.trim().is_empty() {
        return Err(format!(
            "schema collection `{}` must declare an id field",
            collection.name
        ));
    }

    let mut names = std::collections::HashSet::new();
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
            && (field.is_index_unique
                || field.is_index_replace
                || !field.index_case_sensitive
                || field.index_type != "value")
        {
            return Err(format!(
                "schema field `{}.{}` declares index options without an index",
                collection.name, field.name
            ));
        }
        if field.is_index_replace && !field.is_index_unique {
            return Err(format!(
                "schema field `{}.{}` declares replace without a unique index",
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
        if index.is_replace && !index.is_unique {
            return Err(format!(
                "schema composite index `{}.{}` declares replace without a unique index",
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

fn collection_schema(
    connection: &Connection,
    collection: &str,
) -> Result<Option<CollectionSchemaManifest>, String> {
    let schema_bytes = connection
        .query_row(
            "SELECT schema_bytes FROM schema_collections WHERE collection = ?1",
            params![collection],
            |row| row.get::<_, Vec<u8>>(0),
        )
        .optional()
        .map_err(|error| error.to_string())?;
    schema_bytes
        .map(|bytes| decode_schema_record(&bytes).map(|(_, schema)| schema))
        .transpose()
}

fn create_collection_table(
    connection: &Connection,
    collection: &CollectionSchemaManifest,
) -> Result<(), String> {
    let fields = native_fields(collection);
    let mut sql = format!(
        "CREATE TABLE IF NOT EXISTS {} ({} INTEGER PRIMARY KEY",
        collection.name, SQLITE_ROW_ID_COLUMN
    );
    for field in fields {
        sql.push_str(", ");
        sql.push_str(&field.name);
        sql.push(' ');
        sql.push_str(sql_type_for_field(field));
    }
    sql.push(')');
    connection
        .execute(&sql, [])
        .map_err(|error| error.to_string())?;
    // Bootstrap databases written before typed IDs had persisted counters.
    // Reopening or registering schemas must never lower an existing counter.
    let max_id = connection
        .query_row(
            &format!(
                "SELECT MAX({SQLITE_ROW_ID_COLUMN}) FROM {}",
                collection.name
            ),
            [],
            |row| row.get::<_, Option<i64>>(0),
        )
        .map_err(|error| error.to_string())?;
    if let Some(max_id) = max_id {
        advance_id_counter(connection, &collection.name, max_id)?;
    }
    Ok(())
}

fn native_fields(collection: &CollectionSchemaManifest) -> Vec<&FieldSchemaManifest> {
    let mut fields = collection
        .fields
        .iter()
        .filter(|field| !field.is_id)
        .collect::<Vec<_>>();
    fields.sort_by(|left, right| left.name.cmp(&right.name));
    fields
}

fn sql_type_for_field(field: &FieldSchemaManifest) -> &'static str {
    match field.binary_type.as_str() {
        "bool" => "bool",
        "int" => "i64",
        "double" => "f64",
        "string" => "str",
        "list" => "str[]",
        "object" => "json",
        _ => "json",
    }
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
        || existing.is_index_replace != next.is_index_replace
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

fn query_index(
    connection: &Connection,
    collection: &str,
    index: &str,
    lower: Option<&IndexValue>,
    upper: Option<&IndexValue>,
) -> Result<Vec<u64>, String> {
    if !table_exists(connection, "index_entries")? {
        return Ok(Vec::new());
    }
    let lower = lower.map(SqliteIndexKey::from).transpose()?;
    let upper = upper.map(SqliteIndexKey::from).transpose()?;
    let kind = match (&lower, &upper) {
        (Some(lower), Some(upper)) if lower.kind == upper.kind => lower.kind,
        (Some(lower), None) => lower.kind,
        (None, Some(upper)) => upper.kind,
        (Some(_), Some(_)) => return Err("index range bounds must have matching types".into()),
        (None, None) => return Err("index range requires at least one bound".into()),
    };

    match kind {
        INDEX_KIND_BOOL | INDEX_KIND_INT => query_numeric_index(
            connection,
            collection,
            index,
            kind,
            lower.as_ref().and_then(|key| key.int_value),
            upper.as_ref().and_then(|key| key.int_value),
            "int_value",
        ),
        INDEX_KIND_DOUBLE => query_real_index(
            connection,
            collection,
            index,
            lower.as_ref().and_then(|key| key.real_value),
            upper.as_ref().and_then(|key| key.real_value),
        ),
        INDEX_KIND_STRING | INDEX_KIND_LIST => query_text_index(
            connection,
            collection,
            index,
            kind,
            lower.as_ref().and_then(|key| key.text_value.as_deref()),
            upper.as_ref().and_then(|key| key.text_value.as_deref()),
        ),
        _ => Err("unsupported index value kind".into()),
    }
}

fn query_numeric_index(
    connection: &Connection,
    collection: &str,
    index: &str,
    kind: i64,
    lower: Option<i64>,
    upper: Option<i64>,
    column: &str,
) -> Result<Vec<u64>, String> {
    let sql = format!(
        r#"
        SELECT document_id
        FROM index_entries
        WHERE collection = ?1
          AND index_name = ?2
          AND value_kind = ?3
          AND (?4 IS NULL OR {column} >= ?4)
          AND (?5 IS NULL OR {column} <= ?5)
        ORDER BY {column}, document_id
        "#
    );
    query_ids(
        connection,
        &sql,
        params![collection, index, kind, lower, upper],
    )
}

fn query_real_index(
    connection: &Connection,
    collection: &str,
    index: &str,
    lower: Option<f64>,
    upper: Option<f64>,
) -> Result<Vec<u64>, String> {
    query_ids(
        connection,
        r#"
        SELECT document_id
        FROM index_entries
        WHERE collection = ?1
          AND index_name = ?2
          AND value_kind = ?3
          AND (?4 IS NULL OR real_value >= ?4)
          AND (?5 IS NULL OR real_value <= ?5)
        ORDER BY real_value, document_id
        "#,
        params![collection, index, INDEX_KIND_DOUBLE, lower, upper],
    )
}

fn query_text_index(
    connection: &Connection,
    collection: &str,
    index: &str,
    kind: i64,
    lower: Option<&str>,
    upper: Option<&str>,
) -> Result<Vec<u64>, String> {
    query_ids(
        connection,
        r#"
        SELECT document_id
        FROM index_entries
        WHERE collection = ?1
          AND index_name = ?2
          AND value_kind = ?3
          AND (?4 IS NULL OR text_value >= ?4)
          AND (?5 IS NULL OR text_value <= ?5)
        ORDER BY text_value, document_id
        "#,
        params![collection, index, kind, lower, upper],
    )
}

fn query_ids<P>(connection: &Connection, sql: &str, params: P) -> Result<Vec<u64>, String>
where
    P: rusqlite::Params,
{
    let mut statement = connection.prepare(sql).map_err(|error| error.to_string())?;
    let rows = statement
        .query_map(params, |row| row.get::<_, i64>(0))
        .map_err(|error| error.to_string())?;
    let mut ids = Vec::new();
    for row in rows {
        let id = row.map_err(|error| error.to_string())?;
        ids.push(u64::try_from(id).map_err(|error| error.to_string())?);
    }
    Ok(ids)
}

fn optional_sql_id(id: Option<u64>) -> Result<Option<i64>, String> {
    id.map(|value| i64::try_from(value).map_err(|error| error.to_string()))
        .transpose()
}

const INDEX_KIND_BOOL: i64 = 1;
const INDEX_KIND_INT: i64 = 2;
const INDEX_KIND_DOUBLE: i64 = 3;
const INDEX_KIND_STRING: i64 = 4;
const INDEX_KIND_LIST: i64 = 5;

struct SqliteIndexKey {
    kind: i64,
    int_value: Option<i64>,
    real_value: Option<f64>,
    text_value: Option<String>,
}

impl SqliteIndexKey {
    fn from(value: &IndexValue) -> Result<Self, String> {
        match value {
            IndexValue::Bool(value) => Ok(Self {
                kind: INDEX_KIND_BOOL,
                int_value: Some(if *value { 1 } else { 0 }),
                real_value: None,
                text_value: None,
            }),
            IndexValue::Int(value) => Ok(Self {
                kind: INDEX_KIND_INT,
                int_value: Some(*value),
                real_value: None,
                text_value: None,
            }),
            IndexValue::Double(value) if value.is_finite() => Ok(Self {
                kind: INDEX_KIND_DOUBLE,
                int_value: None,
                real_value: Some(*value),
                text_value: None,
            }),
            IndexValue::Double(_) => Err("index double values must be finite".into()),
            IndexValue::String(value) => Ok(Self {
                kind: INDEX_KIND_STRING,
                int_value: None,
                real_value: None,
                text_value: Some(value.clone()),
            }),
            IndexValue::List(values) => Ok(Self {
                kind: INDEX_KIND_LIST,
                int_value: None,
                real_value: None,
                text_value: Some(stable_index_list_key(values)?),
            }),
        }
    }
}

fn stable_index_list_key(values: &[IndexValue]) -> Result<String, String> {
    let value = WireIndexValue::List(
        values
            .iter()
            .map(index_value_to_wire)
            .collect::<Result<Vec<_>, _>>()?,
    );
    encode_index_value(&value).map(hex_encode)
}

fn index_value_to_wire(value: &IndexValue) -> Result<WireIndexValue, String> {
    Ok(match value {
        IndexValue::Bool(value) => WireIndexValue::Bool(*value),
        IndexValue::Int(value) => WireIndexValue::Int(*value),
        IndexValue::Double(value) if value.is_finite() => WireIndexValue::Double(*value),
        IndexValue::Double(_) => return Err("index double values must be finite".into()),
        IndexValue::String(value) => WireIndexValue::String(value.clone()),
        IndexValue::List(values) => WireIndexValue::List(
            values
                .iter()
                .map(index_value_to_wire)
                .collect::<Result<Vec<_>, _>>()?,
        ),
    })
}

fn hex_encode(bytes: Vec<u8>) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        output.push(HEX[(byte >> 4) as usize] as char);
        output.push(HEX[(byte & 0x0f) as usize] as char);
    }
    output
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::*;
    use crate::storage::contract_tests;

    use crate::storage::test_allocations as rust_allocations;

    #[test]
    fn passes_the_shared_storage_engine_contract() {
        // Scenario: SQLite is the current default native storage backend.
        // Covers:
        // - The shared [StorageEngine] behavioral contract used by every
        //   backend candidate.
        // - CRUD, ids, indexes, unique indexes, schemas, revisions, and batch
        //   rollback behavior.
        // Expected: SQLite remains the reference backend for MDBX parity.
        contract_tests::run_storage_engine_contract("sqlite", SqliteStorage::open);
    }

    #[test]
    fn passes_the_shared_storage_transaction_contract() {
        // Scenario: SQLite is the reference transaction implementation.
        // Covers:
        // - The shared [StorageEngine] explicit transaction contract.
        // - Commit, rollback, read transaction write rejection, nested
        //   transaction rejection, and id allocation rollback.
        // Expected: SQLite keeps defining the behavior MDBX must match.
        contract_tests::run_storage_transaction_contract("sqlite", SqliteStorage::open);
    }

    #[test]
    fn stores_reads_and_deletes_bytes_by_collection_and_id() {
        // Scenario: Bytes are written, read, and deleted in one collection.
        // Covers:
        // - Insert and read paths for a document primary key.
        // - Delete path for an existing document.
        // Expected: Stored bytes round-trip once and are missing after delete.

        // Arrange.
        let directory = TemporaryDirectory::new("crud");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.put("users", 1, br#"{"name":"Noel"}"#).unwrap();
        let stored = storage.get("users", 1).unwrap();

        // Assert.
        assert_eq!(stored, Some(br#"{"name":"Noel"}"#.to_vec()));

        // Act.
        storage.delete("users", 1).unwrap();
        let deleted = storage.get("users", 1).unwrap();

        // Assert.
        assert_eq!(deleted, None);
    }

    #[test]
    fn persists_bytes_after_reopening_the_database_directory() {
        // Scenario: A database directory is closed and reopened.
        // Covers:
        // - SQLite persistence across separate connections.
        // - Opening an existing Cindel database file.
        // Expected: Bytes remain readable after reopening the directory.

        // Arrange.
        let directory = TemporaryDirectory::new("persist");

        // Act.
        {
            let mut storage = SqliteStorage::open(directory.path()).unwrap();
            storage.put("settings", 7, br#"{"theme":"dark"}"#).unwrap();
        }

        let reopened = SqliteStorage::open(directory.path()).unwrap();
        let stored = reopened.get("settings", 7).unwrap();

        // Assert.
        assert_eq!(stored, Some(br#"{"theme":"dark"}"#.to_vec()));
    }

    #[test]
    fn rejects_json_era_schema_metadata_on_open() {
        // Scenario: A preview SQLite database has JSON schema metadata rows.
        // Covers:
        // - Fail-closed behavior before old metadata can be used.
        // - Clear incompatibility wording for preview JSON storage.
        // Expected: Opening the database asks the user to recreate it.

        // Arrange.
        let directory = TemporaryDirectory::new("json_schema_metadata");
        fs::create_dir_all(directory.path()).unwrap();
        let connection =
            Connection::open(Path::new(directory.path()).join("cindel.sqlite")).unwrap();
        connection
            .execute_batch(
                r#"
                CREATE TABLE schema_collections (
                    collection TEXT PRIMARY KEY NOT NULL,
                    version INTEGER NOT NULL,
                    schema_json TEXT NOT NULL
                );
                INSERT INTO schema_collections (collection, version, schema_json)
                VALUES ('users', 1, '{"name":"users"}');
                "#,
            )
            .unwrap();
        drop(connection);

        // Act.
        let result = SqliteStorage::open(directory.path());

        // Assert.
        let error = result
            .err()
            .expect("JSON schema metadata should reject SQLite open");
        assert!(error.contains("JSON-era preview schema metadata"));
    }

    #[test]
    fn rejects_corrupt_binary_schema_metadata_on_open() {
        // Scenario: A SQLite database has a malformed binary schema row.
        // Covers:
        // - Binary metadata validation during open.
        // - Corrupt metadata rejection before any write.
        // Expected: Opening fails instead of ignoring the bad record.

        // Arrange.
        let directory = TemporaryDirectory::new("corrupt_schema_metadata");
        fs::create_dir_all(directory.path()).unwrap();
        let connection =
            Connection::open(Path::new(directory.path()).join("cindel.sqlite")).unwrap();
        connection
            .execute_batch(
                r#"
                CREATE TABLE schema_collections (
                    collection TEXT PRIMARY KEY NOT NULL,
                    version INTEGER NOT NULL,
                    schema_bytes BLOB NOT NULL
                );
                INSERT INTO schema_collections (collection, version, schema_bytes)
                VALUES ('users', 1, x'43534d52');
                "#,
            )
            .unwrap();
        drop(connection);

        // Act.
        let result = SqliteStorage::open(directory.path());

        // Assert.
        let error = result
            .err()
            .expect("corrupt schema metadata should reject SQLite open");
        assert!(error.contains("schema metadata is truncated"));
    }

    #[test]
    fn reads_many_documents_with_one_prepared_statement() {
        // Scenario: Several ids are requested in order, including a missing id.
        // Covers:
        // - [StorageEngine::get_many] preserving input order.
        // - Missing documents represented as None.
        // Expected: Existing documents and gaps are returned in one batch.

        // Arrange.
        let directory = TemporaryDirectory::new("get_many");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
        storage.put("users", 3, br#"{"name":"Cid"}"#).unwrap();

        // Act.
        let documents = storage.get_many("users", &[3, 2, 1]).unwrap();

        // Assert.
        assert_eq!(
            documents,
            vec![
                Some(br#"{"name":"Cid"}"#.to_vec()),
                None,
                Some(br#"{"name":"Ana"}"#.to_vec()),
            ]
        );
    }

    #[test]
    fn keeps_documents_with_the_same_id_separate_by_collection() {
        // Scenario: Two collections store different bytes under the same id.
        // Covers:
        // - Composite primary key behavior for collection and id.
        // - Reads scoped by collection name.
        // Expected: Each collection returns its own bytes for the shared id.

        // Arrange.
        let directory = TemporaryDirectory::new("collections");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.put("users", 1, br#"{"name":"Noel"}"#).unwrap();
        storage.put("settings", 1, br#"{"theme":"dark"}"#).unwrap();
        let user = storage.get("users", 1).unwrap();
        let settings = storage.get("settings", 1).unwrap();

        // Assert.
        assert_eq!(user, Some(br#"{"name":"Noel"}"#.to_vec()));
        assert_eq!(settings, Some(br#"{"theme":"dark"}"#.to_vec()));
    }

    #[test]
    fn opens_isolated_in_memory_databases() {
        // Scenario: A database is opened in memory and then another memory
        // database is opened.
        // Covers:
        // - SQLite in-memory connection support.
        // - No file-backed persistence between separate memory handles.
        // Expected: The second in-memory database starts empty.

        // Arrange.
        let mut first_storage = SqliteStorage::open(IN_MEMORY_DIRECTORY).unwrap();

        // Act.
        first_storage
            .put("settings", 7, br#"{"theme":"dark"}"#)
            .unwrap();
        let stored = first_storage.get("settings", 7).unwrap();
        drop(first_storage);

        let second_storage = SqliteStorage::open(IN_MEMORY_DIRECTORY).unwrap();
        let missing = second_storage.get("settings", 7).unwrap();

        // Assert.
        assert_eq!(stored, Some(br#"{"theme":"dark"}"#.to_vec()));
        assert_eq!(missing, None);
    }

    #[test]
    fn lists_document_ids_by_collection() {
        // Scenario: A collection contains multiple documents out of insert order.
        // Covers:
        // - [StorageEngine::document_ids] scanning ids by collection.
        // - Stable id ordering for Dart collection snapshots.
        // Expected: Only ids from the requested collection are returned sorted.

        // Arrange.
        let directory = TemporaryDirectory::new("document_ids");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.put("users", 3, br#"{"name":"Cid"}"#).unwrap();
        storage.put("settings", 1, br#"{"theme":"dark"}"#).unwrap();
        storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
        let ids = storage.document_ids("users").unwrap();

        // Assert.
        assert_eq!(ids, vec![1, 3]);
    }

    #[test]
    fn advances_collection_revision_after_committed_changes() {
        // Scenario: Documents are inserted, updated, deleted, and deleted again.
        // Covers:
        // - Revision increments after committed writes.
        // - No-op deletes leaving the revision unchanged.
        // Expected: Watchers can detect real collection changes monotonically.

        // Arrange.
        let directory = TemporaryDirectory::new("revision");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        let initial = storage.collection_revision("users").unwrap();
        storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
        let after_insert = storage.collection_revision("users").unwrap();
        storage.put("users", 1, br#"{"name":"Ada"}"#).unwrap();
        let after_update = storage.collection_revision("users").unwrap();
        storage.delete("users", 1).unwrap();
        let after_delete = storage.collection_revision("users").unwrap();
        storage.delete("users", 1).unwrap();
        let after_missing_delete = storage.collection_revision("users").unwrap();

        // Assert.
        assert_eq!(initial, 0);
        assert_eq!(after_insert, 1);
        assert_eq!(after_update, 2);
        assert_eq!(after_delete, 3);
        assert_eq!(after_missing_delete, 3);
    }

    #[test]
    fn registers_initial_schema_version() {
        // Scenario: A generated schema is registered for a new collection.
        // Covers:
        // - [StorageEngine::register_schemas] storing schema metadata.
        // - [StorageEngine::schema_version] reading persisted versions.
        // Expected: The collection starts at schema version 1.

        // Arrange.
        let directory = TemporaryDirectory::new("schema_initial");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let manifest = schema_manifest(vec![user_schema(vec![field(
            "email", "String", false, true,
        )])]);

        // Act.
        storage.register_schemas(&manifest).unwrap();
        let version = storage.schema_version("users").unwrap();

        // Assert.
        assert_eq!(version, Some(1));
    }

    #[test]
    fn opens_with_schema_manifest_during_open() {
        // Scenario: Dart opens SQLite with generated schemas already available.
        // Covers:
        // - [SqliteStorage::open_with_schemas] registering runtime schema metadata during open.
        // - Keeping schema-aware SQLite open focused on collection tables.
        // Expected: The collection starts at schema version 1 without a later register call
        // and does not persist Cindel-only metadata tables in schema-aware SQLite mode.

        // Arrange.
        let directory = TemporaryDirectory::new("schema_open");
        let manifest = schema_manifest(vec![user_schema(vec![field(
            "email", "String", false, true,
        )])]);

        // Act.
        let storage = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
        let version = storage.schema_version("users").unwrap();
        let storage_metadata_table = storage
            .connection
            .query_row(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'storage_metadata'",
                [],
                |row| row.get::<_, i64>(0),
            )
            .optional()
            .unwrap();

        // Assert.
        assert_eq!(version, Some(1));
        assert_eq!(storage_metadata_table, None);
    }

    #[test]
    fn opens_with_persisted_schema_manifest_and_metadata() {
        // Scenario: Web opens SQLite with generated schemas inside a persistent
        // database.
        // Covers:
        // - [SqliteStorage::open_with_persisted_schemas] registering schema
        //   metadata during open.
        // - Runtime schema availability after persisted Web-style open.
        // - Storage metadata persistence across close and reopen.
        // - Controlled rejection of incompatible schema changes.
        // Expected: Web SQLite can reopen the same database, report schema
        // version 1, keep storage metadata, expose native document cursors,
        // and leave the old schema intact after an incompatible open attempt.

        // Arrange.
        let directory = TemporaryDirectory::new("schema_open_persisted");
        let original = schema_manifest(vec![user_schema(vec![field(
            "email", "String", false, true,
        )])]);
        let incompatible =
            schema_manifest(vec![user_schema(vec![field("email", "int", false, true)])]);

        // Act.
        let storage =
            SqliteStorage::open_with_persisted_schemas(directory.path(), &original).unwrap();
        let first_version = storage.schema_version("users").unwrap();
        let first_metadata = storage.storage_metadata().unwrap();
        let first_cursor = storage
            .native_document_cursor("users", &[1])
            .unwrap()
            .is_some();
        drop(storage);

        let storage =
            SqliteStorage::open_with_persisted_schemas(directory.path(), &original).unwrap();
        let reopened_version = storage.schema_version("users").unwrap();
        let reopened_metadata = storage.storage_metadata().unwrap();
        drop(storage);

        let incompatible_error =
            match SqliteStorage::open_with_persisted_schemas(directory.path(), &incompatible) {
                Ok(_) => panic!("incompatible schema should be rejected"),
                Err(error) => error,
            };
        let storage =
            SqliteStorage::open_with_persisted_schemas(directory.path(), &original).unwrap();
        let final_version = storage.schema_version("users").unwrap();

        // Assert.
        assert_eq!(first_version, Some(1));
        assert_eq!(reopened_version, Some(1));
        assert_eq!(final_version, Some(1));
        assert!(first_cursor);
        assert_eq!(first_metadata.layout, StorageLayoutVersion::SqliteV1);
        assert_eq!(
            first_metadata.document_format,
            DocumentFormatVersion::BinaryV2
        );
        assert_eq!(
            first_metadata.schema_metadata_format,
            SchemaMetadataVersion::BinaryV1
        );
        assert_eq!(reopened_metadata, first_metadata);
        assert!(incompatible_error.contains("cannot change type"));
    }

    #[test]
    fn inserts_native_documents_into_collection_table() {
        // Scenario: A generated typed collection writes through the native
        // writer on SQLite.
        // Covers:
        // - Isar-like per-collection table storage instead of generic blobs.
        // - Batched native value insertion and native read-back bytes.
        // Expected: Values land in collection columns and no generic document
        // row is required.

        // Arrange.
        let directory = TemporaryDirectory::new("native_insert");
        let manifest = schema_manifest(vec![native_user_schema()]);
        let mut storage = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
        let documents = vec![
            NativeDocumentWrite {
                id: 1,
                values: vec![
                    NativeDocumentValue::Bool(true),
                    NativeDocumentValue::Int(42),
                    NativeDocumentValue::Bytes(b"Ana".to_vec()),
                ],
            },
            NativeDocumentWrite {
                id: 2,
                values: vec![
                    NativeDocumentValue::Bool(false),
                    NativeDocumentValue::Int(84),
                    NativeDocumentValue::Bytes(b"Ada".to_vec()),
                ],
            },
        ];

        // Act.
        storage
            .put_many_native_documents("users", &documents, true)
            .unwrap();
        let row = storage
            .connection
            .query_row(
                "SELECT completed, createdAtMicros, title FROM users WHERE _rowid_ = 1",
                [],
                |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, String>(2)?,
                    ))
                },
            )
            .unwrap();
        let generic_documents_table = storage
            .connection
            .query_row(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'documents'",
                [],
                |row| row.get::<_, i64>(0),
            )
            .optional()
            .unwrap();
        let ids = storage.document_ids("users").unwrap();
        let stored = storage.get_many_stored("users", &[1, 3]).unwrap();
        let mut cursor = storage
            .native_document_cursor("users", &[2, 3])
            .unwrap()
            .unwrap();

        // Assert.
        assert_eq!(row, (1, 42, "Ana".to_string()));
        assert_eq!(generic_documents_table, None);
        assert_eq!(ids, vec![1, 2]);
        assert!(stored[0].is_some());
        assert_eq!(stored[1], None);
        assert_eq!(cursor.len(), 2);
        assert!(cursor.is_present(0).unwrap());
        assert_eq!(cursor.document_id(0), Some(2));
        assert_eq!(cursor.read_bool(0, 0), Some(false));
        assert_eq!(cursor.read_int(0, 1), Some(84));
        assert_eq!(cursor.read_bytes(0, 2), Some(&b"Ada"[..]));
        assert!(!cursor.is_present(1).unwrap());
        assert_eq!(cursor.document_id(1), None);
    }

    #[test]
    fn gets_generic_documents_across_id_chunks_in_input_order() {
        // Scenario: A generic SQLite getAll request crosses SQLite's parameter
        // limit and contains hits, misses, and duplicate ids.
        // Covers:
        // - Chunked `IN (...)` reads for the generic document table.
        // - Reconstructing the original id order after unordered SQL results.
        // - Preserving nulls for missing ids and values for duplicate ids.
        // Expected: The result length and order exactly match the input ids.

        // Arrange.
        let directory = TemporaryDirectory::new("generic_get_chunks");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let second_hit = (SQLITE_MAX_PARAM_COUNT + 1) as u64;
        storage
            .put_many_indexed(
                "users",
                &[
                    document_write(1, b"first", Vec::new()),
                    document_write(second_hit, b"second", Vec::new()),
                ],
            )
            .unwrap();
        let mut ids = (1..=second_hit).collect::<Vec<_>>();
        ids.push(1);

        // Act.
        let documents = storage.get_many("users", &ids).unwrap();

        // Assert.
        assert_eq!(documents.len(), ids.len());
        assert_eq!(documents[0].as_deref(), Some(&b"first"[..]));
        assert_eq!(documents[1], None);
        assert_eq!(
            documents[SQLITE_MAX_PARAM_COUNT].as_deref(),
            Some(&b"second"[..])
        );
        assert_eq!(documents.last().unwrap().as_deref(), Some(&b"first"[..]));
    }

    #[test]
    fn gets_native_documents_across_id_chunks_in_input_order() {
        // Scenario: A generated SQLite-native getAll request crosses SQLite's
        // parameter limit and contains hits, misses, and duplicate ids.
        // Covers:
        // - Chunked native collection-table reads.
        // - Reconstructing the original id order after unordered SQL results.
        // - Preserving nulls for missing ids and values for duplicate ids.
        // Expected: Stored native documents are returned in requested order.

        // Arrange.
        let directory = TemporaryDirectory::new("native_get_chunks");
        let manifest = schema_manifest(vec![native_user_schema()]);
        let mut storage = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
        let second_hit = (SQLITE_MAX_PARAM_COUNT + 1) as u64;
        storage
            .put_many_native_documents(
                "users",
                &[
                    NativeDocumentWrite {
                        id: 1,
                        values: vec![
                            NativeDocumentValue::Bool(true),
                            NativeDocumentValue::Int(42),
                            NativeDocumentValue::Bytes(b"first".to_vec()),
                        ],
                    },
                    NativeDocumentWrite {
                        id: second_hit,
                        values: vec![
                            NativeDocumentValue::Bool(false),
                            NativeDocumentValue::Int(84),
                            NativeDocumentValue::Bytes(b"second".to_vec()),
                        ],
                    },
                ],
                true,
            )
            .unwrap();
        let mut ids = (1..=second_hit).collect::<Vec<_>>();
        ids.push(1);

        // Act.
        let documents = storage.get_many_stored("users", &ids).unwrap();

        // Assert.
        assert_eq!(documents.len(), ids.len());
        assert!(documents[0].is_some());
        assert_eq!(documents[1], None);
        assert!(documents[SQLITE_MAX_PARAM_COUNT].is_some());
        assert!(documents.last().unwrap().is_some());
        assert_eq!(documents[0], *documents.last().unwrap());
    }

    #[test]
    fn inserts_native_documents_across_cached_statement_chunks() {
        // Scenario: A generated typed collection writes enough SQLite-native
        // rows to cross the SQLite parameter limit and require multiple
        // insert chunks.
        // Covers:
        // - Reusing the prepared statement for full native insert chunks.
        // - Preparing a separate remainder statement.
        // - Preserving ids, field values, and one collection revision bump.
        // Expected: All rows are inserted exactly once and remain queryable.

        // Arrange.
        let directory = TemporaryDirectory::new("native_insert_chunks");
        let schema = wide_native_user_schema(200);
        let values_per_document = native_fields(&schema).len() + 1;
        let batch_limit = (SQLITE_MAX_PARAM_COUNT / values_per_document).max(1);
        let count = batch_limit * 2 + 3;
        let manifest = schema_manifest(vec![schema]);
        let mut storage = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
        let documents = (0..count)
            .map(|index| NativeDocumentWrite {
                id: (index + 1) as u64,
                values: (0..200)
                    .map(|field| NativeDocumentValue::Int((index * 1000 + field) as i64))
                    .collect(),
            })
            .collect::<Vec<_>>();

        // Act.
        storage
            .put_many_native_documents("users", &documents, true)
            .unwrap();
        let ids = storage.document_ids("users").unwrap();
        let stored = storage
            .connection
            .query_row(
                "SELECT field_199 FROM users WHERE _rowid_ = ?1",
                params![count as i64],
                |row| row.get::<_, i64>(0),
            )
            .unwrap();

        // Assert.
        assert_eq!(ids.len(), count);
        assert_eq!(ids.first(), Some(&1));
        assert_eq!(ids.last(), Some(&(count as u64)));
        assert_eq!(stored, ((count - 1) * 1000 + 199) as i64);
        assert_eq!(storage.collection_revision("users").unwrap(), 1);
    }

    #[test]
    fn queries_native_documents_with_sql_filter_and_sort() {
        // Scenario: SQLite executes a schema-aware native query plan.
        // Covers:
        // - Wire filters lowered to SQL WHERE over collection columns.
        // - Isar-like explicit SQL ORDER BY and offset handling.
        // - Case-sensitive string filters, matching Dart/Isar defaults.
        // Expected: Matching ids and native document bytes come back in the
        // same order produced by SQLite.

        // Arrange.
        let directory = TemporaryDirectory::new("native_query_plan");
        let manifest = schema_manifest(vec![native_user_schema()]);
        let mut storage = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
        let documents = vec![
            NativeDocumentWrite {
                id: 1,
                values: vec![
                    NativeDocumentValue::Bool(false),
                    NativeDocumentValue::Int(10),
                    NativeDocumentValue::Bytes(b"alpha".to_vec()),
                ],
            },
            NativeDocumentWrite {
                id: 2,
                values: vec![
                    NativeDocumentValue::Bool(true),
                    NativeDocumentValue::Int(20),
                    NativeDocumentValue::Bytes(b"zulu".to_vec()),
                ],
            },
            NativeDocumentWrite {
                id: 3,
                values: vec![
                    NativeDocumentValue::Bool(false),
                    NativeDocumentValue::Int(30),
                    NativeDocumentValue::Bytes(b"zulu".to_vec()),
                ],
            },
            NativeDocumentWrite {
                id: 4,
                values: vec![
                    NativeDocumentValue::Bool(true),
                    NativeDocumentValue::Int(40),
                    NativeDocumentValue::Bytes(b"beta".to_vec()),
                ],
            },
        ];
        storage
            .put_many_native_documents("users", &documents, true)
            .unwrap();
        let filter = crate::wire::encode_filter(&crate::wire::WireFilter::Any {
            predicates: vec![
                crate::wire::WireFilter::Field {
                    field: "title".to_string(),
                    operation: crate::wire::WireFilterOperation::Contains,
                    value: crate::wire::WireValue::String("a".to_string()),
                },
                crate::wire::WireFilter::Field {
                    field: "completed".to_string(),
                    operation: crate::wire::WireFilterOperation::Equal,
                    value: crate::wire::WireValue::Bool(true),
                },
            ],
        })
        .unwrap();
        let filtered = crate::wire::WireQueryPlan {
            source: crate::wire::WireQuerySource::All { dedupe: false },
            filter: Some(filter),
            sorts: Vec::new(),
            distinct_fields: Vec::new(),
            offset: 1,
            limit: None,
        };
        let sorted = crate::wire::WireQueryPlan {
            source: crate::wire::WireQuerySource::All { dedupe: false },
            filter: Some(
                crate::wire::encode_filter(&crate::wire::WireFilter::Field {
                    field: "completed".to_string(),
                    operation: crate::wire::WireFilterOperation::Equal,
                    value: crate::wire::WireValue::Bool(true),
                })
                .unwrap(),
            ),
            sorts: vec![crate::wire::WireQuerySort {
                field: "title".to_string(),
                ascending: true,
            }],
            distinct_fields: Vec::new(),
            offset: 0,
            limit: None,
        };
        let case_sensitive = crate::wire::WireQueryPlan {
            source: crate::wire::WireQuerySource::All { dedupe: false },
            filter: Some(
                crate::wire::encode_filter(&crate::wire::WireFilter::Field {
                    field: "title".to_string(),
                    operation: crate::wire::WireFilterOperation::Contains,
                    value: crate::wire::WireValue::String("A".to_string()),
                })
                .unwrap(),
            ),
            sorts: Vec::new(),
            distinct_fields: Vec::new(),
            offset: 0,
            limit: None,
        };

        // Act.
        let filtered_ids = storage.query_plan_ids("users", &filtered).unwrap();
        let sorted_ids = storage.query_plan_ids("users", &sorted).unwrap();
        let case_sensitive_ids = storage.query_plan_ids("users", &case_sensitive).unwrap();
        let sorted_documents = storage.query_plan_documents("users", &sorted).unwrap();
        let mut sorted_cursor = storage
            .query_plan_native_cursor("users", &sorted)
            .unwrap()
            .unwrap();

        // Assert.
        assert_eq!(filtered_ids, vec![2, 4]);
        assert_eq!(sorted_ids, vec![4, 2]);
        assert!(case_sensitive_ids.is_empty());
        assert_eq!(sorted_documents.len(), 2);
        assert!(sorted_cursor.next().unwrap());
        assert_eq!(sorted_cursor.document_id(0), Some(4));
        assert_eq!(sorted_cursor.read_bool(0, 0), Some(true));
        assert_eq!(sorted_cursor.read_int(0, 1), Some(40));
        assert_eq!(sorted_cursor.read_bytes(0, 2), Some(&b"beta"[..]));
        assert!(sorted_cursor.next().unwrap());
        assert_eq!(sorted_cursor.document_id(0), Some(2));
        assert_eq!(sorted_cursor.read_bool(0, 0), Some(true));
        assert_eq!(sorted_cursor.read_int(0, 1), Some(20));
        assert_eq!(sorted_cursor.read_bytes(0, 2), Some(&b"zulu"[..]));
        assert!(!sorted_cursor.next().unwrap());
    }

    #[test]
    fn queries_native_documents_with_sql_list_element_filter() {
        // Scenario: SQLite executes the same list-element filter shape used by
        // the app benchmark Filter Query.
        // Covers:
        // - Wire `Contains` on a list field lowering to exact JSON element
        //   equality instead of a LIKE over the serialized JSON text.
        // - OR composition with a scalar string contains predicate.
        // Expected: A row containing `time` matches, a row containing only
        // `timer` does not, and scalar string filtering still participates in
        // the same SQL query.

        // Arrange.
        let directory = TemporaryDirectory::new("native_query_plan_list_filter");
        let mut schema = native_user_schema();
        schema
            .fields
            .push(native_field("words", "List<String>", "list", false));
        schema
            .fields
            .sort_by(|left, right| left.name.cmp(&right.name));
        let manifest = schema_manifest(vec![schema]);
        let mut storage = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
        let documents = vec![
            NativeDocumentWrite {
                id: 1,
                values: vec![
                    NativeDocumentValue::Bool(false),
                    NativeDocumentValue::Int(10),
                    NativeDocumentValue::Bytes(b"zulu".to_vec()),
                    NativeDocumentValue::Null,
                ],
            },
            NativeDocumentWrite {
                id: 2,
                values: vec![
                    NativeDocumentValue::Bool(false),
                    NativeDocumentValue::Int(20),
                    NativeDocumentValue::Bytes(b"zulu".to_vec()),
                    NativeDocumentValue::Null,
                ],
            },
            NativeDocumentWrite {
                id: 3,
                values: vec![
                    NativeDocumentValue::Bool(false),
                    NativeDocumentValue::Int(30),
                    NativeDocumentValue::Bytes(b"alpha".to_vec()),
                    NativeDocumentValue::Null,
                ],
            },
        ];
        storage
            .put_many_native_documents("users", &documents, true)
            .unwrap();
        storage
            .connection
            .execute(
                "UPDATE users SET words = ?1 WHERE _rowid_ = ?2",
                params![r#"["time","alpha"]"#, 1i64],
            )
            .unwrap();
        storage
            .connection
            .execute(
                "UPDATE users SET words = ?1 WHERE _rowid_ = ?2",
                params![r#"["timer"]"#, 2i64],
            )
            .unwrap();
        storage
            .connection
            .execute(
                "UPDATE users SET words = ?1 WHERE _rowid_ = ?2",
                params![r#"[]"#, 3i64],
            )
            .unwrap();
        let filter = crate::wire::encode_filter(&crate::wire::WireFilter::Any {
            predicates: vec![
                crate::wire::WireFilter::Field {
                    field: "words".to_string(),
                    operation: crate::wire::WireFilterOperation::Contains,
                    value: crate::wire::WireValue::String("time".to_string()),
                },
                crate::wire::WireFilter::Field {
                    field: "title".to_string(),
                    operation: crate::wire::WireFilterOperation::Contains,
                    value: crate::wire::WireValue::String("a".to_string()),
                },
            ],
        })
        .unwrap();
        let plan = crate::wire::WireQueryPlan {
            source: crate::wire::WireQuerySource::All { dedupe: false },
            filter: Some(filter),
            sorts: Vec::new(),
            distinct_fields: Vec::new(),
            offset: 0,
            limit: None,
        };

        // Act.
        let ids = storage.query_plan_ids("users", &plan).unwrap();

        // Assert.
        assert_eq!(ids, vec![1, 3]);
    }

    #[test]
    fn counts_native_query_windows_with_one_scalar_and_no_sort() {
        for open in [
            SqliteStorage::open_with_schemas,
            SqliteStorage::open_with_persisted_schemas,
        ] {
            let directory = TemporaryDirectory::new("native_count_windows");
            let schema = native_user_schema();
            let manifest = schema_manifest(vec![schema.clone()]);
            let mut storage = open(directory.path(), &manifest).unwrap();
            let documents: Vec<_> = (1..=1000)
                .map(|id| NativeDocumentWrite {
                    id,
                    values: vec![
                        NativeDocumentValue::Bool(id % 2 == 0),
                        NativeDocumentValue::Int(id as i64),
                        NativeDocumentValue::Bytes(format!("Title {}", 1001 - id).into_bytes()),
                    ],
                })
                .collect();
            storage
                .put_many_native_documents("users", &documents, true)
                .unwrap();
            let mut plan = WireQueryPlan {
                source: WireQuerySource::All { dedupe: false },
                filter: None,
                sorts: vec![crate::wire::WireQuerySort {
                    field: "title".into(),
                    ascending: false,
                }],
                distinct_fields: Vec::new(),
                offset: 10,
                limit: Some(20),
            };
            let (sql, params) =
                sqlite_query_plan_sql(&schema, &plan, SqliteQuerySelect::Count).unwrap();
            let mut statement = storage.connection.prepare(&sql).unwrap();
            {
                let mut rows = statement.query(params_from_iter(params.iter())).unwrap();
                assert_eq!(rows.next().unwrap().unwrap().get::<_, i64>(0).unwrap(), 20);
                assert!(rows.next().unwrap().is_none());
            }
            // Verify SQLite did not sort the source merely to count its window.
            assert_eq!(statement.get_status(rusqlite::StatementStatus::Sort), 0);
            for filter in [
                None,
                Some(
                    crate::wire::encode_filter(&WireFilter::Field {
                        field: "completed".into(),
                        operation: WireFilterOperation::Equal,
                        value: WireValue::Bool(true),
                    })
                    .unwrap(),
                ),
            ] {
                plan.filter = filter;
                for offset in [0, 10, 2000, u32::MAX] {
                    for limit in [None, Some(0), Some(1), Some(20), Some(u32::MAX)] {
                        plan.offset = offset;
                        plan.limit = limit;
                        assert_eq!(
                            storage.query_plan_count("users", &plan).unwrap(),
                            storage.query_plan_ids("users", &plan).unwrap().len() as u64
                        );
                    }
                }
            }
            plan.sorts[0].field = "missing".into();
            plan.limit = Some(0);
            assert!(storage.query_plan_count("users", &plan).is_err());
        }
    }

    #[test]
    fn streaming_aggregates_preserve_scalar_results_and_errors() {
        let cases = vec![
            vec![],
            vec![WireValue::Null, WireValue::Null],
            vec![
                WireValue::Int(i64::MAX),
                WireValue::Null,
                WireValue::Int(i64::MIN),
                WireValue::Int(9_007_199_254_740_993),
            ],
            vec![
                WireValue::Double(1e16),
                WireValue::Double(1.0),
                WireValue::Double(-1e16),
                WireValue::Double(1.0),
            ],
            vec![WireValue::Double(-0.0), WireValue::Double(0.0)],
            vec![WireValue::Double(0.0), WireValue::Double(-0.0)],
            vec![
                WireValue::String("z".into()),
                WireValue::Null,
                WireValue::String("Árbol".into()),
                WireValue::String("a".into()),
            ],
            vec![WireValue::Bool(true)],
            vec![WireValue::Int(1), WireValue::String("bad".into())],
            vec![WireValue::Double(f64::NAN)],
            vec![WireValue::Double(1.0), WireValue::Double(f64::NAN)],
            vec![WireValue::Double(f64::INFINITY)],
            vec![WireValue::Double(f64::MAX), WireValue::Double(f64::MAX)],
        ];
        for values in cases {
            for operation in ["count", "min", "max", "sum", "average", "unknown"] {
                let actual = (|| {
                    let mut aggregate = StreamingWireAggregate::new(operation)?;
                    for value in &values {
                        aggregate.push(value.clone())?;
                    }
                    encode_scalar(&aggregate.finish()?)
                })();
                let expected = aggregate_wire_values(&values, operation)
                    .and_then(|scalar| encode_scalar(&scalar));
                assert_eq!(actual, expected, "{operation}: {values:?}");
            }
        }
    }

    #[test]
    fn streaming_aggregates_preserve_read_error_precedence() {
        let directory = TemporaryDirectory::new("streaming_aggregate_errors");
        let schema = native_user_schema();
        let manifest = schema_manifest(vec![schema.clone()]);
        let mut storage = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
        storage
            .put_many_native_documents(
                "users",
                &[
                    NativeDocumentWrite {
                        id: 1,
                        values: vec![
                            NativeDocumentValue::Bool(true),
                            NativeDocumentValue::Int(1),
                            NativeDocumentValue::Bytes(b"text".to_vec()),
                        ],
                    },
                    NativeDocumentWrite {
                        id: 2,
                        values: vec![
                            NativeDocumentValue::Bool(true),
                            NativeDocumentValue::Int(2),
                            NativeDocumentValue::Bytes(b"text".to_vec()),
                        ],
                    },
                ],
                true,
            )
            .unwrap();
        // SUM fails on the first string, but the old materialized path reports
        // the later invalid SQLite column type before any calculation error.
        storage
            .connection
            .execute("UPDATE users SET title = X'ff' WHERE _rowid_ = 2", [])
            .unwrap();
        let plan = WireQueryPlan {
            source: WireQuerySource::All { dedupe: false },
            filter: None,
            sorts: vec![crate::wire::WireQuerySort {
                field: "id".into(),
                ascending: true,
            }],
            distinct_fields: Vec::new(),
            offset: 0,
            limit: None,
        };
        let expected = storage
            .query_plan_native_values(&schema, &plan, "title")
            .unwrap_err();
        for operation in ["count", "min", "max", "sum", "average", "unknown"] {
            assert_eq!(
                storage
                    .query_plan_aggregate("users", &plan, "title", operation)
                    .unwrap_err(),
                expected
            );
        }
    }

    #[test]
    fn query_aggregates_do_not_retain_all_projected_values() {
        for open in [
            SqliteStorage::open_with_schemas,
            SqliteStorage::open_with_persisted_schemas,
        ] {
            let directory = TemporaryDirectory::new("streaming_aggregate_memory");
            let manifest = schema_manifest(vec![native_user_schema()]);
            let mut storage = open(directory.path(), &manifest).unwrap();
            let title = "x".repeat(8192);
            let documents: Vec<_> = (1..=1024)
                .map(|id| NativeDocumentWrite {
                    id,
                    values: vec![
                        NativeDocumentValue::Bool(true),
                        NativeDocumentValue::Int(1),
                        NativeDocumentValue::Bytes(title.as_bytes().to_vec()),
                    ],
                })
                .collect();
            storage
                .put_many_native_documents("users", &documents, true)
                .unwrap();
            for limit in [128, 1024] {
                let plan = WireQueryPlan {
                    source: WireQuerySource::All { dedupe: false },
                    filter: None,
                    sorts: Vec::new(),
                    distinct_fields: Vec::new(),
                    offset: 0,
                    limit: Some(limit),
                };
                for (field, operation, expected) in [
                    ("title", "count", WireScalar::Int(limit as i64)),
                    ("title", "min", WireScalar::String(title.clone())),
                    ("title", "max", WireScalar::String(title.clone())),
                    ("createdAtMicros", "sum", WireScalar::Double(limit as f64)),
                    ("createdAtMicros", "average", WireScalar::Double(1.0)),
                ] {
                    let expected = encode_scalar(&expected).unwrap();
                    let peak = rust_allocations::peak_bytes(|| {
                        assert_eq!(
                            storage
                                .query_plan_aggregate("users", &plan, field, operation)
                                .unwrap(),
                            expected
                        );
                    });
                    // Allow schema/statement setup and a few individual values, but
                    // reject the 1-8 MiB vector of strings used by the old path.
                    assert!(
                        peak < 128 * 1024,
                        "{operation}({field}), limit={limit}: {peak} Rust heap bytes"
                    );
                }
            }
        }
    }

    #[test]
    fn projects_and_aggregates_with_one_statement_regardless_of_row_count() {
        use std::cell::Cell;
        use std::ffi::c_void;

        unsafe extern "C" fn count_statement(
            _: u32,
            context: *mut c_void,
            _: *mut c_void,
            _: *mut c_void,
        ) -> i32 {
            let count = unsafe { &*context.cast::<Cell<usize>>() };
            count.set(count.get() + 1);
            0
        }

        for open in [
            SqliteStorage::open_with_schemas,
            SqliteStorage::open_with_persisted_schemas,
        ] {
            let directory = TemporaryDirectory::new("native_projection_statements");
            let manifest = schema_manifest(vec![native_user_schema()]);
            let mut storage = open(directory.path(), &manifest).unwrap();
            let documents: Vec<_> = (1..=1000)
                .map(|id| NativeDocumentWrite {
                    id,
                    values: vec![
                        NativeDocumentValue::Bool(true),
                        NativeDocumentValue::Int(id as i64),
                        NativeDocumentValue::Bytes(b"Title".to_vec()),
                    ],
                })
                .collect();
            storage
                .put_many_native_documents("users", &documents, true)
                .unwrap();
            for limit in [Some(0), Some(1), None] {
                let plan = WireQueryPlan {
                    source: WireQuerySource::All { dedupe: false },
                    filter: None,
                    sorts: Vec::new(),
                    distinct_fields: Vec::new(),
                    offset: 0,
                    limit,
                };
                for field in ["id", "createdAtMicros", "title"] {
                    for operation in [
                        None,
                        Some("count"),
                        Some("min"),
                        Some("max"),
                        Some("sum"),
                        Some("average"),
                    ] {
                        if field == "title" && matches!(operation, Some("sum" | "average")) {
                            continue;
                        }
                        let count = Cell::new(0_usize);
                        // SQLite invokes this callback synchronously. The counter stays
                        // alive until the trace is removed, before inspecting the result.
                        let result;
                        unsafe {
                            let handle = storage.connection.handle();
                            assert_eq!(
                                rusqlite::ffi::sqlite3_trace_v2(
                                    handle,
                                    rusqlite::ffi::SQLITE_TRACE_STMT as u32,
                                    Some(count_statement),
                                    (&count as *const Cell<usize>).cast_mut().cast(),
                                ),
                                rusqlite::ffi::SQLITE_OK
                            );
                            result = match operation {
                                Some(operation) => {
                                    storage.query_plan_aggregate("users", &plan, field, operation)
                                }
                                None => storage.query_plan_project("users", &plan, field),
                            };
                            rusqlite::ffi::sqlite3_trace_v2(handle, 0, None, std::ptr::null_mut());
                        }
                        result.unwrap();
                        assert_eq!(
                            count.get(),
                            1,
                            "field={field}, operation={operation:?}, limit={limit:?}"
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn projected_query_values_preserve_types_windows_and_aggregate_semantics() {
        for open in [
            SqliteStorage::open_with_schemas,
            SqliteStorage::open_with_persisted_schemas,
        ] {
            let directory = TemporaryDirectory::new("native_projection_values");
            let mut schema = native_user_schema();
            schema
                .fields
                .push(native_field("price", "double?", "double", false));
            schema
                .fields
                .sort_by(|left, right| left.name.cmp(&right.name));
            let manifest = schema_manifest(vec![schema]);
            let mut storage = open(directory.path(), &manifest).unwrap();
            let documents: Vec<_> = (1..=6)
                .map(|id| NativeDocumentWrite {
                    id,
                    values: vec![
                        if id == 1 {
                            NativeDocumentValue::Null
                        } else {
                            NativeDocumentValue::Bool(id % 2 == 0)
                        },
                        NativeDocumentValue::Int(9_007_199_254_740_992 + id as i64),
                        if id % 3 == 0 {
                            NativeDocumentValue::Null
                        } else {
                            NativeDocumentValue::Double(id as f64 + 0.5)
                        },
                        if id == 1 {
                            NativeDocumentValue::Null
                        } else {
                            NativeDocumentValue::Bytes("Árbol".as_bytes().to_vec())
                        },
                    ],
                })
                .collect();
            storage
                .put_many_native_documents("users", &documents, true)
                .unwrap();
            for source in [
                WireQuerySource::All { dedupe: false },
                WireQuerySource::IndexEqual {
                    index_name: "completed".into(),
                    value: WireIndexValue::Bool(true),
                    dedupe: true,
                },
                WireQuerySource::IndexRange {
                    index_name: "createdAtMicros".into(),
                    lower: Some(WireIndexValue::Int(9_007_199_254_740_994)),
                    upper: Some(WireIndexValue::Int(9_007_199_254_740_997)),
                    dedupe: true,
                },
            ] {
                for filter in [
                    None,
                    Some(
                        crate::wire::encode_filter(&WireFilter::Field {
                            field: "id".into(),
                            operation: WireFilterOperation::GreaterThan,
                            value: WireValue::Int(2),
                        })
                        .unwrap(),
                    ),
                ] {
                    for (offset, limit) in [(0, None), (1, Some(3)), (0, Some(0)), (99, None)] {
                        for distinct_fields in [Vec::new(), vec!["completed".into()]] {
                            let plan = WireQueryPlan {
                                source: source.clone(),
                                filter: filter.clone(),
                                sorts: vec![crate::wire::WireQuerySort {
                                    field: "createdAtMicros".into(),
                                    ascending: false,
                                }],
                                distinct_fields,
                                offset,
                                limit,
                            };
                            let ids = storage.query_plan_ids("users", &plan).unwrap();
                            for field in [
                                "id",
                                "createdAtMicros",
                                "price",
                                "completed",
                                "title",
                                "missing",
                            ] {
                                assert_eq!(
                                    storage.query_plan_project("users", &plan, field),
                                    storage.query_project("users", &ids, field),
                                    "projection field={field}, plan={plan:?}",
                                );
                                for operation in
                                    ["count", "min", "max", "sum", "average", "unknown"]
                                {
                                    assert_eq!(
                                        storage.query_plan_aggregate("users", &plan, field, operation),
                                        storage.query_aggregate("users", &ids, field, operation),
                                        "aggregate field={field}, operation={operation}, plan={plan:?}",
                                    );
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn projects_and_aggregates_native_documents_with_sql_query_plan() {
        // Scenario: SQLite executes native projections and aggregates over
        // schema-aware query plans.
        // Covers:
        // - Candidate-id projection and aggregate APIs.
        // - Query-plan projection with range source, sort, offset, and limit.
        // - Count, min, max, sum, and average aggregate scalars.
        // - Distinct query plans keeping the same visible rows for projection
        //   and aggregate work.
        // Expected: Projection rows and scalar aggregate wire payloads match
        // MDBX-visible semantics for scalar SQLite-native columns.

        // Arrange.
        let directory = TemporaryDirectory::new("native_query_projection_aggregate");
        let mut schema = native_user_schema();
        schema
            .fields
            .push(native_field("price", "double", "double", false));
        schema
            .fields
            .sort_by(|left, right| left.name.cmp(&right.name));
        let manifest = schema_manifest(vec![schema]);
        let mut storage = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
        let documents = vec![
            NativeDocumentWrite {
                id: 1,
                values: vec![
                    NativeDocumentValue::Bool(false),
                    NativeDocumentValue::Int(10),
                    NativeDocumentValue::Double(1.5),
                    NativeDocumentValue::Bytes(b"Ana".to_vec()),
                ],
            },
            NativeDocumentWrite {
                id: 2,
                values: vec![
                    NativeDocumentValue::Bool(true),
                    NativeDocumentValue::Int(20),
                    NativeDocumentValue::Double(2.5),
                    NativeDocumentValue::Bytes(b"Ben".to_vec()),
                ],
            },
            NativeDocumentWrite {
                id: 3,
                values: vec![
                    NativeDocumentValue::Bool(true),
                    NativeDocumentValue::Int(30),
                    NativeDocumentValue::Double(3.5),
                    NativeDocumentValue::Bytes(b"Cid".to_vec()),
                ],
            },
            NativeDocumentWrite {
                id: 4,
                values: vec![
                    NativeDocumentValue::Bool(false),
                    NativeDocumentValue::Int(40),
                    NativeDocumentValue::Null,
                    NativeDocumentValue::Bytes(b"Ben".to_vec()),
                ],
            },
        ];
        storage
            .put_many_native_documents("users", &documents, true)
            .unwrap();
        let range_plan = WireQueryPlan {
            source: WireQuerySource::IndexRange {
                index_name: "createdAtMicros".to_string(),
                lower: Some(WireIndexValue::Int(0)),
                upper: Some(WireIndexValue::Int(100)),
                dedupe: false,
            },
            filter: None,
            sorts: vec![crate::wire::WireQuerySort {
                field: "createdAtMicros".to_string(),
                ascending: true,
            }],
            distinct_fields: Vec::new(),
            offset: 1,
            limit: Some(2),
        };
        let distinct_plan = WireQueryPlan {
            source: WireQuerySource::All { dedupe: false },
            filter: None,
            sorts: Vec::new(),
            distinct_fields: vec!["title".to_string()],
            offset: 0,
            limit: None,
        };

        // Act and assert.
        assert_eq!(
            storage
                .query_project("users", &[1, 3, 999], "title")
                .unwrap(),
            encode_projection_rows(&WireProjectionRows {
                row_count: 2,
                column_count: 1,
                cells: vec![
                    WireValue::String("Ana".to_string()),
                    WireValue::String("Cid".to_string()),
                ],
            })
            .unwrap()
        );
        assert_eq!(
            storage
                .query_aggregate("users", &[1, 2, 3, 999], "price", "count")
                .unwrap(),
            encode_scalar(&WireScalar::Int(3)).unwrap()
        );
        assert_eq!(
            storage
                .query_aggregate("users", &[1, 2, 3], "price", "sum")
                .unwrap(),
            encode_scalar(&WireScalar::Double(7.5)).unwrap()
        );
        assert_eq!(
            storage
                .query_aggregate("users", &[1, 2, 3], "price", "average")
                .unwrap(),
            encode_scalar(&WireScalar::Double(2.5)).unwrap()
        );
        assert_eq!(
            storage
                .query_aggregate("users", &[1, 2, 3], "title", "min")
                .unwrap(),
            encode_scalar(&WireScalar::String("Ana".to_string())).unwrap()
        );
        assert_eq!(
            storage
                .query_aggregate("users", &[1, 2, 3], "title", "max")
                .unwrap(),
            encode_scalar(&WireScalar::String("Cid".to_string())).unwrap()
        );
        assert_eq!(
            storage
                .query_plan_project("users", &range_plan, "title")
                .unwrap(),
            encode_projection_rows(&WireProjectionRows {
                row_count: 2,
                column_count: 1,
                cells: vec![
                    WireValue::String("Ben".to_string()),
                    WireValue::String("Cid".to_string()),
                ],
            })
            .unwrap()
        );
        assert_eq!(storage.query_plan_count("users", &range_plan).unwrap(), 2);
        assert_eq!(
            storage
                .query_plan_aggregate("users", &range_plan, "price", "sum")
                .unwrap(),
            encode_scalar(&WireScalar::Double(6.0)).unwrap()
        );
        assert_eq!(
            storage
                .query_plan_aggregate("users", &range_plan, "price", "average")
                .unwrap(),
            encode_scalar(&WireScalar::Double(3.0)).unwrap()
        );
        assert_eq!(
            storage
                .query_plan_project("users", &distinct_plan, "createdAtMicros")
                .unwrap(),
            encode_projection_rows(&WireProjectionRows {
                row_count: 3,
                column_count: 1,
                cells: vec![WireValue::Int(10), WireValue::Int(20), WireValue::Int(30)],
            })
            .unwrap()
        );
        assert_eq!(
            storage
                .query_plan_aggregate("users", &distinct_plan, "price", "sum")
                .unwrap(),
            encode_scalar(&WireScalar::Double(7.5)).unwrap()
        );
    }

    #[test]
    fn updates_native_documents_with_sql_query_plan() {
        // Scenario: SQLite updates rows matched by a schema-aware native query
        // plan without reading and rewriting full documents.
        // Covers:
        // - Isar-like UPDATE table SET field=? WHERE ...
        // - Binding update params before query params.
        // - Collection revision bump after matched rows change.
        // Expected: Only matching rows are updated and nonmatching rows stay
        // untouched.

        // Arrange.
        let directory = TemporaryDirectory::new("native_query_update");
        let manifest = schema_manifest(vec![native_user_schema()]);
        let mut storage = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
        let documents = vec![
            NativeDocumentWrite {
                id: 1,
                values: vec![
                    NativeDocumentValue::Bool(false),
                    NativeDocumentValue::Int(10),
                    NativeDocumentValue::Bytes(b"alpha".to_vec()),
                ],
            },
            NativeDocumentWrite {
                id: 2,
                values: vec![
                    NativeDocumentValue::Bool(true),
                    NativeDocumentValue::Int(20),
                    NativeDocumentValue::Bytes(b"zulu".to_vec()),
                ],
            },
            NativeDocumentWrite {
                id: 3,
                values: vec![
                    NativeDocumentValue::Bool(true),
                    NativeDocumentValue::Int(30),
                    NativeDocumentValue::Bytes(b"beta".to_vec()),
                ],
            },
        ];
        storage
            .put_many_native_documents("users", &documents, true)
            .unwrap();
        let after_insert = storage.collection_revision("users").unwrap();
        let plan = crate::wire::WireQueryPlan {
            source: crate::wire::WireQuerySource::All { dedupe: false },
            filter: Some(
                crate::wire::encode_filter(&crate::wire::WireFilter::Field {
                    field: "completed".to_string(),
                    operation: crate::wire::WireFilterOperation::Equal,
                    value: crate::wire::WireValue::Bool(true),
                })
                .unwrap(),
            ),
            sorts: Vec::new(),
            distinct_fields: Vec::new(),
            offset: 0,
            limit: None,
        };

        // Act.
        let count = storage
            .query_plan_update(
                "users",
                &plan,
                &[("completed".to_string(), crate::wire::WireValue::Bool(false))],
                true,
            )
            .unwrap();
        let after_update = storage.collection_revision("users").unwrap();
        let remaining_true = storage.query_plan_ids("users", &plan).unwrap();
        let false_count = storage
            .connection
            .query_row(
                "SELECT COUNT(*) FROM users WHERE completed = 0",
                [],
                |row| row.get::<_, i64>(0),
            )
            .unwrap();

        // Assert.
        assert_eq!(count, 2);
        assert_eq!(after_insert, 1);
        assert_eq!(after_update, 2);
        assert!(remaining_true.is_empty());
        assert_eq!(false_count, 3);
    }

    #[test]
    fn deletes_native_documents_from_collection_table() {
        // Scenario: A generated typed collection deletes SQLite-native rows.
        // Covers:
        // - Isar-like deletion from the collection table by row id.
        // - Avoiding generic document and index-entry cleanup for native rows.
        // Expected: Existing rows are removed and missing ids do not advance
        // the collection revision.

        // Arrange.
        let directory = TemporaryDirectory::new("native_delete");
        let manifest = schema_manifest(vec![native_user_schema()]);
        let mut storage = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
        let documents = vec![
            NativeDocumentWrite {
                id: 1,
                values: vec![
                    NativeDocumentValue::Bool(true),
                    NativeDocumentValue::Int(42),
                    NativeDocumentValue::Bytes(b"Ana".to_vec()),
                ],
            },
            NativeDocumentWrite {
                id: 2,
                values: vec![
                    NativeDocumentValue::Bool(false),
                    NativeDocumentValue::Int(84),
                    NativeDocumentValue::Bytes(b"Ada".to_vec()),
                ],
            },
        ];
        storage
            .put_many_native_documents("users", &documents, true)
            .unwrap();
        let after_insert = storage.collection_revision("users").unwrap();

        // Act.
        let handled = storage
            .delete_many_native_documents("users", &[1, 3])
            .unwrap();
        let after_delete = storage.collection_revision("users").unwrap();
        storage.delete_many_native_documents("users", &[3]).unwrap();
        let after_missing_delete = storage.collection_revision("users").unwrap();
        let ids = storage.document_ids("users").unwrap();
        let remaining = storage
            .connection
            .query_row("SELECT COUNT(*) FROM users", [], |row| row.get::<_, i64>(0))
            .unwrap();
        let generic_documents_table = storage
            .connection
            .query_row(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'documents'",
                [],
                |row| row.get::<_, i64>(0),
            )
            .optional()
            .unwrap();

        // Assert.
        assert!(handled);
        assert_eq!(after_insert, 1);
        assert_eq!(after_delete, 2);
        assert_eq!(after_missing_delete, 2);
        assert_eq!(ids, vec![2]);
        assert_eq!(remaining, 1);
        assert_eq!(generic_documents_table, None);
    }

    #[test]
    fn advances_schema_version_for_additive_changes() {
        // Scenario: A schema adds a new persisted field.
        // Covers:
        // - Additive schema compatibility validation.
        // - Schema version increments after a compatible additive update.
        // Expected: Re-registering the expanded schema advances to version 2.

        // Arrange.
        let directory = TemporaryDirectory::new("schema_additive");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let original = schema_manifest(vec![user_schema(vec![field(
            "email", "String", false, true,
        )])]);
        let expanded = schema_manifest(vec![user_schema(vec![
            field("email", "String", false, true),
            field("active", "bool?", false, false),
        ])]);

        // Act.
        storage.register_schemas(&original).unwrap();
        storage.register_schemas(&expanded).unwrap();
        let version = storage.schema_version("users").unwrap();

        // Assert.
        assert_eq!(version, Some(2));
    }

    #[test]
    fn rejects_incompatible_schema_changes() {
        // Scenario: A registered field changes its Dart type.
        // Covers:
        // - Incompatible schema validation before metadata is updated.
        // - Existing schema version preservation after rejection.
        // Expected: The schema update fails and remains at the previous version.

        // Arrange.
        let directory = TemporaryDirectory::new("schema_incompatible");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let original = schema_manifest(vec![user_schema(vec![field(
            "email", "String", false, true,
        )])]);
        let incompatible =
            schema_manifest(vec![user_schema(vec![field("email", "int", false, true)])]);

        // Act.
        storage.register_schemas(&original).unwrap();
        let result = storage.register_schemas(&incompatible);
        let version = storage.schema_version("users").unwrap();

        // Assert.
        assert!(result.unwrap_err().contains("cannot change type"));
        assert_eq!(version, Some(1));
    }

    #[test]
    fn persists_index_variant_metadata_in_schemas() {
        // Scenario: A schema declares unique, case-insensitive, and hash index
        // options.
        // Covers:
        // - Native schema manifest validation for index variants.
        // - Schema version stability when the same variants are registered
        //   again.
        // Expected: Valid index variants register once and keep version 1.

        // Arrange.
        let directory = TemporaryDirectory::new("schema_index_variants");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let mut email = field("email", "String", false, true);
        email.is_index_unique = true;
        email.index_case_sensitive = false;
        let mut token = field("token", "String", false, true);
        token.index_type = "hash".to_string();
        let mut bio = field("bio", "String", false, true);
        bio.index_type = "words".to_string();
        bio.index_case_sensitive = false;
        let manifest = schema_manifest(vec![user_schema(vec![email, token, bio])]);

        // Act.
        storage.register_schemas(&manifest).unwrap();
        storage.register_schemas(&manifest).unwrap();
        let version = storage.schema_version("users").unwrap();

        // Assert.
        assert_eq!(version, Some(1));
    }

    #[test]
    fn rejects_incompatible_index_option_changes() {
        // Scenario: A registered index changes its uniqueness option.
        // Covers:
        // - Index option compatibility validation.
        // - Existing schema version preservation after rejection.
        // Expected: Changing index options waits for future public migration
        // tooling.

        // Arrange.
        let directory = TemporaryDirectory::new("schema_index_option_change");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let original = schema_manifest(vec![user_schema(vec![field(
            "email", "String", false, true,
        )])]);
        let mut unique_email = field("email", "String", false, true);
        unique_email.is_index_unique = true;
        let incompatible = schema_manifest(vec![user_schema(vec![unique_email])]);

        // Act.
        storage.register_schemas(&original).unwrap();
        let result = storage.register_schemas(&incompatible);
        let version = storage.schema_version("users").unwrap();

        // Assert.
        assert!(result.unwrap_err().contains("cannot change index options"));
        assert_eq!(version, Some(1));
    }

    #[test]
    fn rejects_ids_outside_sqlite_integer_range() {
        // Scenario: A document id exceeds SQLite's signed INTEGER range.
        // Covers:
        // - Conversion from Cindel's u64 storage trait id to SQLite i64.
        // - Error path before passing values to rusqlite.
        // Expected: Storage rejects the id instead of truncating or wrapping it.

        // Arrange.
        let directory = TemporaryDirectory::new("id_range");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let id = i64::MAX as u64 + 1;

        // Act.
        let result = storage.put("users", id, br#"{"name":"Noel"}"#);

        // Assert.
        assert!(result.unwrap_err().contains("exceeds SQLite INTEGER range"));
    }

    #[test]
    fn allocates_monotonic_ids_by_collection() {
        // Scenario: Native ids are allocated for separate collections.
        // Covers:
        // - Per-collection id counters.
        // - Monotonic id allocation without stored documents.
        // Expected: Each collection starts at 1 and advances independently.

        // Arrange.
        let directory = TemporaryDirectory::new("allocate_monotonic");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        let first_user = storage.allocate_id("users").unwrap();
        let second_user = storage.allocate_id("users").unwrap();
        let first_settings = storage.allocate_id("settings").unwrap();

        // Assert.
        assert_eq!(first_user, 1);
        assert_eq!(second_user, 2);
        assert_eq!(first_settings, 1);
    }

    #[test]
    fn persists_next_id_after_reopening_the_database_directory() {
        // Scenario: Ids are allocated, the database closes, and it reopens.
        // Covers:
        // - Persisted id_counters state.
        // - Continuing from the previous next id after a new connection.
        // Expected: Reopened databases keep allocating monotonically.

        // Arrange.
        let directory = TemporaryDirectory::new("allocate_persist");

        // Act.
        {
            let mut storage = SqliteStorage::open(directory.path()).unwrap();
            assert_eq!(storage.allocate_id("users").unwrap(), 1);
            assert_eq!(storage.allocate_id("users").unwrap(), 2);
        }

        let mut reopened = SqliteStorage::open(directory.path()).unwrap();
        let next_id = reopened.allocate_id("users").unwrap();

        // Assert.
        assert_eq!(next_id, 3);
    }

    #[test]
    fn explicit_put_advances_the_next_allocated_id() {
        // Scenario: A caller stores a manual id before using auto ids.
        // Covers:
        // - Counter advancement from [StorageEngine::put].
        // - Collision avoidance between manual and allocated ids.
        // Expected: The next allocated id is greater than the manual id.

        // Arrange.
        let directory = TemporaryDirectory::new("allocate_after_put");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.put("users", 10, br#"{"name":"Ana"}"#).unwrap();
        let allocated = storage.allocate_id("users").unwrap();

        // Assert.
        assert_eq!(allocated, 11);
    }

    #[test]
    fn typed_id_ranges_update_the_counter_once_and_reject_overflow() {
        for open in [
            SqliteStorage::open_with_schemas,
            SqliteStorage::open_with_persisted_schemas,
        ] {
            let directory = TemporaryDirectory::new("typed_id_ranges");
            let manifest = schema_manifest(vec![native_user_schema()]);
            let mut storage = open(directory.path(), &manifest).unwrap();
            let before = storage.connection.total_changes();
            assert_eq!(storage.reserve_ids("users", 1000).unwrap(), 1);
            assert_eq!(storage.connection.total_changes() - before, 1);
            assert_eq!(storage.allocate_id("users").unwrap(), 1001);
            storage
                .connection
                .execute(
                    "UPDATE id_counters SET next_id = ?1 WHERE collection = 'users'",
                    [i64::MAX - 2],
                )
                .unwrap();
            for transactional in [false, true] {
                if transactional {
                    storage.begin_write_transaction().unwrap();
                }
                assert!(storage.reserve_ids("users", 3).is_err());
                if transactional {
                    assert_eq!(
                        storage.reserve_ids("users", 2).unwrap(),
                        (i64::MAX - 2) as u64
                    );
                    assert!(storage.allocate_id("users").is_err());
                    storage.rollback_transaction().unwrap();
                }
            }
            assert_eq!(
                storage.reserve_ids("users", 2).unwrap(),
                (i64::MAX - 2) as u64
            );
            assert!(storage.allocate_id("users").is_err());
        }
    }

    #[test]
    fn typed_ids_are_shared_by_native_and_web_storage_handles() {
        for open in [
            SqliteStorage::open_with_schemas,
            SqliteStorage::open_with_persisted_schemas,
        ] {
            let directory = TemporaryDirectory::new("typed_shared_ids");
            let manifest = schema_manifest(vec![native_user_schema()]);
            let mut first = open(directory.path(), &manifest).unwrap();
            let mut second = open(directory.path(), &manifest).unwrap();
            first.begin_write_transaction().unwrap();
            assert_eq!(first.allocate_id("users").unwrap(), 1);
            first.commit_transaction().unwrap();
            second.begin_write_transaction().unwrap();
            assert_eq!(second.allocate_id("users").unwrap(), 2);
            second.commit_transaction().unwrap();
            assert_eq!(first.allocate_id("users").unwrap(), 3);
            drop(first);
            drop(second);
            let mut reopened = open(directory.path(), &manifest).unwrap();
            // Allocations remain consumed even without a document insertion.
            assert_eq!(reopened.allocate_id("users").unwrap(), 4);
        }
    }

    #[test]
    fn typed_id_counters_follow_commits_rollbacks_and_manual_writes() {
        for open in [
            SqliteStorage::open_with_schemas,
            SqliteStorage::open_with_persisted_schemas,
        ] {
            let directory = TemporaryDirectory::new("typed_id_transactions");
            let manifest = schema_manifest(vec![native_user_schema()]);
            let mut first = open(directory.path(), &manifest).unwrap();
            let mut second = open(directory.path(), &manifest).unwrap();
            let document = NativeDocumentWrite {
                id: 41,
                values: vec![
                    NativeDocumentValue::Bool(true),
                    NativeDocumentValue::Int(0),
                    NativeDocumentValue::Bytes(b"Manual".to_vec()),
                ],
            };
            first.begin_write_transaction().unwrap();
            first
                .put_many_native_documents("users", &[document.clone()], true)
                .unwrap();
            assert_eq!(first.allocate_id("users").unwrap(), 42);
            first.rollback_transaction().unwrap();
            assert_eq!(second.allocate_id("users").unwrap(), 1);
            first
                .put_many_native_documents("users", &[document], true)
                .unwrap();
            assert_eq!(second.allocate_id("users").unwrap(), 42);
            first.delete("users", 41).unwrap();
            first.begin_write_transaction().unwrap();
            assert_eq!(first.allocate_id("users").unwrap(), 43);
            first.rollback_transaction().unwrap();
            assert_eq!(second.allocate_id("users").unwrap(), 43);
            drop(first);
            drop(second);
            let mut reopened = open(directory.path(), &manifest).unwrap();
            assert_eq!(reopened.allocate_id("users").unwrap(), 44);
        }
    }

    #[test]
    fn typed_ids_bootstrap_existing_rows_without_lowering_persisted_counters() {
        for open in [
            SqliteStorage::open_with_schemas,
            SqliteStorage::open_with_persisted_schemas,
        ] {
            let directory = TemporaryDirectory::new("typed_legacy_ids");
            let manifest = schema_manifest(vec![native_user_schema()]);
            {
                let storage = open(directory.path(), &manifest).unwrap();
                // Simulate a database created before typed counters were persisted.
                storage.connection.execute("INSERT INTO users (_rowid_, completed, createdAtMicros, title) VALUES (41, 1, 0, 'Legacy')", []).unwrap();
            }
            let mut storage = open(directory.path(), &manifest).unwrap();
            assert_eq!(storage.allocate_id("users").unwrap(), 42);
            storage.delete("users", 41).unwrap();
            drop(storage);
            let mut reopened = open(directory.path(), &manifest).unwrap();
            assert_eq!(reopened.allocate_id("users").unwrap(), 43);
        }
    }

    #[test]
    fn concurrent_typed_allocations_are_unique_across_connections() {
        let directory = TemporaryDirectory::new("typed_concurrent_ids");
        let manifest = schema_manifest(vec![native_user_schema()]);
        let mut handles: Vec<_> = (0..4)
            .map(|_| SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap())
            .collect();
        let barrier = std::sync::Barrier::new(4);
        let mut ids = std::thread::scope(|scope| {
            let workers: Vec<_> = handles
                .iter_mut()
                .map(|storage| {
                    let barrier = &barrier;
                    scope.spawn(move || {
                        barrier.wait();
                        (0..16)
                            .map(|_| storage.allocate_id("users").unwrap())
                            .collect::<Vec<_>>()
                    })
                })
                .collect();
            workers
                .into_iter()
                .flat_map(|worker| worker.join().unwrap())
                .collect::<Vec<_>>()
        });
        ids.sort_unstable();
        assert_eq!(ids, (1..=64).collect::<Vec<_>>());
    }

    #[test]
    fn queries_documents_by_index_equality() {
        // Scenario: Documents are indexed by a string field.
        // Covers:
        // - [StorageEngine::put_indexed] inserting index entries.
        // - [StorageEngine::query_index_equal] finding ids by indexed value.
        // Expected: Equality queries return matching document ids in id order.

        // Arrange.
        let directory = TemporaryDirectory::new("index_equal");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage
            .put_indexed(
                "users",
                1,
                br#"{"email":"a@example.com"}"#,
                &[index("email", IndexValue::String("a@example.com".into()))],
            )
            .unwrap();
        storage
            .put_indexed(
                "users",
                2,
                br#"{"email":"b@example.com"}"#,
                &[index("email", IndexValue::String("b@example.com".into()))],
            )
            .unwrap();
        storage
            .put_indexed(
                "users",
                3,
                br#"{"email":"a@example.com"}"#,
                &[index("email", IndexValue::String("a@example.com".into()))],
            )
            .unwrap();
        let ids = storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("a@example.com".into()),
            )
            .unwrap();

        // Assert.
        assert_eq!(ids, vec![1, 3]);
    }

    #[test]
    fn queries_documents_by_index_range() {
        // Scenario: Numeric scores are queried by an inclusive range.
        // Covers:
        // - Ordered range scan over integer index entries.
        // - Lower and upper bound filtering.
        // Expected: Range queries return matching ids ordered by score.

        // Arrange.
        let directory = TemporaryDirectory::new("index_range");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage
            .put_indexed(
                "users",
                1,
                br#"{"score":10}"#,
                &[index("score", IndexValue::Int(10))],
            )
            .unwrap();
        storage
            .put_indexed(
                "users",
                2,
                br#"{"score":30}"#,
                &[index("score", IndexValue::Int(30))],
            )
            .unwrap();
        storage
            .put_indexed(
                "users",
                3,
                br#"{"score":20}"#,
                &[index("score", IndexValue::Int(20))],
            )
            .unwrap();
        let ids = storage
            .query_index_range(
                "users",
                "score",
                Some(&IndexValue::Int(15)),
                Some(&IndexValue::Int(30)),
            )
            .unwrap();

        // Assert.
        assert_eq!(ids, vec![3, 2]);
    }

    #[test]
    fn replaces_and_deletes_index_entries_with_documents() {
        // Scenario: A document changes and is later deleted.
        // Covers:
        // - Replacing old index entries when a document is overwritten.
        // - Removing index entries when a document is deleted.
        // Expected: Queries never return stale index entries.

        // Arrange.
        let directory = TemporaryDirectory::new("index_replace_delete");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage
            .put_indexed(
                "users",
                1,
                br#"{"email":"old@example.com"}"#,
                &[index("email", IndexValue::String("old@example.com".into()))],
            )
            .unwrap();
        storage
            .put_indexed(
                "users",
                1,
                br#"{"email":"new@example.com"}"#,
                &[index("email", IndexValue::String("new@example.com".into()))],
            )
            .unwrap();
        let old_ids = storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("old@example.com".into()),
            )
            .unwrap();
        let new_ids = storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("new@example.com".into()),
            )
            .unwrap();

        // Assert.
        assert_eq!(old_ids, Vec::<u64>::new());
        assert_eq!(new_ids, vec![1]);

        // Act.
        storage.delete("users", 1).unwrap();
        let deleted_ids = storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("new@example.com".into()),
            )
            .unwrap();

        // Assert.
        assert_eq!(deleted_ids, Vec::<u64>::new());
    }

    #[test]
    fn bulk_puts_documents_atomically_and_updates_indexes() {
        // Scenario: Multiple indexed documents are written in one batch.
        // Covers:
        // - [StorageEngine::put_many_indexed] transaction path.
        // - Index writes for every document in the batch.
        // - One collection revision bump for the committed batch.
        // Expected: All documents and indexes are visible after commit.

        // Arrange.
        let directory = TemporaryDirectory::new("bulk_put");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let documents = vec![
            document_write(
                1,
                br#"{"email":"team@example.com"}"#,
                vec![index(
                    "email",
                    IndexValue::String("team@example.com".into()),
                )],
            ),
            document_write(
                2,
                br#"{"email":"solo@example.com"}"#,
                vec![index(
                    "email",
                    IndexValue::String("solo@example.com".into()),
                )],
            ),
        ];

        // Act.
        storage.put_many_indexed("users", &documents).unwrap();
        let ids = storage.document_ids("users").unwrap();
        let team_ids = storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("team@example.com".into()),
            )
            .unwrap();
        let revision = storage.collection_revision("users").unwrap();

        // Assert.
        assert_eq!(ids, vec![1, 2]);
        assert_eq!(team_ids, vec![1]);
        assert_eq!(revision, 1);
    }

    #[test]
    fn rolls_back_bulk_put_when_one_document_is_invalid() {
        // Scenario: One document in a batch has an id outside SQLite range.
        // Covers:
        // - Native transaction rollback for partial bulk write failure.
        // - No persisted documents or revision bump after rollback.
        // Expected: Earlier valid writes in the same batch are not committed.

        // Arrange.
        let directory = TemporaryDirectory::new("bulk_put_rollback");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let documents = vec![
            document_write(1, br#"{"name":"Ana"}"#, vec![]),
            document_write(i64::MAX as u64 + 1, br#"{"name":"Bad"}"#, vec![]),
        ];

        // Act.
        let result = storage.put_many_indexed("users", &documents);
        let stored = storage.get("users", 1).unwrap();
        let revision = storage.collection_revision("users").unwrap();

        // Assert.
        assert!(result.unwrap_err().contains("exceeds SQLite INTEGER range"));
        assert_eq!(stored, None);
        assert_eq!(revision, 0);
    }

    #[test]
    fn bulk_deletes_documents_atomically_and_cleans_indexes() {
        // Scenario: Multiple indexed documents are deleted in one batch.
        // Covers:
        // - [StorageEngine::delete_many] transaction path.
        // - Index cleanup for every deleted document.
        // - One collection revision bump for the committed batch.
        // Expected: Documents and index entries are removed together.

        // Arrange.
        let directory = TemporaryDirectory::new("bulk_delete");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        storage
            .put_many_indexed(
                "users",
                &[
                    document_write(
                        1,
                        br#"{"email":"team@example.com"}"#,
                        vec![index(
                            "email",
                            IndexValue::String("team@example.com".into()),
                        )],
                    ),
                    document_write(
                        2,
                        br#"{"email":"team@example.com"}"#,
                        vec![index(
                            "email",
                            IndexValue::String("team@example.com".into()),
                        )],
                    ),
                ],
            )
            .unwrap();

        // Act.
        storage.delete_many("users", &[1, 2]).unwrap();
        let ids = storage.document_ids("users").unwrap();
        let team_ids = storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("team@example.com".into()),
            )
            .unwrap();
        let revision = storage.collection_revision("users").unwrap();

        // Assert.
        assert_eq!(ids, Vec::<u64>::new());
        assert_eq!(team_ids, Vec::<u64>::new());
        assert_eq!(revision, 2);
    }

    #[test]
    fn rolls_back_bulk_delete_when_one_id_is_invalid() {
        // Scenario: One id in a delete batch is outside SQLite range.
        // Covers:
        // - Native transaction rollback for partial bulk delete failure.
        // - Preserving previously deleted documents after rollback.
        // Expected: The valid delete in the same batch is not committed.

        // Arrange.
        let directory = TemporaryDirectory::new("bulk_delete_rollback");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();

        // Act.
        let result = storage.delete_many("users", &[1, i64::MAX as u64 + 1]);
        let stored = storage.get("users", 1).unwrap();
        let revision = storage.collection_revision("users").unwrap();

        // Assert.
        assert!(result.unwrap_err().contains("exceeds SQLite INTEGER range"));
        assert_eq!(stored, Some(br#"{"name":"Ana"}"#.to_vec()));
        assert_eq!(revision, 1);
    }

    #[test]
    fn commits_explicit_write_transactions() {
        // Scenario: Multiple writes are wrapped in one explicit transaction.
        // Covers:
        // - [StorageEngine::begin_write_transaction].
        // - Writes reusing the active transaction instead of creating nested
        //   SQLite transactions.
        // - [StorageEngine::commit_transaction].
        // Expected: All writes become visible after commit.

        // Arrange.
        let directory = TemporaryDirectory::new("txn_commit");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.begin_write_transaction().unwrap();
        storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
        storage.put("users", 2, br#"{"name":"Ben"}"#).unwrap();
        storage.commit_transaction().unwrap();
        let ids = storage.document_ids("users").unwrap();

        // Assert.
        assert_eq!(ids, vec![1, 2]);
    }

    #[test]
    fn rolls_back_explicit_write_transactions() {
        // Scenario: A write transaction is rolled back after partial writes.
        // Covers:
        // - [StorageEngine::rollback_transaction].
        // - Documents, indexes, counters, and revisions being reverted.
        // Expected: No partial transaction state is persisted.

        // Arrange.
        let directory = TemporaryDirectory::new("txn_rollback");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.begin_write_transaction().unwrap();
        storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
        storage
            .put_indexed(
                "users",
                2,
                br#"{"email":"ben@example.com"}"#,
                &[index("email", IndexValue::String("ben@example.com".into()))],
            )
            .unwrap();
        storage.rollback_transaction().unwrap();
        let ids = storage.document_ids("users").unwrap();
        let indexed_ids = storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("ben@example.com".into()),
            )
            .unwrap();
        let revision = storage.collection_revision("users").unwrap();
        let allocated_id = storage.allocate_id("users").unwrap();

        // Assert.
        assert_eq!(ids, Vec::<u64>::new());
        assert_eq!(indexed_ids, Vec::<u64>::new());
        assert_eq!(revision, 0);
        assert_eq!(allocated_id, 1);
    }

    #[test]
    fn rejects_writes_inside_read_transactions() {
        // Scenario: A caller tries to mutate during an explicit read
        // transaction.
        // Covers:
        // - Native read transaction ownership rules.
        // - Write rejection before SQLite mutating statements run.
        // Expected: The write fails and no data is persisted.

        // Arrange.
        let directory = TemporaryDirectory::new("txn_read_write");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.begin_read_transaction().unwrap();
        let result = storage.put("users", 1, br#"{"name":"Ana"}"#);
        storage.rollback_transaction().unwrap();
        let stored = storage.get("users", 1).unwrap();

        // Assert.
        assert!(result.unwrap_err().contains("read transaction"));
        assert_eq!(stored, None);
    }

    #[test]
    fn rejects_nested_explicit_transactions() {
        // Scenario: A transaction is opened while another is active.
        // Covers:
        // - Native transaction handle ownership rules.
        // Expected: Cindel rejects nested transactions for now.

        // Arrange.
        let directory = TemporaryDirectory::new("txn_nested");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.begin_write_transaction().unwrap();
        let nested = storage.begin_read_transaction();
        storage.rollback_transaction().unwrap();

        // Assert.
        assert!(nested.unwrap_err().contains("already active"));
    }

    fn index(name: &str, value: IndexValue) -> IndexEntry {
        IndexEntry {
            name: name.to_string(),
            value,
        }
    }

    fn document_write(id: u64, bytes: &[u8], indexes: Vec<IndexEntry>) -> DocumentWrite {
        DocumentWrite {
            id,
            bytes: bytes.to_vec(),
            indexes,
        }
    }

    fn schema_manifest(collections: Vec<CollectionSchemaManifest>) -> SchemaManifest {
        SchemaManifest { collections }
    }

    fn user_schema(mut fields: Vec<FieldSchemaManifest>) -> CollectionSchemaManifest {
        fields.push(field("id", "int", true, false));
        fields.sort_by(|left, right| left.name.cmp(&right.name));
        CollectionSchemaManifest {
            name: "users".to_string(),
            id_field: "id".to_string(),
            fields,
            composite_indexes: Vec::new(),
        }
    }

    fn native_user_schema() -> CollectionSchemaManifest {
        let mut fields = vec![
            native_field("completed", "bool", "bool", false),
            native_field("createdAtMicros", "int", "int", false),
            native_field("id", "int", "int", true),
            native_field("title", "String", "string", false),
        ];
        fields.sort_by(|left, right| left.name.cmp(&right.name));
        CollectionSchemaManifest {
            name: "users".to_string(),
            id_field: "id".to_string(),
            fields,
            composite_indexes: Vec::new(),
        }
    }

    fn wide_native_user_schema(field_count: usize) -> CollectionSchemaManifest {
        let mut fields = (0..field_count)
            .map(|index| native_field(&format!("field_{index:03}"), "int", "int", false))
            .collect::<Vec<_>>();
        fields.push(native_field("id", "int", "int", true));
        fields.sort_by(|left, right| left.name.cmp(&right.name));
        CollectionSchemaManifest {
            name: "users".to_string(),
            id_field: "id".to_string(),
            fields,
            composite_indexes: Vec::new(),
        }
    }

    fn field(name: &str, dart_type: &str, is_id: bool, is_indexed: bool) -> FieldSchemaManifest {
        FieldSchemaManifest {
            name: name.to_string(),
            dart_type: dart_type.to_string(),
            binary_type: dart_type.to_string(),
            is_id,
            is_indexed,
            is_index_unique: false,
            is_index_replace: false,
            index_case_sensitive: true,
            index_type: "value".to_string(),
        }
    }

    fn native_field(
        name: &str,
        dart_type: &str,
        binary_type: &str,
        is_id: bool,
    ) -> FieldSchemaManifest {
        FieldSchemaManifest {
            name: name.to_string(),
            dart_type: dart_type.to_string(),
            binary_type: binary_type.to_string(),
            is_id,
            is_indexed: false,
            is_index_unique: false,
            is_index_replace: false,
            index_case_sensitive: true,
            index_type: "value".to_string(),
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
            let path = std::env::temp_dir().join(format!("cindel_{name}_{nonce}"));
            Self { path }
        }

        fn path(&self) -> &str {
            self.path.to_str().unwrap()
        }
    }

    impl Drop for TemporaryDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }
}
