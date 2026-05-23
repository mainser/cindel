#![allow(dead_code)]

use serde::{Deserialize, Serialize};

use super::{IndexValue, SchemaManifest, StorageEngine};

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum StorageLayoutVersion {
    SqliteV1,
    MdbxV1,
    MdbxV2,
}

impl StorageLayoutVersion {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::SqliteV1 => "sqlite-v1",
            Self::MdbxV1 => "mdbx-v1",
            Self::MdbxV2 => "mdbx-v2",
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DocumentFormatVersion {
    JsonV1,
    BinaryV1,
}

impl DocumentFormatVersion {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::JsonV1 => "json-v1",
            Self::BinaryV1 => "binary-v1",
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct StorageMetadata {
    pub layout: StorageLayoutVersion,
    pub document_format: DocumentFormatVersion,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct StorageMigrationTarget {
    pub layout: StorageLayoutVersion,
    pub document_format: DocumentFormatVersion,
}

impl From<StorageMetadata> for StorageMigrationTarget {
    fn from(value: StorageMetadata) -> Self {
        Self {
            layout: value.layout,
            document_format: value.document_format,
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum MigrationAction {
    RewriteStorageLayout {
        from: StorageLayoutVersion,
        to: StorageLayoutVersion,
    },
    RewriteDocumentFormat {
        from: DocumentFormatVersion,
        to: DocumentFormatVersion,
    },
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct StorageMigrationPlan {
    pub current: StorageMetadata,
    pub target: StorageMigrationTarget,
    pub requires_explicit_migration: bool,
    pub actions: Vec<MigrationAction>,
}

impl StorageMigrationPlan {
    pub fn new(current: StorageMetadata, target: StorageMigrationTarget) -> Self {
        let mut actions = Vec::new();
        if current.layout != target.layout {
            actions.push(MigrationAction::RewriteStorageLayout {
                from: current.layout,
                to: target.layout,
            });
        }
        if current.document_format != target.document_format {
            actions.push(MigrationAction::RewriteDocumentFormat {
                from: current.document_format,
                to: target.document_format,
            });
        }
        Self {
            current,
            target,
            requires_explicit_migration: !actions.is_empty(),
            actions,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum IndexVerificationCheck {
    Equal {
        collection: String,
        index: String,
        value: IndexValue,
        expected_ids: Vec<u64>,
    },
    Range {
        collection: String,
        index: String,
        lower: Option<IndexValue>,
        upper: Option<IndexValue>,
        expected_ids: Vec<u64>,
    },
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CollectionVerification {
    pub collection: String,
    pub document_count: usize,
    pub schema_version: Option<u64>,
    pub collection_revision: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StorageVerificationReport {
    pub metadata: StorageMetadata,
    pub collections: Vec<CollectionVerification>,
}

impl StorageVerificationReport {
    pub fn from_storage<S>(
        storage: &S,
        manifest: &SchemaManifest,
        checks: &[IndexVerificationCheck],
    ) -> Result<Self, String>
    where
        S: StorageEngine + ?Sized,
    {
        for check in checks {
            match check {
                IndexVerificationCheck::Equal {
                    collection,
                    index,
                    value,
                    expected_ids,
                } => {
                    let ids = storage.query_index_equal(collection, index, value)?;
                    if ids != *expected_ids {
                        return Err(format!(
                            "index check `{collection}.{index}` expected {:?}, got {:?}",
                            expected_ids, ids
                        ));
                    }
                }
                IndexVerificationCheck::Range {
                    collection,
                    index,
                    lower,
                    upper,
                    expected_ids,
                } => {
                    let ids = storage.query_index_range(
                        collection,
                        index,
                        lower.as_ref(),
                        upper.as_ref(),
                    )?;
                    if ids != *expected_ids {
                        return Err(format!(
                            "range index check `{collection}.{index}` expected {:?}, got {:?}",
                            expected_ids, ids
                        ));
                    }
                }
            }
        }

        let mut collections = Vec::with_capacity(manifest.collections.len());
        for collection in &manifest.collections {
            collections.push(CollectionVerification {
                collection: collection.name.clone(),
                document_count: storage.document_ids(&collection.name)?.len(),
                schema_version: storage.schema_version(&collection.name)?,
                collection_revision: storage.collection_revision(&collection.name)?,
            });
        }
        Ok(Self {
            metadata: storage.storage_metadata()?,
            collections,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plans_noop_when_versions_match() {
        let current = StorageMetadata {
            layout: StorageLayoutVersion::MdbxV1,
            document_format: DocumentFormatVersion::JsonV1,
        };

        let plan = StorageMigrationPlan::new(current, current.into());

        assert!(!plan.requires_explicit_migration);
        assert!(plan.actions.is_empty());
    }

    #[test]
    fn plans_layout_and_document_format_rewrites() {
        let current = StorageMetadata {
            layout: StorageLayoutVersion::MdbxV1,
            document_format: DocumentFormatVersion::JsonV1,
        };
        let target = StorageMigrationTarget {
            layout: StorageLayoutVersion::MdbxV2,
            document_format: DocumentFormatVersion::BinaryV1,
        };

        let plan = StorageMigrationPlan::new(current, target);

        assert!(plan.requires_explicit_migration);
        assert_eq!(
            plan.actions,
            vec![
                MigrationAction::RewriteStorageLayout {
                    from: StorageLayoutVersion::MdbxV1,
                    to: StorageLayoutVersion::MdbxV2,
                },
                MigrationAction::RewriteDocumentFormat {
                    from: DocumentFormatVersion::JsonV1,
                    to: DocumentFormatVersion::BinaryV1,
                },
            ]
        );
    }
}
