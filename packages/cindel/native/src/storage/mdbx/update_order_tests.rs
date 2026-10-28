fn unbounded_sorted_update_plan() -> WireQueryPlan {
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
fn update_order_mdbx_preserves_validation_and_atomicity() {
    // Scenario: A later row has an invalid boolean used only by the removed sort.
    // Covers: Per-row validation, rollback of earlier writes and revision stability.
    // Expected: The update fails without changing earlier rows or emitting changes.
    // Arrange.
    let directory = TemporaryDirectory::new("update_order_corrupt");
    let mut storage = MdbxStorage::open(directory.path()).unwrap();
    storage
        .register_schemas(&task_unindexed_schema_manifest())
        .unwrap();
    let original = task_compact_document(true, "original");
    storage.put("tasks", 1, &original).unwrap();
    storage.put("tasks", 2, &original).unwrap();
    storage
        .with_write_transaction(|transaction, _| {
            let table = open_documents_table(transaction, "tasks")?;
            let mut corrupt = original.clone();
            corrupt[3] = 7;
            transaction
                .put(&table, document_table_key(2), &corrupt, WriteFlags::UPSERT)
                .map_err(|error| error.to_string())
        })
        .unwrap();
    storage.take_change_sets().unwrap();
    let revision = storage.collection_revision("tasks").unwrap();
    let mut plan = unbounded_sorted_update_plan();
    plan.sorts[0].field = "completed".into();
    // Act.
    let result = storage.query_plan_update(
        "tasks",
        &plan,
        &[("title".into(), WireValue::String("changed".into()))],
        true,
    );
    // Assert.
    assert!(result.is_err(), "corrupt sort field must remain an error");
    assert_eq!(storage.get("tasks", 1).unwrap(), Some(original));
    assert_eq!(storage.collection_revision("tasks").unwrap(), revision);
    assert!(storage.take_change_sets().unwrap().is_empty());
    plan.sorts[0].field = "missing".into();
    assert!(storage
        .query_plan_update(
            "tasks",
            &plan,
            &[("title".into(), WireValue::String("changed".into()))],
            false
        )
        .is_err());
}

#[test]
fn update_order_mdbx_keeps_sort_for_windows_distinct_and_index_mutations() {
    // Scenario: Sort order participates in selection or the updated index values.
    // Covers: Offset, limit, distinct, simple indexes and composite members.
    // Expected: Every excluded case retains the existing sorting path.
    for mode in ["limit", "offset", "distinct", "index", "composite"] {
        // Arrange.
        let directory = TemporaryDirectory::new("update_order_exclusions");
        let mut manifest = task_unindexed_schema_manifest();
        if mode == "index" {
            manifest.collections[0].fields[0].is_indexed = true;
        }
        if mode == "composite" {
            manifest.collections[0].composite_indexes.push(
                crate::storage::CompositeIndexSchemaManifest {
                    name: "completed_title".into(),
                    fields: vec!["completed".into(), "title".into()],
                    is_unique: false,
                    is_replace: false,
                    case_sensitive: true,
                },
            );
        }
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        storage.register_schemas(&manifest).unwrap();
        for (id, title) in [(1, "B"), (2, "A"), (3, "C")] {
            storage
                .put("tasks", id, &task_compact_document(true, title))
                .unwrap();
        }
        let mut plan = unbounded_sorted_update_plan();
        match mode {
            "limit" => plan.limit = Some(2),
            "offset" => plan.offset = 1,
            "distinct" => plan.distinct_fields = vec!["completed".into()],
            _ => (),
        }
        SORT_KEY_COMPARISONS.with(|n| n.set(0));
        // Act.
        storage
            .query_plan_update(
                "tasks",
                &plan,
                &[("completed".into(), WireValue::Bool(false))],
                false,
            )
            .unwrap();
        // Assert.
        if mode == "distinct" {
            // Progressive distinct compares representatives separately from the
            // sorted-candidate counter; assert the retained ordered winner.
            assert_eq!(
                storage.get("tasks", 3).unwrap(),
                Some(task_compact_document(false, "C"))
            );
            assert_eq!(
                storage.get("tasks", 1).unwrap(),
                Some(task_compact_document(true, "B"))
            );
            assert_eq!(
                storage.get("tasks", 2).unwrap(),
                Some(task_compact_document(true, "A"))
            );
        } else {
            assert!(SORT_KEY_COMPARISONS.with(|n| n.get()) > 0, "{mode}");
        }
    }
}

#[test]
fn update_order_mdbx_collects_changes_without_changing_query_order() {
    // Scenario: An unlimited ordered update requests changed IDs for watchers.
    // Covers: One revision, all affected IDs and reuse of the original query plan.
    // Expected: Watchers receive the full changed set and reads keep the requested order.
    // Arrange.
    let directory = TemporaryDirectory::new("update_order_changes");
    let mut storage = MdbxStorage::open(directory.path()).unwrap();
    storage
        .register_schemas(&task_unindexed_schema_manifest())
        .unwrap();
    for (id, title) in [(1, "B"), (2, "A"), (3, "C")] {
        storage
            .put("tasks", id, &task_compact_document(true, title))
            .unwrap();
    }
    storage.take_change_sets().unwrap();
    let revision = storage.collection_revision("tasks").unwrap();
    let plan = unbounded_sorted_update_plan();
    // Act.
    assert_eq!(
        storage
            .query_plan_update(
                "tasks",
                &plan,
                &[("completed".into(), WireValue::Bool(false))],
                true
            )
            .unwrap(),
        3
    );
    // Assert.
    let changes = storage.take_change_sets().unwrap();
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0].revision, revision + 1);
    let mut ids = changes[0].document_ids.clone();
    ids.sort();
    assert_eq!(ids, [1, 2, 3]);
    assert_eq!(storage.query_plan_ids("tasks", &plan).unwrap(), [3, 1, 2]);
}

#[test]
fn update_order_mdbx_avoids_candidates_and_bounds_document_memory() {
    // Scenario: An ordered unlimited update changes an unindexed field in growing data.
    // Covers: Actual cursor traversal, sort comparisons, candidate retention and Rust peak.
    // Expected: One cursor scan, no sort/candidates and no document-sized batch retention.
    // Arrange / Act / Assert.
    for count in [2000, 20000] {
        let directory = TemporaryDirectory::new("update_order_memory");
        let mut storage = MdbxStorage::open(directory.path()).unwrap();
        storage
            .register_schemas(&task_unindexed_schema_manifest())
            .unwrap();
        let documents: Vec<_> = (1..=count)
            .map(|id| DocumentWrite {
                id,
                bytes: task_compact_document(true, &format!("value-{:08}", count - id)),
                indexes: vec![],
            })
            .collect();
        storage.put_many_indexed("tasks", &documents).unwrap();
        storage.take_change_sets().unwrap();
        let plan = unbounded_sorted_update_plan();
        let changes = [("completed".into(), WireValue::Bool(false))];
        SORT_KEY_COMPARISONS.with(|n| n.set(0));
        SORT_CANDIDATES_PEAK.with(|n| n.set(0));
        UPDATE_CURSOR_READS.with(|n| n.set(0));
        let peak = crate::storage::test_allocations::peak_bytes(|| {
            assert_eq!(
                storage
                    .query_plan_update("tasks", &plan, &changes, false)
                    .unwrap(),
                count as usize
            );
        });
        let comparisons = SORT_KEY_COMPARISONS.with(|n| n.get());
        let retained = SORT_CANDIDATES_PEAK.with(|n| n.get());
        let reads = UPDATE_CURSOR_READS.with(|n| n.get());
        eprintln!("update_order_mdbx rows={count} peak={peak} comparisons={comparisons} candidates={retained} reads={reads}");
        assert_eq!(comparisons, 0);
        assert_eq!(retained, 0);
        assert_eq!(reads, count as usize + 1);
        assert!(peak < 32768, "retained document batch: {peak}");
        assert_eq!(
            storage.get("tasks", 1).unwrap(),
            Some(task_compact_document(
                false,
                &format!("value-{:08}", count - 1)
            ))
        );
    }
}
