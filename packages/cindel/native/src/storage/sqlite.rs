use std::fs;
use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension};

use super::{
    CollectionSchemaManifest, DocumentWrite, FieldSchemaManifest, IndexEntry, IndexValue,
    SchemaManifest, StorageEngine,
};
use super::{DocumentFormatVersion, StorageLayoutVersion, StorageMetadata};

pub struct SqliteStorage {
    connection: Connection,
    active_transaction: Option<TransactionMode>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum TransactionMode {
    Read,
    Write,
}

impl SqliteStorage {
    pub fn open(directory: &str) -> Result<Self, String> {
        let connection = if directory == IN_MEMORY_DIRECTORY {
            Connection::open_in_memory().map_err(|error| error.to_string())?
        } else {
            fs::create_dir_all(directory).map_err(|error| error.to_string())?;
            let database_path = Path::new(directory).join("cindel.sqlite");
            Connection::open(database_path).map_err(|error| error.to_string())?
        };
        let storage = Self {
            connection,
            active_transaction: None,
        };
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

                CREATE TABLE IF NOT EXISTS id_counters (
                    collection TEXT PRIMARY KEY NOT NULL,
                    next_id INTEGER NOT NULL
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

                CREATE TABLE IF NOT EXISTS storage_metadata (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
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
            .map_err(|error| error.to_string())?;
        ensure_storage_metadata(
            &self.connection,
            StorageLayoutVersion::SqliteV1,
            DocumentFormatVersion::JsonV1,
        )
    }
}

const IN_MEMORY_DIRECTORY: &str = ":memory:";

impl StorageEngine for SqliteStorage {
    fn begin_read_transaction(&mut self) -> Result<(), String> {
        self.begin_transaction(TransactionMode::Read, "BEGIN DEFERRED TRANSACTION")
    }

    fn begin_write_transaction(&mut self) -> Result<(), String> {
        self.begin_transaction(TransactionMode::Write, "BEGIN IMMEDIATE TRANSACTION")
    }

    fn commit_transaction(&mut self) -> Result<(), String> {
        if self.active_transaction.is_none() {
            return Err("no active transaction to commit".into());
        }
        self.connection
            .execute_batch("COMMIT")
            .map_err(|error| error.to_string())?;
        self.active_transaction = None;
        Ok(())
    }

    fn rollback_transaction(&mut self) -> Result<(), String> {
        if self.active_transaction.is_none() {
            return Err("no active transaction to rollback".into());
        }
        self.connection
            .execute_batch("ROLLBACK")
            .map_err(|error| error.to_string())?;
        self.active_transaction = None;
        Ok(())
    }

    fn allocate_id(&mut self, collection: &str) -> Result<u64, String> {
        self.ensure_can_write()?;
        if self.active_transaction.is_some() {
            let id = allocate_id(&self.connection, collection)?;
            return u64::try_from(id).map_err(|error| error.to_string());
        }

        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;

        let id = allocate_id(&transaction, collection)?;

        transaction.commit().map_err(|error| error.to_string())?;
        u64::try_from(id).map_err(|error| error.to_string())
    }

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

    fn get_many(&self, collection: &str, ids: &[u64]) -> Result<Vec<Option<Vec<u8>>>, String> {
        let mut statement = self
            .connection
            .prepare("SELECT bytes FROM documents WHERE collection = ?1 AND id = ?2")
            .map_err(|error| error.to_string())?;
        let mut documents = Vec::with_capacity(ids.len());
        for id in ids {
            let id = sqlite_id(*id)?;
            let document = statement
                .query_row(params![collection, id], |row| row.get(0))
                .optional()
                .map_err(|error| error.to_string())?;
            documents.push(document);
        }
        Ok(documents)
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
        self.ensure_can_write()?;
        if self.active_transaction.is_some() {
            put_document_with_indexes(&self.connection, collection, id, bytes, indexes)?;
            bump_collection_revision(&self.connection, collection)?;
            return Ok(());
        }

        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;

        put_document_with_indexes(&transaction, collection, id, bytes, indexes)?;
        bump_collection_revision(&transaction, collection)?;

        transaction.commit().map_err(|error| error.to_string())
    }

    fn put_many_indexed(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String> {
        if documents.is_empty() {
            return Ok(());
        }
        self.ensure_can_write()?;
        if self.active_transaction.is_some() {
            for document in documents {
                put_document_with_indexes(
                    &self.connection,
                    collection,
                    document.id,
                    &document.bytes,
                    &document.indexes,
                )?;
            }
            bump_collection_revision(&self.connection, collection)?;
            return Ok(());
        }

        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;

        for document in documents {
            put_document_with_indexes(
                &transaction,
                collection,
                document.id,
                &document.bytes,
                &document.indexes,
            )?;
        }
        bump_collection_revision(&transaction, collection)?;

        transaction.commit().map_err(|error| error.to_string())
    }

    fn delete(&mut self, collection: &str, id: u64) -> Result<(), String> {
        self.ensure_can_write()?;
        let id = sqlite_id(id)?;
        if self.active_transaction.is_some() {
            let deleted = delete_document(&self.connection, collection, id)?;
            if deleted {
                bump_collection_revision(&self.connection, collection)?;
            }
            return Ok(());
        }

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

    fn delete_many(&mut self, collection: &str, ids: &[u64]) -> Result<(), String> {
        if ids.is_empty() {
            return Ok(());
        }
        self.ensure_can_write()?;
        if self.active_transaction.is_some() {
            let mut deleted_any = false;
            for id in ids {
                let id = sqlite_id(*id)?;
                let deleted = delete_document(&self.connection, collection, id)?;
                deleted_any |= deleted;
            }
            if deleted_any {
                bump_collection_revision(&self.connection, collection)?;
            }
            return Ok(());
        }

        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;

        let mut deleted_any = false;
        for id in ids {
            let id = sqlite_id(*id)?;
            let deleted = delete_document(&transaction, collection, id)?;
            deleted_any |= deleted;
        }
        if deleted_any {
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
        self.ensure_can_write()?;
        if self.active_transaction.is_some() {
            for collection in &manifest.collections {
                register_collection_schema(
                    &self.connection,
                    collection,
                    SchemaRegistrationMode::Compatible,
                )?;
            }
            return Ok(());
        }

        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;

        for collection in &manifest.collections {
            register_collection_schema(
                &transaction,
                collection,
                SchemaRegistrationMode::Compatible,
            )?;
        }

        transaction.commit().map_err(|error| error.to_string())
    }

    fn register_schemas_after_migration(
        &mut self,
        manifest: &SchemaManifest,
    ) -> Result<(), String> {
        validate_schema_manifest(manifest)?;
        self.ensure_can_write()?;
        if self.active_transaction.is_some() {
            for collection in &manifest.collections {
                register_collection_schema(
                    &self.connection,
                    collection,
                    SchemaRegistrationMode::ExplicitMigration,
                )?;
            }
            return Ok(());
        }

        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;

        for collection in &manifest.collections {
            register_collection_schema(
                &transaction,
                collection,
                SchemaRegistrationMode::ExplicitMigration,
            )?;
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

    fn storage_metadata(&self) -> Result<StorageMetadata, String> {
        read_storage_metadata(&self.connection)
    }

    fn rebuild_indexes(
        &mut self,
        collection: &str,
        documents: &[DocumentWrite],
    ) -> Result<(), String> {
        self.ensure_can_write()?;
        if self.active_transaction.is_some() {
            return rebuild_indexes_on_connection(&self.connection, collection, documents);
        }

        let transaction = self
            .connection
            .transaction()
            .map_err(|error| error.to_string())?;
        rebuild_indexes_on_connection(&transaction, collection, documents)?;
        transaction.commit().map_err(|error| error.to_string())
    }
}

impl SqliteStorage {
    fn begin_transaction(&mut self, mode: TransactionMode, sql: &str) -> Result<(), String> {
        if self.active_transaction.is_some() {
            return Err("a transaction is already active".into());
        }
        self.connection
            .execute_batch(sql)
            .map_err(|error| error.to_string())?;
        self.active_transaction = Some(mode);
        Ok(())
    }

    fn ensure_can_write(&self) -> Result<(), String> {
        match self.active_transaction {
            Some(TransactionMode::Read) => Err("write attempted inside read transaction".into()),
            Some(TransactionMode::Write) | None => Ok(()),
        }
    }
}

fn sqlite_id(id: u64) -> Result<i64, String> {
    i64::try_from(id).map_err(|_| format!("id {id} exceeds SQLite INTEGER range"))
}

fn allocate_id(connection: &Connection, collection: &str) -> Result<i64, String> {
    let existing = connection
        .query_row(
            "SELECT next_id FROM id_counters WHERE collection = ?1",
            params![collection],
            |row| row.get::<_, i64>(0),
        )
        .optional()
        .map_err(|error| error.to_string())?;

    let Some(next_id) = existing else {
        connection
            .execute(
                "INSERT INTO id_counters (collection, next_id) VALUES (?1, 2)",
                params![collection],
            )
            .map_err(|error| error.to_string())?;
        return Ok(1);
    };

    if next_id < 1 {
        return Err(format!(
            "id counter for collection `{collection}` is not positive"
        ));
    }
    let following_id = next_id.checked_add(1).ok_or_else(|| {
        format!("id counter for collection `{collection}` exceeds SQLite INTEGER range")
    })?;
    connection
        .execute(
            "UPDATE id_counters SET next_id = ?2 WHERE collection = ?1",
            params![collection, following_id],
        )
        .map_err(|error| error.to_string())?;
    Ok(next_id)
}

fn advance_id_counter(connection: &Connection, collection: &str, id: i64) -> Result<(), String> {
    let next_id = id.checked_add(1).unwrap_or(i64::MAX);
    connection
        .execute(
            r#"
            INSERT INTO id_counters (collection, next_id)
            VALUES (?1, ?2)
            ON CONFLICT(collection) DO UPDATE SET
                next_id = CASE
                    WHEN id_counters.next_id < excluded.next_id
                    THEN excluded.next_id
                    ELSE id_counters.next_id
                END
            "#,
            params![collection, next_id],
        )
        .map(|_| ())
        .map_err(|error| error.to_string())
}

fn put_document_with_indexes(
    connection: &Connection,
    collection: &str,
    id: u64,
    bytes: &[u8],
    indexes: &[IndexEntry],
) -> Result<(), String> {
    let id = sqlite_id(id)?;
    enforce_unique_indexes(connection, collection, id, indexes)?;
    put_document(connection, collection, id, bytes)?;
    delete_index_entries(connection, collection, id)?;
    insert_index_entries(connection, collection, id, indexes)?;
    advance_id_counter(connection, collection, id)
}

fn put_document(
    connection: &Connection,
    collection: &str,
    id: i64,
    bytes: &[u8],
) -> Result<(), String> {
    connection
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

fn delete_document(connection: &Connection, collection: &str, id: i64) -> Result<bool, String> {
    let deleted = connection
        .execute(
            "DELETE FROM documents WHERE collection = ?1 AND id = ?2",
            params![collection, id],
        )
        .map_err(|error| error.to_string())?;
    delete_index_entries(connection, collection, id)?;
    Ok(deleted > 0)
}

fn delete_index_entries(connection: &Connection, collection: &str, id: i64) -> Result<(), String> {
    connection
        .execute(
            "DELETE FROM index_entries WHERE collection = ?1 AND document_id = ?2",
            params![collection, id],
        )
        .map(|_| ())
        .map_err(|error| error.to_string())
}

#[allow(dead_code)]
fn rebuild_indexes_on_connection(
    connection: &Connection,
    collection: &str,
    documents: &[DocumentWrite],
) -> Result<(), String> {
    connection
        .execute(
            "DELETE FROM index_entries WHERE collection = ?1",
            params![collection],
        )
        .map_err(|error| error.to_string())?;
    for document in documents {
        let id = sqlite_id(document.id)?;
        ensure_document_exists(connection, collection, id)?;
        enforce_unique_indexes(connection, collection, id, &document.indexes)?;
        insert_index_entries(connection, collection, id, &document.indexes)?;
    }
    Ok(())
}

#[allow(dead_code)]
fn ensure_document_exists(
    connection: &Connection,
    collection: &str,
    id: i64,
) -> Result<(), String> {
    let exists = connection
        .query_row(
            "SELECT 1 FROM documents WHERE collection = ?1 AND id = ?2",
            params![collection, id],
            |_| Ok(()),
        )
        .optional()
        .map_err(|error| error.to_string())?
        .is_some();
    if exists {
        Ok(())
    } else {
        Err(format!(
            "cannot rebuild indexes for missing document `{collection}`.`{id}`"
        ))
    }
}

fn enforce_unique_indexes(
    connection: &Connection,
    collection: &str,
    id: i64,
    indexes: &[IndexEntry],
) -> Result<(), String> {
    let unique_indexes = unique_index_names(connection, collection)?;
    if unique_indexes.is_empty() {
        return Ok(());
    }

    for index in indexes {
        if !unique_indexes.contains(index.name.as_str()) {
            continue;
        }
        let existing_ids = query_index(
            connection,
            collection,
            &index.name,
            Some(&index.value),
            Some(&index.value),
        )?;
        for existing_id in existing_ids {
            let existing_id = sqlite_id(existing_id)?;
            if existing_id != id {
                return Err(format!(
                    "Unique index `{}` already contains this value.",
                    index.name
                ));
            }
        }
    }
    Ok(())
}

fn unique_index_names(
    connection: &Connection,
    collection: &str,
) -> Result<std::collections::HashSet<String>, String> {
    let schema_json = connection
        .query_row(
            "SELECT schema_json FROM schema_collections WHERE collection = ?1",
            params![collection],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|error| error.to_string())?;
    let Some(schema_json) = schema_json else {
        return Ok(std::collections::HashSet::new());
    };
    let schema = serde_json::from_str::<CollectionSchemaManifest>(&schema_json)
        .map_err(|error| error.to_string())?;
    Ok(schema
        .fields
        .into_iter()
        .filter(|field| field.is_indexed && field.is_index_unique)
        .map(|field| field.name)
        .collect())
}

fn insert_index_entries(
    connection: &Connection,
    collection: &str,
    id: i64,
    indexes: &[IndexEntry],
) -> Result<(), String> {
    for index in indexes {
        let key = SqliteIndexKey::from(&index.value)?;
        connection
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

fn ensure_storage_metadata(
    connection: &Connection,
    layout: StorageLayoutVersion,
    document_format: DocumentFormatVersion,
) -> Result<(), String> {
    connection
        .execute(
            "INSERT OR IGNORE INTO storage_metadata (key, value) VALUES (?1, ?2)",
            params!["storage_layout", layout.as_str()],
        )
        .map_err(|error| error.to_string())?;
    connection
        .execute(
            "INSERT OR IGNORE INTO storage_metadata (key, value) VALUES (?1, ?2)",
            params!["document_format", document_format.as_str()],
        )
        .map_err(|error| error.to_string())?;
    Ok(())
}

#[allow(dead_code)]
fn read_storage_metadata(connection: &Connection) -> Result<StorageMetadata, String> {
    let layout = connection
        .query_row(
            "SELECT value FROM storage_metadata WHERE key = 'storage_layout'",
            [],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|error| error.to_string())?
        .unwrap_or_else(|| StorageLayoutVersion::SqliteV1.as_str().to_string());
    let document_format = connection
        .query_row(
            "SELECT value FROM storage_metadata WHERE key = 'document_format'",
            [],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|error| error.to_string())?
        .unwrap_or_else(|| DocumentFormatVersion::JsonV1.as_str().to_string());
    Ok(StorageMetadata {
        layout: parse_storage_layout(&layout)?,
        document_format: parse_document_format(&document_format)?,
    })
}

#[allow(dead_code)]
fn parse_storage_layout(value: &str) -> Result<StorageLayoutVersion, String> {
    match value {
        "sqlite-v1" => Ok(StorageLayoutVersion::SqliteV1),
        "mdbx-v1" => Ok(StorageLayoutVersion::MdbxV1),
        "mdbx-v2" => Ok(StorageLayoutVersion::MdbxV2),
        _ => Err(format!("unknown storage layout version `{value}`")),
    }
}

#[allow(dead_code)]
fn parse_document_format(value: &str) -> Result<DocumentFormatVersion, String> {
    match value {
        "json-v1" => Ok(DocumentFormatVersion::JsonV1),
        "binary-v1" => Ok(DocumentFormatVersion::BinaryV1),
        _ => Err(format!("unknown document format version `{value}`")),
    }
}

fn bump_collection_revision(connection: &Connection, collection: &str) -> Result<(), String> {
    connection
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
        if field.index_type != "value" && field.index_type != "hash" && field.index_type != "words"
        {
            return Err(format!(
                "schema field `{}.{}` uses unsupported index type `{}`",
                collection.name, field.name, field.index_type
            ));
        }
        if !field.is_indexed
            && (field.is_index_unique || !field.index_case_sensitive || field.index_type != "value")
        {
            return Err(format!(
                "schema field `{}.{}` declares index options without an index",
                collection.name, field.name
            ));
        }
        let normalized_dart_type = field
            .dart_type
            .strip_suffix('?')
            .unwrap_or(&field.dart_type);
        if field.is_indexed && !field.index_case_sensitive && normalized_dart_type != "String" {
            return Err(format!(
                "schema field `{}.{}` case-insensitive indexes require String fields",
                collection.name, field.name
            ));
        }
        if field.is_indexed && field.index_type == "words" && normalized_dart_type != "String" {
            return Err(format!(
                "schema field `{}.{}` word indexes require String fields",
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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum SchemaRegistrationMode {
    Compatible,
    ExplicitMigration,
}

fn register_collection_schema(
    connection: &Connection,
    collection: &CollectionSchemaManifest,
    mode: SchemaRegistrationMode,
) -> Result<(), String> {
    let next_schema_json = canonical_schema_json(collection)?;
    let existing = connection
        .query_row(
            "SELECT version, schema_json FROM schema_collections WHERE collection = ?1",
            params![collection.name],
            |row| Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?)),
        )
        .optional()
        .map_err(|error| error.to_string())?;

    let Some((version, schema_json)) = existing else {
        connection
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
    if existing_schema == *collection {
        connection
            .execute(
                r#"
                UPDATE schema_collections
                SET schema_json = ?2
                WHERE collection = ?1
                "#,
                params![collection.name, next_schema_json],
            )
            .map(|_| ())
            .map_err(|error| error.to_string())?;
        return Ok(());
    }
    if mode == SchemaRegistrationMode::Compatible {
        validate_compatible_schema_change(&existing_schema, collection)?;
    }

    let next_version = version + 1;
    connection
        .execute(
            r#"
            UPDATE schema_collections
            SET version = ?2, schema_json = ?3
            WHERE collection = ?1
            "#,
            params![collection.name, next_version, next_schema_json],
        )
        .map_err(|error| error.to_string())?;
    connection
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
    if existing.is_index_unique != next.is_index_unique
        || existing.index_case_sensitive != next.index_case_sensitive
        || existing.index_type != next.index_type
    {
        return Err(format!(
            "schema field `{}.{}` cannot change index options without an explicit migration",
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
    use crate::storage::contract_tests;

    #[test]
    fn passes_the_shared_storage_engine_contract() {
        // Scenario: SQLite is the current default native storage backend.
        // Covers:
        // - The shared [StorageEngine] behavioral contract used by every
        //   backend candidate.
        // - CRUD, ids, indexes, unique indexes, schemas, revisions, and batch
        //   rollback behavior.
        // Expected: SQLite remains the reference backend for MDBX parity.
        contract_tests::run_storage_engine_contract("sqlite", SqliteStorage::open);
    }

    #[test]
    fn passes_the_shared_storage_transaction_contract() {
        // Scenario: SQLite is the reference transaction implementation.
        // Covers:
        // - The shared [StorageEngine] explicit transaction contract.
        // - Commit, rollback, read transaction write rejection, nested
        //   transaction rejection, and id allocation rollback.
        // Expected: SQLite keeps defining the behavior MDBX must match.
        contract_tests::run_storage_transaction_contract("sqlite", SqliteStorage::open);
    }

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
    fn reads_many_documents_with_one_prepared_statement() {
        // Scenario: Several ids are requested in order, including a missing id.
        // Covers:
        // - [StorageEngine::get_many] preserving input order.
        // - Missing documents represented as None.
        // Expected: Existing documents and gaps are returned in one batch.

        // Arrange.
        let directory = TemporaryDirectory::new("get_many");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
        storage.put("users", 3, br#"{"name":"Cid"}"#).unwrap();

        // Act.
        let documents = storage.get_many("users", &[3, 2, 1]).unwrap();

        // Assert.
        assert_eq!(
            documents,
            vec![
                Some(br#"{"name":"Cid"}"#.to_vec()),
                None,
                Some(br#"{"name":"Ana"}"#.to_vec()),
            ]
        );
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
    fn opens_isolated_in_memory_databases() {
        // Scenario: A database is opened in memory and then another memory
        // database is opened.
        // Covers:
        // - SQLite in-memory connection support.
        // - No file-backed persistence between separate memory handles.
        // Expected: The second in-memory database starts empty.

        // Arrange.
        let mut first_storage = SqliteStorage::open(IN_MEMORY_DIRECTORY).unwrap();

        // Act.
        first_storage
            .put("settings", 7, br#"{"theme":"dark"}"#)
            .unwrap();
        let stored = first_storage.get("settings", 7).unwrap();
        drop(first_storage);

        let second_storage = SqliteStorage::open(IN_MEMORY_DIRECTORY).unwrap();
        let missing = second_storage.get("settings", 7).unwrap();

        // Assert.
        assert_eq!(stored, Some(br#"{"theme":"dark"}"#.to_vec()));
        assert_eq!(missing, None);
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
    fn accepts_incompatible_schema_after_explicit_migration() {
        // Scenario: A Dart migration has already transformed stored documents.
        // Covers:
        // - Explicit migration schema registration bypassing compatibility
        //   checks.
        // - Schema version advancement after a field rename.
        // Expected: The new schema is committed at the next version.

        // Arrange.
        let directory = TemporaryDirectory::new("schema_explicit_migration");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let original = schema_manifest(vec![user_schema(vec![field(
            "email", "String", false, true,
        )])]);
        let renamed = schema_manifest(vec![user_schema(vec![field(
            "address", "String", false, true,
        )])]);

        // Act.
        storage.register_schemas(&original).unwrap();
        storage.register_schemas_after_migration(&renamed).unwrap();
        let version = storage.schema_version("users").unwrap();

        // Assert.
        assert_eq!(version, Some(2));
    }

    #[test]
    fn persists_index_variant_metadata_in_schemas() {
        // Scenario: A schema declares unique, case-insensitive, and hash index
        // options.
        // Covers:
        // - Native schema manifest validation for index variants.
        // - Schema version stability when the same variants are registered
        //   again.
        // Expected: Valid index variants register once and keep version 1.

        // Arrange.
        let directory = TemporaryDirectory::new("schema_index_variants");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let mut email = field("email", "String", false, true);
        email.is_index_unique = true;
        email.index_case_sensitive = false;
        let mut token = field("token", "String", false, true);
        token.index_type = "hash".to_string();
        let mut bio = field("bio", "String", false, true);
        bio.index_type = "words".to_string();
        bio.index_case_sensitive = false;
        let manifest = schema_manifest(vec![user_schema(vec![email, token, bio])]);

        // Act.
        storage.register_schemas(&manifest).unwrap();
        storage.register_schemas(&manifest).unwrap();
        let version = storage.schema_version("users").unwrap();

        // Assert.
        assert_eq!(version, Some(1));
    }

    #[test]
    fn rejects_incompatible_index_option_changes() {
        // Scenario: A registered index changes its uniqueness option.
        // Covers:
        // - Index option compatibility validation.
        // - Existing schema version preservation after rejection.
        // Expected: Changing index options requires a future explicit
        // migration.

        // Arrange.
        let directory = TemporaryDirectory::new("schema_index_option_change");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let original = schema_manifest(vec![user_schema(vec![field(
            "email", "String", false, true,
        )])]);
        let mut unique_email = field("email", "String", false, true);
        unique_email.is_index_unique = true;
        let incompatible = schema_manifest(vec![user_schema(vec![unique_email])]);

        // Act.
        storage.register_schemas(&original).unwrap();
        let result = storage.register_schemas(&incompatible);
        let version = storage.schema_version("users").unwrap();

        // Assert.
        assert!(result.unwrap_err().contains("cannot change index options"));
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
    fn allocates_monotonic_ids_by_collection() {
        // Scenario: Native ids are allocated for separate collections.
        // Covers:
        // - Per-collection id counters.
        // - Monotonic id allocation without stored documents.
        // Expected: Each collection starts at 1 and advances independently.

        // Arrange.
        let directory = TemporaryDirectory::new("allocate_monotonic");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        let first_user = storage.allocate_id("users").unwrap();
        let second_user = storage.allocate_id("users").unwrap();
        let first_settings = storage.allocate_id("settings").unwrap();

        // Assert.
        assert_eq!(first_user, 1);
        assert_eq!(second_user, 2);
        assert_eq!(first_settings, 1);
    }

    #[test]
    fn persists_next_id_after_reopening_the_database_directory() {
        // Scenario: Ids are allocated, the database closes, and it reopens.
        // Covers:
        // - Persisted id_counters state.
        // - Continuing from the previous next id after a new connection.
        // Expected: Reopened databases keep allocating monotonically.

        // Arrange.
        let directory = TemporaryDirectory::new("allocate_persist");

        // Act.
        {
            let mut storage = SqliteStorage::open(directory.path()).unwrap();
            assert_eq!(storage.allocate_id("users").unwrap(), 1);
            assert_eq!(storage.allocate_id("users").unwrap(), 2);
        }

        let mut reopened = SqliteStorage::open(directory.path()).unwrap();
        let next_id = reopened.allocate_id("users").unwrap();

        // Assert.
        assert_eq!(next_id, 3);
    }

    #[test]
    fn explicit_put_advances_the_next_allocated_id() {
        // Scenario: A caller stores a manual id before using auto ids.
        // Covers:
        // - Counter advancement from [StorageEngine::put].
        // - Collision avoidance between manual and allocated ids.
        // Expected: The next allocated id is greater than the manual id.

        // Arrange.
        let directory = TemporaryDirectory::new("allocate_after_put");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.put("users", 10, br#"{"name":"Ana"}"#).unwrap();
        let allocated = storage.allocate_id("users").unwrap();

        // Assert.
        assert_eq!(allocated, 11);
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

    #[test]
    fn bulk_puts_documents_atomically_and_updates_indexes() {
        // Scenario: Multiple indexed documents are written in one batch.
        // Covers:
        // - [StorageEngine::put_many_indexed] transaction path.
        // - Index writes for every document in the batch.
        // - One collection revision bump for the committed batch.
        // Expected: All documents and indexes are visible after commit.

        // Arrange.
        let directory = TemporaryDirectory::new("bulk_put");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
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

        // Act.
        storage.put_many_indexed("users", &documents).unwrap();
        let ids = storage.document_ids("users").unwrap();
        let team_ids = storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("team@example.com".into()),
            )
            .unwrap();
        let revision = storage.collection_revision("users").unwrap();

        // Assert.
        assert_eq!(ids, vec![1, 2]);
        assert_eq!(team_ids, vec![1]);
        assert_eq!(revision, 1);
    }

    #[test]
    fn rolls_back_bulk_put_when_one_document_is_invalid() {
        // Scenario: One document in a batch has an id outside SQLite range.
        // Covers:
        // - Native transaction rollback for partial bulk write failure.
        // - No persisted documents or revision bump after rollback.
        // Expected: Earlier valid writes in the same batch are not committed.

        // Arrange.
        let directory = TemporaryDirectory::new("bulk_put_rollback");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        let documents = vec![
            document_write(1, br#"{"name":"Ana"}"#, vec![]),
            document_write(i64::MAX as u64 + 1, br#"{"name":"Bad"}"#, vec![]),
        ];

        // Act.
        let result = storage.put_many_indexed("users", &documents);
        let stored = storage.get("users", 1).unwrap();
        let revision = storage.collection_revision("users").unwrap();

        // Assert.
        assert!(result.unwrap_err().contains("exceeds SQLite INTEGER range"));
        assert_eq!(stored, None);
        assert_eq!(revision, 0);
    }

    #[test]
    fn bulk_deletes_documents_atomically_and_cleans_indexes() {
        // Scenario: Multiple indexed documents are deleted in one batch.
        // Covers:
        // - [StorageEngine::delete_many] transaction path.
        // - Index cleanup for every deleted document.
        // - One collection revision bump for the committed batch.
        // Expected: Documents and index entries are removed together.

        // Arrange.
        let directory = TemporaryDirectory::new("bulk_delete");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        storage
            .put_many_indexed(
                "users",
                &[
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
                        br#"{"email":"team@example.com"}"#,
                        vec![index(
                            "email",
                            IndexValue::String("team@example.com".into()),
                        )],
                    ),
                ],
            )
            .unwrap();

        // Act.
        storage.delete_many("users", &[1, 2]).unwrap();
        let ids = storage.document_ids("users").unwrap();
        let team_ids = storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("team@example.com".into()),
            )
            .unwrap();
        let revision = storage.collection_revision("users").unwrap();

        // Assert.
        assert_eq!(ids, Vec::<u64>::new());
        assert_eq!(team_ids, Vec::<u64>::new());
        assert_eq!(revision, 2);
    }

    #[test]
    fn rolls_back_bulk_delete_when_one_id_is_invalid() {
        // Scenario: One id in a delete batch is outside SQLite range.
        // Covers:
        // - Native transaction rollback for partial bulk delete failure.
        // - Preserving previously deleted documents after rollback.
        // Expected: The valid delete in the same batch is not committed.

        // Arrange.
        let directory = TemporaryDirectory::new("bulk_delete_rollback");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();
        storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();

        // Act.
        let result = storage.delete_many("users", &[1, i64::MAX as u64 + 1]);
        let stored = storage.get("users", 1).unwrap();
        let revision = storage.collection_revision("users").unwrap();

        // Assert.
        assert!(result.unwrap_err().contains("exceeds SQLite INTEGER range"));
        assert_eq!(stored, Some(br#"{"name":"Ana"}"#.to_vec()));
        assert_eq!(revision, 1);
    }

    #[test]
    fn commits_explicit_write_transactions() {
        // Scenario: Multiple writes are wrapped in one explicit transaction.
        // Covers:
        // - [StorageEngine::begin_write_transaction].
        // - Writes reusing the active transaction instead of creating nested
        //   SQLite transactions.
        // - [StorageEngine::commit_transaction].
        // Expected: All writes become visible after commit.

        // Arrange.
        let directory = TemporaryDirectory::new("txn_commit");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.begin_write_transaction().unwrap();
        storage.put("users", 1, br#"{"name":"Ana"}"#).unwrap();
        storage.put("users", 2, br#"{"name":"Ben"}"#).unwrap();
        storage.commit_transaction().unwrap();
        let ids = storage.document_ids("users").unwrap();

        // Assert.
        assert_eq!(ids, vec![1, 2]);
    }

    #[test]
    fn rolls_back_explicit_write_transactions() {
        // Scenario: A write transaction is rolled back after partial writes.
        // Covers:
        // - [StorageEngine::rollback_transaction].
        // - Documents, indexes, counters, and revisions being reverted.
        // Expected: No partial transaction state is persisted.

        // Arrange.
        let directory = TemporaryDirectory::new("txn_rollback");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
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
        let ids = storage.document_ids("users").unwrap();
        let indexed_ids = storage
            .query_index_equal(
                "users",
                "email",
                &IndexValue::String("ben@example.com".into()),
            )
            .unwrap();
        let revision = storage.collection_revision("users").unwrap();
        let allocated_id = storage.allocate_id("users").unwrap();

        // Assert.
        assert_eq!(ids, Vec::<u64>::new());
        assert_eq!(indexed_ids, Vec::<u64>::new());
        assert_eq!(revision, 0);
        assert_eq!(allocated_id, 1);
    }

    #[test]
    fn rejects_writes_inside_read_transactions() {
        // Scenario: A caller tries to mutate during an explicit read
        // transaction.
        // Covers:
        // - Native read transaction ownership rules.
        // - Write rejection before SQLite mutating statements run.
        // Expected: The write fails and no data is persisted.

        // Arrange.
        let directory = TemporaryDirectory::new("txn_read_write");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.begin_read_transaction().unwrap();
        let result = storage.put("users", 1, br#"{"name":"Ana"}"#);
        storage.rollback_transaction().unwrap();
        let stored = storage.get("users", 1).unwrap();

        // Assert.
        assert!(result.unwrap_err().contains("read transaction"));
        assert_eq!(stored, None);
    }

    #[test]
    fn rejects_nested_explicit_transactions() {
        // Scenario: A transaction is opened while another is active.
        // Covers:
        // - Native transaction handle ownership rules.
        // Expected: Cindel rejects nested transactions for now.

        // Arrange.
        let directory = TemporaryDirectory::new("txn_nested");
        let mut storage = SqliteStorage::open(directory.path()).unwrap();

        // Act.
        storage.begin_write_transaction().unwrap();
        let nested = storage.begin_read_transaction();
        storage.rollback_transaction().unwrap();

        // Assert.
        assert!(nested.unwrap_err().contains("already active"));
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
            is_index_unique: false,
            index_case_sensitive: true,
            index_type: "value".to_string(),
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
