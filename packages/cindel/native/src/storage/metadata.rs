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
