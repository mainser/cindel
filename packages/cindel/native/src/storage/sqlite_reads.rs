use super::*;
use std::cell::OnceCell;
use std::sync::{Arc, Mutex};

// Each of the native and batch caches holds at most eight idle statements.
// Large IN statements are used normally but never retained after the request.
pub(super) const READ_CACHE_ENTRIES: usize = 8;
pub(super) const READ_CACHE_ENTRY_BYTES: usize = 64 * 1024;

#[derive(Clone)]
pub(super) struct ReadMetadata {
    pub(super) order: Vec<usize>,
    pub(super) select: String,
    pub(super) point: Arc<CString>,
}

impl ReadMetadata {
    fn new(schema: &CollectionSchemaManifest) -> Self {
        let mut order: Vec<_> = (0..schema.fields.len())
            .filter(|&i| !schema.fields[i].is_id)
            .collect();
        order.sort_by(|&a, &b| schema.fields[a].name.cmp(&schema.fields[b].name));
        let mut select = format!("SELECT {SQLITE_ROW_ID_COLUMN}");
        for &i in &order {
            select.push_str(", ");
            select.push_str(&schema.fields[i].name);
        }
        write!(select, " FROM {} WHERE {SQLITE_ROW_ID_COLUMN}", schema.name).unwrap();
        // Registered schema identifiers have already been validated.
        let point = Arc::new(CString::new(format!("{select} = ?")).unwrap());
        Self {
            order,
            select,
            point,
        }
    }
}

impl RegisteredCollectionSchema {
    pub(super) fn new(version: u64, schema: CollectionSchemaManifest) -> Self {
        Self {
            version,
            schema,
            read: OnceCell::new(),
        }
    }

    pub(super) fn read(&self) -> &ReadMetadata {
        self.read.get_or_init(|| ReadMetadata::new(&self.schema))
    }
}

#[derive(Default)]
pub(super) struct NativeReadCache {
    idle: Vec<(Arc<CString>, *mut ffi::sqlite3_stmt)>,
    generation: u64,
    closed: bool,
    #[cfg(test)]
    pub(super) prepares: usize,
}

// Idle statements are exclusively owned by the cache; the mutex serializes
// checkout, return and destruction. Live cursors retain their existing ownership
// contract and are not made Send or Sync by this cache.
unsafe impl Send for NativeReadCache {}

impl NativeReadCache {
    #[cfg(test)]
    pub(super) fn is_closed_and_empty(&self) -> bool {
        self.closed && self.idle.is_empty()
    }
    fn invalidate(&mut self) {
        self.generation = self.generation.wrapping_add(1);
        for (_, statement) in self.idle.drain(..) {
            unsafe {
                ffi::sqlite3_finalize(statement);
            }
        }
    }
}

impl Drop for NativeReadCache {
    fn drop(&mut self) {
        self.invalidate();
    }
}

pub(super) struct NativeReadStatement {
    pub(super) statement: *mut ffi::sqlite3_stmt,
    sql: Arc<CString>,
    cache: Arc<Mutex<NativeReadCache>>,
    generation: u64,
}

impl NativeReadStatement {
    pub(super) fn acquire(
        database: *mut ffi::sqlite3,
        sql: &Arc<CString>,
        cache: &Arc<Mutex<NativeReadCache>>,
    ) -> Result<Self, String> {
        let mut state = cache.lock().unwrap_or_else(|error| error.into_inner());
        let statement = if let Some(i) = state.idle.iter().position(|(key, _)| key == sql) {
            state.idle.remove(i).1
        } else {
            let mut statement = ptr::null_mut();
            let status = unsafe {
                // Cached statements must not pin SQLite's finite lookaside slots.
                ffi::sqlite3_prepare_v3(
                    database,
                    sql.as_ptr(),
                    -1,
                    ffi::SQLITE_PREPARE_PERSISTENT,
                    &mut statement,
                    ptr::null_mut(),
                )
            };
            if status != ffi::SQLITE_OK {
                let error = sqlite_error(database);
                unsafe {
                    ffi::sqlite3_finalize(statement);
                }
                return Err(error);
            }
            #[cfg(test)]
            {
                state.prepares += 1;
            }
            statement
        };
        Ok(Self {
            statement,
            sql: Arc::clone(sql),
            cache: Arc::clone(cache),
            generation: state.generation,
        })
    }
}

impl Drop for NativeReadStatement {
    fn drop(&mut self) {
        let reset = unsafe { ffi::sqlite3_reset(self.statement) };
        let clear = unsafe { ffi::sqlite3_clear_bindings(self.statement) };
        let bytes =
            unsafe { ffi::sqlite3_stmt_status(self.statement, ffi::SQLITE_STMTSTATUS_MEMUSED, 0) }
                .max(0) as usize
                + self.sql.as_bytes().len();
        let mut state = self.cache.lock().unwrap_or_else(|error| error.into_inner());
        if reset == ffi::SQLITE_OK
            && clear == ffi::SQLITE_OK
            && !state.closed
            && state.generation == self.generation
            && bytes <= READ_CACHE_ENTRY_BYTES
        {
            if state.idle.len() == READ_CACHE_ENTRIES {
                let (_, old) = state.idle.remove(0);
                unsafe {
                    ffi::sqlite3_finalize(old);
                }
            }
            state.idle.push((Arc::clone(&self.sql), self.statement));
        } else {
            unsafe {
                ffi::sqlite3_finalize(self.statement);
            }
        }
    }
}

impl SqliteStorage {
    pub(super) fn invalidate_read_preparation(&self) {
        self.read_cache
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .invalidate();
        self.connection.flush_prepared_statement_cache();
    }
}

impl Drop for SqliteStorage {
    fn drop(&mut self) {
        // Idle raw statements must be finalized before the connection closes.
        self.invalidate_read_preparation();
        self.read_cache
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .closed = true;
    }
}

pub(super) fn finish_batch_statement(
    statement: rusqlite::CachedStatement<'_>,
    successful: bool,
    sql_bytes: usize,
) {
    let bytes = statement
        .get_status(rusqlite::StatementStatus::MemUsed)
        .max(0) as usize
        + sql_bytes;
    if !successful || bytes > READ_CACHE_ENTRY_BYTES {
        statement.discard();
    }
}
