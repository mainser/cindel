// Included in sqlite::tests; use the same table shape emitted before TEXT affinity.
fn legacy_string_table(connection: &Connection) {
    connection.execute_batch(
        "CREATE TABLE users (_rowid_ INTEGER PRIMARY KEY, completed bool, createdAtMicros i64, title str)",
    ).unwrap();
}

#[test]
fn string_affinity_new_tables_keep_exact_text() {
    // Scenario: A typed table receives numeric-looking strings through native writes.
    // Covers: TEXT declaration and scalar storage independently of Dart readers.
    // Expected: Every value has SQLite text storage and retains its original bytes.
    // Arrange.
    let mut storage =
        SqliteStorage::open_with_schemas(":memory:", &schema_manifest(vec![native_user_schema()]))
            .unwrap();
    let values = [
        "00123",
        "123",
        "+007",
        "1e3",
        "3.1400",
        " 42 ",
        "99999999999999999999999",
    ];
    // Act / Assert.
    for (id, value) in values.iter().enumerate() {
        storage
            .put_many_native_documents(
                "users",
                &[NativeDocumentWrite {
                    id: id as u64,
                    values: vec![
                        NativeDocumentValue::Bool(true),
                        NativeDocumentValue::Int(42),
                        NativeDocumentValue::Bytes(value.as_bytes().to_vec()),
                    ],
                }],
                true,
            )
            .unwrap();
        let stored: (String, String) = storage
            .connection
            .query_row(
                "SELECT title, typeof(title) FROM users WHERE _rowid_=?1",
                [id as i64],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .unwrap();
        assert_eq!(stored, (value.to_string(), "text".into()));
    }
}

#[test]
fn string_affinity_upgrades_persisted_tables_once_without_side_effects() {
    // Scenario: A legacy database has strings, an already converted numeric value,
    // null, a secondary index, a trigger, a view, relations and reserved IDs.
    // Covers: Reopen upgrade, preserved metadata/objects and idempotent registration.
    // Expected: Existing stored values remain readable; subsequent strings stay exact;
    // no trigger fires while copying and IDs, relations and revisions stay unchanged.
    // Arrange.
    let dir = TemporaryDirectory::new("text_upgrade");
    let manifest = schema_manifest(vec![native_user_schema()]);
    {
        let mut old = SqliteStorage::open(dir.path()).unwrap();
        legacy_string_table(&old.connection);
        old.register_schemas(&manifest).unwrap();
        // Restore the old declaration after metadata registration to simulate disk
        // contents from the previous binary without embedding an obsolete binary.
        old.connection.execute_batch("DROP TABLE users").unwrap();
        legacy_string_table(&old.connection);
        old.connection.execute_batch(
            "INSERT INTO users VALUES (1,1,42,'original'),(2,0,84,'00123'),(3,NULL,NULL,NULL);
             CREATE INDEX users_title ON users(title);
             CREATE TABLE text_audit (value TEXT);
             CREATE TRIGGER users_insert AFTER INSERT ON users BEGIN INSERT INTO text_audit VALUES(new.title); END;
             CREATE VIEW user_titles AS SELECT _rowid_,title FROM users;
             INSERT INTO cindel_relations VALUES ('users',1,'friends','users',2);
             INSERT INTO collection_revisions VALUES ('users',17);",
        ).unwrap();
        assert_eq!(old.reserve_ids("users", 100).unwrap(), 1);
    }
    // Act.
    let mut storage = SqliteStorage::open_with_persisted_schemas(dir.path(), &manifest).unwrap();
    // Assert.
    let titles: Vec<Option<String>> = storage
        .connection
        .prepare("SELECT title FROM user_titles ORDER BY _rowid_")
        .unwrap()
        .query_map([], |r| r.get(0))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    // The original zeros were lost before upgrading; never manufacture them.
    assert_eq!(
        titles,
        vec![Some("original".into()), Some("123".into()), None]
    );
    assert_eq!(storage.collection_revision("users").unwrap(), 17);
    assert_eq!(storage.schema_version("users").unwrap(), Some(1));
    assert_eq!(storage.reserve_ids("users", 1).unwrap(), 101);
    assert_eq!(
        storage
            .connection
            .query_row("SELECT count(*) FROM cindel_relations", [], |r| r
                .get::<_, i64>(0))
            .unwrap(),
        1
    );
    assert_eq!(
        storage
            .connection
            .query_row("SELECT count(*) FROM text_audit", [], |r| r
                .get::<_, i64>(0))
            .unwrap(),
        0
    );
    let before = storage.connection.total_changes();
    text::upgrade_legacy_columns(&storage.connection, "users").unwrap();
    assert_eq!(
        storage.connection.total_changes(),
        before,
        "reopen must not rewrite rows"
    );
    storage
        .connection
        .execute("INSERT INTO users (_rowid_,title) VALUES (4,?1)", ["00123"])
        .unwrap();
    assert_eq!(
        storage
            .connection
            .query_row("SELECT value FROM text_audit", [], |r| r
                .get::<_, String>(0))
            .unwrap(),
        "00123"
    );
    assert_eq!(
        storage
            .connection
            .query_row(
                "SELECT title FROM users INDEXED BY users_title WHERE title='00123'",
                [],
                |r| r.get::<_, String>(0)
            )
            .unwrap(),
        "00123"
    );
}

#[test]
fn string_affinity_upgrade_failure_rolls_back_inside_transaction() {
    // Scenario: Upgrading a legacy table fails after replacing it within a write txn.
    // Covers: Savepoint rollback, restored objects/data and connection PRAGMA state.
    // Expected: Catching the failure and committing leaves the old table intact;
    // a retry upgrades it normally.
    // Arrange.
    let connection = Connection::open_in_memory().unwrap();
    legacy_string_table(&connection);
    connection.execute_batch("INSERT INTO users VALUES(1,1,42,'original'); CREATE INDEX users_title ON users(title); BEGIN").unwrap();
    text::FAIL_AFTER_RENAME.with(|fail| fail.set(true));
    // Act.
    let error = text::upgrade_legacy_columns(&connection, "users").unwrap_err();
    connection.execute_batch("COMMIT").unwrap();
    // Assert.
    assert!(error.contains("injected"));
    assert_eq!(
        connection
            .query_row(
                "SELECT type FROM pragma_table_info('users') WHERE name='title'",
                [],
                |r| r.get::<_, String>(0)
            )
            .unwrap(),
        "str"
    );
    assert_eq!(
        connection
            .query_row("SELECT title FROM users INDEXED BY users_title", [], |r| {
                r.get::<_, String>(0)
            })
            .unwrap(),
        "original"
    );
    assert_eq!(
        connection
            .query_row("PRAGMA legacy_alter_table", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        0
    );
    assert_eq!(
        connection
            .query_row(
                "SELECT count(*) FROM sqlite_schema WHERE name LIKE '_cindel_text_upgrade_%'",
                [],
                |r| r.get::<_, i64>(0)
            )
            .unwrap(),
        0
    );
    text::upgrade_legacy_columns(&connection, "users").unwrap();
    assert_eq!(
        connection
            .query_row(
                "SELECT type FROM pragma_table_info('users') WHERE name='title'",
                [],
                |r| r.get::<_, String>(0)
            )
            .unwrap(),
        "TEXT"
    );
}

#[test]
fn string_affinity_upgrade_streams_rows_without_rust_materialization() {
    // Scenario: The one-time upgrade runs over small and large legacy tables.
    // Covers: Rust peak allocations, copied-row count and metadata-only repeat check.
    // Expected: Exactly N rows copied once, with Rust memory independent of N.
    // Arrange / Act / Assert.
    for count in [1000, 50000, 1_000_000] {
        let dir = TemporaryDirectory::new("text_upgrade_memory");
        fs::create_dir_all(dir.path()).unwrap();
        let connection = Connection::open(dir.path.join("memory.sqlite")).unwrap();
        connection
            .execute_batch("PRAGMA journal_mode=WAL; PRAGMA mmap_size=1073741824;")
            .unwrap();
        legacy_string_table(&connection);
        connection
            .execute_batch(&format!(
                "WITH RECURSIVE seq(n) AS (VALUES(1) UNION ALL SELECT n+1 FROM seq WHERE n<{count})
             INSERT INTO users SELECT n,1,n,'value-'||n FROM seq;",
            ))
            .unwrap();
        let before = connection.total_changes();
        // SQLite uses its own C allocator. Report it separately from Rust, and
        // run this test alone when collecting memory evidence (global counter).
        let sqlite_before = unsafe { ffi::sqlite3_memory_used() };
        unsafe {
            ffi::sqlite3_memory_highwater(1);
        }
        let started = std::time::Instant::now();
        let peak = rust_allocations::peak_bytes(|| {
            text::upgrade_legacy_columns(&connection, "users").unwrap()
        });
        let sqlite_peak = unsafe { ffi::sqlite3_memory_highwater(0) } - sqlite_before;
        eprintln!("string_affinity rows={count} rust_peak={peak} sqlite_additional_peak={sqlite_peak} elapsed_us={}", started.elapsed().as_micros());
        assert!(peak < 32 * 1024, "unexpected row materialization: {peak}");
        assert_eq!(connection.total_changes() - before, count as u64);
        assert_eq!(
            connection
                .query_row("SELECT count(*) FROM users", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            count
        );
        let copied = connection.total_changes();
        text::upgrade_legacy_columns(&connection, "users").unwrap();
        assert_eq!(connection.total_changes(), copied);
    }
}

#[test]
fn string_affinity_upgrade_preserves_extra_columns_and_binary_values() {
    // Scenario: A legacy table retains a column absent from the current manifest,
    // alongside lists, embedded bytes and a full-width integer.
    // Covers: Physical column preservation rather than copying only known fields.
    // Expected: Only str declarations change, with all other values unchanged.
    // Arrange.
    let connection = Connection::open_in_memory().unwrap();
    connection.execute_batch("CREATE TABLE users (_rowid_ INTEGER PRIMARY KEY, extra str, items str[], nested json, number i64); INSERT INTO users VALUES(1,'keep','[\"00123\"]',X'0001FF',9223372036854775807)").unwrap();
    // Act.
    text::upgrade_legacy_columns(&connection, "users").unwrap();
    // Assert.
    let values = connection
        .query_row("SELECT extra,items,nested,number FROM users", [], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, Vec<u8>>(2)?,
                r.get::<_, i64>(3)?,
            ))
        })
        .unwrap();
    assert_eq!(
        values,
        (
            "keep".into(),
            "[\"00123\"]".into(),
            vec![0, 1, 255],
            i64::MAX
        )
    );
}

#[test]
fn string_affinity_upgrade_rejects_unrecognized_table_constraints() {
    // Scenario: A physical table was customized with a constraint not emitted by Cindel.
    // Covers: Conservative layout validation before dropping/rebuilding a table.
    // Expected: An explicit error leaves the original schema and data unchanged.
    // Arrange.
    let connection = Connection::open_in_memory().unwrap();
    connection.execute_batch("CREATE TABLE users (_rowid_ INTEGER PRIMARY KEY, title str CHECK(length(title)>0)); INSERT INTO users VALUES(1,'keep')").unwrap();
    let before: String = connection
        .query_row(
            "SELECT sql FROM sqlite_schema WHERE name='users'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    // Act / Assert.
    assert!(text::upgrade_legacy_columns(&connection, "users")
        .unwrap_err()
        .contains("non-Cindel"));
    assert_eq!(
        connection
            .query_row(
                "SELECT sql FROM sqlite_schema WHERE name='users'",
                [],
                |r| r.get::<_, String>(0)
            )
            .unwrap(),
        before
    );
    assert_eq!(
        connection
            .query_row("SELECT title FROM users", [], |r| r.get::<_, String>(0))
            .unwrap(),
        "keep"
    );
}
