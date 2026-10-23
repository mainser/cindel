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
        assert_eq!(s.take_change_sets().unwrap().iter().find(|c|c.collection=="b").unwrap().revision, s.collection_revision("b").unwrap());
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
