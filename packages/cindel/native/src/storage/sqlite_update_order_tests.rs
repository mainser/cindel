thread_local! {
    pub(super) static UPDATE_STATEMENT_STATS: std::cell::Cell<(i32, i32, i32)> = const { std::cell::Cell::new((0,0,0)) };
}

#[test]
fn update_order_sqlite_keeps_sort_for_windows_distinct_and_index_mutations() {
    // Scenario: Ordered updates have a selection window, distinct or indexed changes.
    // Covers: Actual SQL preparation for every excluded case, including composite members.
    // Expected: They retain the subquery work rather than using a direct full-table update.
    for mode in ["limit", "offset", "distinct", "index", "composite"] {
        // Arrange.
        let storage = read_preparation_storage();
        let mut schema = native_user_schema();
        if mode == "index" {
            schema
                .fields
                .iter_mut()
                .find(|f| f.name == "completed")
                .unwrap()
                .is_indexed = true;
        }
        if mode == "composite" {
            schema
                .composite_indexes
                .push(crate::storage::CompositeIndexSchemaManifest {
                    name: "completed_title".into(),
                    fields: vec!["completed".into(), "title".into()],
                    is_unique: false,
                    is_replace: false,
                    case_sensitive: true,
                });
        }
        let mut plan = unordered_update_plan();
        match mode {
            "limit" => plan.limit = Some(1),
            "offset" => plan.offset = 1,
            "distinct" => plan.distinct_fields = vec!["completed".into()],
            _ => (),
        }
        // Act.
        update_native_query_plan(
            &storage.connection,
            &schema,
            &plan,
            &[("completed".into(), WireValue::Bool(false))],
        )
        .unwrap();
        let stats = UPDATE_STATEMENT_STATS.with(|s| s.get());
        // Assert.
        assert!(stats.1 > 26, "{mode}: {stats:?}");
    }
}

#[test]
fn update_order_sqlite_validates_sort_names_and_preserves_revision() {
    // Scenario: A sorted unlimited update names a nonexistent sort field.
    // Covers: Validation before direct UPDATE and rollback of revision metadata.
    // Expected: An error with unchanged rows and collection revision.
    // Arrange.
    let mut storage = read_preparation_storage();
    let before = storage.get("users", 1).unwrap();
    let revision = storage.collection_revision("users").unwrap();
    let mut plan = unordered_update_plan();
    plan.sorts[0].field = "missing".into();
    // Act.
    let result = storage.query_plan_update(
        "users",
        &plan,
        &[("completed".into(), WireValue::Bool(false))],
        false,
    );
    // Assert.
    assert!(result.is_err());
    assert_eq!(storage.get("users", 1).unwrap(), before);
    assert_eq!(storage.collection_revision("users").unwrap(), revision);
}

#[test]
fn update_order_sqlite_reports_memory_without_retaining_id_batches() {
    // Scenario: Growing tables execute the previous SQL shape and the direct update.
    // Covers: SQLite VM steps, C allocation peak and Rust temporary allocations.
    // Expected: The direct statement performs less VM work with bounded Rust memory.
    // SQLite allocation counters are process-global: run this test alone when
    // collecting C memory evidence. Only thread-local Rust memory is asserted.
    for count in [1000, 50000] {
        // Arrange.
        let schema = native_user_schema();
        let plan = unordered_update_plan();
        let updates = [("completed".into(), WireValue::Bool(false))];
        // Act: use fresh, identically seeded databases for both SQL shapes.
        let mut steps = Vec::new();
        for previous in [true, false] {
            let storage = read_preparation_storage();
            storage.connection.execute_batch(&format!(
                "DELETE FROM users;
                 WITH RECURSIVE seq(n) AS (VALUES(1) UNION ALL SELECT n+1 FROM seq WHERE n<{count})
                 INSERT INTO users (_rowid_,completed,createdAtMicros,title) SELECT n,1,n,'value-'||n FROM seq;"
            )).unwrap();
            let used = unsafe { ffi::sqlite3_memory_used() };
            unsafe {
                ffi::sqlite3_memory_highwater(1);
            }
            let rust_peak = rust_allocations::peak_bytes(|| {
                if previous {
                    let (set_sql, mut params) = sqlite_update_sql(&schema, &updates).unwrap();
                    let (select_sql, select_params) =
                        sqlite_query_plan_sql(&schema, &plan, SqliteQuerySelect::Ids).unwrap();
                    params.extend(select_params);
                    let old_sql =
                        format!("UPDATE users SET {set_sql} WHERE _rowid_ IN ({select_sql})");
                    let mut statement = storage.connection.prepare(&old_sql).unwrap();
                    assert_eq!(
                        statement.execute(params_from_iter(params.iter())).unwrap(),
                        count
                    );
                    steps.push(statement.get_status(rusqlite::StatementStatus::VmStep));
                } else {
                    assert_eq!(
                        update_native_query_plan(&storage.connection, &schema, &plan, &updates)
                            .unwrap(),
                        count
                    );
                    steps.push(UPDATE_STATEMENT_STATS.with(|stats| stats.get().1));
                }
            });
            let c_peak = unsafe { ffi::sqlite3_memory_highwater(0) } - used;
            eprintln!("update_order_sqlite_memory rows={count} previous={previous} rust_peak={rust_peak} sqlite_additional_peak={c_peak} vm_steps={}", steps.last().unwrap());
            // Assert.
            assert!(
                rust_peak < 32768,
                "unexpected Rust batch allocation: {rust_peak}"
            );
            assert_eq!(
                storage
                    .connection
                    .query_row("SELECT count(*) FROM users WHERE completed=0", [], |row| {
                        row.get::<_, i64>(0)
                    })
                    .unwrap(),
                count as i64
            );
        }
        assert!(steps[1] < steps[0]);
    }
}

#[test]
fn update_order_sqlite_rolls_back_a_failure_after_an_earlier_row() {
    // Scenario: A trigger aborts the second row of an eligible ordered update.
    // Covers: Direct UPDATE atomicity and the revision savepoint on engine errors.
    // Expected: The first row and collection revision remain unchanged.
    // Arrange.
    let mut storage = read_preparation_storage();
    let first = storage.get("users", 1).unwrap();
    let second = storage.get("users", 2).unwrap();
    let revision = storage.collection_revision("users").unwrap();
    storage
        .connection
        .execute_batch(
            "CREATE TRIGGER fail_update BEFORE UPDATE ON users WHEN NEW._rowid_=2
         BEGIN SELECT RAISE(ABORT, 'controlled update failure'); END;",
        )
        .unwrap();
    // Act.
    let result = storage.query_plan_update(
        "users",
        &unordered_update_plan(),
        &[("completed".into(), WireValue::Bool(false))],
        false,
    );
    // Assert.
    assert!(result.unwrap_err().contains("controlled update failure"));
    assert_eq!(storage.get("users", 1).unwrap(), first);
    assert_eq!(storage.get("users", 2).unwrap(), second);
    assert_eq!(storage.collection_revision("users").unwrap(), revision);
}

fn unordered_update_plan() -> WireQueryPlan {
    WireQueryPlan {
        source: WireQuerySource::All { dedupe: false },
        filter: None,
        sorts: vec![crate::wire::WireQuerySort {
            field: "title".into(),
            ascending: false,
        }],
        distinct_fields: vec![],
        offset: 0,
        limit: None,
    }
}

#[test]
fn update_order_sqlite_avoids_sort_work_for_unbounded_nonindexed_updates() {
    // Scenario: An ordered unlimited update changes an unindexed field.
    // Covers: The executed SQLite statement, VM work and retained statement memory.
    // Expected: Zero sort operations, same work as the existing unsorted UPDATE.
    // Arrange.
    let mut storage = read_preparation_storage();
    let plan = unordered_update_plan();
    let changes = [("completed".into(), WireValue::Bool(false))];
    // Act.
    assert_eq!(
        storage
            .query_plan_update("users", &plan, &changes, false)
            .unwrap(),
        2
    );
    let sorted = UPDATE_STATEMENT_STATS.with(|stats| stats.get());
    storage
        .query_plan_update(
            "users",
            &WireQueryPlan {
                sorts: vec![],
                ..plan
            },
            &changes,
            false,
        )
        .unwrap();
    let plain = UPDATE_STATEMENT_STATS.with(|stats| stats.get());
    eprintln!("update_order_sqlite sorted={sorted:?} plain={plain:?}");
    // Assert.
    assert_eq!(sorted.0, 0);
    assert_eq!(sorted, plain);
}
