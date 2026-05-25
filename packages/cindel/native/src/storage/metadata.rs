#![allow(dead_code)]

use serde::{Deserialize, Serialize};

use crate::wire::{
    decode_index_entry_list, decode_schema_manifest, encode_index_entry_list,
    encode_schema_manifest, WireCollectionSchema, WireFieldSchema, WireIndexEntry, WireIndexSchema,
    WireIndexValue, WireSchemaManifest,
};

use super::{
    CollectionSchemaManifest, CompositeIndexSchemaManifest, FieldSchemaManifest, IndexEntry,
    IndexValue, SchemaManifest, StorageEngine,
};

const WIRE_SCHEMA_VERSION: u32 = 1;
const SCHEMA_RECORD_MAGIC: &[u8; 4] = b"CSMR";
const SCHEMA_RECORD_VERSION: u32 = 1;
const JSON_METADATA_ERROR: &str =
    "JSON-era preview metadata is incompatible with Cindel binary metadata; recreate the database";

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum StorageLayoutVersion {
    SqliteV1,
    MdbxV1,
    MdbxV2,
    MdbxV3,
    MdbxV4,
}

impl StorageLayoutVersion {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::SqliteV1 => "sqlite-v1",
            Self::MdbxV1 => "mdbx-v1",
            Self::MdbxV2 => "mdbx-v2",
            Self::MdbxV3 => "mdbx-v3",
            Self::MdbxV4 => "mdbx-v4",
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum DocumentFormatVersion {
    JsonV1,
    BinaryV1,
    BinaryV2,
}

impl DocumentFormatVersion {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::JsonV1 => "json-v1",
            Self::BinaryV1 => "binary-v1",
            Self::BinaryV2 => "binary-v2",
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum SchemaMetadataVersion {
    BinaryV1,
}

impl SchemaMetadataVersion {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::BinaryV1 => "binary-v1",
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct StorageMetadata {
    pub layout: StorageLayoutVersion,
    pub document_format: DocumentFormatVersion,
    pub schema_metadata_format: SchemaMetadataVersion,
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

pub(crate) fn decode_wire_schema_manifest(bytes: &[u8]) -> Result<SchemaManifest, String> {
    let manifest = decode_schema_manifest(bytes)?;
    if manifest.version != WIRE_SCHEMA_VERSION {
        return Err(format!(
            "unsupported schema manifest version `{}`",
            manifest.version
        ));
    }
    Ok(SchemaManifest {
        collections: manifest
            .collections
            .into_iter()
            .map(collection_from_wire)
            .collect(),
    })
}

pub(crate) fn encode_schema_record(
    version: u64,
    schema: &CollectionSchemaManifest,
) -> Result<Vec<u8>, String> {
    let manifest = WireSchemaManifest {
        version: WIRE_SCHEMA_VERSION,
        collections: vec![collection_to_wire(schema)],
    };
    let schema_bytes = encode_schema_manifest(&manifest)?;
    let schema_len = u32::try_from(schema_bytes.len())
        .map_err(|_| "schema metadata payload exceeds u32::MAX".to_string())?;
    let mut bytes = Vec::with_capacity(20 + schema_bytes.len());
    bytes.extend_from_slice(SCHEMA_RECORD_MAGIC);
    bytes.extend_from_slice(&SCHEMA_RECORD_VERSION.to_le_bytes());
    bytes.extend_from_slice(&version.to_le_bytes());
    bytes.extend_from_slice(&schema_len.to_le_bytes());
    bytes.extend_from_slice(&schema_bytes);
    Ok(bytes)
}

pub(crate) fn decode_schema_record(
    bytes: &[u8],
) -> Result<(u64, CollectionSchemaManifest), String> {
    reject_json_metadata(bytes)?;
    let minimum_len = SCHEMA_RECORD_MAGIC.len() + 4 + 8 + 4;
    if bytes.len() < minimum_len {
        return Err("schema metadata is truncated".into());
    }
    if &bytes[..SCHEMA_RECORD_MAGIC.len()] != SCHEMA_RECORD_MAGIC {
        return Err("schema metadata has an unknown magic header".into());
    }
    let record_version = read_u32(bytes, 4)?;
    if record_version != SCHEMA_RECORD_VERSION {
        return Err(format!(
            "unsupported schema metadata version `{record_version}`"
        ));
    }
    let version = read_u64(bytes, 8)?;
    let schema_len = read_u32(bytes, 16)? as usize;
    let payload_start = minimum_len;
    let payload_end = payload_start
        .checked_add(schema_len)
        .ok_or_else(|| "schema metadata length overflow".to_string())?;
    if payload_end != bytes.len() {
        return Err("schema metadata length does not match payload".into());
    }
    let manifest = decode_wire_schema_manifest(&bytes[payload_start..payload_end])?;
    let mut collections = manifest.collections;
    if collections.len() != 1 {
        return Err("schema metadata record must contain exactly one collection".into());
    }
    Ok((version, collections.remove(0)))
}

pub(crate) fn encode_index_entry_metadata(
    document_id: u64,
    entries: &[IndexEntry],
) -> Result<Vec<u8>, String> {
    let wire_entries = entries
        .iter()
        .map(|entry| WireIndexEntry {
            document_id,
            index_name: entry.name.clone(),
            value: index_value_to_wire(&entry.value),
        })
        .collect::<Vec<_>>();
    encode_index_entry_list(&wire_entries)
}

pub(crate) fn decode_index_entry_metadata(bytes: &[u8]) -> Result<Vec<IndexEntry>, String> {
    reject_json_metadata(bytes)?;
    decode_index_entry_list(bytes)?
        .into_iter()
        .map(|entry| {
            Ok(IndexEntry {
                name: entry.index_name,
                value: index_value_from_wire(entry.value)?,
            })
        })
        .collect()
}

fn collection_to_wire(collection: &CollectionSchemaManifest) -> WireCollectionSchema {
    WireCollectionSchema {
        name: collection.name.clone(),
        id_field: collection.id_field.clone(),
        fields: collection
            .fields
            .iter()
            .map(|field| WireFieldSchema {
                name: field.name.clone(),
                type_name: field.dart_type.clone(),
                binary_type: field.binary_type.clone(),
                index_type: field.index_type.clone(),
                is_id: field.is_id,
                is_indexed: field.is_indexed,
                is_unique: field.is_index_unique,
                is_nullable: field.dart_type.ends_with('?'),
                case_sensitive: field.index_case_sensitive,
            })
            .collect(),
        indexes: collection
            .composite_indexes
            .iter()
            .map(|index| WireIndexSchema {
                name: index.name.clone(),
                fields: index.fields.clone(),
                is_unique: index.is_unique,
                case_sensitive: index.case_sensitive,
            })
            .collect(),
    }
}

fn collection_from_wire(collection: WireCollectionSchema) -> CollectionSchemaManifest {
    CollectionSchemaManifest {
        name: collection.name,
        id_field: collection.id_field,
        fields: collection
            .fields
            .into_iter()
            .map(|field| FieldSchemaManifest {
                name: field.name,
                dart_type: field.type_name,
                binary_type: field.binary_type,
                is_id: field.is_id,
                is_indexed: field.is_indexed,
                is_index_unique: field.is_unique,
                index_case_sensitive: field.case_sensitive,
                index_type: field.index_type,
            })
            .collect(),
        composite_indexes: collection
            .indexes
            .into_iter()
            .map(|index| CompositeIndexSchemaManifest {
                name: index.name,
                fields: index.fields,
                is_unique: index.is_unique,
                case_sensitive: index.case_sensitive,
            })
            .collect(),
    }
}

fn index_value_to_wire(value: &IndexValue) -> WireIndexValue {
    match value {
        IndexValue::Bool(value) => WireIndexValue::Bool(*value),
        IndexValue::Int(value) => WireIndexValue::Int(*value),
        IndexValue::Double(value) => WireIndexValue::Double(*value),
        IndexValue::String(value) => WireIndexValue::String(value.clone()),
        IndexValue::List(values) => {
            WireIndexValue::List(values.iter().map(index_value_to_wire).collect())
        }
    }
}

fn index_value_from_wire(value: WireIndexValue) -> Result<IndexValue, String> {
    match value {
        WireIndexValue::Null => Err("index metadata cannot contain null index values".into()),
        WireIndexValue::Bool(value) => Ok(IndexValue::Bool(value)),
        WireIndexValue::Int(value) => Ok(IndexValue::Int(value)),
        WireIndexValue::Double(value) if value.is_finite() => Ok(IndexValue::Double(value)),
        WireIndexValue::Double(_) => Err("index metadata double values must be finite".into()),
        WireIndexValue::String(value) => Ok(IndexValue::String(value)),
        WireIndexValue::List(values) => values
            .into_iter()
            .map(index_value_from_wire)
            .collect::<Result<Vec<_>, _>>()
            .map(IndexValue::List),
    }
}

fn reject_json_metadata(bytes: &[u8]) -> Result<(), String> {
    match bytes
        .iter()
        .copied()
        .find(|byte| !byte.is_ascii_whitespace())
    {
        Some(b'{') | Some(b'[') => Err(JSON_METADATA_ERROR.into()),
        _ => Ok(()),
    }
}

fn read_u32(bytes: &[u8], offset: usize) -> Result<u32, String> {
    let slice = bytes
        .get(offset..offset + 4)
        .ok_or_else(|| "schema metadata is truncated".to_string())?;
    let mut value = [0_u8; 4];
    value.copy_from_slice(slice);
    Ok(u32::from_le_bytes(value))
}

fn read_u64(bytes: &[u8], offset: usize) -> Result<u64, String> {
    let slice = bytes
        .get(offset..offset + 8)
        .ok_or_else(|| "schema metadata is truncated".to_string())?;
    let mut value = [0_u8; 8];
    value.copy_from_slice(slice);
    Ok(u64::from_le_bytes(value))
}

pub(crate) fn parse_schema_metadata_format(value: &str) -> Result<SchemaMetadataVersion, String> {
    match value {
        "binary-v1" => Ok(SchemaMetadataVersion::BinaryV1),
        _ => Err(format!("unknown schema metadata format version `{value}`")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn user_schema() -> CollectionSchemaManifest {
        CollectionSchemaManifest {
            name: "users".to_string(),
            id_field: "id".to_string(),
            fields: vec![
                FieldSchemaManifest {
                    name: "id".to_string(),
                    dart_type: "int".to_string(),
                    binary_type: "int".to_string(),
                    is_id: true,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
                FieldSchemaManifest {
                    name: "email".to_string(),
                    dart_type: "String".to_string(),
                    binary_type: "string".to_string(),
                    is_id: false,
                    is_indexed: true,
                    is_index_unique: true,
                    index_case_sensitive: false,
                    index_type: "hash".to_string(),
                },
            ],
            composite_indexes: vec![CompositeIndexSchemaManifest {
                name: "by_email_id".to_string(),
                fields: vec!["email".to_string(), "id".to_string()],
                is_unique: true,
                case_sensitive: false,
            }],
        }
    }

    #[test]
    fn round_trips_schema_record_metadata() {
        let schema = user_schema();
        let bytes = encode_schema_record(3, &schema).unwrap();
        let (version, decoded) = decode_schema_record(&bytes).unwrap();

        assert_eq!(version, 3);
        assert_eq!(decoded, schema);
    }

    #[test]
    fn rejects_future_schema_record_versions() {
        let schema = user_schema();
        let mut bytes = encode_schema_record(1, &schema).unwrap();
        bytes[4..8].copy_from_slice(&2_u32.to_le_bytes());

        let error = decode_schema_record(&bytes).unwrap_err();

        assert!(error.contains("unsupported schema metadata version"));
    }

    #[test]
    fn rejects_future_wire_schema_manifest_versions() {
        let manifest = WireSchemaManifest {
            version: WIRE_SCHEMA_VERSION + 1,
            collections: vec![collection_to_wire(&user_schema())],
        };
        let bytes = encode_schema_manifest(&manifest).unwrap();

        let error = decode_wire_schema_manifest(&bytes).unwrap_err();

        assert!(error.contains("unsupported schema manifest version"));
    }

    #[test]
    fn rejects_json_and_corrupt_schema_metadata() {
        assert!(decode_schema_record(br#"{"version":1}"#)
            .unwrap_err()
            .contains("JSON-era preview metadata"));
        assert!(decode_schema_record(b"CSMR").is_err());
    }

    #[test]
    fn round_trips_reverse_index_metadata() {
        let entries = vec![
            IndexEntry {
                name: "email".to_string(),
                value: IndexValue::String("a@example.com".to_string()),
            },
            IndexEntry {
                name: "tags".to_string(),
                value: IndexValue::List(vec![
                    IndexValue::String("team".to_string()),
                    IndexValue::Int(7),
                ]),
            },
        ];

        let bytes = encode_index_entry_metadata(9, &entries).unwrap();
        let decoded = decode_index_entry_metadata(&bytes).unwrap();

        assert_eq!(decoded, entries);
    }

    #[test]
    fn rejects_json_reverse_index_metadata() {
        assert!(decode_index_entry_metadata(br#"[{"name":"email"}]"#)
            .unwrap_err()
            .contains("JSON-era preview metadata"));
    }
}
