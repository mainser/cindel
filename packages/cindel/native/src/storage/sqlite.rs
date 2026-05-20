use std::fs;
use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension, Transaction};

use super::{IndexEntry, IndexValue, StorageEngine};

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

        transaction.commit().map_err(|error| error.to_string())
    }

    fn delete(&mut self, collection: &str, id: u64) -> Result<(), String> {
        let id = sqlite_id(id)?;
        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;

        transaction
            .execute(
                "DELETE FROM documents WHERE collection = ?1 AND id = ?2",
                params![collection, id],
            )
            .map_err(|error| error.to_string())?;
        delete_index_entries(&transaction, collection, id)?;

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
