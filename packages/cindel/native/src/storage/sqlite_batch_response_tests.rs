// Included in sqlite::tests to exercise the same response encoder used by Web.
#[test]
fn batch_response_preserves_wire_format_and_reads_each_chunk_once() {
    // Scenario: Ordered IDs include duplicates, misses and a SQLite chunk boundary.
    // Covers: Wire compatibility, empty batches, SQL work and shared layout reuse.
    // Expected: Identical bytes without additional queries or rows for response sizing.
    // Arrange.
    let storage = read_preparation_storage();
    for ids in [vec![], vec![99, 98], vec![2, 99, 1, 2], {
        let mut ids = vec![99; SQLITE_MAX_PARAM_COUNT + 2];
        ids[0] = 2;
        ids[1] = 1;
        ids[SQLITE_MAX_PARAM_COUNT] = 2;
        ids
    }] {
        let expected = crate::wire::encode_optional_document_batch(
            &storage.get_many_stored("users", &ids).unwrap(),
        )
        .unwrap();
        NATIVE_BATCH_WORK.with(|work| work.set((0, 0)));
        NATIVE_DOCUMENT_LAYOUT_BUILDS.with(|count| count.set(0));
        // Act.
        let actual = storage.encode_many_stored("users", &ids).unwrap();
        // Assert.
        assert_eq!(actual, expected);
        let chunks = ids.len().div_ceil(SQLITE_MAX_PARAM_COUNT);
        let rows = if ids.len() > SQLITE_MAX_PARAM_COUNT {
            3
        } else if ids.contains(&1) {
            2
        } else {
            0
        };
        NATIVE_BATCH_WORK.with(|work| assert_eq!(work.get(), (chunks, rows)));
        NATIVE_DOCUMENT_LAYOUT_BUILDS.with(|count| assert_eq!(count.get(), usize::from(rows > 0)));
    }
    assert_eq!(
        storage.encode_many_stored("unregistered", &[1, 2]).unwrap(),
        vec![2, 0, 0, 0, 0, 0]
    );
}

#[test]
fn batch_response_does_not_retain_per_position_document_copies() {
    // Scenario: A batch requests one 64 KiB document 256 times.
    // Covers: Peak Rust allocation while the final response is retained.
    // Expected: The response plus small unique-row overhead, not 256 cloned documents.
    // Arrange.
    let mut storage = read_preparation_storage();
    storage
        .put_many_native_documents(
            "users",
            &[NativeDocumentWrite {
                id: 1,
                values: vec![
                    NativeDocumentValue::Bool(true),
                    NativeDocumentValue::Int(42),
                    NativeDocumentValue::Bytes(vec![b'x'; 65536]),
                ],
            }],
            true,
        )
        .unwrap();
    let ids = vec![1; 256];
    drop(storage.encode_many_stored("users", &ids).unwrap());
    let expected = crate::wire::encode_optional_document_batch(
        &storage.get_many_stored("users", &ids).unwrap(),
    )
    .unwrap();
    let mut result = Vec::new();
    // Act.
    let peak = rust_allocations::peak_bytes(|| {
        result = storage.encode_many_stored("users", &ids).unwrap();
    });
    // Assert.
    assert_eq!(result, expected);
    assert!(
        peak < result.len() + 512 * 1024,
        "peak={peak}, response={}",
        result.len()
    );
}

#[test]
fn batch_response_propagates_errors_and_recovers() {
    // Scenario: A prepared Web batch is interrupted, then retried.
    // Covers: Invalid IDs, SQLite failure propagation and statement cleanup.
    // Expected: No partial response escapes and a subsequent request succeeds.
    // Arrange.
    let storage = read_preparation_storage();
    drop(storage.encode_many_stored("users", &[1]).unwrap());
    unsafe extern "C" fn interrupt(_: *mut c_void) -> i32 {
        1
    }
    // Act / Assert.
    assert!(storage.encode_many_stored("users", &[u64::MAX]).is_err());
    unsafe {
        ffi::sqlite3_progress_handler(
            storage.connection.handle(),
            1,
            Some(interrupt),
            ptr::null_mut(),
        );
    }
    assert!(storage.encode_many_stored("users", &[1]).is_err());
    unsafe {
        ffi::sqlite3_progress_handler(storage.connection.handle(), 0, None, ptr::null_mut());
    }
    assert!(retained_read_statements(&storage).is_empty());
    assert_eq!(
        crate::wire::decode_optional_document_batch(
            &storage.encode_many_stored("users", &[1]).unwrap()
        )
        .unwrap(),
        storage.get_many_stored("users", &[1]).unwrap()
    );
}
