use super::*;

const BATCH_ROWS: usize = 128;
const BATCH_BYTES: usize = 2 * 1024 * 1024;

// Upgrade old binary fields once, before exposing a registered collection.
// All columns and their markers commit together, including inside writeTxn.
pub(super) fn normalize(
    connection: &Connection,
    schema: &CollectionSchemaManifest,
) -> Result<(), String> {
    let fields = schema
        .fields
        .iter()
        .filter(|f| matches!(f.binary_type.as_str(), "list" | "object"))
        .collect::<Vec<_>>();
    if fields.is_empty() {
        return Ok(());
    }
    connection
        .execute_batch("SAVEPOINT cindel_json_storage")
        .map_err(sqlite_diagnostic)?;
    let result = (|| {
        connection.execute_batch("CREATE TABLE IF NOT EXISTS cindel_json_columns (collection TEXT NOT NULL, field TEXT NOT NULL, PRIMARY KEY(collection, field)) WITHOUT ROWID").map_err(sqlite_diagnostic)?;
        for field in fields {
            let done = connection
                .query_row(
                    "SELECT 1 FROM cindel_json_columns WHERE collection=?1 AND field=?2",
                    params![schema.name, field.name],
                    |_| Ok(()),
                )
                .optional()
                .map_err(sqlite_diagnostic)?
                .is_some();
            if done {
                continue;
            }
            let select = format!("SELECT {SQLITE_ROW_ID_COLUMN}, {} FROM {} WHERE {SQLITE_ROW_ID_COLUMN}>?1 AND typeof({})='blob' ORDER BY {SQLITE_ROW_ID_COLUMN} LIMIT {BATCH_ROWS}", field.name, schema.name, field.name);
            let update = format!(
                "UPDATE {} SET {}=?1 WHERE {SQLITE_ROW_ID_COLUMN}=?2",
                schema.name, field.name
            );
            let mut after = i64::MIN;
            loop {
                let mut batch = Vec::new();
                let mut retained = 0;
                {
                    let mut statement = connection.prepare(&select).map_err(sqlite_diagnostic)?;
                    let mut rows = statement.query([after]).map_err(sqlite_diagnostic)?;
                    while let Some(row) = rows.next().map_err(sqlite_diagnostic)? {
                        let id: i64 = row.get(0).map_err(sqlite_diagnostic)?;
                        let bytes = row
                            .get_ref(1)
                            .map_err(sqlite_diagnostic)?
                            .as_blob()
                            .map_err(sqlite_diagnostic)?;
                        let json = crate::document_format::sqlite_json::binary_json(
                            bytes,
                            field.binary_type == "list",
                        )?;
                        retained += json.len();
                        batch.push((id, json));
                        if retained >= BATCH_BYTES {
                            break;
                        }
                    }
                }
                if batch.is_empty() {
                    break;
                }
                #[cfg(test)]
                super::super::test_faults::check("sqlite_json_batch")?;
                let mut statement = connection.prepare(&update).map_err(sqlite_diagnostic)?;
                for (id, json) in &batch {
                    statement
                        .execute(params![json, id])
                        .map_err(sqlite_diagnostic)?;
                }
                after = batch.last().unwrap().0;
            }
            connection
                .execute(
                    "INSERT INTO cindel_json_columns(collection, field) VALUES (?1, ?2)",
                    params![schema.name, field.name],
                )
                .map_err(sqlite_diagnostic)?;
        }
        Ok(())
    })();
    match result {
        Ok(()) => connection
            .execute_batch("RELEASE cindel_json_storage")
            .map_err(sqlite_diagnostic),
        Err(error) => {
            connection
                .execute_batch("ROLLBACK TO cindel_json_storage; RELEASE cindel_json_storage")
                .map_err(sqlite_diagnostic)?;
            Err(error)
        }
    }
}
