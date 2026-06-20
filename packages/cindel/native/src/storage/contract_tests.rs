use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use super::{
    CollectionSchemaManifest, DocumentWrite, FieldSchemaManifest, IndexEntry, IndexValue,
    SchemaManifest, StorageEngine,
};
use super::{
    DocumentFormatVersion, IndexVerificationCheck, SchemaMetadataVersion, StorageLayoutVersion,
};

pub(super) fn run_storage_engine_contract<S>(
    backend: &str,
    open: impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    stores_reads_and_deletes_bytes_by_collection_and_id(backend, &open);
    reads_many_documents_in_input_order(backend, &open);
    keeps_documents_with_the_same_id_separate_by_collection(backend, &open);
    lists_document_ids_by_collection(backend, &open);
    advances_collection_revision_after_committed_changes(backend, &open);
    registers_and_migrates_schema_versions(backend, &open);
    rejects_incompatible_schema_changes(backend, &open);
    persists_index_variant_metadata_in_schemas(backend, &open);
    rejects_incompatible_index_option_changes(backend, &open);
    allocates_monotonic_ids_and_advances_after_manual_put(backend, &open);
    queries_documents_by_index_equality_and_range(backend, &open);
    queries_composite_and_multi_entry_indexes(backend, &open);
    replaces_and_deletes_index_entries_with_documents(backend, &open);
    rejects_duplicate_unique_index_values(backend, &open);
    bulk_puts_documents_atomically_and_updates_indexes(backend, &open);
    rolls_back_bulk_put_when_one_document_has_an_invalid_index(backend, &open);
    bulk_deletes_documents_atomically_and_cleans_indexes(backend, &open);
    exposes_storage_metadata(backend, &open);
    rebuilds_indexes_with_supplied_entries(backend, &open);
    verifies_storage_after_index_rebuild(backend, &open);
}

pub(super) fn run_storage_transaction_contract<S>(
    backend: &str,
    open: impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    commits_explicit_write_transactions(backend, &open);
    rolls_back_explicit_write_transactions(backend, &open);
    rejects_writes_inside_read_transactions(backend, &open);
    rejects_nested_explicit_transactions(backend, &open);
    rolls_back_allocated_ids(backend, &open);
    rolls_back_failed_write_transaction_commits(backend, &open);
}

fn stores_reads_and_deletes_bytes_by_collection_and_id<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "crud");
    let mut storage = open(directory.path()).unwrap();

    storage.put("users", 1, br#"{"name":"Noel"}"#).unwrap();
    assert_eq!(
        storage.get("users", 1).unwrap(),
        Some(br#"{"name":"Noel"}"#.to_vec())
    );

    storage.delete("users", 1).unwrap();
    assert_eq!(storage.get("users", 1).unwrap(), None);
}

fn reads_many_documents_in_input_order<S>(backend: &str, open: &impl Fn(&str) -> Result<S, String>)
where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "get_many");
    let mut storage = open(directory.path()).unwrap();

    storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
    storage.put("users", 3, br#"{"name":"Cid"}"#).unwrap();

    assert_eq!(
        storage.get_many("users", &[3, 2, 1]).unwrap(),
        vec![
            Some(br#"{"name":"Cid"}"#.to_vec()),
            None,
            Some(br#"{"name":"Ana"}"#.to_vec()),
        ]
    );
}

fn keeps_documents_with_the_same_id_separate_by_collection<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "collections");
    let mut storage = open(directory.path()).unwrap();

    storage.put("users", 1, br#"{"name":"Noel"}"#).unwrap();
    storage.put("settings", 1, br#"{"theme":"dark"}"#).unwrap();

    assert_eq!(
        storage.get("users", 1).unwrap(),
        Some(br#"{"name":"Noel"}"#.to_vec())
    );
    assert_eq!(
        storage.get("settings", 1).unwrap(),
        Some(br#"{"theme":"dark"}"#.to_vec())
    );
}

fn lists_document_ids_by_collection<S>(backend: &str, open: &impl Fn(&str) -> Result<S, String>)
where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "document_ids");
    let mut storage = open(directory.path()).unwrap();

    storage.put("users", 3, br#"{"name":"Cid"}"#).unwrap();
    storage.put("settings", 1, br#"{"theme":"dark"}"#).unwrap();
    storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();

    assert_eq!(storage.document_ids("users").unwrap(), vec![1, 3]);
}

fn advances_collection_revision_after_committed_changes<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "revision");
    let mut storage = open(directory.path()).unwrap();

    assert_eq!(storage.collection_revision("users").unwrap(), 0);
    storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
    assert_eq!(storage.collection_revision("users").unwrap(), 1);
    storage.put("users", 1, br#"{"name":"Ada"}"#).unwrap();
    assert_eq!(storage.collection_revision("users").unwrap(), 2);
    storage.delete("users", 1).unwrap();
    assert_eq!(storage.collection_revision("users").unwrap(), 3);
    storage.delete("users", 1).unwrap();
    assert_eq!(storage.collection_revision("users").unwrap(), 3);
}

fn registers_and_migrates_schema_versions<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    // Scenario: A backend registers an initial schema and then accepts a
    // compatible additive schema change.
    // Covers:
    // - Persisted per-collection schema version reads.
    // - Version advancement on compatible registration.
    // - Shared SQLite/MDBX schema-version contract used by public migrations.
    // Expected: The first registration stores version 1 and the additive
    // registration advances the same collection to version 2.
    let directory = TemporaryDirectory::new(backend, "schema_versions");
    let mut storage = open(directory.path()).unwrap();
    let original = schema_manifest(vec![user_schema(vec![field(
        "email", "String", false, true,
    )])]);
    let expanded = schema_manifest(vec![user_schema(vec![
        field("email", "String", false, true),
        field("active", "bool?", false, false),
    ])]);

    storage.register_schemas(&original).unwrap();
    assert_eq!(storage.schema_version("users").unwrap(), Some(1));
    storage.register_schemas(&expanded).unwrap();
    assert_eq!(storage.schema_version("users").unwrap(), Some(2));
}

fn rejects_incompatible_schema_changes<S>(backend: &str, open: &impl Fn(&str) -> Result<S, String>)
where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "schema_incompatible");
    let mut storage = open(directory.path()).unwrap();
    let original = schema_manifest(vec![user_schema(vec![field(
        "email", "String", false, true,
    )])]);
    let incompatible = schema_manifest(vec![user_schema(vec![field("email", "int", false, true)])]);

    storage.register_schemas(&original).unwrap();
    let result = storage.register_schemas(&incompatible);

    assert!(result.unwrap_err().contains("cannot change type"));
    assert_eq!(storage.schema_version("users").unwrap(), Some(1));
}

fn persists_index_variant_metadata_in_schemas<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "schema_index_variants");
    let mut storage = open(directory.path()).unwrap();
    let mut email = field("email", "String", false, true);
    email.is_index_unique = true;
    email.index_case_sensitive = false;
    let mut token = field("token", "String", false, true);
    token.index_type = "hash".to_string();
    let mut bio = field("bio", "String", false, true);
    bio.index_type = "words".to_string();
    bio.index_case_sensitive = false;
    let manifest = schema_manifest(vec![user_schema(vec![email, token, bio])]);

    storage.register_schemas(&manifest).unwrap();
    storage.register_schemas(&manifest).unwrap();

    assert_eq!(storage.schema_version("users").unwrap(), Some(1));
}

fn rejects_incompatible_index_option_changes<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "schema_index_option_change");
    let mut storage = open(directory.path()).unwrap();
    let original = schema_manifest(vec![user_schema(vec![field(
        "email", "String", false, true,
    )])]);
    let mut unique_email = field("email", "String", false, true);
    unique_email.is_index_unique = true;
    let incompatible = schema_manifest(vec![user_schema(vec![unique_email])]);

    storage.register_schemas(&original).unwrap();
    let result = storage.register_schemas(&incompatible);

    assert!(result.unwrap_err().contains("cannot change index options"));
    assert_eq!(storage.schema_version("users").unwrap(), Some(1));
}

fn allocates_monotonic_ids_and_advances_after_manual_put<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "allocate");
    let mut storage = open(directory.path()).unwrap();

    assert_eq!(storage.allocate_id("users").unwrap(), 1);
    assert_eq!(storage.allocate_id("users").unwrap(), 2);
    assert_eq!(storage.allocate_id("settings").unwrap(), 1);
    storage.put("users", 10, br#"{"name":"Ana"}"#).unwrap();
    assert_eq!(storage.allocate_id("users").unwrap(), 11);
}

fn queries_documents_by_index_equality_and_range<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "indexes");
    let mut storage = open(directory.path()).unwrap();

    storage
        .put_indexed(
            "users",
            1,
            br#"{"email":"a@example.com","score":10}"#,
            &[
                index("email", IndexValue::String("a@example.com".into())),
                index("score", IndexValue::Int(10)),
            ],
        )
        .unwrap();
    storage
        .put_indexed(
            "users",
            2,
            br#"{"email":"b@example.com","score":30}"#,
            &[
                index("email", IndexValue::String("b@example.com".into())),
                index("score", IndexValue::Int(30)),
            ],
        )
        .unwrap();
    storage
        .put_indexed(
            "users",
            3,
            br#"{"email":"a@example.com","score":20}"#,
            &[
                index("email", IndexValue::String("a@example.com".into())),
                index("score", IndexValue::Int(20)),
            ],
        )
        .unwrap();

    assert_eq!(
        storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("a@example.com".into())
            )
            .unwrap(),
        vec![1, 3]
    );
    assert_eq!(
        storage
            .query_index_range(
                "users",
                "score",
                Some(&IndexValue::Int(15)),
                Some(&IndexValue::Int(30)),
            )
            .unwrap(),
        vec![3, 2]
    );
}

fn queries_composite_and_multi_entry_indexes<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "composite_multi_entry");
    let mut storage = open(directory.path()).unwrap();

    storage
        .put_indexed(
            "users",
            1,
            br#"{"email":"team@example.com","active":true,"tags":["flutter","db"]}"#,
            &[
                index(
                    "email_active",
                    IndexValue::List(vec![
                        IndexValue::String("team@example.com".into()),
                        IndexValue::Bool(true),
                    ]),
                ),
                index("tags", IndexValue::String("flutter".into())),
                index("tags", IndexValue::String("db".into())),
            ],
        )
        .unwrap();
    storage
        .put_indexed(
            "users",
            2,
            br#"{"email":"team@example.com","active":false,"tags":["rust"]}"#,
            &[
                index(
                    "email_active",
                    IndexValue::List(vec![
                        IndexValue::String("team@example.com".into()),
                        IndexValue::Bool(false),
                    ]),
                ),
                index("tags", IndexValue::String("rust".into())),
            ],
        )
        .unwrap();

    assert_eq!(
        storage
            .query_index_equal(
                "users",
                "email_active",
                &IndexValue::List(vec![
                    IndexValue::String("team@example.com".into()),
                    IndexValue::Bool(true),
                ]),
            )
            .unwrap(),
        vec![1]
    );
    assert_eq!(
        storage
            .query_index_equal("users", "tags", &IndexValue::String("rust".into()))
            .unwrap(),
        vec![2]
    );
}

fn replaces_and_deletes_index_entries_with_documents<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "index_replace_delete");
    let mut storage = open(directory.path()).unwrap();

    storage
        .put_indexed(
            "users",
            1,
            br#"{"email":"old@example.com"}"#,
            &[index("email", IndexValue::String("old@example.com".into()))],
        )
        .unwrap();
    storage
        .put_indexed(
            "users",
            1,
            br#"{"email":"new@example.com"}"#,
            &[index("email", IndexValue::String("new@example.com".into()))],
        )
        .unwrap();

    assert_eq!(
        storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("old@example.com".into()),
            )
            .unwrap(),
        Vec::<u64>::new()
    );
    assert_eq!(
        storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("new@example.com".into()),
            )
            .unwrap(),
        vec![1]
    );

    storage.delete("users", 1).unwrap();
    assert_eq!(
        storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("new@example.com".into()),
            )
            .unwrap(),
        Vec::<u64>::new()
    );
}

fn rejects_duplicate_unique_index_values<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "unique_index");
    let mut storage = open(directory.path()).unwrap();
    let mut email = field("email", "String", false, true);
    email.is_index_unique = true;
    storage
        .register_schemas(&schema_manifest(vec![user_schema(vec![email])]))
        .unwrap();

    storage
        .put_indexed(
            "users",
            1,
            &generic_document(),
            &[index("email", IndexValue::String("a@example.com".into()))],
        )
        .unwrap();
    storage
        .put_indexed(
            "users",
            1,
            &generic_document(),
            &[index("email", IndexValue::String("a@example.com".into()))],
        )
        .unwrap();
    let result = storage.put_indexed(
        "users",
        2,
        &generic_document(),
        &[index("email", IndexValue::String("a@example.com".into()))],
    );

    assert!(result.unwrap_err().contains("Unique index `email`"));
    assert_eq!(storage.get("users", 2).unwrap(), None);
    assert_eq!(storage.collection_revision("users").unwrap(), 2);
}

fn bulk_puts_documents_atomically_and_updates_indexes<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "bulk_put");
    let mut storage = open(directory.path()).unwrap();
    let documents = vec![
        document_write(
            1,
            br#"{"email":"team@example.com"}"#,
            vec![index(
                "email",
                IndexValue::String("team@example.com".into()),
            )],
        ),
        document_write(
            2,
            br#"{"email":"solo@example.com"}"#,
            vec![index(
                "email",
                IndexValue::String("solo@example.com".into()),
            )],
        ),
    ];

    storage.put_many_indexed("users", &documents).unwrap();

    assert_eq!(storage.document_ids("users").unwrap(), vec![1, 2]);
    assert_eq!(
        storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("team@example.com".into()),
            )
            .unwrap(),
        vec![1]
    );
    assert_eq!(storage.collection_revision("users").unwrap(), 1);
}

fn rolls_back_bulk_put_when_one_document_has_an_invalid_index<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "bulk_put_rollback");
    let mut storage = open(directory.path()).unwrap();
    let documents = vec![
        document_write(1, br#"{"name":"Ana"}"#, vec![]),
        document_write(
            2,
            br#"{"score":null}"#,
            vec![index("score", IndexValue::Double(f64::NAN))],
        ),
    ];

    let result = storage.put_many_indexed("users", &documents);

    assert!(result.unwrap_err().contains("finite"));
    assert_eq!(storage.get("users", 1).unwrap(), None);
    assert_eq!(storage.collection_revision("users").unwrap(), 0);
}

fn bulk_deletes_documents_atomically_and_cleans_indexes<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "bulk_delete");
    let mut storage = open(directory.path()).unwrap();
    storage
        .put_many_indexed(
            "users",
            &[
                document_write(
                    1,
                    &generic_document(),
                    vec![index(
                        "email",
                        IndexValue::String("team@example.com".into()),
                    )],
                ),
                document_write(
                    2,
                    br#"{"email":"team@example.com"}"#,
                    vec![index(
                        "email",
                        IndexValue::String("team@example.com".into()),
                    )],
                ),
            ],
        )
        .unwrap();

    storage.delete_many("users", &[1, 2]).unwrap();

    assert_eq!(storage.document_ids("users").unwrap(), Vec::<u64>::new());
    assert_eq!(
        storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("team@example.com".into()),
            )
            .unwrap(),
        Vec::<u64>::new()
    );
    assert_eq!(storage.collection_revision("users").unwrap(), 2);
}

fn exposes_storage_metadata<S>(backend: &str, open: &impl Fn(&str) -> Result<S, String>)
where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "storage_metadata");
    let storage = open(directory.path()).unwrap();
    let metadata = storage.storage_metadata().unwrap();
    let expected_layout = if backend == "sqlite" {
        StorageLayoutVersion::SqliteV1
    } else {
        StorageLayoutVersion::MdbxV6
    };
    let expected_document_format = DocumentFormatVersion::BinaryV2;

    assert_eq!(metadata.layout, expected_layout);
    assert_eq!(metadata.document_format, expected_document_format);
    assert_eq!(
        metadata.schema_metadata_format,
        SchemaMetadataVersion::BinaryV1
    );
}

fn rebuilds_indexes_with_supplied_entries<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "rebuild_indexes");
    let mut storage = open(directory.path()).unwrap();
    storage
        .put_indexed(
            "users",
            1,
            br#"{"email":"new@example.com"}"#,
            &[index("email", IndexValue::String("old@example.com".into()))],
        )
        .unwrap();

    storage
        .rebuild_indexes(
            "users",
            &[document_write(
                1,
                br#"{"email":"new@example.com"}"#,
                vec![index("email", IndexValue::String("new@example.com".into()))],
            )],
        )
        .unwrap();

    assert_eq!(
        storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("old@example.com".into()),
            )
            .unwrap(),
        Vec::<u64>::new()
    );
    assert_eq!(
        storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("new@example.com".into()),
            )
            .unwrap(),
        vec![1]
    );
}

fn verifies_storage_after_index_rebuild<S>(backend: &str, open: &impl Fn(&str) -> Result<S, String>)
where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "verify_storage");
    let mut storage = open(directory.path()).unwrap();
    let manifest = schema_manifest(vec![user_schema(vec![field(
        "email", "String", false, true,
    )])]);
    storage.register_schemas(&manifest).unwrap();
    storage
        .put_many_indexed(
            "users",
            &[
                document_write(
                    1,
                    &generic_document(),
                    vec![index(
                        "email",
                        IndexValue::String("team@example.com".into()),
                    )],
                ),
                document_write(
                    2,
                    &generic_document(),
                    vec![index(
                        "email",
                        IndexValue::String("solo@example.com".into()),
                    )],
                ),
            ],
        )
        .unwrap();

    let report = storage
        .verify_storage(
            &manifest,
            &[IndexVerificationCheck::Equal {
                collection: "users".to_string(),
                index: "email".to_string(),
                value: IndexValue::String("team@example.com".into()),
                expected_ids: vec![1],
            }],
        )
        .unwrap();

    assert_eq!(report.collections.len(), 1);
    assert_eq!(report.collections[0].collection, "users");
    assert_eq!(report.collections[0].document_count, 2);
    assert_eq!(report.collections[0].schema_version, Some(1));
    assert_eq!(report.collections[0].collection_revision, 1);
    assert!(storage
        .verify_storage(
            &manifest,
            &[IndexVerificationCheck::Equal {
                collection: "users".to_string(),
                index: "email".to_string(),
                value: IndexValue::String("missing@example.com".into()),
                expected_ids: vec![1],
            }],
        )
        .unwrap_err()
        .contains("expected [1]"));
}

fn commits_explicit_write_transactions<S>(backend: &str, open: &impl Fn(&str) -> Result<S, String>)
where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "txn_commit");
    let mut storage = open(directory.path()).unwrap();

    storage.begin_write_transaction().unwrap();
    storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
    storage
        .put_indexed(
            "users",
            2,
            br#"{"email":"ben@example.com"}"#,
            &[index("email", IndexValue::String("ben@example.com".into()))],
        )
        .unwrap();
    storage.commit_transaction().unwrap();

    assert_eq!(storage.document_ids("users").unwrap(), vec![1, 2]);
    assert_eq!(
        storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("ben@example.com".into())
            )
            .unwrap(),
        vec![2]
    );
    assert_eq!(storage.collection_revision("users").unwrap(), 2);
}

fn rolls_back_explicit_write_transactions<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "txn_rollback");
    let mut storage = open(directory.path()).unwrap();

    storage.begin_write_transaction().unwrap();
    storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
    storage
        .put_indexed(
            "users",
            2,
            br#"{"email":"ben@example.com"}"#,
            &[index("email", IndexValue::String("ben@example.com".into()))],
        )
        .unwrap();
    storage.rollback_transaction().unwrap();

    assert_eq!(storage.document_ids("users").unwrap(), Vec::<u64>::new());
    assert_eq!(
        storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("ben@example.com".into())
            )
            .unwrap(),
        Vec::<u64>::new()
    );
    assert_eq!(storage.collection_revision("users").unwrap(), 0);
    assert_eq!(storage.allocate_id("users").unwrap(), 1);
}

fn rejects_writes_inside_read_transactions<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "txn_read_write");
    let mut storage = open(directory.path()).unwrap();

    storage.begin_read_transaction().unwrap();
    let result = storage.put("users", 1, br#"{"name":"Ana"}"#);
    storage.rollback_transaction().unwrap();

    assert!(result.unwrap_err().contains("read transaction"));
    assert_eq!(storage.get("users", 1).unwrap(), None);
}

fn rejects_nested_explicit_transactions<S>(backend: &str, open: &impl Fn(&str) -> Result<S, String>)
where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "txn_nested");
    let mut storage = open(directory.path()).unwrap();

    storage.begin_write_transaction().unwrap();
    let nested = storage.begin_read_transaction();
    storage.rollback_transaction().unwrap();

    assert!(nested.unwrap_err().contains("already active"));
}

fn rolls_back_allocated_ids<S>(backend: &str, open: &impl Fn(&str) -> Result<S, String>)
where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "txn_allocate_rollback");
    let mut storage = open(directory.path()).unwrap();

    storage.begin_write_transaction().unwrap();
    assert_eq!(storage.allocate_id("users").unwrap(), 1);
    assert_eq!(storage.allocate_id("users").unwrap(), 2);
    storage.put("users", 10, br#"{"name":"Manual"}"#).unwrap();
    storage.rollback_transaction().unwrap();

    assert_eq!(storage.allocate_id("users").unwrap(), 1);
}

fn rolls_back_failed_write_transaction_commits<S>(
    backend: &str,
    open: &impl Fn(&str) -> Result<S, String>,
) where
    S: StorageEngine,
{
    let directory = TemporaryDirectory::new(backend, "txn_failed_commit");
    let mut storage = open(directory.path()).unwrap();
    let mut email = field("email", "String", false, true);
    email.is_index_unique = true;
    storage
        .register_schemas(&schema_manifest(vec![user_schema(vec![email])]))
        .unwrap();

    storage.begin_write_transaction().unwrap();
    storage
        .put_indexed(
            "users",
            1,
            &generic_document(),
            &[index("email", IndexValue::String("a@example.com".into()))],
        )
        .unwrap();
    let duplicate = storage.put_indexed(
        "users",
        2,
        &generic_document(),
        &[index("email", IndexValue::String("a@example.com".into()))],
    );
    let result = if duplicate.is_ok() {
        storage.commit_transaction()
    } else {
        duplicate
    };
    storage.rollback_transaction().unwrap();

    assert!(result.unwrap_err().contains("Unique index `email`"));
    assert_eq!(storage.document_ids("users").unwrap(), Vec::<u64>::new());
    assert_eq!(storage.collection_revision("users").unwrap(), 0);
    assert_eq!(storage.allocate_id("users").unwrap(), 1);
}

fn index(name: &str, value: IndexValue) -> IndexEntry {
    IndexEntry {
        name: name.to_string(),
        value,
    }
}

fn document_write(id: u64, bytes: &[u8], indexes: Vec<IndexEntry>) -> DocumentWrite {
    DocumentWrite {
        id,
        bytes: bytes.to_vec(),
        indexes,
    }
}

fn generic_document() -> Vec<u8> {
    vec![
        0x43, 0x47, 0x44, 0x31, // CGD1
        1, 0, 0, 0, // version
        6, 0, 0, 0, 0, // empty object
    ]
}

fn schema_manifest(collections: Vec<CollectionSchemaManifest>) -> SchemaManifest {
    SchemaManifest { collections }
}

fn user_schema(mut fields: Vec<FieldSchemaManifest>) -> CollectionSchemaManifest {
    fields.push(field("id", "int", true, false));
    fields.sort_by(|left, right| left.name.cmp(&right.name));
    CollectionSchemaManifest {
        name: "users".to_string(),
        id_field: "id".to_string(),
        fields,
        composite_indexes: Vec::new(),
    }
}

fn field(name: &str, dart_type: &str, is_id: bool, is_indexed: bool) -> FieldSchemaManifest {
    FieldSchemaManifest {
        name: name.to_string(),
        dart_type: dart_type.to_string(),
        binary_type: dart_type.to_string(),
        is_id,
        is_indexed,
        is_index_unique: false,
        is_index_replace: false,
        index_case_sensitive: true,
        index_type: "value".to_string(),
    }
}

struct TemporaryDirectory {
    path: PathBuf,
}

impl TemporaryDirectory {
    fn new(backend: &str, name: &str) -> Self {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "cindel_contract_{backend}_{name}_{}_{}",
            std::process::id(),
            nonce
        ));
        Self { path }
    }

    fn path(&self) -> &str {
        self.path.to_str().expect("temporary path must be UTF-8")
    }
}

impl Drop for TemporaryDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}
