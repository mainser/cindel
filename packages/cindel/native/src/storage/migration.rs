//! Private migration workspaces. The live database is never rewritten by a
//! Dart callback. Publication is a single native transaction.
use super::*;

pub(crate) struct MigrationOrigin {
    pub storage: StorageBackend,
    pub revision: u64,
}

impl StorageBackend {
    pub(crate) fn migration_ids_page(
        &self,
        name: &str,
        after: Option<u64>,
        limit: usize,
    ) -> Result<Vec<u64>, String> {
        match self {
            Self::Sqlite(s) => s.migration_ids_page(name, after, limit),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(s) => s.document_ids_page(name, after, limit),
        }
    }

    pub(crate) fn migration_fork(
        &mut self,
        token: &str,
        manifest: &SchemaManifest,
    ) -> Result<(Self, u64), String> {
        match self {
            Self::Sqlite(s) => s
                .migration_fork(token, manifest)
                .map(|(s, r)| (Self::Sqlite(s), r)),
            #[cfg(feature = "mdbx")]
            Self::Mdbx(s) => s.migration_fork(manifest).map(|(s, r)| (Self::Mdbx(s), r)),
        }
    }

    pub(crate) fn migration_publish(
        &mut self,
        stage: &Self,
        revision: u64,
        version: u64,
    ) -> Result<(), String> {
        match (self, stage) {
            (Self::Sqlite(s), Self::Sqlite(stage)) => s.migration_publish(stage, revision, version),
            #[cfg(feature = "mdbx")]
            (Self::Mdbx(s), Self::Mdbx(stage)) => s.migration_publish(stage, revision, version),
            #[allow(unreachable_patterns)]
            _ => Err("migration backend mismatch".into()),
        }
    }
}

// Measures actual records copied and peak retained rows, not database size or
// engine-owned dirty pages. Each copy loop holds at most one record.
#[cfg(test)]
thread_local! { static COPIED: std::cell::Cell<usize> = const { std::cell::Cell::new(0) }; }
pub(crate) fn copied_record() -> Result<(), String> {
    #[cfg(test)]
    {
        COPIED.with(|n| n.set(n.get() + 1));
        FAIL_AFTER.with(|n| -> Result<(), String> {
            if n.get() == Some(0) {
                return Err("injected migration copy failure".into());
            }
            n.set(n.get().map(|v| v - 1));
            Ok(())
        })?;
    }
    Ok(())
}
#[cfg(test)]
thread_local! { static FAIL_AFTER: std::cell::Cell<Option<usize>> = const { std::cell::Cell::new(None) }; }
#[cfg(test)]
pub(crate) fn measure<T>(action: impl FnOnce() -> T) -> (T, usize) {
    COPIED.with(|n| n.set(0));
    let value = action();
    (value, COPIED.with(|n| n.get()))
}
#[cfg(test)]
pub(crate) fn fail_after(value: Option<usize>) {
    FAIL_AFTER.with(|n| n.set(value));
}
