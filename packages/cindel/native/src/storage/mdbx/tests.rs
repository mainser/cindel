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
    // - Explicit id advancement with persisted counter-table writes.
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
    // Scenario: A database is reopened with manually stored ids and no
    // prior auto-increment allocations.
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
fn persists_allocate_only_ids_without_documents() {
    // Scenario: An app allocates ids but never commits documents before the
    // process exits.
    // Covers:
    // - Counter state being persisted for MDBX.
    // - Reopen reading id_counters even when no document exists.
    // Expected: Empty collections still continue after allocated ids.
    let directory = TemporaryDirectory::new("allocate_only_ids");
    {
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        assert_eq!(storage.allocate_id("users").unwrap(), 1);
        assert_eq!(storage.allocate_id("users").unwrap(), 2);
    }

    let mut reopened = MdbxStorage::open(directory.path()).unwrap();

    assert_eq!(reopened.allocate_id("users").unwrap(), 3);
}

#[test]
fn does_not_reuse_deleted_high_water_ids_after_reopen() {
    // Scenario: Mirrors isar-community/isar-community#115.
    // Covers:
    // - Persisted MDBX auto-increment high-water counters.
    // - Deletes of the highest allocated document ids before reopen.
    // Expected: Reopened storage continues after deleted ids instead of
    // deriving from the remaining max document id.
    let directory = TemporaryDirectory::new("deleted_high_water_ids");
    {
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        for expected in 1..=3 {
            let id = storage.allocate_id("users").unwrap();
            assert_eq!(id, expected);
            storage.put("users", id, br#"{"name":"User"}"#).unwrap();
        }
        storage.delete("users", 3).unwrap();
        let fourth = storage.allocate_id("users").unwrap();
        assert_eq!(fourth, 4);
        storage
            .put("users", fourth, br#"{"name":"Fourth"}"#)
            .unwrap();
        storage.delete_many("users", &[2, 4]).unwrap();
        assert_eq!(storage.document_ids("users").unwrap(), vec![1]);
    }

    let mut reopened = MdbxStorage::open(directory.path()).unwrap();

    assert_eq!(reopened.allocate_id("users").unwrap(), 5);
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
fn streams_index_range_query_documents_from_borrowed_rows() {
    // Scenario: MDBX streams an unsorted index range query directly from
    // index and document cursors.
    // Covers:
    // - The non-sorted `IndexRange` query-reader source.
    // - Offset/limit without materializing the full range first.
    // - Additional native filters over streamed document bytes.
    // Expected: Results preserve index-range order, apply the visible
    //   window, and expose each current document payload.
    let directory = TemporaryDirectory::new("index_range_query_reader");
    let mut storage = MdbxStorage::open(directory.path()).unwrap();
    storage.register_schemas(&schema_manifest()).unwrap();

    for (id, email, name, score) in [
        (1, "ana@example.com", "Ana", 10),
        (2, "ben@example.com", "Ben", 20),
        (3, "cid@example.com", "Cid", 30),
        (4, "dee@example.com", "Dee", 40),
        (5, "eli@example.com", "Eli", 50),
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
        source: WireQuerySource::IndexRange {
            index_name: "score".to_string(),
            lower: Some(WireIndexValue::Int(15)),
            upper: Some(WireIndexValue::Int(45)),
            dedupe: false,
        },
        filter: None,
        sorts: Vec::new(),
        distinct_fields: Vec::new(),
        offset: 1,
        limit: Some(2),
    };

    let mut reader = storage
        .query_document_reader("users", &plan)
        .unwrap()
        .expect("index range queries should stream through MDBX");

    assert!(reader.next().unwrap());
    assert_eq!(reader.document_id(0).unwrap(), Some(3));
    assert_eq!(
        reader.document_bytes(0).unwrap().unwrap(),
        user_document("cid@example.com", 3, "Cid", 30).as_slice()
    );
    assert!(reader.next().unwrap());
    assert_eq!(reader.document_id(0).unwrap(), Some(4));
    assert_eq!(
        reader.document_bytes(0).unwrap().unwrap(),
        user_document("dee@example.com", 4, "Dee", 40).as_slice()
    );
    assert!(!reader.next().unwrap());
    assert_eq!(reader.document_bytes(0).unwrap(), None);
    assert_eq!(reader.document_id(0).unwrap(), None);

    let filter = crate::wire::WireFilter::Field {
        field: "name".to_string(),
        operation: crate::wire::WireFilterOperation::StartsWith,
        value: WireValue::String("C".to_string()),
    };
    let filtered_plan = WireQueryPlan {
        source: WireQuerySource::IndexRange {
            index_name: "score".to_string(),
            lower: Some(WireIndexValue::Int(0)),
            upper: Some(WireIndexValue::Int(100)),
            dedupe: false,
        },
        filter: Some(crate::wire::encode_filter(&filter).unwrap()),
        sorts: Vec::new(),
        distinct_fields: Vec::new(),
        offset: 0,
        limit: None,
    };
    let mut filtered_reader = storage
        .query_document_reader("users", &filtered_plan)
        .unwrap()
        .expect("filtered index range queries should stream through MDBX");

    assert!(filtered_reader.next().unwrap());
    assert_eq!(filtered_reader.document_id(0).unwrap(), Some(3));
    assert_eq!(
        filtered_reader.document_bytes(0).unwrap().unwrap(),
        user_document("cid@example.com", 3, "Cid", 30).as_slice()
    );
    assert!(!filtered_reader.next().unwrap());
}

#[test]
fn streams_index_range_dedupes_and_skips_missing_documents() {
    // Scenario: MDBX streams a range from explicit generic-document index
    // rows where one document appears more than once and one index row
    // points at a missing document.
    // Covers:
    // - `dedupe` handling for range sources.
    // - Missing document rows being ignored during streaming.
    // Expected: Each existing id is emitted once, and dangling index rows
    //   do not produce stale bytes.
    let directory = TemporaryDirectory::new("index_range_query_reader_dedupe");
    let mut storage = MdbxStorage::open(directory.path()).unwrap();
    storage.register_schemas(&schema_manifest()).unwrap();

    let generic = generic_document();
    storage
        .put_indexed(
            "users",
            1,
            &generic,
            &[
                index("score", IndexValue::Int(10)),
                index("score", IndexValue::Int(20)),
            ],
        )
        .unwrap();
    storage
        .put_indexed("users", 2, &generic, &[index("score", IndexValue::Int(15))])
        .unwrap();
    storage
        .with_write_transaction(|transaction, _tables| {
            let index_table = create_index_table(transaction, "users", "score")?;
            transaction
                .put(
                    &index_table,
                    index_value_key(&IndexValue::Int(12))?,
                    document_id_key(404),
                    WriteFlags::empty(),
                )
                .map_err(|error| error.to_string())?;
            Ok(())
        })
        .unwrap();

    let plan = WireQueryPlan {
        source: WireQuerySource::IndexRange {
            index_name: "score".to_string(),
            lower: Some(WireIndexValue::Int(0)),
            upper: Some(WireIndexValue::Int(30)),
            dedupe: true,
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
        .expect("deduped index range queries should stream through MDBX");

    assert!(reader.next().unwrap());
    assert_eq!(reader.document_id(0).unwrap(), Some(1));
    assert_eq!(
        reader.document_bytes(0).unwrap().unwrap(),
        generic.as_slice()
    );
    assert!(reader.next().unwrap());
    assert_eq!(reader.document_id(0).unwrap(), Some(2));
    assert_eq!(
        reader.document_bytes(0).unwrap().unwrap(),
        generic.as_slice()
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
fn streams_query_plan_count_and_aggregate_for_index_range_window() {
    // Scenario: MDBX count and aggregate query plans consume the query
    // document reader instead of materializing every planned document.
    // Covers:
    // - IndexRange source with offset/limit.
    // - Dangling index rows being ignored before window accounting.
    // - Incremental count, sum, average, min, and max.
    // Expected: Streaming query-plan operations preserve the same visible
    //   window and scalar results as the materialized plan.
    let directory = TemporaryDirectory::new("query_plan_stream_count_aggregate");
    let mut storage = MdbxStorage::open(directory.path()).unwrap();
    storage.register_schemas(&schema_manifest()).unwrap();

    for (id, name, score) in [
        (1, "Ana", 10),
        (2, "Ben", 20),
        (3, "Cid", 30),
        (4, "Dee", 40),
    ] {
        storage
            .put_indexed(
                "users",
                id,
                &user_document(&format!("user-{id}@example.com"), id as i64, name, score),
                &[],
            )
            .unwrap();
    }
    storage
        .with_write_transaction(|transaction, _tables| {
            let index_table = create_index_table(transaction, "users", "score")?;
            transaction
                .put(
                    &index_table,
                    index_value_key(&IndexValue::Int(25))?,
                    document_id_key(404),
                    WriteFlags::empty(),
                )
                .map_err(|error| error.to_string())?;
            Ok(())
        })
        .unwrap();

    let plan = WireQueryPlan {
        source: WireQuerySource::IndexRange {
            index_name: "score".to_string(),
            lower: Some(WireIndexValue::Int(0)),
            upper: Some(WireIndexValue::Int(100)),
            dedupe: false,
        },
        filter: None,
        sorts: Vec::new(),
        distinct_fields: Vec::new(),
        offset: 1,
        limit: Some(2),
    };

    assert_eq!(storage.query_plan_count("users", &plan).unwrap(), 2);
    assert_eq!(
        storage
            .query_plan_aggregate("users", &plan, "score", "count")
            .unwrap(),
        encode_scalar(&WireScalar::Int(2)).unwrap()
    );
    assert_eq!(
        storage
            .query_plan_aggregate("users", &plan, "score", "sum")
            .unwrap(),
        encode_scalar(&WireScalar::Double(50.0)).unwrap()
    );
    assert_eq!(
        storage
            .query_plan_aggregate("users", &plan, "score", "average")
            .unwrap(),
        encode_scalar(&WireScalar::Double(25.0)).unwrap()
    );
    assert_eq!(
        storage
            .query_plan_aggregate("users", &plan, "name", "min")
            .unwrap(),
        encode_scalar(&WireScalar::String("Ben".to_string())).unwrap()
    );
    assert_eq!(
        storage
            .query_plan_aggregate("users", &plan, "name", "max")
            .unwrap(),
        encode_scalar(&WireScalar::String("Cid".to_string())).unwrap()
    );
}

#[test]
fn distinct_query_plan_count_and_aggregate_keep_materialized_fallback() {
    // Scenario: Distinct query plans are not supported by the streaming
    // query document reader.
    // Covers:
    // - query_plan_count fallback to execute_query_plan.
    // - query_plan_aggregate fallback to the existing Vec-based aggregate.
    // Expected: Distinct semantics remain unchanged while non-distinct
    //   plans are free to stream.
    let directory = TemporaryDirectory::new("query_plan_distinct_aggregate_fallback");
    let mut storage = MdbxStorage::open(directory.path()).unwrap();
    storage.register_schemas(&schema_manifest()).unwrap();

    for (id, name, score) in [(1, "Ana", 10), (2, "Ana", 20), (3, "Ben", 30)] {
        storage
            .put_indexed(
                "users",
                id,
                &user_document(&format!("user-{id}@example.com"), id as i64, name, score),
                &[],
            )
            .unwrap();
    }

    let plan = WireQueryPlan {
        source: WireQuerySource::All { dedupe: false },
        filter: None,
        sorts: Vec::new(),
        distinct_fields: vec!["name".to_string()],
        offset: 0,
        limit: None,
    };

    assert_eq!(storage.query_plan_count("users", &plan).unwrap(), 2);
    assert_eq!(
        storage
            .query_plan_aggregate("users", &plan, "score", "count")
            .unwrap(),
        encode_scalar(&WireScalar::Int(2)).unwrap()
    );
    assert_eq!(
        storage
            .query_plan_aggregate("users", &plan, "score", "sum")
            .unwrap(),
        encode_scalar(&WireScalar::Double(40.0)).unwrap()
    );
}

#[test]
fn streams_query_plan_projection_for_index_range_window() {
    // Scenario: MDBX query-plan projection consumes the query document
    // reader instead of materializing every planned document.
    // Covers:
    // - IndexRange source with offset/limit.
    // - Scalar projection wire encoding.
    // - Dangling index rows being ignored before window accounting.
    // Expected: The projected row payload preserves visible query order and
    //   matches the existing projection wire format.
    let directory = TemporaryDirectory::new("query_plan_stream_projection");
    let mut storage = MdbxStorage::open(directory.path()).unwrap();
    storage.register_schemas(&schema_manifest()).unwrap();

    for (id, name, score) in [
        (1, "Ana", 10),
        (2, "Ben", 20),
        (3, "Cid", 30),
        (4, "Dee", 40),
    ] {
        storage
            .put_indexed(
                "users",
                id,
                &user_document(&format!("user-{id}@example.com"), id as i64, name, score),
                &[],
            )
            .unwrap();
    }
    storage
        .with_write_transaction(|transaction, _tables| {
            let index_table = create_index_table(transaction, "users", "score")?;
            transaction
                .put(
                    &index_table,
                    index_value_key(&IndexValue::Int(25))?,
                    document_id_key(404),
                    WriteFlags::empty(),
                )
                .map_err(|error| error.to_string())?;
            Ok(())
        })
        .unwrap();

    let plan = WireQueryPlan {
        source: WireQuerySource::IndexRange {
            index_name: "score".to_string(),
            lower: Some(WireIndexValue::Int(0)),
            upper: Some(WireIndexValue::Int(100)),
            dedupe: false,
        },
        filter: None,
        sorts: Vec::new(),
        distinct_fields: Vec::new(),
        offset: 1,
        limit: Some(2),
    };

    assert_eq!(
        storage.query_plan_project("users", &plan, "name").unwrap(),
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
    assert_eq!(
        storage.query_plan_project("users", &plan, "score").unwrap(),
        encode_projection_rows(&WireProjectionRows {
            row_count: 2,
            column_count: 1,
            cells: vec![WireValue::Int(20), WireValue::Int(30)],
        })
        .unwrap()
    );
}

#[test]
fn streams_query_plan_projection_for_lists_and_sorted_plans() {
    // Scenario: Query-plan projection still handles dynamic list fields and
    // sorted plans when the query document reader materializes the sorted
    // window internally.
    // Covers:
    // - List value projection wire encoding.
    // - Sorted reader source.
    // Expected: Projection semantics remain identical across scalar and
    //   nested list values.
    let directory = TemporaryDirectory::new("query_plan_stream_projection_lists");
    let mut storage = MdbxStorage::open(directory.path()).unwrap();
    storage
        .register_schemas(&task_tags_schema_manifest())
        .unwrap();

    for (id, completed, title, tags) in [
        (1, true, "Cid", vec!["fresh", "fast"]),
        (2, false, "Ana", vec!["slow"]),
        (3, true, "Ben", vec!["fresh", "stable"]),
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

    let plan = WireQueryPlan {
        source: WireQuerySource::All { dedupe: false },
        filter: None,
        sorts: vec![crate::wire::WireQuerySort {
            field: "title".to_string(),
            ascending: true,
        }],
        distinct_fields: Vec::new(),
        offset: 0,
        limit: Some(2),
    };

    assert_eq!(
        storage.query_plan_project("tasks", &plan, "title").unwrap(),
        encode_projection_rows(&WireProjectionRows {
            row_count: 2,
            column_count: 1,
            cells: vec![
                WireValue::String("Ana".to_string()),
                WireValue::String("Ben".to_string()),
            ],
        })
        .unwrap()
    );
    assert_eq!(
        storage.query_plan_project("tasks", &plan, "tags").unwrap(),
        encode_projection_rows(&WireProjectionRows {
            row_count: 2,
            column_count: 1,
            cells: vec![
                WireValue::List(vec![WireValue::String("slow".to_string())]),
                WireValue::List(vec![
                    WireValue::String("fresh".to_string()),
                    WireValue::String("stable".to_string()),
                ]),
            ],
        })
        .unwrap()
    );
}

#[test]
fn distinct_query_plan_projection_keeps_materialized_fallback() {
    // Scenario: Distinct query plans are not supported by the streaming
    // query document reader.
    // Covers:
    // - query_plan_project fallback to execute_query_plan.
    // Expected: Distinct projection keeps the first visible document for
    //   each distinct key exactly as before.
    let directory = TemporaryDirectory::new("query_plan_distinct_projection_fallback");
    let mut storage = MdbxStorage::open(directory.path()).unwrap();
    storage.register_schemas(&schema_manifest()).unwrap();

    for (id, name, score) in [(1, "Ana", 10), (2, "Ana", 20), (3, "Ben", 30)] {
        storage
            .put_indexed(
                "users",
                id,
                &user_document(&format!("user-{id}@example.com"), id as i64, name, score),
                &[],
            )
            .unwrap();
    }

    let plan = WireQueryPlan {
        source: WireQuerySource::All { dedupe: false },
        filter: None,
        sorts: Vec::new(),
        distinct_fields: vec!["name".to_string()],
        offset: 0,
        limit: None,
    };

    assert_eq!(
        storage.query_plan_project("users", &plan, "score").unwrap(),
        encode_projection_rows(&WireProjectionRows {
            row_count: 2,
            column_count: 1,
            cells: vec![WireValue::Int(10), WireValue::Int(30)],
        })
        .unwrap()
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
            assert!(ignore_not_found(
                transaction
                    .get::<Vec<u8>>(&tables.document_indexes, &encode_document_key("users", 1),)
            )?
            .is_none());
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
    let unique_indexes = HashMap::from([("email".to_string(), false)]);

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

fn test_field(name: &str, dart_type: &str, is_id: bool, is_indexed: bool) -> FieldSchemaManifest {
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

fn list_field(name: &str, dart_type: &str, is_indexed: bool) -> FieldSchemaManifest {
    FieldSchemaManifest {
        name: name.to_string(),
        dart_type: dart_type.to_string(),
        binary_type: "list".to_string(),
        is_id: false,
        is_indexed,
        is_index_unique: false,
        is_index_replace: false,
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

fn generic_document() -> Vec<u8> {
    vec![
        0x43, 0x47, 0x44, 0x31, // CGD1
        1, 0, 0, 0, // version
        6, 0, 0, 0, 0, // empty object
    ]
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
