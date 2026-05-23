use serde::Deserialize;
use serde_json::Value;

use crate::document_format::{BinaryDocument, BinaryValue};
use crate::storage::CollectionSchemaManifest;

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
pub(crate) enum NativeFilter {
    #[serde(rename = "field")]
    Field {
        field: String,
        operation: FieldFilterOperation,
        value: Value,
    },
    #[serde(rename = "all")]
    All { predicates: Vec<NativeFilter> },
    #[serde(rename = "any")]
    Any { predicates: Vec<NativeFilter> },
    #[serde(rename = "not")]
    Not { predicate: Box<NativeFilter> },
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FieldFilterOperation {
    EqualTo,
    GreaterThan,
    GreaterThanOrEqualTo,
    LessThan,
    LessThanOrEqualTo,
    Contains,
    StartsWith,
    EndsWith,
}

impl NativeFilter {
    pub(crate) fn from_json(bytes: &[u8]) -> Result<Self, String> {
        serde_json::from_slice(bytes).map_err(|error| error.to_string())
    }

    pub(crate) fn matches(
        &self,
        schema: &CollectionSchemaManifest,
        bytes: &[u8],
    ) -> Result<bool, String> {
        let document = BinaryDocument::parse(bytes)?;
        self.matches_document(schema, &document)
    }

    fn matches_document(
        &self,
        schema: &CollectionSchemaManifest,
        document: &BinaryDocument<'_>,
    ) -> Result<bool, String> {
        match self {
            Self::Field {
                field,
                operation,
                value,
            } => {
                let Some(index) = schema
                    .fields
                    .iter()
                    .position(|schema_field| schema_field.name == *field)
                else {
                    return Ok(false);
                };
                if index >= document.field_count() {
                    return Ok(false);
                }
                match document.field_value(index)? {
                    Some(actual) => field_matches(&actual, *operation, value),
                    None => {
                        Ok(matches!(operation, FieldFilterOperation::EqualTo) && value.is_null())
                    }
                }
            }
            Self::All { predicates } => {
                for predicate in predicates {
                    if !predicate.matches_document(schema, document)? {
                        return Ok(false);
                    }
                }
                Ok(true)
            }
            Self::Any { predicates } => {
                for predicate in predicates {
                    if predicate.matches_document(schema, document)? {
                        return Ok(true);
                    }
                }
                Ok(false)
            }
            Self::Not { predicate } => Ok(!predicate.matches_document(schema, document)?),
        }
    }
}

fn field_matches(
    actual: &BinaryValue,
    operation: FieldFilterOperation,
    expected: &Value,
) -> Result<bool, String> {
    Ok(match operation {
        FieldFilterOperation::EqualTo => {
            let Some(expected) = json_to_binary_value(expected)? else {
                return Ok(false);
            };
            binary_values_equal(actual, &expected)
        }
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
        FieldFilterOperation::StartsWith => match (binary_string(actual), expected.as_str()) {
            (Some(actual), Some(expected)) => actual.starts_with(expected),
            _ => false,
        },
        FieldFilterOperation::EndsWith => match (binary_string(actual), expected.as_str()) {
            (Some(actual), Some(expected)) => actual.ends_with(expected),
            _ => false,
        },
    })
}

fn compare_numbers(actual: &BinaryValue, expected: &Value) -> Option<i8> {
    let actual = binary_number(actual)?;
    let expected = json_number(expected)?;
    if actual < expected {
        Some(-1)
    } else if actual > expected {
        Some(1)
    } else {
        Some(0)
    }
}

fn contains_value(actual: &BinaryValue, expected: &Value) -> Result<bool, String> {
    if let (Some(actual), Some(expected)) = (binary_string(actual), expected.as_str()) {
        return Ok(actual.contains(expected));
    }
    let Some(expected) = json_to_binary_value(expected)? else {
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

fn json_number(value: &Value) -> Option<f64> {
    match value {
        Value::Number(value) => value.as_f64(),
        _ => None,
    }
}

fn binary_string(value: &BinaryValue) -> Option<&str> {
    match value {
        BinaryValue::String(value) | BinaryValue::Enum(value) => Some(value.as_str()),
        _ => None,
    }
}

fn json_to_binary_value(value: &Value) -> Result<Option<BinaryValue>, String> {
    match value {
        Value::Null => Ok(None),
        Value::Bool(value) => Ok(Some(BinaryValue::Bool(*value))),
        Value::Number(value) => {
            if let Some(value) = value.as_i64() {
                Ok(Some(BinaryValue::Int(value)))
            } else if let Some(value) = value.as_f64().filter(|value| value.is_finite()) {
                Ok(Some(BinaryValue::Double(value)))
            } else {
                Err("filter number cannot be represented as a finite binary value".into())
            }
        }
        Value::String(value) => Ok(Some(BinaryValue::String(value.clone()))),
        Value::Array(values) => Ok(Some(BinaryValue::List(
            values
                .iter()
                .map(json_to_binary_value)
                .collect::<Result<Vec<_>, String>>()?,
        ))),
        Value::Object(values) => {
            let mut entries = values
                .iter()
                .map(|(name, value)| Ok((name.clone(), json_to_binary_value(value)?)))
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

    fn schema() -> CollectionSchemaManifest {
        CollectionSchemaManifest {
            name: "users".to_string(),
            id_field: "id".to_string(),
            fields: vec![
                FieldSchemaManifest {
                    name: "active".to_string(),
                    dart_type: "bool".to_string(),
                    is_id: false,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
                FieldSchemaManifest {
                    name: "age".to_string(),
                    dart_type: "int".to_string(),
                    is_id: false,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
                FieldSchemaManifest {
                    name: "name".to_string(),
                    dart_type: "String".to_string(),
                    is_id: false,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
                FieldSchemaManifest {
                    name: "nickname".to_string(),
                    dart_type: "String?".to_string(),
                    is_id: false,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
                FieldSchemaManifest {
                    name: "tags".to_string(),
                    dart_type: "List<String>".to_string(),
                    is_id: false,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
                FieldSchemaManifest {
                    name: "profile".to_string(),
                    dart_type: "Recipient".to_string(),
                    is_id: false,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
            ],
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

    #[test]
    fn evaluates_field_and_group_predicates() {
        let filter = NativeFilter::from_json(
            br#"{
              "type":"all",
              "predicates":[
                {"type":"field","field":"active","operation":"equal_to","value":true},
                {"type":"field","field":"age","operation":"greater_than_or_equal_to","value":40},
                {"type":"field","field":"name","operation":"contains","value":"Love"}
              ]
            }"#,
        )
        .unwrap();

        assert!(filter.matches(&schema(), &document()).unwrap());
    }

    #[test]
    fn evaluates_not_and_string_suffix_predicates() {
        let filter = NativeFilter::from_json(
            br#"{
              "type":"not",
              "predicate":{"type":"field","field":"name","operation":"ends_with","value":"Byron"}
            }"#,
        )
        .unwrap();

        assert!(filter.matches(&schema(), &document()).unwrap());
    }

    #[test]
    fn evaluates_null_list_and_object_predicates() {
        let filter = NativeFilter::from_json(
            br#"{
              "type":"all",
              "predicates":[
                {"type":"field","field":"nickname","operation":"equal_to","value":null},
                {"type":"field","field":"tags","operation":"contains","value":"math"},
                {"type":"field","field":"profile","operation":"equal_to","value":{"label":"admin"}}
              ]
            }"#,
        )
        .unwrap();

        assert!(filter.matches(&schema(), &document()).unwrap());
    }
}
