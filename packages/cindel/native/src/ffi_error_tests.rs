use super::*;
use crate::document_format::write_compact_document_for_test;
use crate::storage::{test_faults, CollectionSchemaManifest, FieldSchemaManifest, SchemaManifest};
use crate::wire::WireQuerySource;

fn kinds() -> Vec<StorageBackendKind> {
    vec![
        StorageBackendKind::Sqlite,
        #[cfg(feature = "mdbx")]
        StorageBackendKind::Mdbx,
    ]
}

fn schema() -> SchemaManifest {
    SchemaManifest {
        collections: vec![CollectionSchemaManifest {
            name: "items".into(),
            id_field: "id".into(),
            composite_indexes: vec![],
            fields: ["id", "value"]
                .into_iter()
                .map(|name| FieldSchemaManifest {
                    name: name.into(),
                    dart_type: "int".into(),
                    binary_type: "int".into(),
                    is_id: name == "id",
                    is_indexed: false,
                    is_index_unique: false,
                    is_index_replace: false,
                    index_case_sensitive: true,
                    index_type: "value".into(),
                })
                .collect(),
        }],
    }
}

fn seeded(kind: StorageBackendKind) -> CindelEngine {
    let schema = schema();
    let mut engine =
        CindelEngine::open_with_backend_and_schemas(":memory:", kind, &schema).unwrap();
    for id in 1..=5 {
        let bytes = write_compact_document_for_test(
            &schema.collections[0],
            &[None, Some(BinaryValue::Int(id as i64))],
        )
        .unwrap();
        if !engine
            .put_many_native_documents(
                "items",
                &[NativeDocumentWrite {
                    id,
                    values: vec![NativeDocumentValue::Int(id as i64)],
                }],
                true,
            )
            .unwrap()
        {
            engine.put("items", id, &bytes).unwrap();
        }
    }
    engine
}

fn reader(engine: &CindelEngine) -> CindelNativeDocumentReader {
    let plan = WireQueryPlan {
        source: WireQuerySource::All { dedupe: false },
        filter: None,
        sorts: vec![],
        distinct_fields: vec![],
        offset: 0,
        limit: None,
    };
    let layout = NativeBatchLayout::new(&[1]).unwrap();
    #[cfg(feature = "mdbx")]
    if let Some(cursor) = engine.mdbx_query_document_reader("items", &plan).unwrap() {
        return CindelNativeDocumentReader {
            error: ReaderError::default(),
            current_index: None,
            mode: CindelNativeDocumentReaderMode::MdbxQueryCursor { layout, cursor },
        };
    }
    let cursor = engine
        .sqlite_query_plan_native_cursor("items", &plan)
        .unwrap()
        .unwrap();
    CindelNativeDocumentReader {
        error: ReaderError::default(),
        current_index: None,
        mode: CindelNativeDocumentReaderMode::SqliteQueryCursor { layout, cursor },
    }
}

unsafe fn diagnostic(reader: Option<&CindelNativeDocumentReader>) -> Option<String> {
    let mut length = 0;
    let pointer = match reader {
        Some(reader) => cindel_native_document_reader_error(reader, &mut length),
        None => panic!("use take_status for operation diagnostics"),
    };
    if pointer.is_null() {
        return None;
    }
    let result = String::from_utf8(std::slice::from_raw_parts(pointer, length).to_vec()).unwrap();
    cindel_free_buffer(pointer, length);
    Some(result)
}

unsafe fn take_status(status: i32) -> Option<String> {
    let mut length = 0;
    let pointer = cindel_take_error(status, &mut length);
    if pointer.is_null() {
        return None;
    }
    let result = String::from_utf8(std::slice::from_raw_parts(pointer, length).to_vec()).unwrap();
    cindel_free_buffer(pointer, length);
    Some(result)
}

#[test]
fn errors_ffi_cursor_failure_after_rows_is_sticky_and_not_eof() {
    for kind in kinds() {
        let mut engine = seeded(kind);
        let mut reader = reader(&engine);
        let _fault = test_faults::after("query_next", 2);
        unsafe {
            assert!(cindel_native_document_reader_next(&mut reader));
            assert!(cindel_native_document_reader_next(&mut reader));
            assert!(!cindel_native_document_reader_next(&mut reader));
            assert_eq!(
                diagnostic(Some(&reader)).as_deref(),
                Some("controlled failure at query_next")
            );
            // An unrelated call cannot overwrite the reader's first failure.
            let mut other = seeded(kind);
            let status = cindel_commit_txn(&mut other);
            assert!(status < 0);
            assert!(take_status(status).unwrap().contains("transaction"));
            assert_eq!(
                diagnostic(Some(&reader)).as_deref(),
                Some("controlled failure at query_next")
            );
            assert!(!cindel_native_document_reader_next(&mut reader));
        }
        drop(reader);
        engine.begin_write_transaction().unwrap();
        engine.commit_transaction().unwrap();
        assert_eq!(engine.document_ids("items").unwrap().len(), 5);
    }
}

#[test]
fn errors_ffi_seek_failure_is_not_a_missing_document() {
    for kind in kinds() {
        let mut engine = seeded(kind);
        let ids = encode_id_list(&[1, 99]).unwrap();
        unsafe {
            let mut status = 0;
            let reader = cindel_native_document_reader_new(
                &mut engine,
                b"items".as_ptr(),
                5,
                ids.as_ptr(),
                ids.len(),
                [1].as_ptr(),
                1,
                &mut status,
            );
            assert!(!reader.is_null(), "{:?}", take_status(status));
            let _fault = test_faults::after("document_seek", 0);
            assert!(!cindel_native_document_reader_is_present(reader, 0));
            assert_eq!(
                diagnostic(reader.as_ref()).as_deref(),
                Some("controlled failure at document_seek")
            );
            cindel_native_document_reader_free(reader);
            let reader = cindel_native_document_reader_new(
                &mut engine,
                b"items".as_ptr(),
                5,
                ids.as_ptr(),
                ids.len(),
                [1].as_ptr(),
                1,
                &mut status,
            );
            assert!(cindel_native_document_reader_is_present(reader, 0));
            assert!(!cindel_native_document_reader_is_present(reader, 1));
            assert_eq!(diagnostic(reader.as_ref()), None);
            cindel_native_document_reader_free(reader);
        }
    }
}

#[test]
fn errors_ffi_commit_cause_survives_rollback_and_connection_recovers() {
    for kind in kinds() {
        let mut engine = seeded(kind);
        unsafe {
            assert_eq!(cindel_begin_write_txn(&mut engine), 0);
            engine.delete("items", 1).unwrap();
            let _fault = test_faults::after("commit", 0);
            let status = cindel_commit_txn(&mut engine);
            assert!(status < 0);
            let original = take_status(status).unwrap();
            assert_eq!(original, "controlled failure at commit");
            assert_eq!(cindel_rollback_txn(&mut engine), 0);
            assert_eq!(take_status(0), None);
            assert!(engine.document_ids("items").unwrap().contains(&1));
            assert_eq!(cindel_begin_write_txn(&mut engine), 0);
            assert_eq!(cindel_commit_txn(&mut engine), 0);
        }
    }
}

#[test]
fn errors_ffi_wire_and_writer_failures_keep_their_cause() {
    for kind in kinds() {
        let mut engine = seeded(kind);
        unsafe {
            let status = cindel_register_schemas(&mut engine, b"bad".as_ptr(), 3);
            assert!(status < 0);
            assert!(take_status(status).is_some());
            assert!(take_status(status).is_none());
            assert_eq!(take_status(0), None);
            let mut status = 0;
            let writer = cindel_native_batch_writer_new([4].as_ptr(), 1, 1, 0, &mut status);
            let child = cindel_native_batch_writer_begin_list(writer, 0, 1);
            cindel_native_batch_writer_write_int(child, 100, 1);
            cindel_native_batch_writer_end_list(writer, child);
            let status =
                cindel_native_batch_writer_finish(&mut engine, b"items".as_ptr(), 5, writer);
            assert!(status < 0);
            assert!(take_status(status)
                .unwrap()
                .contains("index `100` is out of range"));
            assert_eq!(engine.document_ids("items").unwrap().len(), 5);
        }
    }
}

#[test]
fn errors_ffi_diagnostics_belong_to_results_across_threads_and_connections() {
    clear_error();
    record_error("first connection");
    let first = error_status();
    record_error("second connection");
    let second = error_status();
    assert_ne!(first, second);
    // Simulates an isolate resuming on another native thread between the FFI
    // operation and consuming its result. Errors may be consumed in any order.
    std::thread::spawn(move || unsafe {
        assert_eq!(take_status(second).as_deref(), Some("second connection"));
        assert_eq!(take_status(first).as_deref(), Some("first connection"));
        assert_eq!(take_status(first), None);
    })
    .join()
    .unwrap();
}

#[test]
fn errors_ffi_distinguishes_empty_lists_from_malformed_payloads() {
    assert!(parse_native_raw_list(b"[]").unwrap().entries.is_empty());
    assert!(parse_native_raw_list(&[0, 0, 0, 0])
        .unwrap()
        .entries
        .is_empty());
    assert!(parse_native_raw_list(&[255; 4]).is_err());
    assert!(parse_native_raw_object(&[255; 4], vec![]).is_err());
    assert!(decode_native_field_names(&[255; 4]).is_err());
}
