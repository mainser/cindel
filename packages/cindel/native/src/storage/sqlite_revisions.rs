//! Persist revisions with their data, grouping all affected collections per batch.
use super::*;

pub(super) fn initialize(connection: &Connection) -> Result<(), String> {
    connection
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS collection_revisions (
            collection TEXT PRIMARY KEY NOT NULL, revision INTEGER NOT NULL
        );
        CREATE TEMP TABLE cindel_pending_revisions (
            collection TEXT PRIMARY KEY NOT NULL
        ) WITHOUT ROWID;",
        )
        .map_err(sqlite_diagnostic)
}

pub(super) fn mark(connection: &Connection, collection: &str) -> Result<(), String> {
    connection
        .execute(
            "INSERT OR IGNORE INTO temp.cindel_pending_revisions VALUES (?1)",
            [collection],
        )
        .map_err(sqlite_diagnostic)?;
    Ok(())
}

pub(super) fn flush(connection: &Connection) -> Result<(), String> {
    // The temp set is transactional too. Relation cleanup can mark thousands of
    // edges, but each affected collection advances once when the batch finishes.
    // Overflow must fail, not promote the counter to an imprecise SQLite REAL.
    connection
        .execute_batch(
            "INSERT INTO collection_revisions(collection, revision)
         SELECT collection, 1 FROM temp.cindel_pending_revisions WHERE true
         ON CONFLICT(collection) DO UPDATE SET revision =
             CASE WHEN revision < 9223372036854775807 THEN revision + 1 ELSE NULL END;
         DELETE FROM temp.cindel_pending_revisions;",
        )
        .map_err(sqlite_diagnostic)
}

pub(super) fn read(connection: &Connection, collection: &str) -> Result<u64, String> {
    connection
        .query_row(
            "SELECT revision FROM collection_revisions WHERE collection=?1",
            [collection],
            |row| row.get::<_, i64>(0),
        )
        .optional()
        .map_err(sqlite_diagnostic)?
        .map(u64::try_from)
        .transpose()
        .map_err(sqlite_diagnostic)
        .map(Option::unwrap_or_default)
}
