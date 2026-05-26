use crate::document_format::{read_binary_field, read_binary_field_payload, BinaryValue};
use crate::storage::CollectionSchemaManifest;
use crate::wire::{decode_filter, WireFilter, WireFilterOperation, WireValue};

#[derive(Debug)]
pub(crate) enum NativeFilter {
    Field {
        field: String,
        operation: FieldFilterOperation,
        value: WireValue,
    },
    All {
        predicates: Vec<NativeFilter>,
    },
    Any {
        predicates: Vec<NativeFilter>,
    },
    Not {
        predicate: Box<NativeFilter>,
    },
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum FieldFilterOperation {
    EqualTo,
    GreaterThan,
    GreaterThanOrEqualTo,
    LessThan,
    LessThanOrEqualTo,
    Contains,
    StartsWith,
    EndsWith,
    IsNull,
}

impl NativeFilter {
    pub(crate) fn decode(bytes: &[u8]) -> Result<Self, String> {
        let filter = decode_filter(bytes)?;
        Self::from_wire(filter)
    }

    fn from_wire(filter: WireFilter) -> Result<Self, String> {
        match filter {
            WireFilter::Field {
                field,
                operation,
                value,
            } => Ok(Self::Field {
                field,
                operation: FieldFilterOperation::from_wire(operation),
                value,
            }),
            WireFilter::All { predicates } => Ok(Self::All {
                predicates: predicates
                    .into_iter()
                    .map(Self::from_wire)
                    .collect::<Result<Vec<_>, String>>()?,
            }),
            WireFilter::Any { predicates } => Ok(Self::Any {
                predicates: predicates
                    .into_iter()
                    .map(Self::from_wire)
                    .collect::<Result<Vec<_>, String>>()?,
            }),
            WireFilter::Not { predicate } => Ok(Self::Not {
                predicate: Box::new(Self::from_wire(*predicate)?),
            }),
        }
    }

    pub(crate) fn matches(
        &self,
        schema: &CollectionSchemaManifest,
        bytes: &[u8],
    ) -> Result<bool, String> {
        self.matches_document(schema, bytes)
    }

    fn matches_document(
        &self,
        schema: &CollectionSchemaManifest,
        bytes: &[u8],
    ) -> Result<bool, String> {
        match self {
            Self::Field {
                field,
                operation,
                value,
            } => {
                if !schema
                    .fields
                    .iter()
                    .any(|schema_field| schema_field.name == *field)
                {
                    return Ok(false);
                }
                if let Some(matches) = raw_field_matches(schema, bytes, field, *operation, value)? {
                    return Ok(matches);
                }
                match read_binary_field(schema, bytes, field)? {
                    Some(actual) => field_matches(&actual, *operation, value),
                    None => Ok(matches!(
                        operation,
                        FieldFilterOperation::EqualTo | FieldFilterOperation::IsNull
                    ) && matches!(value, WireValue::Null)),
                }
            }
            Self::All { predicates } => {
                for predicate in predicates {
                    if !predicate.matches_document(schema, bytes)? {
                        return Ok(false);
                    }
                }
                Ok(true)
            }
            Self::Any { predicates } => {
                for predicate in predicates {
                    if predicate.matches_document(schema, bytes)? {
                        return Ok(true);
                    }
                }
                Ok(false)
            }
            Self::Not { predicate } => Ok(!predicate.matches_document(schema, bytes)?),
        }
    }
}

fn raw_field_matches(
    schema: &CollectionSchemaManifest,
    bytes: &[u8],
    field: &str,
    operation: FieldFilterOperation,
    expected: &WireValue,
) -> Result<Option<bool>, String> {
    if !matches!(operation, FieldFilterOperation::Contains) {
        return Ok(None);
    }
    let WireValue::String(expected) = expected else {
        return Ok(None);
    };
    let Some((binary_type, payload)) = read_binary_field_payload(schema, bytes, field)? else {
        return Ok(Some(false));
    };
    let expected = expected.as_bytes();
    match binary_type {
        "string" | "String" => Ok(Some(bytes_contains(payload, expected))),
        "list" => Ok(Some(raw_string_list_contains(payload, expected)?)),
        _ => Ok(None),
    }
}

fn bytes_contains(haystack: &[u8], needle: &[u8]) -> bool {
    needle.is_empty()
        || (needle.len() <= haystack.len()
            && haystack
                .windows(needle.len())
                .any(|window| window == needle))
}

fn raw_string_list_contains(bytes: &[u8], expected: &[u8]) -> Result<bool, String> {
    let count = read_u32_le(bytes, 0)? as usize;
    let mut offset = 4usize;
    for _ in 0..count {
        let header = read_slice(bytes, offset, 8)?;
        let kind = header[0];
        let flags = header[1];
        let len = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as usize;
        offset += 8;
        let payload = read_slice(bytes, offset, len)?;
        offset += len;
        if flags & 0x01 == 0 && matches!(kind, 4 | 8) && payload == expected {
            return Ok(true);
        }
    }
    if offset != bytes.len() {
        return Err("binary list contains trailing bytes".into());
    }
    Ok(false)
}

fn read_u32_le(bytes: &[u8], offset: usize) -> Result<u32, String> {
    let bytes = read_slice(bytes, offset, 4)?;
    Ok(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
}

fn read_slice(bytes: &[u8], offset: usize, len: usize) -> Result<&[u8], String> {
    let end = offset
        .checked_add(len)
        .ok_or_else(|| "binary list offset overflow".to_string())?;
    bytes
        .get(offset..end)
        .ok_or_else(|| "binary list is truncated".to_string())
}

impl FieldFilterOperation {
    fn from_wire(operation: WireFilterOperation) -> Self {
        match operation {
            WireFilterOperation::Equal => Self::EqualTo,
            WireFilterOperation::LessThan => Self::LessThan,
            WireFilterOperation::LessThanOrEqual => Self::LessThanOrEqualTo,
            WireFilterOperation::GreaterThan => Self::GreaterThan,
            WireFilterOperation::GreaterThanOrEqual => Self::GreaterThanOrEqualTo,
            WireFilterOperation::Contains => Self::Contains,
            WireFilterOperation::StartsWith => Self::StartsWith,
            WireFilterOperation::EndsWith => Self::EndsWith,
            WireFilterOperation::IsNull => Self::IsNull,
        }
    }
}

fn field_matches(
    actual: &BinaryValue,
    operation: FieldFilterOperation,
    expected: &WireValue,
) -> Result<bool, String> {
    Ok(match operation {
        FieldFilterOperation::EqualTo => {
            let Some(expected) = wire_to_binary_value(expected)? else {
                return Ok(false);
            };
            binary_values_equal(actual, &expected)
        }
        FieldFilterOperation::IsNull => false,
        FieldFilterOperation::GreaterThan => compare_numbers(actual, expected)
            .map(|ordering| ordering > 0)
            .unwrap_or(false),
        FieldFilterOperation::GreaterThanOrEqualTo => compare_numbers(actual, expected)
            .map(|ordering| ordering >= 0)
            .unwrap_or(false),
        FieldFilterOperation::LessThan => compare_numbers(actual, expected)
            .map(|ordering| ordering < 0)
            .unwrap_or(false),
        FieldFilterOperation::LessThanOrEqualTo => compare_numbers(actual, expected)
            .map(|ordering| ordering <= 0)
            .unwrap_or(false),
        FieldFilterOperation::Contains => contains_value(actual, expected)?,
        FieldFilterOperation::StartsWith => match (binary_string(actual), wire_string(expected)) {
            (Some(actual), Some(expected)) => actual.starts_with(expected),
            _ => false,
        },
        FieldFilterOperation::EndsWith => match (binary_string(actual), wire_string(expected)) {
            (Some(actual), Some(expected)) => actual.ends_with(expected),
            _ => false,
        },
    })
}

fn compare_numbers(actual: &BinaryValue, expected: &WireValue) -> Option<i8> {
    let actual = binary_number(actual)?;
    let expected = wire_number(expected)?;
    if actual < expected {
        Some(-1)
    } else if actual > expected {
        Some(1)
    } else {
        Some(0)
    }
}

fn contains_value(actual: &BinaryValue, expected: &WireValue) -> Result<bool, String> {
    if let (Some(actual), Some(expected)) = (binary_string(actual), wire_string(expected)) {
        return Ok(actual.contains(expected));
    }
    let Some(expected) = wire_to_binary_value(expected)? else {
        return Ok(false);
    };
    match actual {
        BinaryValue::List(values) => Ok(values
            .iter()
            .flatten()
            .any(|value| binary_values_equal(value, &expected))),
        _ => Ok(false),
    }
}

fn binary_values_equal(left: &BinaryValue, right: &BinaryValue) -> bool {
    match (left, right) {
        (BinaryValue::Int(left), BinaryValue::DateTimeMicros(right))
        | (BinaryValue::Int(left), BinaryValue::DurationMicros(right))
        | (BinaryValue::DateTimeMicros(left), BinaryValue::Int(right))
        | (BinaryValue::DurationMicros(left), BinaryValue::Int(right))
        | (BinaryValue::DateTimeMicros(left), BinaryValue::DurationMicros(right))
        | (BinaryValue::DurationMicros(left), BinaryValue::DateTimeMicros(right)) => left == right,
        _ => left == right,
    }
}

fn binary_number(value: &BinaryValue) -> Option<f64> {
    match value {
        BinaryValue::Int(value)
        | BinaryValue::DateTimeMicros(value)
        | BinaryValue::DurationMicros(value) => Some(*value as f64),
        BinaryValue::Double(value) => Some(*value),
        _ => None,
    }
}

fn wire_number(value: &WireValue) -> Option<f64> {
    match value {
        WireValue::Int(value) => Some(*value as f64),
        WireValue::Double(value) if value.is_finite() => Some(*value),
        _ => None,
    }
}

fn binary_string(value: &BinaryValue) -> Option<&str> {
    match value {
        BinaryValue::String(value) | BinaryValue::Enum(value) => Some(value.as_str()),
        _ => None,
    }
}

fn wire_string(value: &WireValue) -> Option<&str> {
    match value {
        WireValue::String(value) => Some(value.as_str()),
        _ => None,
    }
}

fn wire_to_binary_value(value: &WireValue) -> Result<Option<BinaryValue>, String> {
    match value {
        WireValue::Null => Ok(None),
        WireValue::Bool(value) => Ok(Some(BinaryValue::Bool(*value))),
        WireValue::Int(value) => Ok(Some(BinaryValue::Int(*value))),
        WireValue::Double(value) => {
            if value.is_finite() {
                Ok(Some(BinaryValue::Double(*value)))
            } else {
                Err("filter number cannot be represented as a finite binary value".into())
            }
        }
        WireValue::String(value) => Ok(Some(BinaryValue::String(value.clone()))),
        WireValue::List(values) => Ok(Some(BinaryValue::List(
            values
                .iter()
                .map(wire_to_binary_value)
                .collect::<Result<Vec<_>, String>>()?,
        ))),
        WireValue::Object(values) => {
            let mut entries = values
                .iter()
                .map(|(name, value)| Ok((name.clone(), wire_to_binary_value(value)?)))
                .collect::<Result<Vec<(String, Option<BinaryValue>)>, String>>()?;
            entries.sort_by(|left, right| left.0.cmp(&right.0));
            Ok(Some(BinaryValue::Object(entries)))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::document_format::write_document;
    use crate::storage::FieldSchemaManifest;
    use crate::wire::encode_filter;

    fn schema() -> CollectionSchemaManifest {
        CollectionSchemaManifest {
            name: "users".to_string(),
            id_field: "id".to_string(),
            fields: vec![
                FieldSchemaManifest {
                    name: "active".to_string(),
                    dart_type: "bool".to_string(),
                    binary_type: "bool".to_string(),
                    is_id: false,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
                FieldSchemaManifest {
                    name: "age".to_string(),
                    dart_type: "int".to_string(),
                    binary_type: "int".to_string(),
                    is_id: false,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
                FieldSchemaManifest {
                    name: "name".to_string(),
                    dart_type: "String".to_string(),
                    binary_type: "string".to_string(),
                    is_id: false,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
                FieldSchemaManifest {
                    name: "nickname".to_string(),
                    dart_type: "String?".to_string(),
                    binary_type: "string".to_string(),
                    is_id: false,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
                FieldSchemaManifest {
                    name: "tags".to_string(),
                    dart_type: "List<String>".to_string(),
                    binary_type: "list".to_string(),
                    is_id: false,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
                FieldSchemaManifest {
                    name: "profile".to_string(),
                    dart_type: "Recipient".to_string(),
                    binary_type: "object".to_string(),
                    is_id: false,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
            ],
            composite_indexes: Vec::new(),
        }
    }

    fn document() -> Vec<u8> {
        write_document(&[
            Some(BinaryValue::Bool(true)),
            Some(BinaryValue::Int(42)),
            Some(BinaryValue::String("Ada Lovelace".to_string())),
            None,
            Some(BinaryValue::List(vec![
                Some(BinaryValue::String("math".to_string())),
                Some(BinaryValue::String("code".to_string())),
            ])),
            Some(BinaryValue::Object(vec![(
                "label".to_string(),
                Some(BinaryValue::String("admin".to_string())),
            )])),
        ])
        .unwrap()
    }

    // Scenario: Rust evaluates a decoded binary filter with field predicates.
    // Covers:
    // - CindelWireV1 all-group decoding.
    // - Bool equality, numeric comparison, and string contains operations.
    // Expected: The typed binary document matches all field predicates.
    #[test]
    fn evaluates_field_and_group_predicates() {
        // Arrange.
        let bytes = encode_filter(&WireFilter::All {
            predicates: vec![
                WireFilter::Field {
                    field: "active".to_string(),
                    operation: WireFilterOperation::Equal,
                    value: WireValue::Bool(true),
                },
                WireFilter::Field {
                    field: "age".to_string(),
                    operation: WireFilterOperation::GreaterThanOrEqual,
                    value: WireValue::Int(40),
                },
                WireFilter::Field {
                    field: "name".to_string(),
                    operation: WireFilterOperation::Contains,
                    value: WireValue::String("Love".to_string()),
                },
            ],
        })
        .unwrap();

        // Act.
        let filter = NativeFilter::decode(&bytes).unwrap();

        // Assert.
        assert!(filter.matches(&schema(), &document()).unwrap());
    }

    // Scenario: Rust evaluates a decoded binary negated filter.
    // Covers:
    // - CindelWireV1 not decoding.
    // - String suffix operation over binary document fields.
    // Expected: The negated suffix predicate matches the document.
    #[test]
    fn evaluates_not_and_string_suffix_predicates() {
        // Arrange.
        let bytes = encode_filter(&WireFilter::Not {
            predicate: Box::new(WireFilter::Field {
                field: "name".to_string(),
                operation: WireFilterOperation::EndsWith,
                value: WireValue::String("Byron".to_string()),
            }),
        })
        .unwrap();

        // Act.
        let filter = NativeFilter::decode(&bytes).unwrap();

        // Assert.
        assert!(filter.matches(&schema(), &document()).unwrap());
    }

    // Scenario: Rust evaluates null, list, and object filter operands.
    // Covers:
    // - CindelWireV1 isNull operation.
    // - List contains and embedded object equality conversion.
    // Expected: Nullable, list, and object predicates preserve old semantics.
    #[test]
    fn evaluates_null_list_and_object_predicates() {
        // Arrange.
        let bytes = encode_filter(&WireFilter::All {
            predicates: vec![
                WireFilter::Field {
                    field: "nickname".to_string(),
                    operation: WireFilterOperation::IsNull,
                    value: WireValue::Null,
                },
                WireFilter::Field {
                    field: "tags".to_string(),
                    operation: WireFilterOperation::Contains,
                    value: WireValue::String("math".to_string()),
                },
                WireFilter::Field {
                    field: "profile".to_string(),
                    operation: WireFilterOperation::Equal,
                    value: WireValue::Object(vec![(
                        "label".to_string(),
                        WireValue::String("admin".to_string()),
                    )]),
                },
            ],
        })
        .unwrap();

        // Act.
        let filter = NativeFilter::decode(&bytes).unwrap();

        // Assert.
        assert!(filter.matches(&schema(), &document()).unwrap());
    }
}
