fn revision_documents(count: u64) -> Vec<NativeDocumentWrite> {
    (1..=count)
        .map(|id| NativeDocumentWrite {
            id,
            values: vec![
                NativeDocumentValue::Bool(true),
                NativeDocumentValue::Int(id as i64),
                NativeDocumentValue::Bytes(b"title".to_vec()),
            ],
        })
        .collect()
}

fn revision_plan() -> WireQueryPlan {
    WireQueryPlan {
        source: WireQuerySource::All { dedupe: false },
        filter: None,
        sorts: vec![],
        distinct_fields: vec![],
        offset: 0,
        limit: None,
    }
}

#[test]
fn persistent_revisions_initialize_legacy_typed_databases_without_losing_rows() {
    // Scenario: A typed-only database predates persistent collection revisions.
    // Covers: Additive initialization and the first post-upgrade typed batch.
    // Expected: Existing rows survive, and new commits share a persisted counter.
    let directory = TemporaryDirectory::new("revision_legacy");
    let manifest = schema_manifest(vec![native_user_schema()]);
    let mut old = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
    old.put_many_native_documents("users", &revision_documents(2), false)
        .unwrap();
    old.connection
        .execute_batch("DROP TABLE collection_revisions")
        .unwrap();
    drop(old);
    let mut upgraded = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
    let observer = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
    assert_eq!(observer.document_ids("users").unwrap(), vec![1, 2]);
    assert_eq!(observer.collection_revision("users").unwrap(), 0);
    upgraded
        .put_many_native_documents("users", &revision_documents(3), false)
        .unwrap();
    assert_eq!(observer.collection_revision("users").unwrap(), 1);
    assert_eq!(observer.document_ids("users").unwrap(), vec![1, 2, 3]);
}

#[test]
fn persistent_revisions_follow_all_typed_writes_across_connections_and_reopen() {
    // Scenario: Native and persisted-schema/Web layouts alternate typed writers.
    // Covers: Batches without change tracking, updates, both deletes and legacy counters.
    // Expected: One shared monotonic revision, unchanged by empty/missing operations.
    for open in [
        SqliteStorage::open_with_schemas,
        SqliteStorage::open_with_persisted_schemas,
    ] {
        let directory = TemporaryDirectory::new("persistent_revisions");
        let manifest = schema_manifest(vec![native_user_schema()]);
        let mut a = open(directory.path(), &manifest).unwrap();
        let mut b = open(directory.path(), &manifest).unwrap();
        a.connection
            .execute("INSERT INTO collection_revisions VALUES ('users',100)", [])
            .unwrap();
        let documents = revision_documents(3);
        a.put_many_native_documents("users", &documents, false)
            .unwrap();
        assert_eq!(b.collection_revision("users").unwrap(), 101);
        b.query_plan_update(
            "users",
            &revision_plan(),
            &[("completed".into(), WireValue::Bool(false))],
            false,
        )
        .unwrap();
        assert_eq!(a.collection_revision("users").unwrap(), 102);
        a.delete("users", 1).unwrap();
        assert_eq!(b.collection_revision("users").unwrap(), 103);
        b.delete_many_native_documents("users", &[2]).unwrap();
        assert_eq!(a.collection_revision("users").unwrap(), 104);
        a.query_plan_delete("users", &revision_plan()).unwrap();
        assert_eq!(b.collection_revision("users").unwrap(), 105);
        b.put_many_native_documents("users", &[], true).unwrap();
        b.delete_many("users", &[999]).unwrap();
        b.query_plan_update(
            "users",
            &revision_plan(),
            &[("completed".into(), WireValue::Bool(true))],
            true,
        )
        .unwrap();
        assert_eq!(a.collection_revision("users").unwrap(), 105);
        drop(a);
        drop(b);
        let mut reopened = open(directory.path(), &manifest).unwrap();
        assert_eq!(reopened.collection_revision("users").unwrap(), 105);
        reopened
            .put_many_native_documents("users", &documents, true)
            .unwrap();
        assert_eq!(reopened.collection_revision("users").unwrap(), 106);
    }
}

#[test]
fn persistent_revisions_rollback_and_obey_read_snapshots() {
    // Scenario: A reader holds a snapshot while another connection commits/rolls back.
    // Covers: Typed and generic writes to the same revision namespace.
    // Expected: Data and revisions become visible together, only after commit.
    let directory = TemporaryDirectory::new("revision_snapshot");
    let manifest = schema_manifest(vec![native_user_schema()]);
    let mut a = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
    let mut b = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
    a.begin_read_transaction().unwrap();
    assert_eq!(a.collection_revision("users").unwrap(), 0);
    b.put_many_native_documents("users", &revision_documents(2), true)
        .unwrap();
    assert_eq!(a.collection_revision("users").unwrap(), 0);
    assert!(a.document_ids("users").unwrap().is_empty());
    a.rollback_transaction().unwrap();
    assert_eq!(a.collection_revision("users").unwrap(), 1);
    b.begin_write_transaction().unwrap();
    b.delete_many_native_documents("users", &[1, 2]).unwrap();
    assert_eq!(b.collection_revision("users").unwrap(), 2);
    assert_eq!(a.collection_revision("users").unwrap(), 1);
    b.rollback_transaction().unwrap();
    assert_eq!(b.collection_revision("users").unwrap(), 1);
    assert_eq!(a.document_ids("users").unwrap(), vec![1, 2]);
    b.take_change_sets().unwrap();
    b.put("users", 90, b"legacy").unwrap();
    assert_eq!(a.collection_revision("users").unwrap(), 2);
    a.put_many_native_documents("users", &revision_documents(2), false)
        .unwrap();
    assert_eq!(b.collection_revision("users").unwrap(), 3);
}

#[test]
fn persistent_revision_failures_cannot_commit_unversioned_data() {
    // Scenario: SQLite rejects the revision write after data statements succeed.
    // Covers: Implicit/explicit transactions, caught errors, query updates and deletes.
    // Expected: The operation rolls back even if the caller catches and commits.
    for explicit in [false, true] {
        let manifest = schema_manifest(vec![native_user_schema()]);
        let mut s = SqliteStorage::open_with_schemas(":memory:", &manifest).unwrap();
        s.put_many_native_documents("users", &revision_documents(2), true)
            .unwrap();
        s.take_change_sets().unwrap();
        s.connection.execute_batch("CREATE TEMP TRIGGER reject_revision BEFORE UPDATE ON collection_revisions BEGIN SELECT RAISE(ABORT,'controlled revision failure'); END;").unwrap();
        if explicit {
            s.begin_write_transaction().unwrap();
        }
        assert!(s
            .put_many_native_documents("users", &revision_documents(3), true)
            .unwrap_err()
            .contains("controlled revision failure"));
        assert!(s
            .query_plan_update(
                "users",
                &revision_plan(),
                &[("completed".into(), WireValue::Bool(false))],
                true
            )
            .is_err());
        assert!(s.delete_many_native_documents("users", &[1]).is_err());
        if explicit {
            s.commit_transaction().unwrap();
        }
        assert_eq!(s.document_ids("users").unwrap(), vec![1, 2]);
        assert_eq!(
            s.connection
                .query_row("SELECT completed FROM users WHERE _rowid_=1", [], |r| r
                    .get::<_, bool>(0))
                .unwrap(),
            true
        );
        assert_eq!(s.collection_revision("users").unwrap(), 1);
        assert!(s.take_change_sets().unwrap().is_empty());
        s.connection
            .execute_batch("DROP TRIGGER reject_revision")
            .unwrap();
        s.put_many_native_documents("users", &revision_documents(3), true)
            .unwrap();
        assert_eq!(s.collection_revision("users").unwrap(), 2);
        s.connection
            .execute("UPDATE collection_revisions SET revision=?1", [i64::MAX])
            .unwrap();
        assert!(s.delete("users", 1).unwrap_err().contains("overflow"));
        assert_eq!(s.document_ids("users").unwrap(), vec![1, 2, 3]);
        assert_eq!(s.collection_revision("users").unwrap(), i64::MAX as u64);
    }
}

#[derive(Default)]
struct RevisionCost {
    writes: std::cell::Cell<usize>,
    commits: std::cell::Cell<usize>,
}

struct RevisionHookGuard(*mut ffi::sqlite3);

impl Drop for RevisionHookGuard {
    fn drop(&mut self) {
        unsafe {
            ffi::sqlite3_update_hook(self.0, None, ptr::null_mut());
            ffi::sqlite3_commit_hook(self.0, None, ptr::null_mut());
        }
    }
}

fn revision_cost<T>(
    storage: &mut SqliteStorage,
    action: impl FnOnce(&mut SqliteStorage) -> T,
) -> (T, usize, usize) {
    unsafe extern "C" fn update(
        context: *mut c_void,
        _: i32,
        _: *const std::ffi::c_char,
        table: *const std::ffi::c_char,
        _: i64,
    ) {
        let cost = unsafe { &*context.cast::<RevisionCost>() };
        if unsafe { CStr::from_ptr(table) }.to_bytes() == b"collection_revisions" {
            cost.writes.set(cost.writes.get() + 1);
        }
    }
    unsafe extern "C" fn commit(context: *mut c_void) -> i32 {
        let cost = unsafe { &*context.cast::<RevisionCost>() };
        cost.commits.set(cost.commits.get() + 1);
        0
    }
    let cost = Box::<RevisionCost>::default();
    let handle = unsafe { storage.connection.handle() };
    // Callbacks run synchronously. Unregister before freeing their context,
    // including when a test assertion unwinds through the action.
    let guard = RevisionHookGuard(handle);
    unsafe {
        let context = (&*cost as *const RevisionCost).cast_mut().cast();
        ffi::sqlite3_update_hook(handle, Some(update), context);
        ffi::sqlite3_commit_hook(handle, Some(commit), context);
    }
    let result = action(storage);
    drop(guard);
    (result, cost.writes.get(), cost.commits.get())
}

#[test]
fn persistent_revision_cost_is_one_write_and_commit_per_batch() {
    // Scenario: Batches grow from 1 to 10,000 rows, with tracking on/off.
    // Covers: Actual SQLite update/commit hooks, explicit transactions and reads.
    // Expected: One revision row write per batch and no additional commit for revisions.
    for count in [1, 1000, 10000] {
        for track in [false, true] {
            let manifest = schema_manifest(vec![native_user_schema()]);
            let mut s = SqliteStorage::open_with_schemas(":memory:", &manifest).unwrap();
            let documents = revision_documents(count);
            let (result, writes, commits) = revision_cost(&mut s, |s| {
                s.put_many_native_documents("users", &documents, track)
            });
            result.unwrap();
            assert_eq!((writes, commits), (1, 1));
            let (result, writes, commits) = revision_cost(&mut s, |s| {
                s.query_plan_update(
                    "users",
                    &revision_plan(),
                    &[("completed".into(), WireValue::Bool(false))],
                    track,
                )
            });
            assert_eq!(result.unwrap(), count as usize);
            assert_eq!((writes, commits), (1, 1));
            s.begin_write_transaction().unwrap();
            let (result, writes, commits) = revision_cost(&mut s, |s| {
                s.delete_many_native_documents("users", &(1..=count).collect::<Vec<_>>())
            });
            result.unwrap();
            assert_eq!((writes, commits), (1, 0));
            let (_, writes, commits) = revision_cost(&mut s, |s| s.commit_transaction().unwrap());
            assert_eq!((writes, commits), (0, 1));
            let (_, writes, commits) = revision_cost(&mut s, |s| {
                for _ in 0..100 {
                    s.collection_revision("users").unwrap();
                }
            });
            assert_eq!((writes, commits), (0, 0));
            eprintln!(
                "revision cost: rows={count}, tracking={track}, writes/batch=1, commits/batch=1"
            );
        }
    }
}

#[test]
fn persistent_relation_revisions_cover_both_endpoints_and_cleanup_batches() {
    // Scenario: Links cross collections and are removed by deletes or orphan cleanup.
    // Covers: External visibility, rollback, repeated writes before draining and batching.
    // Expected: Each affected collection advances once per operation, not once per edge.
    let directory = TemporaryDirectory::new("revision_relations");
    let mut other = native_user_schema();
    other.name = "targets".into();
    let manifest = schema_manifest(vec![native_user_schema(), other]);
    let mut s = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
    let reader = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
    for name in ["users", "targets"] {
        s.put_many_native_documents(name, &revision_documents(2), false)
            .unwrap();
    }
    let link = LinkSave {
        source_collection: "users".into(),
        source_id: 1,
        link_name: "children".into(),
        target_collection: "targets".into(),
        target_ids: vec![1, 2],
    };
    s.replace_links(&link).unwrap();
    for name in ["users", "targets"] {
        assert_eq!(reader.collection_revision(name).unwrap(), 2);
    }
    s.begin_write_transaction().unwrap();
    s.delete_many_native_documents("targets", &[1, 2]).unwrap();
    s.rollback_transaction().unwrap();
    for name in ["users", "targets"] {
        assert_eq!(s.collection_revision(name).unwrap(), 2);
    }
    let (result, writes, commits) = revision_cost(&mut s, |s| {
        s.delete_many_native_documents("targets", &[1, 2])
    });
    result.unwrap();
    assert_eq!((writes, commits), (2, 1));
    for name in ["users", "targets"] {
        assert_eq!(reader.collection_revision(name).unwrap(), 3);
    }
    // Seed old orphan links without revising them, as an older database may contain.
    for id in 1..=1000 {
        s.connection
            .execute(
                "INSERT INTO cindel_relations VALUES ('users',1,?1,'targets',999)",
                [format!("old{id}")],
            )
            .unwrap();
    }
    let (result, writes, commits) = revision_cost(&mut s, |s| s.cleanup_orphan_links());
    assert_eq!(result.unwrap(), (1000, 1000));
    assert_eq!((writes, commits), (2, 1));
    for name in ["users", "targets"] {
        assert_eq!(reader.collection_revision(name).unwrap(), 4);
    }
    s.take_change_sets().unwrap();
    for name in ["users", "targets"] {
        assert_eq!(reader.collection_revision(name).unwrap(), 4);
    }
}

#[test]
fn persistent_revisions_continue_after_migration_publication() {
    // Scenario: Migration copies existing counters, then normal writes resume.
    // Covers: A high persisted revision, publication and later writes by another handle.
    // Expected: Publication and each later write are observable without counter masking.
    let directory = TemporaryDirectory::new("revision_migration");
    let manifest = schema_manifest(vec![native_user_schema()]);
    let mut s = SqliteStorage::open_with_persisted_schemas(directory.path(), &manifest).unwrap();
    let mut observer =
        SqliteStorage::open_with_persisted_schemas(directory.path(), &manifest).unwrap();
    s.put_many_native_documents("users", &revision_documents(1), false)
        .unwrap();
    s.connection
        .execute("UPDATE collection_revisions SET revision=100", [])
        .unwrap();
    let token = format!(
        "revision-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    let (mut stage, revision) = s.migration_fork(&token, &manifest).unwrap();
    stage
        .put_many_native_documents("users", &revision_documents(2), false)
        .unwrap();
    assert_eq!(observer.collection_revision("users").unwrap(), 100);
    s.migration_publish(&stage, revision, 1).unwrap();
    assert_eq!(observer.collection_revision("users").unwrap(), 102);
    observer
        .put_many_native_documents("users", &revision_documents(3), false)
        .unwrap();
    assert_eq!(s.collection_revision("users").unwrap(), 103);
}

#[test]
fn persistent_restore_revisions_are_atomic_and_visible_to_existing_handles() {
    // Scenario: A staged restore fails its revision update, then retries successfully.
    // Covers: Rollback, metadata/data publication and post-restore writes.
    // Expected: No partial restore and one revision write for a multi-batch import.
    let directory = TemporaryDirectory::new("revision_restore");
    let manifest = schema_manifest(vec![native_user_schema()]);
    let mut s = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
    let reader = SqliteStorage::open_with_schemas(directory.path(), &manifest).unwrap();
    let token = format!(
        "revision-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    let mut spool =
        crate::backup::BackupSpool::open(&token, vec![("users".into(), Some(1))], 0).unwrap();
    for id in 1..=3 {
        let bytes = crate::wire::encode_native_document_write_batch(&[
            crate::wire::WireNativeDocumentWrite {
                id,
                values: vec![
                    crate::wire::WireNativeDocumentValue::Bool(true),
                    crate::wire::WireNativeDocumentValue::Int(id as i64),
                    crate::wire::WireNativeDocumentValue::Bytes(b"title".to_vec()),
                ],
            },
        ])
        .unwrap();
        spool.stage("users", true, &bytes).unwrap();
    }
    s.connection.execute_batch("CREATE TEMP TRIGGER fail_restore_revision BEFORE INSERT ON collection_revisions BEGIN SELECT RAISE(ABORT,'controlled restore revision failure'); END;").unwrap();
    assert!(s.restore_backup(&spool, 1).is_err());
    assert!(reader.document_ids("users").unwrap().is_empty());
    assert_eq!(reader.collection_revision("users").unwrap(), 0);
    s.connection
        .execute_batch("DROP TRIGGER fail_restore_revision")
        .unwrap();
    let (result, writes, commits) = revision_cost(&mut s, |s| s.restore_backup(&spool, 1));
    result.unwrap();
    assert_eq!((writes, commits), (1, 1));
    assert_eq!(reader.document_ids("users").unwrap(), vec![1, 2, 3]);
    assert_eq!(reader.collection_revision("users").unwrap(), 1);
    s.put_many_native_documents("users", &revision_documents(4), false)
        .unwrap();
    assert_eq!(reader.collection_revision("users").unwrap(), 2);
}
