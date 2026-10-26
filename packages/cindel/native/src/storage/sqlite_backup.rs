use super::*;

impl SqliteStorage {
    pub(crate) fn backup_check_idle(&self) -> Result<(), String> {
        if self.active_transaction.is_some() {
            Err("restore cannot run inside a transaction".into())
        } else {
            Ok(())
        }
    }

    pub(crate) fn backup_link_ids(
        &self,
        link: &LinkSave,
        after: Option<u64>,
        limit: usize,
    ) -> Result<Vec<u64>, String> {
        let mut statement = self.connection.prepare("SELECT target_id FROM cindel_relations WHERE source_collection=?1 AND source_id=?2 AND link_name=?3 AND target_collection=?4 AND target_id>?5 ORDER BY target_id LIMIT ?6").map_err(sqlite_diagnostic)?;
        let rows = statement
            .query_map(
                params![
                    link.source_collection,
                    sqlite_id(link.source_id)?,
                    link.link_name,
                    link.target_collection,
                    after.map(sqlite_id).transpose()?.unwrap_or(-1),
                    limit as i64
                ],
                |r| r.get::<_, i64>(0).map(|v| v as u64),
            )
            .map_err(sqlite_diagnostic)?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(sqlite_diagnostic)
    }

    pub(crate) fn restore_backup(
        &mut self,
        spool: &crate::backup::BackupSpool,
        version: u64,
    ) -> Result<(), String> {
        self.backup_check_idle()?;
        self.invalidate_read_preparation();
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(sqlite_diagnostic)?;
        if read_migration_version(&transaction)?.unwrap_or(0) != spool.migration_version {
            return Err("restore target metadata changed".into());
        }
        for (name, expected) in &spool.collections {
            let schema = self.schemas.get(name).ok_or("restore schema missing")?;
            if Some(schema.version) != *expected {
                return Err("restore target schema changed".into());
            }
            // Collection names have already passed schema identifier validation.
            let exists: bool = transaction
                .query_row(
                    &format!("SELECT EXISTS(SELECT 1 FROM \"{name}\" LIMIT 1)"),
                    [],
                    |r| r.get(0),
                )
                .map_err(sqlite_diagnostic)?;
            if exists {
                return Err(format!("Restore target `{name}` must be empty."));
            }
        }
        spool.documents(|name, native, bytes| {
            let schema = &self
                .schemas
                .get(name)
                .ok_or("restore schema missing")?
                .schema;
            if !native {
                return Err("SQLite restore requires native document rows".into());
            }
            let documents = crate::backup::native_documents(bytes)?;
            // Validate unique keys against each preceding restored row, also
            // within a batch. Restore must never replace an archived document.
            let unique = schema.fields.iter().any(|f| f.is_index_unique)
                || schema.composite_indexes.iter().any(|i| i.is_unique);
            let mut strict_schema = schema.clone();
            for field in &mut strict_schema.fields {
                field.is_index_replace = false;
            }
            for index in &mut strict_schema.composite_indexes {
                index.is_replace = false;
            }
            let chunk_size = if unique { 1 } else { documents.len().max(1) };
            for chunk in documents.chunks(chunk_size) {
                if let Some(max_id) = put_native_documents(&transaction, &strict_schema, chunk)? {
                    advance_id_counter(&transaction, name, max_id)?;
                }
            }
            Ok(())
        })?;
        for (name, _) in &spool.collections {
            let actual: i64 = transaction
                .query_row(&format!("SELECT count(*) FROM \"{name}\""), [], |r| {
                    r.get(0)
                })
                .map_err(sqlite_diagnostic)?;
            if actual as u64 != spool.document_count(name)? {
                return Err("backup unique index would discard documents".into());
            }
        }
        ensure_relation_tables(&transaction)?;
        spool.edges(|link| {
            ensure_sqlite_document_exists(&transaction, &link.source_collection, link.source_id)?;
            ensure_sqlite_document_exists(
                &transaction,
                &link.target_collection,
                link.target_ids[0],
            )?;
            transaction
                .execute(
                    "INSERT INTO cindel_relations VALUES (?1,?2,?3,?4,?5)",
                    params![
                        link.source_collection,
                        sqlite_id(link.source_id)?,
                        link.link_name,
                        link.target_collection,
                        sqlite_id(link.target_ids[0])?
                    ],
                )
                .map_err(sqlite_diagnostic)?;
            Ok(())
        })?;
        write_migration_version(&transaction, version)?;
        for (name, _) in &spool.collections {
            revisions::mark(&transaction, name)?;
        }
        revisions::flush(&transaction)?;
        transaction.commit().map_err(sqlite_diagnostic)?;
        self.last_change_sets.clear();
        Ok(())
    }
}
