#[test]
fn nested_deletes_measure_window_work_and_memory() {
    // Scenario: A nested predicate matches the first row of a growing collection.
    // Covers: Native delete selection, filter evaluations, allocation peak and
    // the existing active-write overlay, including a pending insert.
    // Expected: Standalone limited deletes evaluate one row; active writes see
    // every overlay candidate and rollback restores the deleted identity.
    // Arrange / Act / Assert.
    for count in [2000, 20000] {
        for active in [false, true] {
            let directory = TemporaryDirectory::new("nested_delete_work");
            let mut storage = MdbxStorage::open(directory.path()).unwrap();
            let mut manifest = task_unindexed_schema_manifest();
            let schema = &mut manifest.collections[0];
            let mut nested = schema.fields.last().unwrap().clone();
            nested.name = "profile".into();
            nested.dart_type = "Profile?".into();
            nested.binary_type = "object".into();
            schema.fields.push(nested);
            storage.register_schemas(&manifest).unwrap();
            let schema = &manifest.collections[0];
            let rows: Vec<_> = (1..=count)
                .map(|id| DocumentWrite {
                    id,
                    bytes: write_compact_document_for_test(
                        schema,
                        &[
                            Some(BinaryValue::Bool(true)),
                            Some(BinaryValue::Int(id as i64)),
                            Some(BinaryValue::String("original".into())),
                            Some(BinaryValue::Object(vec![(
                                "label".into(),
                                Some(BinaryValue::String(
                                    if id == 1 { "yes" } else { "no" }.into(),
                                )),
                            )])),
                        ],
                    )
                    .unwrap(),
                    indexes: vec![],
                })
                .collect();
            storage.put_many_indexed("tasks", &rows).unwrap();
            let filter = crate::wire::encode_filter(&crate::wire::WireFilter::Path {
                path: vec!["profile".into(), "label".into()],
                operation: crate::wire::WireFilterOperation::Equal,
                value: WireValue::String("yes".into()),
            })
            .unwrap();

            if active {
                storage.begin_write_transaction().unwrap();
                storage
                    .put_indexed("tasks", count + 1, &rows[1].bytes, &[])
                    .unwrap();
            }
            let plan = WireQueryPlan {
                source: WireQuerySource::All { dedupe: false },
                filter: Some(filter),
                sorts: vec![],
                distinct_fields: vec![],
                offset: 0,
                limit: Some(1),
            };
            crate::native_filter::PATH_EVALUATIONS.with(|n| n.set(0));
            let peak = crate::storage::test_allocations::peak_bytes(|| {
                assert_eq!(storage.query_plan_delete("tasks", &plan).unwrap(), vec![1]);
            });
            let evaluations = crate::native_filter::PATH_EVALUATIONS.with(|n| n.get());
            assert_eq!(evaluations, if active { count as usize + 1 } else { 1 });
            if !active {
                assert!(peak < 65536, "limited delete retained collection: {peak}");
            }
            eprintln!(
                "nested_delete rows={count} active={active} evaluations={evaluations} peak={peak}"
            );
            assert!(storage.get("tasks", 1).unwrap().is_none());
            if active {
                storage.rollback_transaction().unwrap();
                assert!(storage.get("tasks", 1).unwrap().is_some());
                assert!(storage.get("tasks", count + 1).unwrap().is_none());
            }
        }
    }
}

#[test]
fn nested_delete_filter_failure_preserves_rows_and_revision() {
    // Scenario: An unlimited nested delete encounters a malformed embedded leaf
    // after an earlier matching row.
    // Covers: Error propagation before deletion, revisions and change sets.
    // Expected: No row is deleted and no revision or notification is produced.
    // Arrange.
    let count = 2;
    let directory = TemporaryDirectory::new("nested_delete_work");
    let mut storage = MdbxStorage::open(directory.path()).unwrap();
    let mut manifest = task_unindexed_schema_manifest();
    let schema = &mut manifest.collections[0];
    let mut nested = schema.fields.last().unwrap().clone();
    nested.name = "profile".into();
    nested.dart_type = "Profile?".into();
    nested.binary_type = "object".into();
    schema.fields.push(nested);
    storage.register_schemas(&manifest).unwrap();
    let schema = &manifest.collections[0];
    let rows: Vec<_> = (1..=count)
        .map(|id| DocumentWrite {
            id,
            bytes: write_compact_document_for_test(
                schema,
                &[
                    Some(BinaryValue::Bool(true)),
                    Some(BinaryValue::Int(id as i64)),
                    Some(BinaryValue::String("original".into())),
                    Some(BinaryValue::Object(vec![(
                        "label".into(),
                        Some(BinaryValue::String(
                            if id == 1 { "yes" } else { "no" }.into(),
                        )),
                    )])),
                ],
            )
            .unwrap(),
            indexes: vec![],
        })
        .collect();
    storage.put_many_indexed("tasks", &rows).unwrap();
    let filter = crate::wire::encode_filter(&crate::wire::WireFilter::Path {
        path: vec!["profile".into(), "label".into()],
        operation: crate::wire::WireFilterOperation::Equal,
        value: WireValue::String("yes".into()),
    })
    .unwrap();

    let original = storage.get("tasks", 1).unwrap();
    let mut corrupt = rows[1].bytes.clone();
    *corrupt.last_mut().unwrap() = 255;
    storage
        .with_write_transaction(|transaction, _| {
            let table = open_documents_table(transaction, "tasks")?;
            transaction
                .put(&table, document_table_key(2), &corrupt, WriteFlags::UPSERT)
                .map_err(|error| error.to_string())
        })
        .unwrap();
    storage.take_change_sets().unwrap();
    let revision = storage.collection_revision("tasks").unwrap();
    let plan = WireQueryPlan {
        source: WireQuerySource::All { dedupe: false },
        filter: Some(filter),
        sorts: vec![],
        distinct_fields: vec![],
        offset: 0,
        limit: None,
    };
    // Act / Assert.
    assert!(storage.query_plan_delete("tasks", &plan).is_err());
    assert_eq!(storage.get("tasks", 1).unwrap(), original);
    assert_eq!(storage.collection_revision("tasks").unwrap(), revision);
    assert!(storage.take_change_sets().unwrap().is_empty());
}
