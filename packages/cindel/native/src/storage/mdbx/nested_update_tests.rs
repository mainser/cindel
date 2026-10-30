#[test]
fn nested_updates_scan_once_and_stop_at_window() {
    // Scenario: A nested predicate matches the first row of a growing collection.
    // Covers: Filter evaluations, cursor reads, selection window and Rust allocation peak.
    // Expected: Limited updates visit one row; distinct updates never rescan candidates.
    // Arrange / Act / Assert.
    for count in [2000, 20000] {
        let directory = TemporaryDirectory::new("nested_update_work");
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
        let mut plan = WireQueryPlan {
            source: WireQuerySource::All { dedupe: false },
            filter: Some(filter),
            sorts: vec![],
            distinct_fields: vec![],
            offset: 0,
            limit: Some(1),
        };
        for mode in 0..3 {
            let distinct = mode > 0;
            plan.limit = if mode == 2 { None } else { Some(1) };
            plan.distinct_fields = if distinct {
                vec!["title".into()]
            } else {
                vec![]
            };
            crate::native_filter::PATH_EVALUATIONS.with(|n| n.set(0));
            UPDATE_CURSOR_READS.with(|n| n.set(0));
            let peak = crate::storage::test_allocations::peak_bytes(|| {
                assert_eq!(
                    storage
                        .query_plan_update(
                            "tasks",
                            &plan,
                            &[("title".into(), WireValue::String("changed".into()))],
                            false
                        )
                        .unwrap(),
                    1
                );
            });
            let evaluations = crate::native_filter::PATH_EVALUATIONS.with(|n| n.get());
            assert_eq!(
                evaluations,
                if mode == 2 { count as usize } else { 1 },
                "unexpected candidate visits"
            );
            if !distinct {
                assert_eq!(evaluations, 1);
                assert_eq!(UPDATE_CURSOR_READS.with(|n| n.get()), 1);
            }
            assert!(peak < 65536, "retained collection: {peak}");
            eprintln!("nested_update rows={count} distinct={distinct} evaluations={evaluations} peak={peak}");
        }

        // Scenario: A later malformed embedded leaf fails after an earlier direct write.
        // Covers: Error propagation, transaction rollback and revision/change-set preservation.
        // Expected: No partial mutation or notification survives the controlled corrupt row.
        // Arrange.
        let original = storage.get("tasks", 1).unwrap();
        let mut corrupt = rows[1].bytes.clone();
        *corrupt.last_mut().unwrap() = 255;
        storage
            .with_write_transaction(|transaction, _| {
                let table = open_documents_table(transaction, "tasks")?;
                transaction
                    .put(&table, document_table_key(2), &corrupt, WriteFlags::UPSERT)
                    .map_err(|e| e.to_string())
            })
            .unwrap();
        storage.take_change_sets().unwrap();
        let revision = storage.collection_revision("tasks").unwrap();
        plan.limit = None;
        plan.distinct_fields.clear();
        // Act / Assert.
        assert!(storage
            .query_plan_update(
                "tasks",
                &plan,
                &[("title".into(), WireValue::String("must-rollback".into()))],
                true
            )
            .is_err());
        assert_eq!(storage.get("tasks", 1).unwrap(), original);
        assert_eq!(storage.collection_revision("tasks").unwrap(), revision);
        assert!(storage.take_change_sets().unwrap().is_empty());
    }
}
