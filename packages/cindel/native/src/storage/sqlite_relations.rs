use super::*;

const PAGE: usize = 128;
type Edge = (String, i64, String, String, i64);

pub(super) fn initialize(connection: &Connection) -> Result<(), String> {
    connection.execute_batch("CREATE TEMP TABLE IF NOT EXISTS cindel_relation_changes (collection TEXT PRIMARY KEY) WITHOUT ROWID;").map_err(sqlite_diagnostic)
}

fn row_edge(row: &Row<'_>) -> rusqlite::Result<Edge> {
    Ok((
        row.get(0)?,
        row.get(1)?,
        row.get(2)?,
        row.get(3)?,
        row.get(4)?,
    ))
}

fn remove_edge(connection: &Connection, edge: &Edge) -> Result<(), String> {
    connection.execute("DELETE FROM cindel_relations WHERE source_collection=?1 AND source_id=?2 AND link_name=?3 AND target_collection=?4 AND target_id=?5", params![edge.0,edge.1,edge.2,edge.3,edge.4]).map_err(|e|e.to_string())?;
    for name in [&edge.0, &edge.3] {
        mark_change(connection, name)?;
    }
    Ok(())
}

pub(super) fn mark_change(connection: &Connection, name: &str) -> Result<(), String> {
    revisions::mark(connection, name)?;
    connection
        .execute(
            "INSERT OR IGNORE INTO temp.cindel_relation_changes VALUES (?1)",
            [name],
        )
        .map_err(sqlite_diagnostic)?;
    Ok(())
}

pub(super) fn delete_relations(
    connection: &Connection,
    collection: &str,
    id: i64,
) -> Result<(), String> {
    for endpoint in ["source", "target"] {
        // Both predicates use an existing leading index pair; never scan unrelated edges.
        let sql = format!("SELECT source_collection,source_id,link_name,target_collection,target_id FROM cindel_relations WHERE {endpoint}_collection=?1 AND {endpoint}_id=?2 LIMIT {PAGE}");
        loop {
            let mut statement = connection.prepare(&sql).map_err(sqlite_diagnostic)?;
            let page = statement
                .query_map(params![collection, id], row_edge)
                .map_err(sqlite_diagnostic)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(sqlite_diagnostic)?;
            #[cfg(test)]
            assert_eq!(
                statement.get_status(rusqlite::StatementStatus::FullscanStep),
                0,
                "relation endpoint lookup must use its index"
            );
            drop(statement);
            super::super::relations::observe_page(page.len());
            if page.is_empty() {
                break;
            }
            for edge in page {
                remove_edge(connection, &edge)?;
            }
        }
    }
    Ok(())
}

fn exists(connection: &Connection, collection: &str, id: i64) -> Result<bool, String> {
    if table_exists(connection, collection)? {
        // Names stored by Cindel are validated, but quote legacy metadata defensively.
        let name = collection.replace('"', "\"\"");
        if connection
            .query_row(
                &format!("SELECT EXISTS(SELECT 1 FROM \"{name}\" WHERE _rowid_=?1)"),
                [id],
                |r| r.get::<_, bool>(0),
            )
            .map_err(sqlite_diagnostic)?
        {
            return Ok(true);
        }
    }
    if table_exists(connection, "documents")? {
        return connection
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM documents WHERE collection=?1 AND id=?2)",
                params![collection, id],
                |r| r.get(0),
            )
            .map_err(sqlite_diagnostic);
    }
    Ok(false)
}

#[test]
fn orphan_cleanup_rolls_back_earlier_pages_and_notifications_on_storage_error() {
    let mut s = SqliteStorage::open(":memory:").unwrap();
    for id in 1..=5 {
        s.put("nodes", id, br#"{}"#).unwrap();
    }
    s.seed_legacy_edges(256);
    s.take_change_sets().unwrap();
    s.connection.execute_batch("CREATE TEMP TRIGGER fail_cleanup BEFORE DELETE ON cindel_relations WHEN OLD.source_id=5 AND OLD.link_name='link00000199' BEGIN SELECT RAISE(ABORT,'injected storage failure'); END;").unwrap();
    let before = s.relation_counts();
    assert!(s.cleanup_orphan_links().is_err());
    assert_eq!(s.relation_counts(), before);
    assert!(s.take_change_sets().unwrap().is_empty());
    s.connection
        .execute_batch("DROP TRIGGER fail_cleanup")
        .unwrap();
    assert_eq!(s.cleanup_orphan_links().unwrap(), (768, 256));
}

impl SqliteStorage {
    #[cfg(test)]
    pub(crate) fn seed_legacy_edges(&mut self, count: usize) {
        let txn = self.connection.transaction().unwrap();
        {
            let mut statement = txn
                .prepare("INSERT INTO cindel_relations VALUES ('nodes',?1,?2,'nodes',?3)")
                .unwrap();
            for i in 0..count {
                for (source, target) in [(1, 2), (3, 4), (5, 999)] {
                    statement
                        .execute(params![source, format!("link{i:08}"), target])
                        .unwrap();
                }
            }
        }
        txn.commit().unwrap();
    }

    #[cfg(test)]
    pub(crate) fn relation_counts(&self) -> (usize, usize) {
        let count = self
            .connection
            .query_row("SELECT count(*) FROM cindel_relations", [], |r| {
                r.get::<_, i64>(0)
            })
            .unwrap() as usize;
        (count, count)
    }

    pub(crate) fn cleanup_orphan_links(&mut self) -> Result<(u64, u64), String> {
        self.backup_check_idle()?;
        let txn = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(sqlite_diagnostic)?;
        let (mut examined, mut removed) = (0, 0);
        let mut after: Option<Edge> = None;
        loop {
            let base = "SELECT source_collection,source_id,link_name,target_collection,target_id FROM cindel_relations";
            let order = format!(" ORDER BY source_collection,source_id,link_name,target_collection,target_id LIMIT {PAGE}");
            let page = if let Some(e) = &after {
                txn.prepare(&format!("{base} WHERE (source_collection,source_id,link_name,target_collection,target_id) > (?1,?2,?3,?4,?5){order}")).map_err(|e|e.to_string())?
                    .query_map(params![e.0,e.1,e.2,e.3,e.4],row_edge).map_err(|e|e.to_string())?.collect::<Result<Vec<_>,_>>().map_err(|e|e.to_string())?
            } else {
                txn.prepare(&format!("{base}{order}"))
                    .map_err(sqlite_diagnostic)?
                    .query_map([], row_edge)
                    .map_err(sqlite_diagnostic)?
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(sqlite_diagnostic)?
            };
            super::super::relations::observe_page(page.len());
            if page.is_empty() {
                break;
            }
            after = page.last().cloned();
            for edge in page {
                examined += 1;
                if !exists(&txn, &edge.0, edge.1)? || !exists(&txn, &edge.3, edge.4)? {
                    remove_edge(&txn, &edge)?;
                    removed += 1;
                }
            }
        }
        revisions::flush(&txn)?;
        txn.commit().map_err(sqlite_diagnostic)?;
        self.last_change_sets.clear();
        Ok((examined, removed))
    }

    pub(super) fn take_relation_changes(&mut self) -> Result<(), String> {
        if self.active_transaction.is_some() {
            return Ok(());
        }
        let names = self
            .connection
            .prepare("SELECT collection FROM temp.cindel_relation_changes")
            .map_err(sqlite_diagnostic)?
            .query_map([], |r| r.get::<_, String>(0))
            .map_err(sqlite_diagnostic)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(sqlite_diagnostic)?;
        for name in names {
            let current = self.collection_revision(&name)?;
            self.last_change_sets.retain(|c| c.collection != name);
            self.last_change_sets.push(StorageChangeSet {
                collection: name,
                revision: current,
                document_ids: vec![],
            });
        }
        self.connection
            .execute("DELETE FROM temp.cindel_relation_changes", [])
            .map_err(sqlite_diagnostic)?;
        Ok(())
    }
}
