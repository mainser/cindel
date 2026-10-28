use super::*;

fn quote(identifier: &str) -> String {
    format!("\"{}\"", identifier.replace('"', "\"\""))
}

#[cfg(test)]
thread_local! {
    pub(super) static FAIL_AFTER_RENAME: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

// Old Cindel tables declared strings as `str`, which has NUMERIC affinity.
// Repair the physical table once, at schema registration, never on reads/writes.
// SQLite streams INSERT SELECT; Rust retains only column and index definitions.
pub(super) fn upgrade_legacy_columns(
    connection: &Connection,
    collection: &str,
) -> Result<(), String> {
    let table = quote(collection);
    let columns = connection
        .prepare(&format!("PRAGMA table_info({table})"))
        .map_err(sqlite_diagnostic)?
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, bool>(3)?,
                row.get::<_, Option<String>>(4)?,
                row.get::<_, i64>(5)?,
            ))
        })
        .map_err(sqlite_diagnostic)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(sqlite_diagnostic)?;
    if !columns
        .iter()
        .any(|(_, ty, _, _, _)| ty.eq_ignore_ascii_case("str"))
    {
        return Ok(());
    }

    // Accept the layout emitted by Cindel, including retained columns that may
    // not be in the current manifest. Do not silently discard SQL constraints
    // or other table features if someone has changed the physical schema.
    let mut old_definition = format!("CREATE TABLE {collection} (");
    let mut definitions = Vec::with_capacity(columns.len());
    let mut names = Vec::with_capacity(columns.len());
    for (i, (name, ty, not_null, default, pk)) in columns.iter().enumerate() {
        let row_id = name == SQLITE_ROW_ID_COLUMN && ty == "INTEGER" && *pk == 1;
        if *not_null || default.is_some() || (!row_id && *pk != 0) {
            return Err(format!(
                "cannot upgrade non-Cindel string table `{collection}`"
            ));
        }
        if i != 0 {
            old_definition.push_str(", ");
        }
        let suffix = if row_id { " PRIMARY KEY" } else { "" };
        write!(old_definition, "{name} {ty}{suffix}").unwrap();
        let new_type = if ty.eq_ignore_ascii_case("str") {
            "TEXT"
        } else {
            ty
        };
        definitions.push(format!("{} {new_type}{suffix}", quote(name)));
        names.push(quote(name));
    }
    old_definition.push(')');
    let stored_definition: String = connection
        .query_row(
            "SELECT sql FROM sqlite_schema WHERE type='table' AND name=?1",
            [collection],
            |row| row.get(0),
        )
        .map_err(sqlite_diagnostic)?;
    if stored_definition != old_definition {
        return Err(format!(
            "cannot upgrade non-Cindel string table `{collection}`"
        ));
    }
    let objects = connection.prepare(
        "SELECT sql FROM sqlite_schema WHERE tbl_name=?1 AND type IN ('index','trigger') AND sql IS NOT NULL ORDER BY type,name",
    ).map_err(sqlite_diagnostic)?.query_map([collection], |row| row.get::<_, String>(0))
        .map_err(sqlite_diagnostic)?.collect::<Result<Vec<_>, _>>().map_err(sqlite_diagnostic)?;
    let temporary = quote(&format!("_cindel_text_upgrade_{collection}"));
    let names = names.join(", ");
    let legacy_alter: bool = connection
        .query_row("PRAGMA legacy_alter_table", [], |row| row.get(0))
        .map_err(sqlite_diagnostic)?;
    connection
        .execute_batch("SAVEPOINT cindel_text_upgrade")
        .map_err(sqlite_diagnostic)?;
    let result = (|| {
        connection.execute_batch(&format!(
            "CREATE TABLE {temporary} ({}); INSERT INTO {temporary} ({names}) SELECT {names} FROM {table}; DROP TABLE {table};",
            definitions.join(", "),
        )).map_err(sqlite_diagnostic)?;
        // Views referencing the original name stay valid after the replacement;
        // do not ask RENAME to validate them during the temporary absence.
        connection
            .execute_batch("PRAGMA legacy_alter_table=ON")
            .map_err(sqlite_diagnostic)?;
        connection
            .execute_batch(&format!("ALTER TABLE {temporary} RENAME TO {table}"))
            .map_err(sqlite_diagnostic)?;
        #[cfg(test)]
        if FAIL_AFTER_RENAME.with(|fail| fail.replace(false)) {
            return Err("injected string table upgrade failure".into());
        }
        for sql in &objects {
            connection.execute_batch(sql).map_err(sqlite_diagnostic)?;
        }
        Ok(())
    })();
    let reset = connection
        .execute_batch(if legacy_alter {
            "PRAGMA legacy_alter_table=ON"
        } else {
            "PRAGMA legacy_alter_table=OFF"
        })
        .map_err(sqlite_diagnostic);
    match result.and(reset) {
        Ok(()) => connection
            .execute_batch("RELEASE cindel_text_upgrade")
            .map_err(sqlite_diagnostic),
        Err(error) => {
            connection
                .execute_batch("ROLLBACK TO cindel_text_upgrade; RELEASE cindel_text_upgrade")
                .map_err(|rollback| {
                    format!("{error}; string upgrade rollback failed: {rollback}")
                })?;
            Err(error)
        }
    }
}
