fn structured_schema(list_type: &str) -> CollectionSchemaManifest {
    user_schema(vec![
        native_field("items", list_type, "list", false),
        native_field("object", "Embedded?", "object", false),
    ])
}

#[test]
fn structured_json_writes_and_updates_keep_types() {
    // Scenario: Typed lists/objects enter through binary puts and query updates.
    // Covers:
    // - Physical JSON TEXT storage, exact int64, floating-point kinds and nulls.
    // - Matching storage after both writing routes.
    // Expected: The same valid JSON and typed transport survive every write.
    // Arrange.
    use crate::document_format::sqlite_json::{binary_json, json_binary};
    let schema = structured_schema("List<double?>?");
    let mut storage =
        SqliteStorage::open_with_schemas(":memory:", &schema_manifest(vec![schema.clone()]))
            .unwrap();
    let list = b"[2.0,-0.0,1.2345678901234567,5e-324,null]";
    let object = br#"{"name":"001","value":9007199254740993,"nested":[true,null,"2.0"]}"#;
    // Act.
    storage
        .put_many_native_documents(
            "users",
            &[NativeDocumentWrite {
                id: 1,
                values: vec![
                    NativeDocumentValue::Bytes(json_binary(list, true).unwrap()),
                    NativeDocumentValue::Bytes(json_binary(object, false).unwrap()),
                ],
            }],
            true,
        )
        .unwrap();
    // Assert.
    for (column, expected, is_list) in [
        ("items", list.as_slice(), true),
        ("object", object.as_slice(), false),
    ] {
        let (text, kind, valid): (String, String, bool) = storage
            .connection
            .query_row(
                &format!("SELECT {column},typeof({column}),json_valid({column}) FROM users"),
                [],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .unwrap();
        assert_eq!(kind, "text");
        assert!(valid);
        assert_eq!(
            json_binary(text.as_bytes(), is_list).unwrap(),
            json_binary(expected, is_list).unwrap()
        );
        assert_eq!(
            binary_json(&json_binary(expected, is_list).unwrap(), is_list).unwrap(),
            text
        );
        let field = schema.fields.iter().find(|f| f.name == column).unwrap();
        let wire = json_wire_value(serde_json::from_slice(expected).unwrap()).unwrap();
        assert_eq!(
            sqlite_update_value(field, &wire).unwrap(),
            Value::Text(text)
        );
    }
}

#[test]
fn structured_json_normalization_is_atomic_and_once_only() {
    // Scenario: Older SQLite tables mix binary and JSON lists/objects.
    // Covers:
    // - Controlled failure after the first batch; markers and data roll back.
    // - Retry, unchanged revisions/IDs and no data scan on repeated registration.
    // Expected: All binary fields become JSON together, exactly once.
    // Arrange.
    let schema = structured_schema("List<int?>");
    let mut storage =
        SqliteStorage::open_with_schemas(":memory:", &schema_manifest(vec![schema.clone()]))
            .unwrap();
    let list = crate::document_format::sqlite_json::json_binary(b"[42,null]", true).unwrap();
    let object =
        crate::document_format::sqlite_json::json_binary(br#"{"name":"001"}"#, false).unwrap();
    storage
        .connection
        .execute("DELETE FROM cindel_json_columns", [])
        .unwrap();
    for id in 1..=300 {
        storage
            .connection
            .execute(
                "INSERT INTO users(_rowid_,items,object) VALUES(?1,?2,?3)",
                params![id, list, object],
            )
            .unwrap();
    }
    let revision = storage.collection_revision("users").unwrap();
    let next_id = storage.reserve_ids("users", 1).unwrap();
    // Act / Assert.
    {
        let _fault = super::super::test_faults::after("sqlite_json_batch", 1);
        assert!(json_storage::normalize(&storage.connection, &schema)
            .unwrap_err()
            .contains("controlled failure"));
    }
    let blobs = || {
        storage
            .connection
            .query_row(
                "SELECT count(*) FROM users WHERE typeof(items)='blob' AND typeof(object)='blob'",
                [],
                |r| r.get::<_, i64>(0),
            )
            .unwrap()
    };
    assert_eq!(blobs(), 300);
    assert_eq!(
        storage
            .connection
            .query_row("SELECT count(*) FROM cindel_json_columns", [], |r| r
                .get::<_, i64>(0))
            .unwrap(),
        0
    );
    json_storage::normalize(&storage.connection, &schema).unwrap();
    assert_eq!(blobs(), 0);
    assert_eq!(storage.connection.query_row("SELECT count(*) FROM users WHERE json_extract(object,'$.name')='001' AND json_extract(items,'$[0]')=42", [], |r| r.get::<_, i64>(0)).unwrap(), 300);
    assert_eq!(storage.collection_revision("users").unwrap(), revision);
    assert_eq!(storage.reserve_ids("users", 1).unwrap(), next_id + 1);
    // A deliberately corrupt payload must not be visited after the marker.
    storage
        .connection
        .execute("UPDATE users SET items=X'ff' WHERE _rowid_=1", [])
        .unwrap();
    json_storage::normalize(&storage.connection, &schema).unwrap();
}

#[test]
fn structured_json_normalization_retains_only_a_batch() {
    // Scenario: Existing binary data is much larger than the conversion buffer.
    // Covers:
    // - Byte-limited batches and measured Rust allocation high-water mark.
    // Expected: A 16 MiB table converts with less than 4 MiB of Rust heap.
    // Arrange.
    let schema = structured_schema("List<String>");
    let storage =
        SqliteStorage::open_with_schemas(":memory:", &schema_manifest(vec![schema.clone()]))
            .unwrap();
    storage
        .connection
        .execute("DELETE FROM cindel_json_columns", [])
        .unwrap();
    let binary =
        crate::document_format::write_list(&[Some(BinaryValue::String("x".repeat(16384)))])
            .unwrap();
    for id in 1..=1024 {
        storage
            .connection
            .execute(
                "INSERT INTO users(_rowid_,items) VALUES(?1,?2)",
                params![id, binary],
            )
            .unwrap();
    }
    // Act.
    let peak = super::super::test_allocations::peak_bytes(|| {
        json_storage::normalize(&storage.connection, &schema).unwrap()
    });
    // Assert.
    eprintln!("JSON normalization peak Rust heap: {peak} bytes");
    assert!(peak < 4 * 1024 * 1024, "peak Rust heap: {peak}");
    assert_eq!(
        storage
            .connection
            .query_row(
                "SELECT count(*) FROM users WHERE typeof(items)='text' AND json_valid(items)",
                [],
                |r| r.get::<_, i64>(0)
            )
            .unwrap(),
        1024
    );
}

#[test]
fn structured_json_rejects_lossy_numbers_and_preserves_binary_prefix_collisions() {
    // Scenario: A list count begins with '[' and JSON contains an overflowing integer.
    // Covers:
    // - Binary/JSON boundary discrimination and number precision validation.
    // Expected: Binary lists remain readable; out-of-range integers are rejected.
    // Arrange.
    use crate::document_format::sqlite_json::{binary_json, json_binary};
    let values = vec![Some(BinaryValue::Int(42)); 91];
    let bytes = crate::document_format::write_list(&values).unwrap();
    // Act / Assert.
    assert_eq!(bytes[0], b'[');
    assert!(has_binary_list_payload(&bytes));
    assert_eq!(
        decode_list(&json_binary(binary_json(&bytes, true).unwrap().as_bytes(), true).unwrap())
            .unwrap(),
        values
    );
    assert!(json_binary(b"[9223372036854775808]", true).is_err());
    let mut invalid =
        crate::document_format::write_list(&[Some(BinaryValue::Double(1.0))]).unwrap();
    invalid[12..20].copy_from_slice(&f64::INFINITY.to_le_bytes());
    assert!(binary_json(&invalid, true).is_err());
}
