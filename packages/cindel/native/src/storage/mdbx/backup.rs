use super::*;

impl MdbxStorage {
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
        self.with_read_transaction(|transaction, tables| {
            let prefix = relation_forward_prefix(
                &link.source_collection,
                link.source_id,
                &link.link_name,
                &link.target_collection,
            );
            let mut start = prefix.clone();
            if let Some(id) = after {
                let Some(next) = id.checked_add(1) else {
                    return Ok(vec![]);
                };
                start.extend_from_slice(&next.to_be_bytes());
            }
            let mut cursor = transaction
                .cursor(&tables.relations_forward)
                .map_err(|e| e.to_string())?;
            let mut ids = Vec::new();
            for row in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(&start) {
                let (key, _) = row.map_err(|e| e.to_string())?;
                if !key.starts_with(&prefix) {
                    break;
                }
                ids.push(decode_relation_key_id(&key)?);
                if ids.len() == limit {
                    break;
                }
            }
            Ok(ids)
        })
    }

    pub(crate) fn restore_backup(
        &mut self,
        spool: &crate::backup::BackupSpool,
        version: u64,
    ) -> Result<(), String> {
        self.backup_check_idle()?;
        let mut maxima = std::collections::HashMap::new();
        self.with_write_transaction(|transaction, tables| {
            if read_migration_version(transaction, &tables)?.unwrap_or(0) != spool.migration_version
            {
                return Err("restore target metadata changed".into());
            }
            for (name, expected) in &spool.collections {
                if schema_record(transaction, &tables, name)?.map(|r| r.0) != *expected {
                    return Err("restore target schema changed".into());
                }
                let table = open_documents_table(transaction, name)?;
                if !scan_document_ids_page(transaction, &table, None, 1)?.is_empty() {
                    return Err(format!("Restore target `{name}` must be empty."));
                }
            }
            spool.documents(|name, native, bytes| {
                if native {
                    return Err("MDBX restore requires binary documents".into());
                }
                let documents = crate::backup::binary_documents(bytes)?;
                let schema = self.cached_collection_schema(transaction, &tables, name)?;
                put_many_documents_with_indexes(
                    transaction,
                    &tables,
                    name,
                    schema.as_ref(),
                    &documents,
                    false,
                )?;
                if let Some(maximum) = documents.iter().map(|d| d.id).max() {
                    let next = maximum.checked_add(1).ok_or("backup id exhausted")?;
                    ids::set_persisted_next_id_at_least(transaction, &tables, name, next)?;
                    maxima
                        .entry(name.to_string())
                        .and_modify(|v: &mut u64| *v = (*v).max(next))
                        .or_insert(next);
                }
                Ok(())
            })?;
            for (name, _) in &spool.collections {
                let table = open_documents_table(transaction, name)?;
                let actual = transaction
                    .table_stat(&table)
                    .map_err(|e| e.to_string())?
                    .entries() as u64;
                if actual != spool.document_count(name)? {
                    return Err("backup unique index would discard documents".into());
                }
            }
            spool.edges(|link| {
                ensure_link_document_exists(transaction, &link.source_collection, link.source_id)?;
                ensure_link_document_exists(
                    transaction,
                    &link.target_collection,
                    link.target_ids[0],
                )?;
                transaction
                    .put(
                        &tables.relations_forward,
                        relation_forward_key(
                            &link.source_collection,
                            link.source_id,
                            &link.link_name,
                            &link.target_collection,
                            link.target_ids[0],
                        ),
                        [],
                        WriteFlags::UPSERT,
                    )
                    .map_err(|e| e.to_string())?;
                transaction
                    .put(
                        &tables.relations_backlink,
                        relation_backlink_key(
                            &link.target_collection,
                            link.target_ids[0],
                            &link.source_collection,
                            &link.link_name,
                            link.source_id,
                        ),
                        [],
                        WriteFlags::UPSERT,
                    )
                    .map_err(|e| e.to_string())?;
                Ok(())
            })?;
            for (name, _) in &spool.collections {
                bump_collection_revision(transaction, &tables, name)?;
            }
            write_migration_version(transaction, &tables, version)
        })?;
        self.last_change_sets.clear();
        for (name, next) in maxima {
            self.set_cached_next_id_at_least(&name, next)?;
        }
        Ok(())
    }
}
