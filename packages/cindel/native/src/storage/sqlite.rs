use std::fs;
use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension, Transaction};

use super::{
    CollectionSchemaManifest, FieldSchemaManifest, IndexEntry, IndexValue, SchemaManifest,
    StorageEngine,
};

pub struct SqliteStorage {
    connection: Connection,
}

impl SqliteStorage {
    pub fn open(directory: &str) -> Result<Self, String> {
        fs::create_dir_all(directory).map_err(|error| error.to_string())?;

        let database_path = Path::new(directory).join("cindel.sqlite");
        let connection = Connection::open(database_path).map_err(|error| error.to_string())?;
        let storage = Self { connection };
        storage.initialize()?;

        Ok(storage)
    }

    fn initialize(&self) -> Result<(), String> {
        self.connection
            .execute_batch(
                r#"
                PRAGMA journal_mode = WAL;
                CREATE TABLE IF NOT EXISTS documents (
                    collection TEXT NOT NULL,
                    id INTEGER NOT NULL,
                    bytes BLOB NOT NULL,
                    PRIMARY KEY (collection, id)
                );

                CREATE TABLE IF NOT EXISTS index_entries (
                    collection TEXT NOT NULL,
                    index_name TEXT NOT NULL,
                    value_kind INTEGER NOT NULL,
                    int_value INTEGER,
                    real_value REAL,
                    text_value TEXT,
                    document_id INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS collection_revisions (
                    collection TEXT PRIMARY KEY NOT NULL,
                    revision INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS schema_collections (
                    collection TEXT PRIMARY KEY NOT NULL,
                    version INTEGER NOT NULL,
                    schema_json TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS schema_migrations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    collection TEXT NOT NULL,
                    from_version INTEGER NOT NULL,
                    to_version INTEGER NOT NULL,
                    from_schema_json TEXT NOT NULL,
                    to_schema_json TEXT NOT NULL,
                    applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );

                CREATE INDEX IF NOT EXISTS cindel_index_entries_lookup
                ON index_entries (
                    collection,
                    index_name,
                    value_kind,
                    int_value,
                    real_value,
                    text_value,
                    document_id
                );
                "#,
            )
            .map_err(|error| error.to_string())
    }
}

impl StorageEngine for SqliteStorage {
    fn get(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String> {
        let id = sqlite_id(id)?;

        self.connection
            .query_row(
                "SELECT bytes FROM documents WHERE collection = ?1 AND id = ?2",
                params![collection, id],
                |row| row.get(0),
            )
            .optional()
            .map_err(|error| error.to_string())
    }

    fn document_ids(&self, collection: &str) -> Result<Vec<u64>, String> {
        query_ids(
            &self.connection,
            r#"
            SELECT id
            FROM documents
            WHERE collection = ?1
            ORDER BY id
            "#,
            params![collection],
        )
    }

    fn put(&mut self, collection: &str, id: u64, bytes: &[u8]) -> Result<(), String> {
        self.put_indexed(collection, id, bytes, &[])
    }

    fn put_indexed(
        &mut self,
        collection: &str,
        id: u64,
        bytes: &[u8],
        indexes: &[IndexEntry],
    ) -> Result<(), String> {
        let id = sqlite_id(id)?;
        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;

        put_document(&transaction, collection, id, bytes)?;
        delete_index_entries(&transaction, collection, id)?;
        insert_index_entries(&transaction, collection, id, indexes)?;
        bump_collection_revision(&transaction, collection)?;

        transaction.commit().map_err(|error| error.to_string())
    }

    fn delete(&mut self, collection: &str, id: u64) -> Result<(), String> {
        let id = sqlite_id(id)?;
        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;

        let deleted = transaction
            .execute(
                "DELETE FROM documents WHERE collection = ?1 AND id = ?2",
                params![collection, id],
            )
            .map_err(|error| error.to_string())?;
        delete_index_entries(&transaction, collection, id)?;
        if deleted > 0 {
            bump_collection_revision(&transaction, collection)?;
        }

        transaction.commit().map_err(|error| error.to_string())
    }

    fn query_index_equal(
        &self,
        collection: &str,
        index: &str,
        value: &IndexValue,
    ) -> Result<Vec<u64>, String> {
        query_index(
            &self.connection,
            collection,
            index,
            Some(value),
            Some(value),
        )
    }

    fn query_index_range(
        &self,
        collection: &str,
        index: &str,
        lower: Option<&IndexValue>,
        upper: Option<&IndexValue>,
    ) -> Result<Vec<u64>, String> {
        query_index(&self.connection, collection, index, lower, upper)
    }

    fn collection_revision(&self, collection: &str) -> Result<u64, String> {
        self.connection
            .query_row(
                "SELECT revision FROM collection_revisions WHERE collection = ?1",
                params![collection],
                |row| row.get::<_, i64>(0),
            )
            .optional()
            .map_err(|error| error.to_string())?
            .map(u64::try_from)
            .transpose()
            .map_err(|error| error.to_string())
            .map(Option::unwrap_or_default)
    }

    fn register_schemas(&mut self, manifest: &SchemaManifest) -> Result<(), String> {
        validate_schema_manifest(manifest)?;
        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;

        for collection in &manifest.collections {
            register_collection_schema(&transaction, collection)?;
        }

        transaction.commit().map_err(|error| error.to_string())
    }

    fn schema_version(&self, collection: &str) -> Result<Option<u64>, String> {
        self.connection
            .query_row(
                "SELECT version FROM schema_collections WHERE collection = ?1",
                params![collection],
                |row| row.get::<_, i64>(0),
            )
            .optional()
            .map_err(|error| error.to_string())?
            .map(u64::try_from)
            .transpose()
            .map_err(|error| error.to_string())
    }
}

fn sqlite_id(id: u64) -> Result<i64, String> {
    i64::try_from(id).map_err(|_| format!("id {id} exceeds SQLite INTEGER range"))
}

fn put_document(
    transaction: &Transaction<'_>,
    collection: &str,
    id: i64,
    bytes: &[u8],
) -> Result<(), String> {
    transaction
        .execute(
            r#"
            INSERT INTO documents (collection, id, bytes)
            VALUES (?1, ?2, ?3)
            ON CONFLICT(collection, id) DO UPDATE SET bytes = excluded.bytes
            "#,
            params![collection, id, bytes],
        )
        .map(|_| ())
        .map_err(|error| error.to_string())
}

fn delete_index_entries(
    transaction: &Transaction<'_>,
    collection: &str,
    id: i64,
) -> Result<(), String> {
    transaction
        .execute(
            "DELETE FROM index_entries WHERE collection = ?1 AND document_id = ?2",
            params![collection, id],
        )
        .map(|_| ())
        .map_err(|error| error.to_string())
}

fn insert_index_entries(
    transaction: &Transaction<'_>,
    collection: &str,
    id: i64,
    indexes: &[IndexEntry],
) -> Result<(), String> {
    for index in indexes {
        let key = SqliteIndexKey::from(&index.value)?;
        transaction
            .execute(
                r#"
                INSERT INTO index_entries (
                    collection,
                    index_name,
                    value_kind,
                    int_value,
                    real_value,
                    text_value,
                    document_id
                )
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                "#,
                params![
                    collection,
                    index.name,
                    key.kind,
                    key.int_value,
                    key.real_value,
                    key.text_value,
                    id,
                ],
            )
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn bump_collection_revision(transaction: &Transaction<'_>, collection: &str) -> Result<(), String> {
    transaction
        .execute(
            r#"
            INSERT INTO collection_revisions (collection, revision)
            VALUES (?1, 1)
            ON CONFLICT(collection) DO UPDATE SET
                revision = collection_revisions.revision + 1
            "#,
            params![collection],
        )
        .map(|_| ())
        .map_err(|error| error.to_string())
}

fn validate_schema_manifest(manifest: &SchemaManifest) -> Result<(), String> {
    let mut names = std::collections::HashSet::new();
    for collection in &manifest.collections {
        if collection.name.trim().is_empty() {
            return Err("schema collection name must not be empty".into());
        }
        if !names.insert(collection.name.as_str()) {
            return Err(format!(
                "schema collection `{}` is duplicated",
                collection.name
            ));
        }
        validate_collection_schema(collection)?;
    }
    Ok(())
}

fn validate_collection_schema(collection: &CollectionSchemaManifest) -> Result<(), String> {
    if collection.id_field.trim().is_empty() {
        return Err(format!(
            "schema collection `{}` must declare an id field",
            collection.name
        ));
    }

    let mut names = std::collections::HashSet::new();
    let mut id_fields = 0;
    for field in &collection.fields {
        if field.name.trim().is_empty() {
            return Err(format!(
                "schema collection `{}` contains an empty field name",
                collection.name
            ));
        }
        if field.dart_type.trim().is_empty() {
            return Err(format!(
                "schema field `{}.{}` must declare a Dart type",
                collection.name, field.name
            ));
        }
        if !names.insert(field.name.as_str()) {
            return Err(format!(
                "schema field `{}.{}` is duplicated",
                collection.name, field.name
            ));
        }
        if field.is_id {
            id_fields += 1;
            if field.name != collection.id_field {
                return Err(format!(
                    "schema field `{}.{}` is marked as id but id_field is `{}`",
                    collection.name, field.name, collection.id_field
                ));
            }
        }
    }

    if id_fields != 1 {
        return Err(format!(
            "schema collection `{}` must declare exactly one id field",
            collection.name
        ));
    }

    Ok(())
}

fn register_collection_schema(
    transaction: &Transaction<'_>,
    collection: &CollectionSchemaManifest,
) -> Result<(), String> {
    let next_schema_json = canonical_schema_json(collection)?;
    let existing = transaction
        .query_row(
            "SELECT version, schema_json FROM schema_collections WHERE collection = ?1",
            params![collection.name],
            |row| Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?)),
        )
        .optional()
        .map_err(|error| error.to_string())?;

    let Some((version, schema_json)) = existing else {
        transaction
            .execute(
                r#"
                INSERT INTO schema_collections (collection, version, schema_json)
                VALUES (?1, 1, ?2)
                "#,
                params![collection.name, next_schema_json],
            )
            .map(|_| ())
            .map_err(|error| error.to_string())?;
        return Ok(());
    };

    if schema_json == next_schema_json {
        return Ok(());
    }

    let existing_schema = serde_json::from_str::<CollectionSchemaManifest>(&schema_json)
        .map_err(|error| error.to_string())?;
    validate_compatible_schema_change(&existing_schema, collection)?;

    let next_version = version + 1;
    transaction
        .execute(
            r#"
            UPDATE schema_collections
            SET version = ?2, schema_json = ?3
            WHERE collection = ?1
            "#,
            params![collection.name, next_version, next_schema_json],
        )
        .map_err(|error| error.to_string())?;
    transaction
        .execute(
            r#"
            INSERT INTO schema_migrations (
                collection,
                from_version,
                to_version,
                from_schema_json,
                to_schema_json
            )
            VALUES (?1, ?2, ?3, ?4, ?5)
            "#,
            params![
                collection.name,
                version,
                next_version,
                schema_json,
                next_schema_json,
            ],
        )
        .map(|_| ())
        .map_err(|error| error.to_string())
}

fn canonical_schema_json(collection: &CollectionSchemaManifest) -> Result<String, String> {
    serde_json::to_string(collection).map_err(|error| error.to_string())
}

fn validate_compatible_schema_change(
    existing: &CollectionSchemaManifest,
    next: &CollectionSchemaManifest,
) -> Result<(), String> {
    if existing.name != next.name {
        return Err("schema collection names cannot change".into());
    }
    if existing.id_field != next.id_field {
        return Err(format!(
            "schema collection `{}` cannot change id field",
            existing.name
        ));
    }

    let next_fields = next
        .fields
        .iter()
        .map(|field| (field.name.as_str(), field))
        .collect::<std::collections::HashMap<_, _>>();

    for existing_field in &existing.fields {
        let Some(next_field) = next_fields.get(existing_field.name.as_str()) else {
            return Err(format!(
                "schema field `{}.{}` cannot be removed",
                existing.name, existing_field.name
            ));
        };
        validate_compatible_field(existing, existing_field, next_field)?;
    }

    Ok(())
}

fn validate_compatible_field(
    collection: &CollectionSchemaManifest,
    existing: &FieldSchemaManifest,
    next: &FieldSchemaManifest,
) -> Result<(), String> {
    if existing.dart_type != next.dart_type {
        return Err(format!(
            "schema field `{}.{}` cannot change type from `{}` to `{}`",
            collection.name, existing.name, existing.dart_type, next.dart_type
        ));
    }
    if existing.is_id != next.is_id {
        return Err(format!(
            "schema field `{}.{}` cannot change id status",
            collection.name, existing.name
        ));
    }
    if existing.is_indexed != next.is_indexed {
        return Err(format!(
            "schema field `{}.{}` cannot change index status without an explicit migration",
            collection.name, existing.name
        ));
    }
    Ok(())
}

fn query_index(
    connection: &Connection,
    collection: &str,
    index: &str,
    lower: Option<&IndexValue>,
    upper: Option<&IndexValue>,
) -> Result<Vec<u64>, String> {
    let lower = lower.map(SqliteIndexKey::from).transpose()?;
    let upper = upper.map(SqliteIndexKey::from).transpose()?;
    let kind = match (&lower, &upper) {
        (Some(lower), Some(upper)) if lower.kind == upper.kind => lower.kind,
        (Some(lower), None) => lower.kind,
        (None, Some(upper)) => upper.kind,
        (Some(_), Some(_)) => return Err("index range bounds must have matching types".into()),
        (None, None) => return Err("index range requires at least one bound".into()),
    };

    match kind {
        INDEX_KIND_BOOL | INDEX_KIND_INT => query_numeric_index(
            connection,
            collection,
            index,
            kind,
            lower.as_ref().and_then(|key| key.int_value),
            upper.as_ref().and_then(|key| key.int_value),
            "int_value",
        ),
        INDEX_KIND_DOUBLE => query_real_index(
            connection,
            collection,
            index,
            lower.as_ref().and_then(|key| key.real_value),
            upper.as_ref().and_then(|key| key.real_value),
        ),
        INDEX_KIND_STRING => query_text_index(
            connection,
            collection,
            index,
            lower.as_ref().and_then(|key| key.text_value.as_deref()),
            upper.as_ref().and_then(|key| key.text_value.as_deref()),
        ),
        _ => Err("unsupported index value kind".into()),
    }
}

fn query_numeric_index(
    connection: &Connection,
    collection: &str,
    index: &str,
    kind: i64,
    lower: Option<i64>,
    upper: Option<i64>,
    column: &str,
) -> Result<Vec<u64>, String> {
    let sql = format!(
        r#"
        SELECT document_id
        FROM index_entries
        WHERE collection = ?1
          AND index_name = ?2
          AND value_kind = ?3
          AND (?4 IS NULL OR {column} >= ?4)
          AND (?5 IS NULL OR {column} <= ?5)
        ORDER BY {column}, document_id
        "#
    );
    query_ids(
        connection,
        &sql,
        params![collection, index, kind, lower, upper],
    )
}

fn query_real_index(
    connection: &Connection,
    collection: &str,
    index: &str,
    lower: Option<f64>,
    upper: Option<f64>,
) -> Result<Vec<u64>, String> {
    query_ids(
        connection,
        r#"
        SELECT document_id
        FROM index_entries
        WHERE collection = ?1
          AND index_name = ?2
          AND value_kind = ?3
          AND (?4 IS NULL OR real_value >= ?4)
          AND (?5 IS NULL OR real_value <= ?5)
        ORDER BY real_value, document_id
        "#,
        params![collection, index, INDEX_KIND_DOUBLE, lower, upper],
    )
}

fn query_text_index(
    connection: &Connection,
    collection: &str,
    index: &str,
    lower: Option<&str>,
    upper: Option<&str>,
) -> Result<Vec<u64>, String> {
    query_ids(
        connection,
        r#"
        SELECT document_id
        FROM index_entries
        WHERE collection = ?1
          AND index_name = ?2
          AND value_kind = ?3
          AND (?4 IS NULL OR text_value >= ?4)
          AND (?5 IS NULL OR text_value <= ?5)
        ORDER BY text_value, document_id
        "#,
        params![collection, index, INDEX_KIND_STRING, lower, upper],
    )
}

fn query_ids<P>(connection: &Connection, sql: &str, params: P) -> Result<Vec<u64>, String>
where
    P: rusqlite::Params,
{
    let mut statement = connection.prepare(sql).map_err(|error| error.to_string())?;
    let rows = statement
        .query_map(params, |row| row.get::<_, i64>(0))
        .map_err(|error| error.to_string())?;
    let mut ids = Vec::new();
    for row in rows {
        let id = row.map_err(|error| error.to_string())?;
        ids.push(u64::try_from(id).map_err(|error| error.to_string())?);
    }
    Ok(ids)
}

const INDEX_KIND_BOOL: i64 = 1;
const INDEX_KIND_INT: i64 = 2;
const INDEX_KIND_DOUBLE: i64 = 3;
const INDEX_KIND_STRING: i64 = 4;

struct SqliteIndexKey {
    kind: i64,
    int_value: Option<i64>,
    real_value: Option<f64>,
    text_value: Option<String>,
}

impl SqliteIndexKey {
    fn from(value: &IndexValue) -> Result<Self, String> {
        match value {
            IndexValue::Bool(value) => Ok(Self {
                kind: INDEX_KIND_BOOL,
                int_value: Some(if *value { 1 } else { 0 }),
                real_value: None,
                text_value: None,
            }),
            IndexValue::Int(value) => Ok(Self {
                kind: INDEX_KIND_INT,
                int_value: Some(*value),
                real_value: None,
                text_value: None,
            }),
            IndexValue::Double(value) if value.is_finite() => Ok(Self {
                kind: INDEX_KIND_DOUBLE,
                int_value: None,
                real_value: Some(*value),
                text_value: None,
            }),
            IndexValue::Double(_) => Err("index double values must be finite".into()),
            IndexValue::String(value) => Ok(Self {
                kind: INDEX_KIND_STRING,
                int_value: None,
                real_value: None,
                text_value: Some(value.clone()),
            }),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::*;

    #[test]
    fn stores_reads_and_deletes_bytes_by_collection_and_id() {
        // Scenario: Bytes are written, read, and deleted in one collection.
        // Covers:
        // - Insert and read paths for a document primary key.
        // - Delete path for an existing document.
        // Expected: Stored bytes round-trip once and are missing after delete.

        // Arrange.
        let directory = TemporaryDirectory::new("crud");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.put("users", 1, br#"{"name":"Noel"}"#).unwrap();
        let stored = storage.get("users", 1).unwrap();

        // Assert.
        assert_eq!(stored, Some(br#"{"name":"Noel"}"#.to_vec()));

        // Act.
        storage.delete("users", 1).unwrap();
        let deleted = storage.get("users", 1).unwrap();

        // Assert.
        assert_eq!(deleted, None);
    }

    #[test]
    fn persists_bytes_after_reopening_the_database_directory() {
        // Scenario: A database directory is closed and reopened.
        // Covers:
        // - SQLite persistence across separate connections.
        // - Opening an existing Cindel database file.
        // Expected: Bytes remain readable after reopening the directory.

        // Arrange.
        let directory = TemporaryDirectory::new("persist");

        // Act.
        {
            let mut storage = SqliteStorage::open(directory.path()).unwrap();
            storage.put("settings", 7, br#"{"theme":"dark"}"#).unwrap();
        }

        let reopened = SqliteStorage::open(directory.path()).unwrap();
        let stored = reopened.get("settings", 7).unwrap();

        // Assert.
        assert_eq!(stored, Some(br#"{"theme":"dark"}"#.to_vec()));
    }

    #[test]
    fn keeps_documents_with_the_same_id_separate_by_collection() {
        // Scenario: Two collections store different bytes under the same id.
        // Covers:
        // - Composite primary key behavior for collection and id.
        // - Reads scoped by collection name.
        // Expected: Each collection returns its own bytes for the shared id.

        // Arrange.
        let directory = TemporaryDirectory::new("collections");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.put("users", 1, br#"{"name":"Noel"}"#).unwrap();
        storage.put("settings", 1, br#"{"theme":"dark"}"#).unwrap();
        let user = storage.get("users", 1).unwrap();
        let settings = storage.get("settings", 1).unwrap();

        // Assert.
        assert_eq!(user, Some(br#"{"name":"Noel"}"#.to_vec()));
        assert_eq!(settings, Some(br#"{"theme":"dark"}"#.to_vec()));
    }

    #[test]
    fn lists_document_ids_by_collection() {
        // Scenario: A collection contains multiple documents out of insert order.
        // Covers:
        // - [StorageEngine::document_ids] scanning ids by collection.
        // - Stable id ordering for Dart collection snapshots.
        // Expected: Only ids from the requested collection are returned sorted.

        // Arrange.
        let directory = TemporaryDirectory::new("document_ids");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.put("users", 3, br#"{"name":"Cid"}"#).unwrap();
        storage.put("settings", 1, br#"{"theme":"dark"}"#).unwrap();
        storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
        let ids = storage.document_ids("users").unwrap();

        // Assert.
        assert_eq!(ids, vec![1, 3]);
    }

    #[test]
    fn advances_collection_revision_after_committed_changes() {
        // Scenario: Documents are inserted, updated, deleted, and deleted again.
        // Covers:
        // - Revision increments after committed writes.
        // - No-op deletes leaving the revision unchanged.
        // Expected: Watchers can detect real collection changes monotonically.

        // Arrange.
        let directory = TemporaryDirectory::new("revision");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        let initial = storage.collection_revision("users").unwrap();
        storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
        let after_insert = storage.collection_revision("users").unwrap();
        storage.put("users", 1, br#"{"name":"Ada"}"#).unwrap();
        let after_update = storage.collection_revision("users").unwrap();
        storage.delete("users", 1).unwrap();
        let after_delete = storage.collection_revision("users").unwrap();
        storage.delete("users", 1).unwrap();
        let after_missing_delete = storage.collection_revision("users").unwrap();

        // Assert.
        assert_eq!(initial, 0);
        assert_eq!(after_insert, 1);
        assert_eq!(after_update, 2);
        assert_eq!(after_delete, 3);
        assert_eq!(after_missing_delete, 3);
    }

    #[test]
    fn registers_initial_schema_version() {
        // Scenario: A generated schema is registered for a new collection.
        // Covers:
        // - [StorageEngine::register_schemas] storing schema metadata.
        // - [StorageEngine::schema_version] reading persisted versions.
        // Expected: The collection starts at schema version 1.

        // Arrange.
        let directory = TemporaryDirectory::new("schema_initial");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let manifest = schema_manifest(vec![user_schema(vec![field(
            "email", "String", false, true,
        )])]);

        // Act.
        storage.register_schemas(&manifest).unwrap();
        let version = storage.schema_version("users").unwrap();

        // Assert.
        assert_eq!(version, Some(1));
    }

    #[test]
    fn advances_schema_version_for_additive_changes() {
        // Scenario: A schema adds a new persisted field.
        // Covers:
        // - Additive schema compatibility validation.
        // - Schema version increments after a compatible migration.
        // Expected: Re-registering the expanded schema advances to version 2.

        // Arrange.
        let directory = TemporaryDirectory::new("schema_additive");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let original = schema_manifest(vec![user_schema(vec![field(
            "email", "String", false, true,
        )])]);
        let expanded = schema_manifest(vec![user_schema(vec![
            field("email", "String", false, true),
            field("active", "bool?", false, false),
        ])]);

        // Act.
        storage.register_schemas(&original).unwrap();
        storage.register_schemas(&expanded).unwrap();
        let version = storage.schema_version("users").unwrap();

        // Assert.
        assert_eq!(version, Some(2));
    }

    #[test]
    fn rejects_incompatible_schema_changes() {
        // Scenario: A registered field changes its Dart type.
        // Covers:
        // - Incompatible schema validation before metadata is updated.
        // - Existing schema version preservation after rejection.
        // Expected: The schema update fails and remains at the previous version.

        // Arrange.
        let directory = TemporaryDirectory::new("schema_incompatible");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let original = schema_manifest(vec![user_schema(vec![field(
            "email", "String", false, true,
        )])]);
        let incompatible =
            schema_manifest(vec![user_schema(vec![field("email", "int", false, true)])]);

        // Act.
        storage.register_schemas(&original).unwrap();
        let result = storage.register_schemas(&incompatible);
        let version = storage.schema_version("users").unwrap();

        // Assert.
        assert!(result.unwrap_err().contains("cannot change type"));
        assert_eq!(version, Some(1));
    }

    #[test]
    fn rejects_ids_outside_sqlite_integer_range() {
        // Scenario: A document id exceeds SQLite's signed INTEGER range.
        // Covers:
        // - Conversion from Cindel's u64 storage trait id to SQLite i64.
        // - Error path before passing values to rusqlite.
        // Expected: Storage rejects the id instead of truncating or wrapping it.

        // Arrange.
        let directory = TemporaryDirectory::new("id_range");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let id = i64::MAX as u64 + 1;

        // Act.
        let result = storage.put("users", id, br#"{"name":"Noel"}"#);

        // Assert.
        assert!(result.unwrap_err().contains("exceeds SQLite INTEGER range"));
    }

    #[test]
    fn queries_documents_by_index_equality() {
        // Scenario: Documents are indexed by a string field.
        // Covers:
        // - [StorageEngine::put_indexed] inserting index entries.
        // - [StorageEngine::query_index_equal] finding ids by indexed value.
        // Expected: Equality queries return matching document ids in id order.

        // Arrange.
        let directory = TemporaryDirectory::new("index_equal");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage
            .put_indexed(
                "users",
                1,
                br#"{"email":"a@example.com"}"#,
                &[index("email", IndexValue::String("a@example.com".into()))],
            )
            .unwrap();
        storage
            .put_indexed(
                "users",
                2,
                br#"{"email":"b@example.com"}"#,
                &[index("email", IndexValue::String("b@example.com".into()))],
            )
            .unwrap();
        storage
            .put_indexed(
                "users",
                3,
                br#"{"email":"a@example.com"}"#,
                &[index("email", IndexValue::String("a@example.com".into()))],
            )
            .unwrap();
        let ids = storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("a@example.com".into()),
            )
            .unwrap();

        // Assert.
        assert_eq!(ids, vec![1, 3]);
    }

    #[test]
    fn queries_documents_by_index_range() {
        // Scenario: Numeric scores are queried by an inclusive range.
        // Covers:
        // - Ordered range scan over integer index entries.
        // - Lower and upper bound filtering.
        // Expected: Range queries return matching ids ordered by score.

        // Arrange.
        let directory = TemporaryDirectory::new("index_range");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage
            .put_indexed(
                "users",
                1,
                br#"{"score":10}"#,
                &[index("score", IndexValue::Int(10))],
            )
            .unwrap();
        storage
            .put_indexed(
                "users",
                2,
                br#"{"score":30}"#,
                &[index("score", IndexValue::Int(30))],
            )
            .unwrap();
        storage
            .put_indexed(
                "users",
                3,
                br#"{"score":20}"#,
                &[index("score", IndexValue::Int(20))],
            )
            .unwrap();
        let ids = storage
            .query_index_range(
                "users",
                "score",
                Some(&IndexValue::Int(15)),
                Some(&IndexValue::Int(30)),
            )
            .unwrap();

        // Assert.
        assert_eq!(ids, vec![3, 2]);
    }

    #[test]
    fn replaces_and_deletes_index_entries_with_documents() {
        // Scenario: A document changes and is later deleted.
        // Covers:
        // - Replacing old index entries when a document is overwritten.
        // - Removing index entries when a document is deleted.
        // Expected: Queries never return stale index entries.

        // Arrange.
        let directory = TemporaryDirectory::new("index_replace_delete");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
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
        let old_ids = storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("old@example.com".into()),
            )
            .unwrap();
        let new_ids = storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("new@example.com".into()),
            )
            .unwrap();

        // Assert.
        assert_eq!(old_ids, Vec::<u64>::new());
        assert_eq!(new_ids, vec![1]);

        // Act.
        storage.delete("users", 1).unwrap();
        let deleted_ids = storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("new@example.com".into()),
            )
            .unwrap();

        // Assert.
        assert_eq!(deleted_ids, Vec::<u64>::new());
    }

    fn index(name: &str, value: IndexValue) -> IndexEntry {
        IndexEntry {
            name: name.to_string(),
            value,
        }
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
        }
    }

    fn field(name: &str, dart_type: &str, is_id: bool, is_indexed: bool) -> FieldSchemaManifest {
        FieldSchemaManifest {
            name: name.to_string(),
            dart_type: dart_type.to_string(),
            is_id,
            is_indexed,
        }
    }

    struct TemporaryDirectory {
        path: PathBuf,
    }

    impl TemporaryDirectory {
        fn new(name: &str) -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let path = std::env::temp_dir().join(format!("cindel_{name}_{nonce}"));
            Self { path }
        }

        fn path(&self) -> &str {
            self.path.to_str().unwrap()
        }
    }

    impl Drop for TemporaryDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }
}
