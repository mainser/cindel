use super::*;

fn quote(name: &str) -> String {
    format!("\"{}\"", name.replace('"', "\"\""))
}

fn page_ids(
    connection: &Connection,
    sql: &str,
    params: impl rusqlite::Params,
) -> Result<Vec<u64>, String> {
    let mut statement = connection.prepare(sql).map_err(sqlite_diagnostic)?;
    let ids = statement
        .query_map(params, |r| r.get::<_, i64>(0))
        .map_err(sqlite_diagnostic)?
        .map(|r| {
            r.map_err(sqlite_diagnostic)
                .and_then(|v| u64::try_from(v).map_err(sqlite_diagnostic))
        })
        .collect::<Result<Vec<_>, _>>()?;
    #[cfg(test)]
    assert_eq!(
        statement.get_status(rusqlite::StatementStatus::FullscanStep),
        0,
        "migration pages must seek, not rescan the prefix"
    );
    Ok(ids)
}

fn objects(connection: &Connection, kind: &str) -> Result<Vec<(String, String)>, String> {
    connection.prepare("SELECT name,sql FROM sqlite_schema WHERE type=?1 AND substr(name,1,7) != 'sqlite_' AND sql IS NOT NULL ORDER BY name")
        .map_err(sqlite_diagnostic)?.query_map([kind], |r| Ok((r.get(0)?, r.get(1)?)))
        .map_err(sqlite_diagnostic)?.collect::<Result<_, _>>().map_err(sqlite_diagnostic)
}

fn copy_tables(source: &Connection, target: &Connection) -> Result<(), String> {
    for (name, _) in objects(target, "view")? {
        target
            .execute_batch(&format!("DROP VIEW {}", quote(&name)))
            .map_err(sqlite_diagnostic)?;
    }
    for (name, _) in objects(target, "table")? {
        target
            .execute_batch(&format!("DROP TABLE {}", quote(&name)))
            .map_err(sqlite_diagnostic)?;
    }
    for (name, sql) in objects(source, "table")? {
        target.execute_batch(&sql).map_err(sqlite_diagnostic)?;
        let mut read = source
            .prepare(&format!("SELECT * FROM {}", quote(&name)))
            .map_err(sqlite_diagnostic)?;
        let count = read.column_count();
        let params = std::iter::repeat("?")
            .take(count)
            .collect::<Vec<_>>()
            .join(",");
        let mut write = target
            .prepare(&format!("INSERT INTO {} VALUES ({params})", quote(&name)))
            .map_err(sqlite_diagnostic)?;
        let mut rows = read.query([]).map_err(sqlite_diagnostic)?;
        while let Some(row) = rows.next().map_err(sqlite_diagnostic)? {
            let values = (0..count)
                .map(|i| row.get::<_, Value>(i))
                .collect::<Result<Vec<_>, _>>()
                .map_err(sqlite_diagnostic)?;
            write
                .execute(params_from_iter(values.iter()))
                .map_err(sqlite_diagnostic)?;
            super::super::migration::copied_record()?;
        }
    }
    for kind in ["index", "trigger", "view"] {
        for (_, sql) in objects(source, kind)? {
            target.execute_batch(&sql).map_err(sqlite_diagnostic)?;
        }
    }
    Ok(())
}

impl SqliteStorage {
    #[cfg(test)]
    pub(crate) fn migration_temp_path(&self) -> std::path::PathBuf {
        std::path::PathBuf::from(self.migration_path.as_ref().unwrap().database_directory())
    }
    pub(crate) fn migration_ids_page(
        &self,
        name: &str,
        after: Option<u64>,
        limit: usize,
    ) -> Result<Vec<u64>, String> {
        let after = after.map(sqlite_id).transpose()?.unwrap_or(-1);
        let mut ids = Vec::new();
        if self.collection_schema(name).is_some() && table_exists(&self.connection, name)? {
            let sql = format!("SELECT {SQLITE_ROW_ID_COLUMN} FROM {} WHERE {SQLITE_ROW_ID_COLUMN}>?1 ORDER BY {SQLITE_ROW_ID_COLUMN} LIMIT ?2", quote(name));
            ids = page_ids(&self.connection, &sql, params![after, limit as i64])?;
        }
        if table_exists(&self.connection, "documents")? {
            ids.extend(page_ids(
                &self.connection,
                "SELECT id FROM documents WHERE collection=?1 AND id>?2 ORDER BY id LIMIT ?3",
                params![name, after, limit as i64],
            )?);
        }
        ids.sort_unstable();
        ids.dedup();
        ids.truncate(limit);
        Ok(ids)
    }

    pub(crate) fn migration_fork(
        &mut self,
        token: &str,
        manifest: &SchemaManifest,
    ) -> Result<(Self, u64), String> {
        self.backup_check_idle()?;
        let path = crate::backup::TemporaryBackupPath::new(token, "migration")?;
        let mut stage = Self::open_uninitialized(path.database_directory(), true)?;
        stage.migration_path = Some(path);
        stage
            .connection
            .execute_batch("PRAGMA cache_size=-1024; PRAGMA temp_store=FILE;")
            .map_err(sqlite_diagnostic)?;
        stage.initialize(None)?;
        self.begin_read_transaction()?;
        let result = (|| {
            // Reading data_version also establishes the source read snapshot.
            let revision = self
                .connection
                .query_row("PRAGMA data_version", [], |r| r.get::<_, i64>(0))
                .map_err(sqlite_diagnostic)?;
            let txn = stage.connection.transaction().map_err(sqlite_diagnostic)?;
            copy_tables(&self.connection, &txn)?;
            txn.commit().map_err(sqlite_diagnostic)?;
            stage.register_schemas(manifest)?;
            for schema in &manifest.collections {
                let version =
                    persisted_schema_version(&self.connection, &schema.name)?.unwrap_or(1);
                self.schemas.insert(
                    schema.name.clone(),
                    RegisteredCollectionSchema {
                        version,
                        schema: schema.clone(),
                    },
                );
            }
            Ok((stage, revision as u64))
        })();
        if result.is_err() {
            self.rollback_transaction()?;
        }
        result
    }

    pub(crate) fn migration_publish(
        &mut self,
        stage: &Self,
        revision: u64,
        version: u64,
    ) -> Result<(), String> {
        stage.backup_check_idle()?;
        self.rollback_transaction()?;
        let txn = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(sqlite_diagnostic)?;
        let current = txn
            .query_row("PRAGMA data_version", [], |r| r.get::<_, i64>(0))
            .map_err(sqlite_diagnostic)?;
        if current as u64 != revision {
            return Err("migration source changed during preparation".into());
        }
        copy_tables(&stage.connection, &txn)?;
        for name in stage.schemas.keys() {
            let current = stage.collection_revision(name)?;
            let next = current
                .checked_add(1)
                .ok_or("migration revision overflow")?;
            txn.execute("INSERT INTO collection_revisions VALUES (?1,?2) ON CONFLICT(collection) DO UPDATE SET revision=excluded.revision", params![name, i64::try_from(next).map_err(sqlite_diagnostic)?]).map_err(sqlite_diagnostic)?;
        }
        write_migration_version(&txn, version)?;
        txn.commit().map_err(sqlite_diagnostic)?;
        self.schemas = stage.schemas.clone();
        self.last_change_sets.clear();
        Ok(())
    }
}
