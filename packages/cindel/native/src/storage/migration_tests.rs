use super::*;
use std::time::{SystemTime, UNIX_EPOCH};

fn kinds() -> Vec<StorageBackendKind> {
    let kinds = vec![StorageBackendKind::Sqlite];
    #[cfg(feature = "mdbx")]
    let kinds = [kinds, vec![StorageBackendKind::Mdbx]].concat();
    kinds
}
fn token() -> String {
    format!(
        "{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    )
}
fn empty() -> SchemaManifest {
    SchemaManifest {
        collections: vec![],
    }
}

#[test]
fn migration_publication_is_atomic_and_preserves_unmodified_data_and_counters() {
    for kind in kinds() {
        let mut source = StorageBackend::open(kind, ":memory:").unwrap();
        source.put("nodes", 1, br#"{}"#).unwrap();
        source.put("other", 50, br#"{}"#).unwrap();
        source.set_migration_version(1).unwrap();
        let (mut stage, rev) = source.migration_fork(&token(), &empty()).unwrap();
        stage.put("nodes", 2, br#"{}"#).unwrap();
        stage.take_change_sets().unwrap();
        assert_eq!(source.document_ids("nodes").unwrap(), vec![1]);
        migration::fail_after(Some(3));
        assert!(source.migration_publish(&stage, rev, 2).is_err());
        migration::fail_after(None);
        assert_eq!(source.document_ids("nodes").unwrap(), vec![1]);
        assert_eq!(source.migration_version().unwrap(), Some(1));
        let path = match &stage {
            StorageBackend::Sqlite(s) => s.migration_temp_path(),
            #[cfg(feature = "mdbx")]
            StorageBackend::Mdbx(s) => s.migration_temp_path(),
        };
        assert!(path.exists());
        drop(stage);
        assert!(!path.exists(), "migration workspace was not removed");
        let (mut stage, rev) = source.migration_fork(&token(), &empty()).unwrap();
        stage.put("nodes", 2, br#"{}"#).unwrap();
        stage.take_change_sets().unwrap();
        source.migration_publish(&stage, rev, 2).unwrap();
        assert_eq!(source.document_ids("nodes").unwrap(), vec![1, 2]);
        assert_eq!(source.document_ids("other").unwrap(), vec![50]);
        assert_eq!(source.migration_version().unwrap(), Some(2));
        assert_eq!(source.allocate_id("other").unwrap(), 51);
    }
}

#[test]
fn migration_rejects_a_changed_source_without_overwriting_concurrent_data() {
    for kind in kinds() {
        let directory = std::env::temp_dir().join(format!("cindel-migration-conflict-{}", token()));
        std::fs::create_dir(&directory).unwrap();
        let path = directory.to_str().unwrap();
        {
            let mut source = StorageBackend::open(kind, path).unwrap();
            source.put("nodes", 1, br#"{}"#).unwrap();
            let mut other = StorageBackend::open(kind, path).unwrap();
            let (mut stage, rev) = source.migration_fork(&token(), &empty()).unwrap();
            stage.put("nodes", 2, br#"{}"#).unwrap();
            stage.take_change_sets().unwrap();
            other.put("nodes", 3, br#"{}"#).unwrap();
            assert_eq!(source.document_ids("nodes").unwrap(), vec![1]);
            assert!(source
                .migration_publish(&stage, rev, 2)
                .unwrap_err()
                .contains("changed"));
            assert_eq!(source.document_ids("nodes").unwrap(), vec![1, 3]);
        }
        std::fs::remove_dir_all(directory).unwrap();
    }
}

#[test]
fn migration_copy_memory_is_bounded_and_traversals_are_linear() {
    for kind in kinds() {
        let mut previous = None;
        for n in [1000, 10000] {
            let payload = format!("{{\"value\":\"{}\"}}", "x".repeat(4096)).into_bytes();
            let mut source = StorageBackend::open(kind, ":memory:").unwrap();
            for start in (1..=n).step_by(100) {
                source.begin_write_transaction().unwrap();
                for id in start..start + 100 {
                    source.put("nodes", id, &payload).unwrap();
                }
                source.commit_transaction().unwrap();
            }
            let mut visited = 0;
            let peak = test_allocations::peak_bytes(|| {
                let (_, records) = migration::measure(|| {
                    let (stage, rev) = source.migration_fork(&token(), &empty()).unwrap();
                    source.migration_publish(&stage, rev, 2).unwrap();
                });
                visited = records;
            });
            assert!(peak < 512 * 1024, "{kind:?}: heap {peak}");
            if let Some(small) = previous {
                assert_eq!(visited - 2 * n as usize, small, "extra data traversals");
            }
            previous = Some(visited - 2 * n as usize);
            assert!(visited >= 2 * n as usize);
            eprintln!("{kind:?}: {n} documents; copied={visited}; Rust peak={peak}");
            let mut after = None;
            let mut seen = 0;
            loop {
                let ids = source.migration_ids_page("nodes", after, 37).unwrap();
                if ids.is_empty() {
                    break;
                }
                assert!(ids.len() <= 37);
                seen += ids.len();
                after = ids.last().copied();
            }
            assert_eq!(seen, n as usize);
        }
    }
}

#[test]
fn migration_schema_reconstruction_has_bounded_memory_and_keeps_relations() {
    use crate::document_format::{write_compact_document_for_test, BinaryValue};
    let field = |name: &str, id| FieldSchemaManifest {
        name: name.into(),
        dart_type: "int".into(),
        binary_type: "int".into(),
        is_id: id,
        is_indexed: !id,
        is_index_unique: !id,
        is_index_replace: false,
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
    for kind in kinds() {
        for n in [1000, 10000] {
            let mut source = StorageBackend::open(kind, ":memory:").unwrap();
            source.register_schemas(&manifest).unwrap();
            for start in (1..=n).step_by(100) {
                if matches!(kind, StorageBackendKind::Sqlite) {
                    let documents = (start..start + 100)
                        .map(|id| NativeDocumentWrite {
                            id,
                            values: vec![NativeDocumentValue::Int(id as i64)],
                        })
                        .collect::<Vec<_>>();
                    source
                        .put_many_native_documents("nodes", &documents, false)
                        .unwrap();
                } else {
                    let documents = (start..start + 100)
                        .map(|id| DocumentWrite {
                            id,
                            bytes: write_compact_document_for_test(
                                &manifest.collections[0],
                                &[None, Some(BinaryValue::Int(id as i64))],
                            )
                            .unwrap(),
                            indexes: vec![],
                        })
                        .collect::<Vec<_>>();
                    source.put_many_indexed("nodes", &documents).unwrap();
                }
            }
            source
                .replace_links(&LinkSave {
                    source_collection: "nodes".into(),
                    source_id: 1,
                    link_name: "next".into(),
                    target_collection: "nodes".into(),
                    target_ids: vec![2],
                })
                .unwrap();
            let (mut stage, rev) = source.migration_fork(&token(), &manifest).unwrap();
            let peak = test_allocations::peak_bytes(|| {
                stage.register_migrated_schemas(&manifest).unwrap()
            });
            assert!(peak < 512 * 1024, "{kind:?} schema clear heap: {peak}");
            assert!(stage.document_ids("nodes").unwrap().is_empty());
            assert_eq!(
                stage.forward_link_ids("nodes", 1, "next", "nodes").unwrap(),
                vec![2]
            );
            let mut after = None;
            let mut seen = 0;
            loop {
                let ids = source.migration_ids_page("nodes", after, 73).unwrap();
                if ids.is_empty() {
                    break;
                }
                seen += ids.len();
                after = ids.last().copied();
            }
            assert_eq!(seen, n as usize);
            let before = source.collection_revision("nodes").unwrap();
            source.migration_publish(&stage, rev, 2).unwrap();
            assert!(source.collection_revision("nodes").unwrap() > before);
            assert_eq!(source.schema_version("nodes").unwrap(), Some(2));
            eprintln!("{kind:?}: clear {n} indexed rows, Rust peak={peak}");
        }
    }
}
