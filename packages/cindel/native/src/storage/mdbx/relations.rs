use super::*;

const PAGE: usize = 128;

fn endpoint_prefix(collection: &str, id: u64) -> Vec<u8> {
    let mut key = Vec::new();
    push_relation_segment(&mut key, collection);
    key.extend_from_slice(&id.to_be_bytes());
    key
}

fn decode_edge(mut bytes: &[u8], reverse: bool) -> Result<LinkSave, String> {
    fn text(bytes: &mut &[u8]) -> Result<String, String> {
        let n = bytes.get(..4).ok_or("truncated relation key")?;
        let n = u32::from_be_bytes(n.try_into().unwrap()) as usize;
        *bytes = &bytes[4..];
        let value = std::str::from_utf8(bytes.get(..n).ok_or("truncated relation key")?)
            .map_err(|e| e.to_string())?
            .to_owned();
        *bytes = &bytes[n..];
        Ok(value)
    }
    fn id(bytes: &mut &[u8]) -> Result<u64, String> {
        let value = u64::from_be_bytes(
            bytes
                .get(..8)
                .ok_or("truncated relation key")?
                .try_into()
                .unwrap(),
        );
        *bytes = &bytes[8..];
        Ok(value)
    }
    let first = text(&mut bytes)?;
    let first_id = id(&mut bytes)?;
    let second = text(&mut bytes)?;
    let third = text(&mut bytes)?;
    let last_id = id(&mut bytes)?;
    if !bytes.is_empty() {
        return Err("invalid relation key".into());
    }
    Ok(if reverse {
        LinkSave {
            source_collection: second,
            source_id: last_id,
            link_name: third,
            target_collection: first,
            target_ids: vec![first_id],
        }
    } else {
        LinkSave {
            source_collection: first,
            source_id: first_id,
            link_name: second,
            target_collection: third,
            target_ids: vec![last_id],
        }
    })
}

fn edge_page(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    table: &Table<'_>,
    prefix: &[u8],
    after: Option<&[u8]>,
) -> Result<Vec<Vec<u8>>, String> {
    let mut cursor = transaction.cursor(table).map_err(|e| e.to_string())?;
    #[cfg(test)]
    super::super::relations::observe_resource();
    edge_page_with_cursor(&mut cursor, prefix, after)
}

fn edge_page_with_cursor(
    cursor: &mut libmdbx::Cursor<'_, RW>,
    prefix: &[u8],
    after: Option<&[u8]>,
) -> Result<Vec<Vec<u8>>, String> {
    let mut page = Vec::new();
    for item in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(after.unwrap_or(prefix)) {
        let (key, _) = item.map_err(|e| e.to_string())?;
        if !key.starts_with(prefix) {
            break;
        }
        if after == Some(key.as_ref()) {
            continue;
        }
        page.push(key.into_owned());
        if page.len() == PAGE {
            break;
        }
    }
    super::super::relations::observe_page(page.len());
    Ok(page)
}

fn remove_edge(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    edge: &LinkSave,
) -> Result<(), String> {
    ignore_not_found(transaction.del(
        &tables.relations_forward,
        relation_forward_key(
            &edge.source_collection,
            edge.source_id,
            &edge.link_name,
            &edge.target_collection,
            edge.target_ids[0],
        ),
        None,
    ))?;
    ignore_not_found(transaction.del(
        &tables.relations_backlink,
        relation_backlink_key(
            &edge.target_collection,
            edge.target_ids[0],
            &edge.source_collection,
            &edge.link_name,
            edge.source_id,
        ),
        None,
    ))?;
    let mut changed = tables.relation_changes.borrow_mut();
    changed.insert(edge.source_collection.clone());
    changed.insert(edge.target_collection.clone());
    Ok(())
}

pub(super) fn delete_relations(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    id: u64,
) -> Result<(), String> {
    if tables.preserve_relations.get() {
        return Ok(());
    }
    let prefix = endpoint_prefix(collection, id);
    for (table, reverse) in [
        (&tables.relations_forward, false),
        (&tables.relations_backlink, true),
    ] {
        loop {
            let page = edge_page(transaction, table, &prefix, None)?;
            if page.is_empty() {
                break;
            }
            for key in page {
                remove_edge(transaction, tables, &decode_edge(&key, reverse)?)?;
            }
        }
    }
    Ok(())
}

pub(super) fn delete_many_relations(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    ids: &[u64],
) -> Result<(), String> {
    if ids.is_empty() || tables.preserve_relations.get() {
        return Ok(());
    }
    let mut collection_prefix = Vec::new();
    push_relation_segment(&mut collection_prefix, collection);
    let mut prefix = collection_prefix.clone();
    for (table, reverse) in [
        (&tables.relations_forward, false),
        (&tables.relations_backlink, true),
    ] {
        let mut cursor = transaction.cursor(table).map_err(|e| e.to_string())?;
        #[cfg(test)]
        super::super::relations::observe_resource();
        #[cfg(test)]
        super::super::relations::observe_collection_check();
        let present = match cursor
            .iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(&collection_prefix)
            .next()
        {
            Some(result) => result
                .map_err(|e| e.to_string())?
                .0
                .starts_with(&collection_prefix),
            None => false,
        };
        if !present {
            continue;
        }
        for id in ids {
            prefix.truncate(collection_prefix.len());
            prefix.extend_from_slice(&id.to_be_bytes());
            loop {
                let page = edge_page_with_cursor(&mut cursor, &prefix, None)?;
                if page.is_empty() {
                    break;
                }
                for key in page {
                    remove_edge(transaction, tables, &decode_edge(&key, reverse)?)?;
                }
            }
        }
    }
    Ok(())
}

fn exists(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    collection: &str,
    id: u64,
) -> Result<bool, String> {
    let table = match open_documents_table(transaction, collection) {
        Ok(table) => table,
        Err(error) if error.contains("NOTFOUND") || error.contains("No matching") => {
            return Ok(false)
        }
        Err(error) => return Err(error),
    };
    Ok(transaction
        .get::<Cow<'_, [u8]>>(&table, &document_table_key(id))
        .map_err(|e| e.to_string())?
        .is_some())
}

// Scenario: A malformed legacy relation is reached after documents and earlier
// valid relation pages have already been deleted by a batch.
// Covers:
// - Native batch rollback on relation-decoding errors.
// - Restoration of documents, both relation tables, revisions and notifications.
// Expected: The error publishes no partial deletion or collection changes.
#[test]
fn relation_batch_rolls_back_documents_and_earlier_edges_on_failure() {
    // Arrange.
    let mut storage = MdbxStorage::open(":memory:").unwrap();
    for id in 1..=5 {
        storage.put("nodes", id, br#"{}"#).unwrap();
    }
    storage.seed_legacy_edges(256);
    storage
        .with_write_transaction(|txn, tables| {
            let mut invalid = endpoint_prefix("nodes", 3);
            invalid.push(255);
            txn.put(&tables.relations_forward, invalid, [], WriteFlags::UPSERT)
                .map_err(|e| e.to_string())?;
            Ok(())
        })
        .unwrap();
    storage.take_change_sets().unwrap();
    let before = storage.relation_counts();
    let revision = storage.collection_revision("nodes").unwrap();
    // Act.
    let result = storage.delete_many("nodes", &[1, 3]);
    // Assert.
    assert!(result.is_err());
    assert_eq!(storage.document_ids("nodes").unwrap(), vec![1, 2, 3, 4, 5]);
    assert_eq!(storage.relation_counts(), before);
    assert_eq!(storage.collection_revision("nodes").unwrap(), revision);
    assert!(storage.take_change_sets().unwrap().is_empty());
}

#[test]
fn orphan_cleanup_rolls_back_earlier_pages_on_invalid_legacy_metadata() {
    let mut s = MdbxStorage::open(":memory:").unwrap();
    for id in 1..=5 {
        s.put("nodes", id, br#"{}"#).unwrap();
    }
    s.seed_legacy_edges(256);
    s.with_write_transaction(|txn, t| {
        txn.put(&t.relations_forward, [255u8; 8], [], WriteFlags::UPSERT)
            .map_err(|e| e.to_string())?;
        Ok(())
    })
    .unwrap();
    s.take_change_sets().unwrap();
    let before = s.relation_counts();
    assert!(s.cleanup_orphan_links().is_err());
    assert_eq!(s.relation_counts(), before);
    assert!(s.take_change_sets().unwrap().is_empty());
}

impl MdbxStorage {
    #[cfg(test)]
    pub(crate) fn seed_legacy_edges(&self, count: usize) {
        self.with_write_transaction(|txn, tables| {
            for i in 0..count {
                for (source, target) in [(1, 2), (3, 4), (5, 999)] {
                    let name = format!("link{i:08}");
                    txn.put(
                        &tables.relations_forward,
                        relation_forward_key("nodes", source, &name, "nodes", target),
                        [],
                        WriteFlags::UPSERT,
                    )
                    .unwrap();
                    txn.put(
                        &tables.relations_backlink,
                        relation_backlink_key("nodes", target, "nodes", &name, source),
                        [],
                        WriteFlags::UPSERT,
                    )
                    .unwrap();
                }
            }
            Ok(())
        })
        .unwrap();
    }

    #[cfg(test)]
    pub(crate) fn relation_counts(&self) -> (usize, usize) {
        self.with_read_transaction(|txn, t| {
            Ok((
                txn.table_stat(&t.relations_forward).unwrap().entries(),
                txn.table_stat(&t.relations_backlink).unwrap().entries(),
            ))
        })
        .unwrap()
    }

    pub(super) fn staged_link_ids(
        &self,
        mut ids: Vec<u64>,
        source: &str,
        owner: u64,
        name: &str,
        target: &str,
        reverse: bool,
    ) -> Vec<u64> {
        let Some(staged) = self.active_write() else {
            return ids;
        };
        for operation in &staged.operations {
            match operation {
                MdbxWriteOperation::Delete { collection, id } => {
                    if collection == if reverse { target } else { source } && *id == owner {
                        ids.clear();
                    }
                    if collection == if reverse { source } else { target } {
                        ids.retain(|v| v != id);
                    }
                }
                MdbxWriteOperation::DeleteMany {
                    collection,
                    ids: deleted,
                } => {
                    if collection == if reverse { target } else { source }
                        && deleted.contains(&owner)
                    {
                        ids.clear();
                    }
                    if collection == if reverse { source } else { target } {
                        ids.retain(|v| !deleted.contains(v));
                    }
                }
                MdbxWriteOperation::ReplaceLinks { links }
                    if links.source_collection == source
                        && links.target_collection == target
                        && links.link_name == name =>
                {
                    if reverse {
                        ids.retain(|id| *id != links.source_id);
                        if links.target_ids.contains(&owner) {
                            ids.push(links.source_id);
                        }
                    } else if links.source_id == owner {
                        ids = links.target_ids.clone();
                    }
                }
                _ => {}
            }
        }
        ids.sort_unstable();
        ids.dedup();
        ids
    }

    pub(crate) fn cleanup_orphan_links(&mut self) -> Result<(u64, u64), String> {
        self.backup_check_idle()?;
        let result = self.with_write_transaction(|transaction, tables| {
            let (mut examined, mut removed) = (0, 0);
            let mut after: Option<Vec<u8>> = None;
            loop {
                let page = edge_page(
                    transaction,
                    &tables.relations_forward,
                    &[],
                    after.as_deref(),
                )?;
                if page.is_empty() {
                    break;
                }
                after = page.last().cloned();
                for key in page {
                    examined += 1;
                    let edge = decode_edge(&key, false)?;
                    if !exists(transaction, &edge.source_collection, edge.source_id)?
                        || !exists(transaction, &edge.target_collection, edge.target_ids[0])?
                    {
                        remove_edge(transaction, &tables, &edge)?;
                        removed += 1;
                    }
                }
            }
            Ok((examined, removed))
        })?;
        self.last_change_sets.clear();
        Ok(result)
    }
}
