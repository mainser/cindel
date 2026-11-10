//! SQLite's persisted representation for typed lists and embedded objects.
//! Binary encoding remains the transport used by native/Web document readers.
use super::{decode_list, decode_object, encode_object, write_list, BinaryValue};
use std::fmt::Write as _;

pub(crate) fn binary_json(bytes: &[u8], list: bool) -> Result<String, String> {
    let value = if list {
        BinaryValue::List(decode_list(bytes)?)
    } else {
        BinaryValue::Object(decode_object(bytes)?)
    };
    let mut out = String::with_capacity(bytes.len());
    append(&mut out, Some(&value))?;
    Ok(out)
}

fn append(out: &mut String, value: Option<&BinaryValue>) -> Result<(), String> {
    match value {
        None => out.push_str("null"),
        Some(BinaryValue::Bool(v)) => out.push_str(if *v { "true" } else { "false" }),
        Some(
            BinaryValue::Int(v) | BinaryValue::DateTimeMicros(v) | BinaryValue::DurationMicros(v),
        ) => out.push_str(&v.to_string()),
        Some(BinaryValue::Double(v)) => {
            if !v.is_finite() {
                return Err("SQLite JSON double values must be finite".into());
            }
            out.push_str(&serde_json::to_string(v).map_err(|e| e.to_string())?);
        }
        Some(BinaryValue::String(v) | BinaryValue::Enum(v)) => push_json_string(out, v)?,
        Some(BinaryValue::List(values)) => {
            out.push('[');
            for (i, value) in values.iter().enumerate() {
                if i != 0 {
                    out.push(',');
                }
                append(out, value.as_ref())?;
            }
            out.push(']');
        }
        Some(BinaryValue::Object(fields)) => {
            out.push('{');
            for (i, (name, value)) in fields.iter().enumerate() {
                if i != 0 {
                    out.push(',');
                }
                push_json_string(out, name)?;
                out.push(':');
                append(out, value.as_ref())?;
            }
            out.push('}');
        }
    }
    Ok(())
}

pub(crate) fn json_binary(bytes: &[u8], list: bool) -> Result<Vec<u8>, String> {
    let value = from_json(serde_json::from_slice(bytes).map_err(|e| e.to_string())?)?;
    match (list, value) {
        (true, Some(BinaryValue::List(values))) => write_list(&values),
        (false, Some(BinaryValue::Object(fields))) => encode_object(&fields),
        _ => Err("SQLite JSON value does not match its structured field type".into()),
    }
}

fn from_json(value: serde_json::Value) -> Result<Option<BinaryValue>, String> {
    use serde_json::Value;
    Ok(Some(match value {
        Value::Null => return Ok(None),
        Value::Bool(v) => BinaryValue::Bool(v),
        Value::Number(v) => {
            if let Some(v) = v.as_i64() {
                BinaryValue::Int(v)
            } else if v.is_f64() {
                BinaryValue::Double(v.as_f64().ok_or("invalid JSON double")?)
            } else {
                return Err("SQLite JSON integer is outside the signed 64-bit range".into());
            }
        }
        Value::String(v) => BinaryValue::String(v),
        Value::Array(values) => BinaryValue::List(
            values
                .into_iter()
                .map(from_json)
                .collect::<Result<_, _>>()?,
        ),
        Value::Object(fields) => BinaryValue::Object(
            fields
                .into_iter()
                .map(|(name, value)| Ok((name, from_json(value)?)))
                .collect::<Result<_, String>>()?,
        ),
    }))
}

pub(crate) fn push_json_string(json: &mut String, value: &str) -> Result<(), String> {
    json.push('"');
    for character in value.chars() {
        match character {
            '"' => json.push_str("\\\""),
            '\\' => json.push_str("\\\\"),
            '\n' => json.push_str("\\n"),
            '\r' => json.push_str("\\r"),
            '\t' => json.push_str("\\t"),
            '\u{08}' => json.push_str("\\b"),
            '\u{0c}' => json.push_str("\\f"),
            character if character <= '\u{1f}' => {
                write!(json, "\\u{:04x}", character as u32).map_err(|e| e.to_string())?;
            }
            character => json.push(character),
        }
    }
    json.push('"');
    Ok(())
}
