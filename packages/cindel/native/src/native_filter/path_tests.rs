#[test]
fn nested_paths_validate_payloads_and_bound_memory() {
    // Scenario: A small selected leaf shares its object with a large unused field.
    // Covers: Borrowed traversal, malformed siblings, missing parents, null leaves and allocation peak.
    // Expected: Leaf evaluation allocates independently of the sibling payload and rejects corruption.
    // Arrange.
    use crate::document_format::visit_binary_path;
    // Embedded payload can be obtained from the compact root without copying it.
    let schema = schema();
    let mut values = vec![None; schema.fields.len()];
    values[5] = Some(BinaryValue::Object(vec![
        ("label".into(), Some(BinaryValue::String("yes".into()))),
        (
            "unused".into(),
            Some(BinaryValue::String("x".repeat(1_000_000))),
        ),
        ("missing".into(), None),
    ]));
    let bytes = write_compact_document_for_test(&schema, &values).unwrap();
    let filter = NativeFilter::from_wire(WireFilter::Path {
        path: vec!["profile".into(), "label".into()],
        operation: WireFilterOperation::Equal,
        value: WireValue::String("yes".into()),
    })
    .unwrap()
    .prepare_for_schema(&schema);
    // Act.
    let peak = crate::storage::test_allocations::peak_bytes(|| {
        for _ in 0..100 {
            assert!(filter.matches_with_id(&schema, &bytes, 1).unwrap());
        }
    });
    // Assert.
    eprintln!("nested_filter leaf_peak_bytes={peak}");
    assert!(peak < 128, "unused embedded payload was retained: {peak}");
    let (_, payload) = read_binary_field_payload(&schema, &bytes, "profile")
        .unwrap()
        .unwrap();
    let path = vec!["label".into()];
    let mut corrupt = payload.to_vec();
    corrupt.push(0);
    assert!(visit_binary_path("object", &corrupt, &path, &mut |_| Ok(())).is_err());
    let mut leaves = 0;
    visit_binary_path("object", payload, &["missing".into()], &mut |v| {
        assert!(v.is_none());
        leaves += 1;
        Ok(())
    })
    .unwrap();
    assert_eq!(leaves, 1);
    visit_binary_path(
        "object",
        payload,
        &["missing".into(), "child".into()],
        &mut |_| {
            leaves += 1;
            Ok(())
        },
    )
    .unwrap();
    assert_eq!(leaves, 1);
}

#[test]
fn nested_path_leaf_semantics_match_dart() {
    // Scenario: Nested predicates include null, numeric boundaries and reordered object keys.
    // Covers: Dart numeric fallback, deep equality, nullable list elements and string fallbacks.
    // Expected: Path predicates keep typed Dart behavior without changing flat filter behavior.
    // Arrange / Act / Assert.
    use FieldFilterOperation::*;
    assert!(path_leaf_matches(None, LessThan, &WireValue::Int(1)).unwrap());
    assert!(!path_leaf_matches(None, GreaterThanOrEqualTo, &WireValue::Int(1)).unwrap());
    assert!(path_leaf_matches(None, StartsWith, &WireValue::String("".into())).unwrap());
    assert!(path_leaf_matches(
        Some(&BinaryValue::List(vec![None])),
        Contains,
        &WireValue::Null
    )
    .unwrap());
    assert!(path_leaf_matches(
        Some(&BinaryValue::Int(9_007_199_254_740_993)),
        GreaterThan,
        &WireValue::Int(9_007_199_254_740_992)
    )
    .unwrap());
    assert!(path_leaf_matches(
        Some(&BinaryValue::Double(-0.0)),
        LessThan,
        &WireValue::Int(0)
    )
    .unwrap());
    assert!(path_values_equal(
        Some(&BinaryValue::Int(1)),
        &WireValue::Double(1.0)
    ));
    assert!(path_values_equal(
        Some(&BinaryValue::Object(vec![
            ("b".into(), None),
            ("a".into(), Some(BinaryValue::Int(1)))
        ])),
        &WireValue::Object(vec![
            ("a".into(), WireValue::Int(1)),
            ("b".into(), WireValue::Null)
        ])
    ));
}

#[test]
fn nested_path_wire_round_trip_and_validation() {
    // Scenario: The ABI carries a nested property path and malformed path counts.
    // Covers: New tag round-trip and rejection before allocation/traversal.
    // Expected: A valid path survives exactly; empty paths and truncated payloads fail.
    // Arrange.
    let value = WireFilter::Path {
        path: vec!["profile".into(), "label".into()],
        operation: WireFilterOperation::Equal,
        value: WireValue::String("yes".into()),
    };
    // Act / Assert.
    let bytes = crate::wire::encode_filter(&value).unwrap();
    assert_eq!(crate::wire::decode_filter(&bytes).unwrap(), value);
    for end in 0..bytes.len() {
        assert!(crate::wire::decode_filter(&bytes[..end]).is_err());
    }
    assert!(crate::wire::decode_filter(&[5, 0, 0, 0, 0]).is_err());
    assert!(crate::wire::decode_filter(&[5, 255, 255, 255, 255]).is_err());
}
