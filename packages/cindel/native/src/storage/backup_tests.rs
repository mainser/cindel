use super::*;
use crate::backup::BackupSpool;
use crate::document_format::{write_compact_document_for_test, BinaryValue};
use crate::wire::{
    encode_document_write_batch, encode_native_document_write_batch, WireDocumentWrite,
    WireNativeDocumentValue, WireNativeDocumentWrite,
};
use std::time::{SystemTime, UNIX_EPOCH};

fn token() -> String {
    format!(
        "test-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    )
}
fn kinds() -> Vec<StorageBackendKind> {
    vec![
        StorageBackendKind::Sqlite,
        #[cfg(feature = "mdbx")]
        StorageBackendKind::Mdbx,
    ]
}
fn schema(replace: bool) -> SchemaManifest {
    let field = |name: &str, kind: &str, id, indexed| FieldSchemaManifest {
        name: name.into(),
        dart_type: kind.into(),
        binary_type: kind.into(),
        is_id: id,
        is_indexed: indexed,
        is_index_unique: indexed,
        is_index_replace: replace && indexed,
        index_case_sensitive: true,
        index_type: "value".into(),
    };
    SchemaManifest {
        collections: vec![CollectionSchemaManifest {
            name: "nodes".into(),
            id_field: "id".into(),
            fields: vec![
                field("code", "int", false, true),
                field("id", "int", true, false),
                field("payload", "string", false, false),
            ],
            composite_indexes: vec![],
        }],
    }
}
fn payload(
    schema: &SchemaManifest,
    start: u64,
    count: usize,
    size: usize,
    duplicate: bool,
    native: bool,
) -> Vec<u8> {
    if native {
        return encode_native_document_write_batch(
            &(0..count)
                .map(|i| WireNativeDocumentWrite {
                    id: start + i as u64,
                    values: vec![
                        WireNativeDocumentValue::Int(if duplicate {
                            1
                        } else {
                            (start + i as u64) as i64
                        }),
                        WireNativeDocumentValue::Bytes(vec![b'x'; size]),
                    ],
                })
                .collect::<Vec<_>>(),
        )
        .unwrap();
    }
    encode_document_write_batch(
        &(0..count)
            .map(|i| WireDocumentWrite {
                id: start + i as u64,
                bytes: write_compact_document_for_test(
                    &schema.collections[0],
                    &[
                        Some(BinaryValue::Int(if duplicate {
                            1
                        } else {
                            (start + i as u64) as i64
                        })),
                        None,
                        Some(BinaryValue::String("x".repeat(size))),
                    ],
                )
                .unwrap(),
            })
            .collect::<Vec<_>>(),
    )
    .unwrap()
}
fn restore(storage: &mut StorageBackend, spool: &BackupSpool) -> Result<(), String> {
    match storage {
        StorageBackend::Sqlite(s) => s.restore_backup(spool, 7),
        #[cfg(feature = "mdbx")]
        StorageBackend::Mdbx(s) => s.restore_backup(spool, 7),
    }
}

#[test]
fn backup_rolls_back_failed_publication_and_rejects_unique_replace_data_loss() {
    for kind in kinds() {
        let native = kind == StorageBackendKind::Sqlite;
        for replace in [false, true] {
            let directory = std::env::temp_dir().join(token());
            let schema = schema(replace);
            let mut storage =
                StorageBackend::open_with_schemas(kind, directory.to_str().unwrap(), &schema)
                    .unwrap();
            storage.set_migration_version(9).unwrap();
            let mut spool =
                BackupSpool::open(&token(), vec![("nodes".into(), Some(1))], 9).unwrap();
            spool
                .stage("nodes", native, &payload(&schema, 1, 2, 128, true, native))
                .unwrap();
            let result = restore(&mut storage, &spool);
            assert!(result.is_err(), "{kind:?} replace={replace}: {result:?}");
            assert!(storage
                .document_ids_page("nodes", None, 1)
                .unwrap()
                .is_empty());
            assert_eq!(storage.migration_version().unwrap(), Some(9));
            assert_eq!(storage.allocate_id("nodes").unwrap(), 1);
            drop(spool);
            drop(storage);
            std::fs::remove_dir_all(directory).unwrap();
        }
    }
}

// Scenario: Restore archives grow from 8 to 64 MiB while other tests may hold
// unrelated SQLite allocations in the test runner.
// Covers:
// - Process-isolated SQLite memory counters and page-cache accounting.
// - Bounded Rust/C allocations, disk staging, ID counters and file cleanup.
// Expected: Unrelated allocations do not affect the measurement; the original
// Rust heap and staging-cache limits still hold as the archive grows.
#[test]
fn backup_memory_is_bounded_while_staging_and_restoring_64_mib() {
    #[cfg(not(target_family = "wasm"))]
    {
        const CHILD: &str = "CINDEL_BACKUP_MEMORY_TEST_CHILD";
        if std::env::var_os(CHILD).is_none() {
            // Arrange: keep unrelated C allocations alive in the parent. This
            // also checks isolation when this test is run on its own.
            let unrelated = rusqlite::Connection::open_in_memory().unwrap();
            unrelated
                .execute_batch(
                    "CREATE TABLE unrelated(payload BLOB);
                     INSERT INTO unrelated VALUES (zeroblob(16777216));",
                )
                .unwrap();
            assert!(unsafe { rusqlite::ffi::sqlite3_memory_used() } >= 16 * 1024 * 1024);
            // Act: SQLite's allocator and unified page-cache pool are process
            // global. A mutex around this test alone cannot isolate them from
            // other tests that open connections without that mutex.
            let output = std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    concat!(
                        module_path!(),
                        "::backup_memory_is_bounded_while_staging_and_restoring_64_mib"
                    )
                    .strip_prefix("cindel_native::")
                    .unwrap(),
                    "--nocapture",
                    "--test-threads=1",
                ])
                .env(CHILD, "1")
                .output()
                .unwrap();
            // Assert: propagate the child's diagnostics and failure to Cargo.
            let stdout = String::from_utf8_lossy(&output.stdout);
            let stderr = String::from_utf8_lossy(&output.stderr);
            print!("{stdout}");
            eprint!("{stderr}");
            assert!(output.status.success(), "isolated memory test failed");
            assert!(stdout.contains("1 passed;"), "memory test was not executed");
            drop(unrelated);
            return;
        }
        assert!(unsafe { rusqlite::ffi::sqlite3_memory_used() } < 1024 * 1024);
    }
    // Arrange.
    for kind in kinds() {
        let native = kind == StorageBackendKind::Sqlite;
        for count in [128, 1024] {
            let directory = std::env::temp_dir().join(token());
            let schema = schema(false);
            let mut storage =
                StorageBackend::open_with_schemas(kind, directory.to_str().unwrap(), &schema)
                    .unwrap();
            let mut spool =
                BackupSpool::open(&token(), vec![("nodes".into(), Some(1))], 0).unwrap();
            let stage_path = spool.connection.path().unwrap().to_string();
            // SQLite's C allocations are separate from Rust's allocator. The
            // isolated process keeps other tests out of this global peak.
            unsafe {
                rusqlite::ffi::sqlite3_memory_highwater(1);
            }
            // Act.
            let peak = super::test_allocations::peak_bytes(|| {
                for start in (1..=count).step_by(8) {
                    spool
                        .stage(
                            "nodes",
                            native,
                            &payload(&schema, start, 8, 65536, false, native),
                        )
                        .unwrap();
                }
                restore(&mut storage, &spool).unwrap();
            });
            let sqlite_peak = unsafe { rusqlite::ffi::sqlite3_memory_highwater(0) };
            let mut cache = 0;
            let mut unused = 0;
            let status = unsafe {
                rusqlite::ffi::sqlite3_db_status(
                    spool.connection.handle(),
                    rusqlite::ffi::SQLITE_DBSTATUS_CACHE_USED,
                    &mut cache,
                    &mut unused,
                    0,
                )
            };
            // Assert.
            assert_eq!(status, rusqlite::ffi::SQLITE_OK);
            eprintln!("{kind:?}: archive={} MiB, Rust peak={peak}, SQLite C peak={sqlite_peak}, staging cache={cache}", count / 16);
            assert!(peak < 8 * 1024 * 1024, "{peak} Rust heap bytes retained");
            assert!(
                sqlite_peak < 8 * 1024 * 1024,
                "{sqlite_peak} SQLite heap bytes retained"
            );
            assert!(
                cache < 2 * 1024 * 1024,
                "{cache} staging cache bytes retained"
            );
            // The archive itself lives on disk, not in a SQLite memory database.
            assert!(std::fs::metadata(&stage_path).unwrap().len() >= count * 65536);
            assert_eq!(storage.allocate_id("nodes").unwrap(), count + 1);
            drop(spool);
            assert!(!std::path::Path::new(&stage_path).exists());
            drop(storage);
            std::fs::remove_dir_all(directory).unwrap();
        }
    }
}
