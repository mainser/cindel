// Included in sqlite::tests to share the existing generated-schema fixtures.
fn read_preparation_storage() -> SqliteStorage {
    let mut storage =
        SqliteStorage::open_with_schemas(":memory:", &schema_manifest(vec![native_user_schema()]))
            .unwrap();
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
                    id: 2,
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
    storage
}

fn retained_read_statements(storage: &SqliteStorage) -> Vec<(String, usize, i32)> {
    let mut statements = Vec::new();
    unsafe {
        let db = storage.connection.handle();
        let mut stmt = ffi::sqlite3_next_stmt(db, ptr::null_mut());
        while !stmt.is_null() {
            let sql = CStr::from_ptr(ffi::sqlite3_sql(stmt))
                .to_string_lossy()
                .into_owned();
            if sql.starts_with("SELECT _rowid_") {
                assert_eq!(
                    ffi::sqlite3_stmt_busy(stmt),
                    0,
                    "idle cache must not retain a snapshot"
                );
                let bytes = ffi::sqlite3_stmt_status(stmt, ffi::SQLITE_STMTSTATUS_MEMUSED, 0)
                    as usize
                    + sql.len();
                statements.push((
                    sql,
                    bytes,
                    ffi::sqlite3_stmt_status(stmt, ffi::SQLITE_STMTSTATUS_RUN, 0),
                ));
            }
            stmt = ffi::sqlite3_next_stmt(db, stmt);
        }
    }
    statements
}

#[test]
fn read_preparation_reuses_native_statement_without_retaining_results() {
    // Scenario: Repeated readers use different IDs and cross a committed update.
    // Covers: Native prepare reuse, binding cleanup, missing rows and fresh snapshots.
    // Expected: One preparation; each reader observes its own IDs and current data.
    // Arrange.
    let mut storage = read_preparation_storage();
    // Act / Assert.
    for id in [1, 99, 2, 1] {
        let mut reader = storage
            .native_document_cursor("users", &[id])
            .unwrap()
            .unwrap();
        assert_eq!(reader.is_present(0).unwrap(), id != 99);
        if id == 1 {
            assert!(reader.is_present(0).unwrap());
            assert_eq!(reader.current_read_bytes(2), Some(&b"first"[..]));
        }
        if id == 2 {
            assert!(reader.is_present(0).unwrap());
            assert_eq!(reader.current_read_bytes(2), Some(&b"second"[..]));
        }
    }
    storage
        .connection
        .execute("UPDATE users SET title='updated' WHERE _rowid_=1", [])
        .unwrap();
    let mut reader = storage
        .native_document_cursor("users", &[1])
        .unwrap()
        .unwrap();
    assert!(reader.is_present(0).unwrap());
    assert_eq!(reader.current_read_bytes(2), Some(&b"updated"[..]));
    drop(reader);
    assert_eq!(storage.read_cache.lock().unwrap().prepares, 1);
    assert_eq!(retained_read_statements(&storage).len(), 1);
    storage.begin_read_transaction().unwrap();
    let mut reader = storage
        .native_document_cursor("users", &[2])
        .unwrap()
        .unwrap();
    assert!(reader.is_present(0).unwrap());
    assert_eq!(reader.current_read_int(1), Some(84));
    drop(reader);
    storage.commit_transaction().unwrap();
    assert_eq!(storage.read_cache.lock().unwrap().prepares, 1);
}

#[test]
fn read_preparation_leases_exclusively_and_discards_invalidated_readers() {
    // Scenario: Two readers overlap in a transaction while the idle cache is invalidated.
    // Covers: Exclusive statement ownership and generation checks on late returns.
    // Expected: Independent values; an invalidated active statement never reenters the cache.
    // Arrange.
    let mut storage = read_preparation_storage();
    storage.begin_read_transaction().unwrap();
    // Act.
    let mut first = storage
        .native_document_cursor("users", &[1, 2])
        .unwrap()
        .unwrap();
    let mut second = storage
        .native_document_cursor("users", &[2, 1])
        .unwrap()
        .unwrap();
    // Assert.
    assert_ne!(first.statement, second.statement);
    assert!(first.is_present(0).unwrap());
    assert_eq!(first.current_read_bytes(2), Some(&b"first"[..]));
    assert!(second.is_present(0).unwrap());
    assert_eq!(second.current_read_bytes(2), Some(&b"second"[..]));
    assert!(first.is_present(1).unwrap());
    assert_eq!(first.current_read_bytes(2), Some(&b"second"[..]));
    storage.invalidate_read_preparation();
    assert!(second.is_present(1).unwrap());
    assert_eq!(second.current_read_bytes(2), Some(&b"first"[..]));
    drop(first);
    drop(second);
    storage.commit_transaction().unwrap();
    assert!(retained_read_statements(&storage).is_empty());
}

#[test]
fn read_preparation_reuses_web_batches_and_bounds_retained_memory() {
    // Scenario: Web's result encoder repeats batches and then varies their sizes.
    // Covers: Actual SQLite statement reuse, entry/byte bounds and oversized exclusion.
    // Expected: Repeated SQL runs on one statement; cache memory stays bounded.
    // Arrange.
    let storage = read_preparation_storage();
    // Act / Assert.
    for _ in 0..4 {
        let rows = storage.get_many_stored("users", &[2, 99, 1, 2]).unwrap();
        assert_eq!(rows[0], rows[3]);
        assert!(rows[1].is_none());
    }
    let cached = retained_read_statements(&storage);
    assert_eq!(cached.len(), 1);
    assert_eq!(cached[0].2, 4);
    for size in 1..=40 {
        storage.get_many_stored("users", &vec![1; size]).unwrap();
        let cached = retained_read_statements(&storage);
        assert!(cached.len() <= READ_CACHE_ENTRIES);
        assert!(cached.iter().all(|v| v.1 <= READ_CACHE_ENTRY_BYTES));
        assert!(
            cached.iter().map(|v| v.1).sum::<usize>()
                <= READ_CACHE_ENTRIES * READ_CACHE_ENTRY_BYTES
        );
    }
    storage.get_many_stored("users", &vec![1; 4096]).unwrap();
    assert!(retained_read_statements(&storage)
        .iter()
        .all(|v| v.1 <= READ_CACHE_ENTRY_BYTES));
}

#[test]
fn read_preparation_refreshes_ordered_fields_after_schema_changes() {
    // Scenario: Cached native and Web reads precede a field inserted before old columns.
    // Covers: Schema invalidation and rebuilding ordered read metadata.
    // Expected: New column order is correct in both result paths; no old statement survives.
    // Arrange.
    let mut storage = read_preparation_storage();
    drop(
        storage
            .native_document_cursor("users", &[1])
            .unwrap()
            .unwrap(),
    );
    storage.get_many_stored("users", &[1]).unwrap();
    let mut schema = native_user_schema();
    schema
        .fields
        .push(native_field("aaa", "String?", "string", false));
    // Act.
    storage
        .connection
        .execute("ALTER TABLE users ADD COLUMN aaa TEXT", [])
        .unwrap();
    storage
        .register_schemas(&schema_manifest(vec![schema]))
        .unwrap();
    // Assert.
    assert!(retained_read_statements(&storage).is_empty());
    let mut reader = storage
        .native_document_cursor("users", &[1])
        .unwrap()
        .unwrap();
    assert!(reader.is_present(0).unwrap());
    assert_eq!(reader.current_read_bytes(0), None);
    assert!(reader.is_present(0).unwrap());
    assert_eq!(reader.current_read_bool(1), Some(true));
    assert!(reader.is_present(0).unwrap());
    assert_eq!(reader.current_read_int(2), Some(42));
    assert!(reader.is_present(0).unwrap());
    assert_eq!(reader.current_read_bytes(3), Some(&b"first"[..]));
    drop(reader);
    let rows = storage.get_many_stored("users", &[1]).unwrap();
    assert_eq!(&rows[0].as_ref().unwrap()[..3], &[15, 0, 0]);
}

#[test]
fn read_preparation_discards_failed_statements_and_recovers() {
    // Scenario: SQLite is interrupted while reusing prepared reads.
    // Covers: Error propagation and eviction of failed native/Web statements.
    // Expected: Failed statements are not retained and a subsequent read succeeds.
    // Arrange.
    let storage = read_preparation_storage();
    unsafe extern "C" fn interrupt(_: *mut c_void) -> i32 {
        1
    }
    // Act / Assert.
    let mut reader = storage
        .native_document_cursor("users", &[1])
        .unwrap()
        .unwrap();
    unsafe {
        ffi::sqlite3_progress_handler(
            storage.connection.handle(),
            1,
            Some(interrupt),
            ptr::null_mut(),
        );
    }
    assert!(reader.is_present(0).is_err());
    unsafe {
        ffi::sqlite3_progress_handler(storage.connection.handle(), 0, None, ptr::null_mut());
    }
    drop(reader);
    assert!(retained_read_statements(&storage).is_empty());
    storage.get_many_stored("users", &[1]).unwrap();
    unsafe {
        ffi::sqlite3_progress_handler(
            storage.connection.handle(),
            1,
            Some(interrupt),
            ptr::null_mut(),
        );
    }
    assert!(storage.get_many_stored("users", &[1]).is_err());
    unsafe {
        ffi::sqlite3_progress_handler(storage.connection.handle(), 0, None, ptr::null_mut());
    }
    assert!(retained_read_statements(&storage).is_empty());
    assert!(storage.get_many_stored("users", &[1]).unwrap()[0].is_some());
}

#[test]
fn read_preparation_bounds_native_cache_and_excludes_wide_statements() {
    // Scenario: Many collections and one very wide collection are read.
    // Covers: Native entry and byte bounds, close cleanup and metadata isolation.
    // Expected: No more than eight small statements survive; oversized SQL is released.
    // Arrange.
    let mut storage = read_preparation_storage();
    let schemas: Vec<_> = (0..20)
        .map(|i| {
            let mut schema = native_user_schema();
            schema.name = format!("users{i}");
            schema
        })
        .collect();
    storage.register_schemas(&schema_manifest(schemas)).unwrap();
    // Act / Assert.
    for i in 0..20 {
        drop(
            storage
                .native_document_cursor(&format!("users{i}"), &[99])
                .unwrap()
                .unwrap(),
        );
        let entries = retained_read_statements(&storage);
        assert!(entries.len() <= READ_CACHE_ENTRIES);
        assert!(entries.iter().all(|v| v.1 <= READ_CACHE_ENTRY_BYTES));
    }
    let mut wide = wide_native_user_schema(512);
    wide.name = "wide".into();
    storage
        .register_schemas(&schema_manifest(vec![wide]))
        .unwrap();
    drop(
        storage
            .native_document_cursor("wide", &[1])
            .unwrap()
            .unwrap(),
    );
    assert!(retained_read_statements(&storage).is_empty());
    let cache = Arc::clone(&storage.read_cache);
    drop(storage);
    assert!(cache.lock().unwrap().is_closed_and_empty());
}

#[test]
fn read_preparation_does_not_pin_sqlite_lookaside_memory() {
    // Scenario: Long-lived cached reads share a connection with other operations.
    // Covers: The persistent-prepare hint preserving SQLite's temporary allocation pool.
    // Expected: Returning cached statements leaves the original number of lookaside slots in use.
    // Arrange.
    let storage = read_preparation_storage();
    let used = || {
        let mut current = 0;
        let mut peak = 0;
        unsafe {
            assert_eq!(
                ffi::sqlite3_db_status(
                    storage.connection.handle(),
                    ffi::SQLITE_DBSTATUS_LOOKASIDE_USED,
                    &mut current,
                    &mut peak,
                    0
                ),
                ffi::SQLITE_OK
            );
        }
        current
    };
    let before = used();
    // Act.
    {
        let mut reader = storage
            .native_document_cursor("users", &[1])
            .unwrap()
            .unwrap();
        assert!(reader.is_present(0).unwrap());
    }
    storage.get_many_stored("users", &[1, 2]).unwrap();
    // Assert.
    assert_eq!(retained_read_statements(&storage).len(), 2);
    assert_eq!(used(), before);
}
