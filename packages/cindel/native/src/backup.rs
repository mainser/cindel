//! Disk-backed restore staging. No destination transaction is held while Dart
//! awaits an input stream. Publication runs synchronously in one engine transaction.
use crate::storage::{DocumentWrite, LinkSave, NativeDocumentValue, NativeDocumentWrite};
use crate::wire::{self, WireNativeDocumentValue, WireValue};
use rusqlite::{params, Connection};

pub(crate) struct BackupSpool {
    pub connection: Connection,
    pub collections: Vec<(String, Option<u64>)>,
    pub migration_version: u64,
    // Fields drop in declaration order: close SQLite before removing its file.
    _path: TemporaryBackupPath,
}

pub(crate) struct TemporaryBackupPath(String);

impl BackupSpool {
    pub fn document_count(&self, collection: &str) -> Result<u64, String> {
        self.connection
            .query_row(
                "SELECT count(*) FROM ids WHERE collection=?1",
                [collection],
                |r| r.get::<_, i64>(0),
            )
            .map(|n| n as u64)
            .map_err(|e| e.to_string())
    }

    pub fn open(
        token: &str,
        collections: Vec<(String, Option<u64>)>,
        migration_version: u64,
    ) -> Result<Self, String> {
        let path = TemporaryBackupPath::new(token, "restore")?;
        #[cfg(not(target_family = "wasm"))]
        let connection = Connection::open(&path.0).map_err(|e| e.to_string())?;
        #[cfg(target_family = "wasm")]
        let connection = Connection::open_with_flags_and_vfs(
            &path.0,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_WRITE | rusqlite::OpenFlags::SQLITE_OPEN_CREATE,
            "opfs-sahpool",
        )
        .map_err(|e| e.to_string())?;
        let spool = Self {
            connection,
            collections,
            migration_version,
            _path: path,
        };
        spool.connection.execute_batch("PRAGMA cache_size=-1024; PRAGMA temp_store=FILE;
            CREATE TABLE batches (seq INTEGER PRIMARY KEY, collection TEXT NOT NULL, kind INTEGER NOT NULL, payload BLOB NOT NULL);
            CREATE TABLE ids (collection TEXT NOT NULL, id INTEGER NOT NULL, PRIMARY KEY(collection,id)) WITHOUT ROWID;
            CREATE TABLE edges (source TEXT NOT NULL, id INTEGER NOT NULL, name TEXT NOT NULL, target TEXT NOT NULL, target_id INTEGER NOT NULL,
                PRIMARY KEY(source,id,name,target,target_id)) WITHOUT ROWID;").map_err(|e| e.to_string())?;
        Ok(spool)
    }

    pub fn stage(&mut self, collection: &str, native: bool, payload: &[u8]) -> Result<(), String> {
        if !self.collections.iter().any(|(name, _)| name == collection) {
            return Err("unknown restore collection".into());
        }
        let ids: Vec<u64> = if native {
            native_documents(payload)?.iter().map(|d| d.id).collect()
        } else {
            binary_documents(payload)?.iter().map(|d| d.id).collect()
        };
        let txn = self.connection.transaction().map_err(|e| e.to_string())?;
        for id in ids {
            let id = i64::try_from(id).map_err(|_| "invalid backup document id")?;
            txn.execute("INSERT INTO ids VALUES (?1,?2)", params![collection, id])
                .map_err(|e| format!("duplicate/invalid backup id: {e}"))?;
        }
        txn.execute(
            "INSERT INTO batches(collection,kind,payload) VALUES (?1,?2,?3)",
            params![collection, native as i32, payload],
        )
        .map_err(|e| e.to_string())?;
        txn.commit().map_err(|e| e.to_string())
    }

    pub fn stage_edges(&self, links: &[(LinkSave, bool)]) -> Result<(), String> {
        let transaction = self
            .connection
            .unchecked_transaction()
            .map_err(|e| e.to_string())?;
        for (link, many) in links {
            self.stage_edge(link, *many)?;
        }
        transaction.commit().map_err(|e| e.to_string())
    }

    fn stage_edge(&self, link: &LinkSave, many: bool) -> Result<(), String> {
        if !self
            .collections
            .iter()
            .any(|(n, _)| n == &link.source_collection)
            || !self
                .collections
                .iter()
                .any(|(n, _)| n == &link.target_collection)
        {
            return Err("backup link refers to an omitted collection".into());
        }
        if !many {
            let count: i64 = self
                .connection
                .query_row(
                    "SELECT count(*) FROM edges WHERE source=?1 AND id=?2 AND name=?3",
                    params![
                        link.source_collection,
                        link.source_id as i64,
                        link.link_name
                    ],
                    |r| r.get(0),
                )
                .map_err(|e| e.to_string())?;
            if count != 0 {
                return Err("multiple targets for a to-one backup link".into());
            }
        }
        self.connection
            .execute(
                "INSERT INTO edges VALUES (?1,?2,?3,?4,?5)",
                params![
                    link.source_collection,
                    link.source_id as i64,
                    link.link_name,
                    link.target_collection,
                    link.target_ids[0] as i64
                ],
            )
            .map_err(|e| format!("duplicate/invalid backup link: {e}"))?;
        Ok(())
    }

    pub fn documents(
        &self,
        mut visit: impl FnMut(&str, bool, &[u8]) -> Result<(), String>,
    ) -> Result<(), String> {
        let mut statement = self
            .connection
            .prepare("SELECT collection,kind,payload FROM batches ORDER BY seq")
            .map_err(|e| e.to_string())?;
        let mut rows = statement.query([]).map_err(|e| e.to_string())?;
        while let Some(row) = rows.next().map_err(|e| e.to_string())? {
            let name: String = row.get(0).map_err(|e| e.to_string())?;
            let native: bool = row.get(1).map_err(|e| e.to_string())?;
            let payload = row
                .get_ref(2)
                .map_err(|e| e.to_string())?
                .as_blob()
                .map_err(|e| e.to_string())?;
            visit(&name, native, payload)?;
        }
        Ok(())
    }

    pub fn edges(
        &self,
        mut visit: impl FnMut(&LinkSave) -> Result<(), String>,
    ) -> Result<(), String> {
        let mut statement = self
            .connection
            .prepare("SELECT source,id,name,target,target_id FROM edges")
            .map_err(|e| e.to_string())?;
        let mut rows = statement.query([]).map_err(|e| e.to_string())?;
        while let Some(row) = rows.next().map_err(|e| e.to_string())? {
            let link = LinkSave {
                source_collection: row.get(0).map_err(|e| e.to_string())?,
                source_id: row.get::<_, i64>(1).map_err(|e| e.to_string())? as u64,
                link_name: row.get(2).map_err(|e| e.to_string())?,
                target_collection: row.get(3).map_err(|e| e.to_string())?,
                target_ids: vec![row.get::<_, i64>(4).map_err(|e| e.to_string())? as u64],
            };
            visit(&link)?;
        }
        Ok(())
    }
}

impl TemporaryBackupPath {
    pub(crate) fn new(token: &str, purpose: &str) -> Result<Self, String> {
        if token.is_empty()
            || token.len() > 100
            || !token
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'-')
        {
            return Err("invalid staging token".into());
        }
        #[cfg(not(target_family = "wasm"))]
        let path = {
            let directory = std::env::temp_dir().join(format!("cindel-{purpose}-{token}"));
            std::fs::create_dir(&directory).map_err(|e| e.to_string())?;
            directory
                .join("cindel.sqlite")
                .to_string_lossy()
                .into_owned()
        };
        #[cfg(target_family = "wasm")]
        let path = format!("/cindel-{purpose}-{token}.sqlite");
        Ok(Self(path))
    }

    pub(crate) fn database_directory(&self) -> &str {
        #[cfg(not(target_family = "wasm"))]
        {
            std::path::Path::new(&self.0)
                .parent()
                .unwrap()
                .to_str()
                .unwrap()
        }
        #[cfg(target_family = "wasm")]
        {
            &self.0
        }
    }
}

impl Drop for TemporaryBackupPath {
    fn drop(&mut self) {
        #[cfg(not(target_family = "wasm"))]
        {
            let _ = std::fs::remove_file(&self.0);
            if let Some(parent) = std::path::Path::new(&self.0).parent() {
                let _ = std::fs::remove_dir(parent);
            }
        }
        #[cfg(target_family = "wasm")]
        unsafe {
            let name = std::ffi::CString::new("opfs-sahpool").unwrap();
            let path = std::ffi::CString::new(self.0.as_str()).unwrap();
            let vfs = rusqlite::ffi::sqlite3_vfs_find(name.as_ptr());
            if !vfs.is_null() {
                if let Some(delete) = (*vfs).xDelete {
                    delete(vfs, path.as_ptr(), 0);
                }
            }
        }
    }
}

pub(crate) fn binary_documents(bytes: &[u8]) -> Result<Vec<DocumentWrite>, String> {
    Ok(wire::decode_document_write_batch(bytes)?
        .into_iter()
        .map(|d| DocumentWrite {
            id: d.id,
            bytes: d.bytes,
            indexes: vec![],
        })
        .collect())
}
pub(crate) fn field<'a>(
    fields: &'a [(String, WireValue)],
    name: &str,
) -> Result<&'a WireValue, String> {
    fields
        .iter()
        .find(|(n, _)| n == name)
        .map(|(_, v)| v)
        .ok_or_else(|| format!("missing backup argument {name}"))
}
pub(crate) fn string(value: &WireValue) -> Result<&str, String> {
    if let WireValue::String(v) = value {
        Ok(v)
    } else {
        Err("expected backup string".into())
    }
}
pub(crate) fn integer(value: &WireValue) -> Result<u64, String> {
    if let WireValue::Int(v) = value {
        u64::try_from(*v).map_err(|_| "negative backup integer".into())
    } else {
        Err("expected backup integer".into())
    }
}

pub(crate) fn native_documents(bytes: &[u8]) -> Result<Vec<NativeDocumentWrite>, String> {
    wire::decode_native_document_write_batch(bytes)?
        .into_iter()
        .map(|d| {
            Ok(NativeDocumentWrite {
                id: d.id,
                values: d
                    .values
                    .into_iter()
                    .map(|v| match v {
                        WireNativeDocumentValue::Null => Ok(NativeDocumentValue::Null),
                        WireNativeDocumentValue::Bool(v) => Ok(NativeDocumentValue::Bool(v)),
                        WireNativeDocumentValue::Int(v) => Ok(NativeDocumentValue::Int(v)),
                        WireNativeDocumentValue::Double(v) if v.is_finite() => {
                            Ok(NativeDocumentValue::Double(v))
                        }
                        WireNativeDocumentValue::Bytes(v) => Ok(NativeDocumentValue::Bytes(v)),
                        _ => Err("invalid backup number".into()),
                    })
                    .collect::<Result<Vec<_>, String>>()?,
            })
        })
        .collect()
}
