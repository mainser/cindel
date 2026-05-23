#![allow(dead_code)]
// MDBX-03 proves the key format before MDBX-04 wires it into MdbxStorage.

use super::IndexValue;

pub(crate) const DOCUMENTS_TABLE: &str = "documents";
pub(crate) const INDEXES_TABLE: &str = "indexes";
pub(crate) const UNIQUE_INDEXES_TABLE: &str = "unique_indexes";
pub(crate) const ID_COUNTERS_TABLE: &str = "id_counters";
pub(crate) const COLLECTION_REVISIONS_TABLE: &str = "collection_revisions";
pub(crate) const SCHEMA_COLLECTIONS_TABLE: &str = "schema_collections";
pub(crate) const STORAGE_METADATA_TABLE: &str = "storage_metadata";

const SIGN_BIT: u64 = 0x8000_0000_0000_0000;
const TEXT_ESCAPE: u8 = 0x00;
const TEXT_TERMINATOR: u8 = 0x00;
const TEXT_NULL_ESCAPE: u8 = 0xff;

#[derive(Debug, Clone, Eq, PartialEq)]
pub(crate) struct MdbxKeyRange {
    pub start: Vec<u8>,
    pub end_inclusive: Vec<u8>,
}

pub(crate) fn encode_document_key(collection: &str, document_id: u64) -> Vec<u8> {
    let mut key = Vec::new();
    push_text_segment(&mut key, collection);
    push_u64(&mut key, document_id);
    key
}

pub(crate) fn encode_index_key(
    collection: &str,
    index_name: &str,
    value: &IndexValue,
    document_id: u64,
) -> Result<Vec<u8>, String> {
    let mut key = encode_index_equal_prefix(collection, index_name, value)?;
    push_u64(&mut key, document_id);
    Ok(key)
}

pub(crate) fn encode_index_equal_prefix(
    collection: &str,
    index_name: &str,
    value: &IndexValue,
) -> Result<Vec<u8>, String> {
    let mut key = encode_index_prefix(collection, index_name);
    push_index_value(&mut key, value)?;
    Ok(key)
}

pub(crate) fn encode_unique_index_key(
    collection: &str,
    index_name: &str,
    value: &IndexValue,
) -> Result<Vec<u8>, String> {
    encode_index_equal_prefix(collection, index_name, value)
}

pub(crate) fn encode_collection_key(collection: &str) -> Vec<u8> {
    let mut key = Vec::new();
    push_text_segment(&mut key, collection);
    key
}

pub(crate) fn encode_index_range(
    collection: &str,
    index_name: &str,
    lower: Option<&IndexValue>,
    upper: Option<&IndexValue>,
) -> Result<MdbxKeyRange, String> {
    let Some(kind) = range_kind(lower, upper)? else {
        return Err("index range requires at least one bound".into());
    };

    let prefix = encode_index_prefix(collection, index_name);
    let mut start = prefix.clone();
    let mut end_inclusive = prefix;

    if let Some(lower) = lower {
        push_index_value(&mut start, lower)?;
    } else {
        push_kind_lower_bound(&mut start, kind);
    }

    if let Some(upper) = upper {
        push_index_value(&mut end_inclusive, upper)?;
        push_u64(&mut end_inclusive, u64::MAX);
    } else {
        push_kind_upper_bound(&mut end_inclusive, kind);
    }

    Ok(MdbxKeyRange {
        start,
        end_inclusive,
    })
}

pub(crate) fn decode_key_document_id(key: &[u8]) -> Result<u64, String> {
    let id_bytes = key
        .get(key.len().saturating_sub(8)..)
        .ok_or_else(|| "MDBX key is too short to contain a document id".to_string())?;
    let id_bytes = id_bytes
        .try_into()
        .map_err(|_| "MDBX document id must be 8 bytes".to_string())?;
    Ok(u64::from_be_bytes(id_bytes))
}

fn encode_index_prefix(collection: &str, index_name: &str) -> Vec<u8> {
    let mut key = Vec::new();
    push_text_segment(&mut key, collection);
    push_text_segment(&mut key, index_name);
    key
}

fn range_kind(
    lower: Option<&IndexValue>,
    upper: Option<&IndexValue>,
) -> Result<Option<IndexValueKind>, String> {
    match (
        lower.map(IndexValueKind::from),
        upper.map(IndexValueKind::from),
    ) {
        (Some(lower), Some(upper)) if lower == upper => Ok(Some(lower)),
        (Some(_), Some(_)) => Err("index range bounds must have matching types".into()),
        (Some(kind), None) | (None, Some(kind)) => Ok(Some(kind)),
        (None, None) => Ok(None),
    }
}

fn push_text_segment(key: &mut Vec<u8>, value: &str) {
    for byte in value.as_bytes() {
        if *byte == TEXT_ESCAPE {
            key.push(TEXT_ESCAPE);
            key.push(TEXT_NULL_ESCAPE);
        } else {
            key.push(*byte);
        }
    }
    key.push(TEXT_ESCAPE);
    key.push(TEXT_TERMINATOR);
}

fn decode_text_segment(bytes: &[u8]) -> Result<String, String> {
    let mut decoded = Vec::new();
    let mut index = 0;
    while index < bytes.len() {
        let byte = bytes[index];
        if byte != TEXT_ESCAPE {
            decoded.push(byte);
            index += 1;
            continue;
        }

        let next = bytes
            .get(index + 1)
            .ok_or_else(|| "text segment ended inside escape sequence".to_string())?;
        match *next {
            TEXT_TERMINATOR if index + 2 == bytes.len() => {
                return String::from_utf8(decoded).map_err(|error| error.to_string());
            }
            TEXT_NULL_ESCAPE => {
                decoded.push(TEXT_ESCAPE);
                index += 2;
            }
            _ => return Err("text segment contains an invalid escape sequence".into()),
        }
    }

    Err("text segment is missing a terminator".into())
}

fn push_index_value(key: &mut Vec<u8>, value: &IndexValue) -> Result<(), String> {
    match value {
        IndexValue::Bool(value) => {
            key.push(IndexValueKind::Bool.tag());
            key.push(u8::from(*value));
        }
        IndexValue::Int(value) => {
            key.push(IndexValueKind::Int.tag());
            key.extend_from_slice(&encode_i64(*value));
        }
        IndexValue::Double(value) => {
            key.push(IndexValueKind::Double.tag());
            key.extend_from_slice(&encode_f64(*value)?);
        }
        IndexValue::String(value) => {
            key.push(IndexValueKind::String.tag());
            push_text_segment(key, value);
        }
    }
    Ok(())
}

fn push_kind_lower_bound(key: &mut Vec<u8>, kind: IndexValueKind) {
    key.push(kind.tag());
    match kind {
        IndexValueKind::Bool => key.push(0),
        IndexValueKind::Int | IndexValueKind::Double => key.extend_from_slice(&[0; 8]),
        IndexValueKind::String => {}
    }
}

fn push_kind_upper_bound(key: &mut Vec<u8>, kind: IndexValueKind) {
    key.push(kind.tag());
    match kind {
        IndexValueKind::Bool => {
            key.push(1);
            push_u64(key, u64::MAX);
        }
        IndexValueKind::Int | IndexValueKind::Double => {
            key.extend_from_slice(&[0xff; 8]);
            push_u64(key, u64::MAX);
        }
        IndexValueKind::String => key.push(0xff),
    }
}

fn push_u64(key: &mut Vec<u8>, value: u64) {
    key.extend_from_slice(&value.to_be_bytes());
}

fn encode_i64(value: i64) -> [u8; 8] {
    ((value as u64) ^ SIGN_BIT).to_be_bytes()
}

fn decode_i64(bytes: &[u8]) -> Result<i64, String> {
    let bytes = bytes
        .try_into()
        .map_err(|_| "encoded int value must be 8 bytes".to_string())?;
    Ok((u64::from_be_bytes(bytes) ^ SIGN_BIT) as i64)
}

fn encode_f64(value: f64) -> Result<[u8; 8], String> {
    if !value.is_finite() {
        return Err("index double values must be finite".into());
    }

    let value = if value == 0.0 { 0.0 } else { value };
    let bits = value.to_bits();
    let ordered = if bits & SIGN_BIT == 0 {
        bits ^ SIGN_BIT
    } else {
        !bits
    };
    Ok(ordered.to_be_bytes())
}

fn decode_f64(bytes: &[u8]) -> Result<f64, String> {
    let bytes = bytes
        .try_into()
        .map_err(|_| "encoded double value must be 8 bytes".to_string())?;
    let ordered = u64::from_be_bytes(bytes);
    let bits = if ordered & SIGN_BIT == 0 {
        !ordered
    } else {
        ordered ^ SIGN_BIT
    };
    Ok(f64::from_bits(bits))
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum IndexValueKind {
    Bool,
    Int,
    Double,
    String,
}

impl IndexValueKind {
    fn tag(self) -> u8 {
        match self {
            Self::Bool => 1,
            Self::Int => 2,
            Self::Double => 3,
            Self::String => 4,
        }
    }
}

impl From<&IndexValue> for IndexValueKind {
    fn from(value: &IndexValue) -> Self {
        match value {
            IndexValue::Bool(_) => Self::Bool,
            IndexValue::Int(_) => Self::Int,
            IndexValue::Double(_) => Self::Double,
            IndexValue::String(_) => Self::String,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn document_keys_group_documents_by_collection_and_order_ids() {
        // Scenario: MDBX document keys are encoded for one table.
        // Covers:
        // - Collection text segment boundaries.
        // - Big-endian document id ordering.
        // Expected: Keys from the same collection sort by document id.
        let first = encode_document_key("users", 1);
        let second = encode_document_key("users", 2);
        let tenth = encode_document_key("users", 10);

        assert!(first < second);
        assert!(second < tenth);
        assert!(encode_document_key("users", 2) < encode_document_key("users\0archive", 1));
    }

    #[test]
    fn signed_integer_components_preserve_numeric_order_and_round_trip() {
        // Scenario: Cindel indexed integers can be negative.
        // Covers:
        // - Sign-bit flipping for lexicographic byte ordering.
        // - Round-trip decoding used by the key format tests.
        // Expected: Encoded bytes sort in the same order as signed integers.
        let values = [i64::MIN, -100, -1, 0, 1, 100, i64::MAX];
        let mut encoded = values
            .iter()
            .map(|value| (encode_i64(*value), *value))
            .collect::<Vec<_>>();
        encoded.sort_by(|left, right| left.0.cmp(&right.0));

        assert_eq!(
            encoded.iter().map(|(_, value)| *value).collect::<Vec<_>>(),
            values
        );
        for value in values {
            assert_eq!(decode_i64(&encode_i64(value)).unwrap(), value);
        }
    }

    #[test]
    fn finite_double_components_preserve_numeric_order_and_round_trip() {
        // Scenario: Cindel indexed doubles use MDBX byte ordering.
        // Covers:
        // - Sortable finite f64 encoding.
        // - Rejection of non-finite values, matching the existing SQLite path.
        // Expected: Encoded bytes sort in numeric order and reject NaN/Infinity.
        let values = [-f64::MAX, -10.5, -1.0, 0.0, 0.25, 1.0, 10.5, f64::MAX];
        let mut encoded = values
            .iter()
            .map(|value| (encode_f64(*value).unwrap(), *value))
            .collect::<Vec<_>>();
        encoded.sort_by(|left, right| left.0.cmp(&right.0));

        assert_eq!(
            encoded.iter().map(|(_, value)| *value).collect::<Vec<_>>(),
            values
        );
        for value in values {
            assert_eq!(decode_f64(&encode_f64(value).unwrap()).unwrap(), value);
        }
        assert_eq!(encode_f64(-0.0).unwrap(), encode_f64(0.0).unwrap());
        assert!(encode_f64(f64::NAN).is_err());
        assert!(encode_f64(f64::INFINITY).is_err());
        assert!(encode_f64(f64::NEG_INFINITY).is_err());
    }

    #[test]
    fn string_segments_preserve_lexicographic_order_and_escape_nul() {
        // Scenario: MDBX stores string values inside compound keys.
        // Covers:
        // - NUL escaping for collision-free text segments.
        // - Terminators that preserve normal lexicographic string ordering.
        // Expected: Encoded strings sort like their original values.
        let values = ["", "\0", "\0a", "a", "a\0", "aa", "b"];
        let mut encoded = values
            .iter()
            .map(|value| {
                let mut key = Vec::new();
                push_text_segment(&mut key, value);
                assert_eq!(decode_text_segment(&key).unwrap(), *value);
                (key, *value)
            })
            .collect::<Vec<_>>();
        encoded.sort_by(|left, right| left.0.cmp(&right.0));

        assert_eq!(
            encoded.iter().map(|(_, value)| *value).collect::<Vec<_>>(),
            values
        );
    }

    #[test]
    fn index_value_kinds_do_not_collide() {
        // Scenario: Different Dart values can have similar textual forms.
        // Covers:
        // - Explicit value-kind tags in MDBX index keys.
        // - Bool/int/double/string separation before encoded payloads.
        // Expected: Equivalent-looking values produce distinct key bytes.
        let values = [
            IndexValue::Bool(true),
            IndexValue::Int(1),
            IndexValue::Double(1.0),
            IndexValue::String("1".into()),
        ];
        let mut encoded = Vec::new();
        for value in values {
            let mut key = Vec::new();
            push_index_value(&mut key, &value).unwrap();
            encoded.push(key);
        }

        encoded.sort();
        encoded.dedup();

        assert_eq!(encoded.len(), 4);
    }

    #[test]
    fn equality_prefix_matches_only_same_collection_index_and_value() {
        // Scenario: An MDBX equality query scans by a key prefix.
        // Covers:
        // - Collection, index name, and value in the equality prefix.
        // - Document id as the final sortable key segment.
        // Expected: Only keys with the exact same indexed value share the prefix.
        let prefix = encode_index_equal_prefix("users", "score", &IndexValue::Int(10)).unwrap();
        let first = encode_index_key("users", "score", &IndexValue::Int(10), 1).unwrap();
        let second = encode_index_key("users", "score", &IndexValue::Int(10), 2).unwrap();
        let other_value = encode_index_key("users", "score", &IndexValue::Int(11), 1).unwrap();
        let other_index = encode_index_key("users", "age", &IndexValue::Int(10), 1).unwrap();

        assert!(first.starts_with(&prefix));
        assert!(second.starts_with(&prefix));
        assert!(!other_value.starts_with(&prefix));
        assert!(!other_index.starts_with(&prefix));
        assert!(first < second);
    }

    #[test]
    fn range_bounds_cover_matching_values_without_crossing_value_kinds() {
        // Scenario: An MDBX range query scans contiguous ordered keys.
        // Covers:
        // - Inclusive lower and upper boundaries.
        // - Same-kind range boundaries for one-sided ranges.
        // Expected: Matching int keys are inside the bounds and string keys are not.
        let range = encode_index_range(
            "users",
            "score",
            Some(&IndexValue::Int(10)),
            Some(&IndexValue::Int(20)),
        )
        .unwrap();
        let inside_lower = encode_index_key("users", "score", &IndexValue::Int(10), 1).unwrap();
        let inside_upper = encode_index_key("users", "score", &IndexValue::Int(20), 99).unwrap();
        let outside_high = encode_index_key("users", "score", &IndexValue::Int(21), 1).unwrap();
        let other_kind =
            encode_index_key("users", "score", &IndexValue::String("15".into()), 1).unwrap();

        assert!(range.start <= inside_lower);
        assert!(inside_lower <= range.end_inclusive);
        assert!(range.start <= inside_upper);
        assert!(inside_upper <= range.end_inclusive);
        assert!(outside_high > range.end_inclusive);
        assert!(other_kind > range.end_inclusive);

        let open_upper =
            encode_index_range("users", "score", Some(&IndexValue::Int(10)), None).unwrap();
        assert!(inside_upper <= open_upper.end_inclusive);
        assert!(other_kind > open_upper.end_inclusive);
    }

    #[test]
    fn range_bounds_reject_mixed_or_missing_bound_types() {
        // Scenario: MDBX range queries mirror SQLite index type checks.
        // Covers:
        // - Mixed-type lower and upper bounds.
        // - Empty range requests.
        // Expected: Invalid range requests fail before opening an MDBX cursor.
        let mixed = encode_index_range(
            "users",
            "score",
            Some(&IndexValue::Int(1)),
            Some(&IndexValue::String("2".into())),
        );
        let missing = encode_index_range("users", "score", None, None);

        assert!(matches!(
            mixed,
            Err(error) if error.contains("matching types")
        ));
        assert!(matches!(
            missing,
            Err(error) if error.contains("at least one bound")
        ));
    }

    #[test]
    fn table_names_match_the_planned_mdbx_layout() {
        // Scenario: MDBX-03 names the tables that MDBX-04 will open.
        // Covers:
        // - Planned table identifiers from the adoption plan.
        // Expected: The constants remain stable for the prototype.
        assert_eq!(DOCUMENTS_TABLE, "documents");
        assert_eq!(INDEXES_TABLE, "indexes");
        assert_eq!(UNIQUE_INDEXES_TABLE, "unique_indexes");
        assert_eq!(ID_COUNTERS_TABLE, "id_counters");
        assert_eq!(COLLECTION_REVISIONS_TABLE, "collection_revisions");
        assert_eq!(SCHEMA_COLLECTIONS_TABLE, "schema_collections");
        assert_eq!(
            encode_unique_index_key("users", "email", &IndexValue::String("a".into())).unwrap(),
            encode_index_equal_prefix("users", "email", &IndexValue::String("a".into())).unwrap()
        );
        assert_eq!(
            encode_collection_key("users"),
            encode_collection_key("users")
        );
    }
}
