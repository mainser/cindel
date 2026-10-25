use super::*;

fn kinds() -> Vec<StorageBackendKind> {
    vec![
        StorageBackendKind::Sqlite,
        #[cfg(feature = "mdbx")]
        StorageBackendKind::Mdbx,
    ]
}
fn edge(source: &str, id: u64, target: &str, targets: Vec<u64>) -> LinkSave {
    LinkSave {
        source_collection: source.into(),
        source_id: id,
        link_name: "link".into(),
        target_collection: target.into(),
        target_ids: targets,
    }
}
fn cleanup(storage: &mut StorageBackend) -> (u64, u64) {
    match storage {
        StorageBackend::Sqlite(s) => s.cleanup_orphan_links().unwrap(),
        #[cfg(feature = "mdbx")]
        StorageBackend::Mdbx(s) => s.cleanup_orphan_links().unwrap(),
    }
}
fn counts(storage: &StorageBackend) -> (usize, usize) {
    match storage {
        StorageBackend::Sqlite(s) => s.relation_counts(),
        #[cfg(feature = "mdbx")]
        StorageBackend::Mdbx(s) => s.relation_counts(),
    }
}

fn batch_storage(kind: StorageBackendKind, typed: bool) -> StorageBackend {
    if !typed {
        let mut storage = StorageBackend::open(kind, ":memory:").unwrap();
        for id in 1..=5 {
            storage.put("nodes", id, br#"{}"#).unwrap();
        }
        return storage;
    }
    let field = |name: &str, is_id| FieldSchemaManifest {
        name: name.into(),
        dart_type: "int".into(),
        binary_type: "int".into(),
        is_id,
        is_indexed: false,
        is_index_unique: false,
        is_index_replace: false,
        index_case_sensitive: true,
        index_type: "value".into(),
    };
    let schema = CollectionSchemaManifest {
        name: "nodes".into(),
        id_field: "id".into(),
        fields: vec![field("id", true), field("value", false)],
        composite_indexes: vec![],
    };
    let manifest = SchemaManifest {
        collections: vec![schema.clone()],
    };
    let mut storage = StorageBackend::open_with_schemas(kind, ":memory:", &manifest).unwrap();
    for id in 1..=5 {
        if matches!(storage, StorageBackend::Sqlite(_)) {
            storage
                .put_many_native_documents(
                    "nodes",
                    &[NativeDocumentWrite {
                        id,
                        values: vec![NativeDocumentValue::Int(id as i64)],
                    }],
                    true,
                )
                .unwrap();
        } else {
            let bytes = crate::document_format::write_compact_document_for_test(
                &schema,
                &[
                    None,
                    Some(crate::document_format::BinaryValue::Int(id as i64)),
                ],
            );
            storage
                .put_many_indexed(
                    "nodes",
                    &[DocumentWrite {
                        id,
                        bytes: bytes.unwrap(),
                        indexes: vec![],
                    }],
                )
                .unwrap();
        }
    }
    storage
}

fn delete_batch(storage: &mut StorageBackend, typed: bool, ids: &[u64]) -> Result<(), String> {
    if typed && matches!(storage, StorageBackend::Sqlite(_)) {
        assert!(storage.delete_many_native_documents("nodes", ids)?);
        Ok(())
    } else {
        storage.delete_many("nodes", ids)
    }
}

// Scenario: Large typed/generic ID batches target a collection with no relations,
// while another collection with a similar name has live links.
// Covers:
// - Empty endpoint lookups and resource creation, including missing IDs.
// - Collection-specific checks rather than schema declarations or global emptiness.
// Expected: Two collection checks, no per-ID relation reads, and untouched links.
#[test]
fn relation_batch_without_edges_has_constant_lookup_work() {
    // Arrange.
    for kind in kinds() {
        for typed in [false, true] {
            for count in [1, 1000, 25000] {
                let mut storage = batch_storage(kind, typed);
                storage.put("nodes_other", 1, br#"{}"#).unwrap();
                storage
                    .replace_links(&edge("nodes_other", 1, "nodes_other", vec![1]))
                    .unwrap();
                let ids = (1..=count).collect::<Vec<_>>();
                // Act.
                let (result, work) =
                    relations::measure_work(|| delete_batch(&mut storage, typed, &ids));
                // Assert.
                result.unwrap();
                assert_eq!(
                    work.collection_checks, 2,
                    "{kind:?}, typed={typed}, count={count}: {work:?}"
                );
                assert_eq!(work.pages, 0, "{kind:?}: empty per-ID lookups: {work:?}");
                assert!(work.resources <= 4, "{kind:?}: {work:?}");
                assert_eq!(counts(&storage), (1, 1));
                assert_eq!(
                    storage.document_ids("nodes").unwrap(),
                    if count == 1 { vec![2, 3, 4, 5] } else { vec![] }
                );
            }
        }
    }
}

// Scenario: A batch removes an incoming endpoint and a missing legacy endpoint,
// with repeated IDs and more edges than fit in one page.
// Covers:
// - Reused endpoint resources, bounded pages, and cleanup for absent documents.
// - Preservation of unrelated edges in both storage layouts.
// Expected: Only incident edges are visited; preparation stays constant and
// retained pages never exceed 128 edges as the relation set grows.
#[test]
fn relation_batch_reuses_endpoint_resources_and_bounds_pages() {
    // Arrange.
    for kind in kinds() {
        for typed in [false, true] {
            for count in [256, 2048] {
                let mut storage = batch_storage(kind, typed);
                match &mut storage {
                    StorageBackend::Sqlite(s) => s.seed_legacy_edges(count),
                    #[cfg(feature = "mdbx")]
                    StorageBackend::Mdbx(s) => s.seed_legacy_edges(count),
                }
                // Act.
                let mut measurement = None;
                let peak = test_allocations::peak_bytes(|| {
                    measurement = Some(relations::measure_work(|| {
                        relations::measure(|| delete_batch(&mut storage, typed, &[2, 2, 999]))
                    }));
                });
                let ((result, visited, retained), work) = measurement.unwrap();
                // Assert.
                result.unwrap();
                assert_eq!(visited, 2 * count, "{kind:?}, typed={typed}");
                assert!(retained <= 128);
                assert!(peak < 512 * 1024, "{kind:?}, typed={typed}: peak={peak}");
                assert_eq!(work.collection_checks, 2);
                assert!(work.resources <= 4, "{kind:?}: {work:?}");
                assert_eq!(counts(&storage), (count, count));
                assert_eq!(storage.document_ids("nodes").unwrap(), vec![1, 3, 4, 5]);
                eprintln!("{kind:?}, typed={typed}, edges={count}: {work:?}, visited={visited}, retained={retained}, peak={peak}");
            }
        }
    }
}

#[test]
fn relation_deletes_are_atomic_in_both_directions_and_notify_related_collections() {
    for kind in kinds() {
        let mut s = StorageBackend::open(kind, ":memory:").unwrap();
        for (name, id) in [("a", 1), ("a", 2), ("b", 1)] {
            s.put(name, id, br#"{"name":"before"}"#).unwrap();
        }
        s.replace_links(&edge("a", 1, "a", vec![1, 2])).unwrap();
        s.replace_links(&edge("b", 1, "a", vec![1])).unwrap();
        s.take_change_sets().unwrap();
        s.put("a", 1, br#"{"name":"updated"}"#).unwrap();
        assert_eq!(s.forward_link_ids("a", 1, "link", "a").unwrap(), vec![1, 2]);
        s.take_change_sets().unwrap();
        let related_revision = s.collection_revision("b").unwrap();
        s.begin_write_transaction().unwrap();
        s.delete("a", 1).unwrap();
        assert!(s.forward_link_ids("b", 1, "link", "a").unwrap().is_empty());
        assert!(s
            .backlink_source_ids("a", 2, "a", "link")
            .unwrap()
            .is_empty());
        s.rollback_transaction().unwrap();
        assert_eq!(counts(&s), (3, 3));
        assert_eq!(s.collection_revision("b").unwrap(), related_revision);
        assert!(s.take_change_sets().unwrap().is_empty());
        s.begin_write_transaction().unwrap();
        s.delete_many("a", &[1, 1, 999]).unwrap();
        s.put("a", 1, br#"{"name":"replacement"}"#).unwrap();
        assert!(s.forward_link_ids("b", 1, "link", "a").unwrap().is_empty());
        s.commit_transaction().unwrap();
        assert_eq!(counts(&s), (0, 0));
        assert!(s.collection_revision("b").unwrap() > related_revision);
        let changes = s.take_change_sets().unwrap();
        assert!(changes
            .iter()
            .any(|c| c.collection == "b" && c.document_ids.is_empty()));
        assert!(changes
            .iter()
            .any(|c| c.collection == "a" && c.document_ids.is_empty()));
        assert_eq!(cleanup(&mut s), (0, 0));
        let after_cleanup = s.collection_revision("b").unwrap();
        s.put("b", 1, br#"{"name":"later update"}"#).unwrap();
        assert!(s.collection_revision("b").unwrap() > after_cleanup);
        assert_eq!(
            s.take_change_sets()
                .unwrap()
                .iter()
                .find(|c| c.collection == "b")
                .unwrap()
                .revision,
            s.collection_revision("b").unwrap()
        );
    }
}

#[test]
fn relation_deletes_cover_direct_bool_index_and_unique_replacement_rollback() {
    use crate::document_format::{write_compact_document_for_test, BinaryValue};
    for kind in kinds() {
        for boolean in [true, false] {
            let field = |name: &str, id: bool| FieldSchemaManifest {
                name: name.into(),
                dart_type: if !id && boolean { "bool" } else { "int" }.into(),
                binary_type: if !id && boolean { "bool" } else { "int" }.into(),
                is_id: id,
                is_indexed: !id,
                is_index_unique: !id && !boolean,
                is_index_replace: !id && !boolean,
                index_case_sensitive: true,
                index_type: "value".into(),
            };
            let manifest = SchemaManifest {
                collections: vec![CollectionSchemaManifest {
                    name: "nodes".into(),
                    id_field: "id".into(),
                    fields: vec![field("id", true), field("value", false)],
                    composite_indexes: vec![],
                }],
            };
            let mut s = StorageBackend::open_with_schemas(kind, ":memory:", &manifest).unwrap();
            let put = |s: &mut StorageBackend, id, value| {
                if matches!(s, StorageBackend::Sqlite(_)) {
                    s.put_many_native_documents(
                        "nodes",
                        &[NativeDocumentWrite {
                            id,
                            values: vec![if boolean {
                                NativeDocumentValue::Bool(value != 0)
                            } else {
                                NativeDocumentValue::Int(value)
                            }],
                        }],
                        true,
                    )
                    .unwrap();
                } else {
                    let bytes = write_compact_document_for_test(
                        &manifest.collections[0],
                        &[
                            None,
                            Some(if boolean {
                                BinaryValue::Bool(value != 0)
                            } else {
                                BinaryValue::Int(value)
                            }),
                        ],
                    )
                    .unwrap();
                    s.put_many_indexed(
                        "nodes",
                        &[DocumentWrite {
                            id,
                            bytes,
                            indexes: vec![],
                        }],
                    )
                    .unwrap();
                }
            };
            put(&mut s, 1, 1);
            put(&mut s, 2, 0);
            s.replace_links(&edge("nodes", 1, "nodes", vec![2]))
                .unwrap();
            s.take_change_sets().unwrap();
            s.begin_write_transaction().unwrap();
            if boolean {
                s.delete_many("nodes", &[2]).unwrap();
            } else {
                put(&mut s, 3, 0);
            }
            s.rollback_transaction().unwrap();
            assert_eq!(counts(&s), (1, 1));
            if boolean {
                s.delete_many("nodes", &[2]).unwrap();
            } else {
                put(&mut s, 3, 0);
            }
            assert_eq!(counts(&s), (0, 0), "{kind:?}, bool={boolean}");
            put(&mut s, 2, 7);
            assert!(s
                .forward_link_ids("nodes", 1, "link", "nodes")
                .unwrap()
                .is_empty());
        }
    }
}

#[test]
fn relation_cleanup_pages_bound_memory_and_delete_visits_only_incident_edges() {
    for kind in kinds() {
        for n in [1000, 10000] {
            let mut s = StorageBackend::open(kind, ":memory:").unwrap();
            for id in 1..=5 {
                s.put("nodes", id, br#"{}"#).unwrap();
            }
            match &mut s {
                StorageBackend::Sqlite(s) => s.seed_legacy_edges(n),
                #[cfg(feature = "mdbx")]
                StorageBackend::Mdbx(s) => s.seed_legacy_edges(n),
            }
            s.take_change_sets().unwrap();
            let mut visited = 0;
            let mut retained = 0;
            let peak = test_allocations::peak_bytes(|| {
                let (result, seen, page) = relations::measure(|| s.delete("nodes", 2));
                result.unwrap();
                visited = seen;
                retained = page;
                s.take_change_sets().unwrap();
            });
            assert_eq!(visited, n, "{kind:?}: unrelated relations were scanned");
            assert!(retained <= 128);
            assert!(peak < 512 * 1024, "{kind:?}: deletion heap {peak}");
            assert_eq!(counts(&s), (2 * n, 2 * n));
            let mut result = (0, 0);
            let cleanup_peak = test_allocations::peak_bytes(|| {
                let (value, seen, page) = relations::measure(|| cleanup(&mut s));
                result = value;
                visited = seen;
                retained = page;
                s.take_change_sets().unwrap();
            });
            assert_eq!(result, ((2 * n) as u64, n as u64));
            assert_eq!(visited, 2 * n);
            assert!(retained <= 128);
            assert!(
                cleanup_peak < 512 * 1024,
                "{kind:?}: cleanup heap {cleanup_peak}"
            );
            assert_eq!(counts(&s), (n, n));
            assert_eq!(cleanup(&mut s), (n as u64, 0));
            eprintln!("{kind:?}: {n} incident edges, delete peak={peak}, cleanup peak={cleanup_peak}, page bound=128");
        }
    }
}
