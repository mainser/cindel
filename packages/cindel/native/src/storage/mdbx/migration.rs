use super::*;

fn table_names<K: libmdbx::TransactionKind>(
    txn: &Transaction<'_, K, NoWriteMap>,
) -> Result<Vec<String>, String> {
    let main = txn.open_table(None).map_err(|e| e.to_string())?;
    let mut cursor = txn.cursor(&main).map_err(|e| e.to_string())?;
    cursor
        .iter_start::<Cow<'_, [u8]>, Cow<'_, [u8]>>()
        .map(|row| {
            let (key, _) = row.map_err(|e| e.to_string())?;
            String::from_utf8(key.into_owned()).map_err(|e| e.to_string())
        })
        .collect()
}

fn copy_tables(
    source: &Transaction<'_, RO, NoWriteMap>,
    target: &Transaction<'_, RW, NoWriteMap>,
) -> Result<(), String> {
    // Keep DBI handles valid for existing readers: empty tables instead of
    // dropping them. Cindel stores application data only in named tables.
    for name in table_names(target)? {
        let table = target.open_table(Some(&name)).map_err(|e| e.to_string())?;
        target.clear_table(&table).map_err(|e| e.to_string())?;
    }
    for name in table_names(source)? {
        let from = source.open_table(Some(&name)).map_err(|e| e.to_string())?;
        let flags = source.table_flags(&from).map_err(|e| e.to_string())?;
        let to = target
            .create_table(Some(&name), flags)
            .map_err(|e| e.to_string())?;
        let mut cursor = source.cursor(&from).map_err(|e| e.to_string())?;
        for row in cursor.iter_start::<Cow<'_, [u8]>, Cow<'_, [u8]>>() {
            let (key, value) = row.map_err(|e| e.to_string())?;
            target
                .put(&to, &key, &value, WriteFlags::UPSERT)
                .map_err(|e| e.to_string())?;
            crate::storage::migration::copied_record()?;
        }
    }
    Ok(())
}

impl MdbxStorage {
    #[cfg(test)]
    pub(crate) fn migration_temp_path(&self) -> PathBuf {
        self._temporary_directory.as_ref().unwrap().path.clone()
    }
    pub(crate) fn migration_fork(
        &mut self,
        manifest: &SchemaManifest,
    ) -> Result<(Self, u64), String> {
        self.backup_check_idle()?;
        self.begin_read_transaction()?;
        let result = (|| {
            let snapshot = self.read_transaction()?;
            let mut stage = Self::open(IN_MEMORY_DIRECTORY)?; // disk-backed private directory
            let txn = stage
                .state
                .database
                .begin_rw_txn()
                .map_err(|e| e.to_string())?;
            copy_tables(&snapshot.transaction, &txn)?;
            txn.commit().map_err(|e| e.to_string())?;
            stage.register_schemas(manifest)?;
            Ok((stage, snapshot.transaction.id()))
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
        // Pending reservations are not persisted yet. Reject rather than
        // invalidating another writer's allocation/schema assumptions.
        let mut ids = self.state.ids.lock().map_err(|e| e.to_string())?;
        if ids.pending.iter().any(|p| p.strong_count() != 0) {
            return Err("migration conflicts with an active writer".into());
        }
        let mut schemas = self.state.schemas.lock().map_err(|e| e.to_string())?;
        let txn = self
            .state
            .database
            .begin_rw_txn()
            .map_err(|e| e.to_string())?;
        if txn.id() != revision + 1 {
            return Err("migration source changed during preparation".into());
        }
        let snapshot = stage.read_transaction()?;
        copy_tables(&snapshot.transaction, &txn)?;
        let tables = open_tables(&txn)?;
        // Collection revisions must advance even when a migration empties a
        // collection without importing any replacement rows.
        let mut names = Vec::new();
        let mut cursor = txn
            .cursor(&tables.schema_collections)
            .map_err(|e| e.to_string())?;
        for row in cursor.iter_start::<Cow<'_, [u8]>, Cow<'_, [u8]>>() {
            let (_, value) = row.map_err(|e| e.to_string())?;
            names.push(decode_schema_record(&value)?.1.name);
        }
        drop(cursor);
        for name in names {
            bump_collection_revision(&txn, &tables, &name)?;
        }
        write_migration_version(&txn, &tables, version)?;
        drop(tables);
        txn.commit().map_err(|e| e.to_string())?;
        ids.committed.clear();
        schemas.clear();
        self.last_change_sets.clear();
        Ok(())
    }
}
