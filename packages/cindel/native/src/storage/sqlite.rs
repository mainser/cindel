use std::fs;
use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension};

use super::StorageEngine;

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
                "#,
            )
            .map_err(|error| error.to_string())
    }
}

impl StorageEngine for SqliteStorage {
    fn get(&self, collection: &str, id: u64) -> Result<Option<Vec<u8>>, String> {
        self.connection
            .query_row(
                "SELECT bytes FROM documents WHERE collection = ?1 AND id = ?2",
                params![collection, id],
                |row| row.get(0),
            )
            .optional()
            .map_err(|error| error.to_string())
    }

    fn put(&self, collection: &str, id: u64, bytes: &[u8]) -> Result<(), String> {
        self.connection
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

    fn delete(&self, collection: &str, id: u64) -> Result<(), String> {
        self.connection
            .execute(
                "DELETE FROM documents WHERE collection = ?1 AND id = ?2",
                params![collection, id],
            )
            .map(|_| ())
            .map_err(|error| error.to_string())
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::*;

    #[test]
    fn stores_reads_and_deletes_bytes_by_collection_and_id() {
        let directory = temporary_directory("crud");
        let storage = SqliteStorage::open(directory.to_str().unwrap()).unwrap();

        storage.put("users", 1, br#"{"name":"Noel"}"#).unwrap();

        assert_eq!(
            storage.get("users", 1).unwrap(),
            Some(br#"{"name":"Noel"}"#.to_vec())
        );

        storage.delete("users", 1).unwrap();

        assert_eq!(storage.get("users", 1).unwrap(), None);

        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn persists_bytes_after_reopening_the_database_directory() {
        let directory = temporary_directory("persist");

        {
            let storage = SqliteStorage::open(directory.to_str().unwrap()).unwrap();
            storage.put("settings", 7, br#"{"theme":"dark"}"#).unwrap();
        }

        let reopened = SqliteStorage::open(directory.to_str().unwrap()).unwrap();

        assert_eq!(
            reopened.get("settings", 7).unwrap(),
            Some(br#"{"theme":"dark"}"#.to_vec())
        );

        fs::remove_dir_all(directory).unwrap();
    }

    fn temporary_directory(name: &str) -> std::path::PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("cindel_{name}_{nonce}"))
    }
}
