//! Validated traversal of embedded values without building their object trees.
use super::*;

/// Visits the leaves addressed by a typed path. An absent parent is not a null
/// leaf. Lists propagate the same remaining path to each element, as in Dart.
pub(crate) fn visit_binary_path(
    binary_type: &str,
    bytes: &[u8],
    path: &[String],
    visit: &mut impl FnMut(Option<BinaryValue>) -> Result<(), String>,
) -> Result<(), String> {
    let kind = match binary_type {
        "object" => BinaryKind::Object,
        "list" => BinaryKind::List,
        _ => return Ok(()),
    };
    walk(kind, bytes, Some(path), visit)
}

fn walk(
    kind: BinaryKind,
    bytes: &[u8],
    path: Option<&[String]>,
    visit: &mut impl FnMut(Option<BinaryValue>) -> Result<(), String>,
) -> Result<(), String> {
    if path.is_some_and(|path| path.is_empty()) {
        // Only the selected leaf is decoded. Siblings are validated in place.
        return visit(if kind == BinaryKind::Null {
            None
        } else {
            Some(decode_payload(kind, bytes)?)
        });
    }
    match kind {
        BinaryKind::Object | BinaryKind::List => {
            if kind == BinaryKind::List
                && (is_compact_string_list(bytes) || decode_nested_string_list(bytes).is_ok())
            {
                // A string list cannot contain another property segment.
                decode_list(bytes)?;
                return Ok(());
            }
            let count = read_u32(bytes, 0)? as usize;
            let minimum = if kind == BinaryKind::Object { 12 } else { 8 };
            if count > bytes.len().saturating_sub(4) / minimum {
                return Err("nested value count exceeds payload".into());
            }
            let mut offset = 4;
            for _ in 0..count {
                let child_path = if kind == BinaryKind::Object {
                    let len = read_u32(bytes, offset)? as usize;
                    offset += 4;
                    let name = std::str::from_utf8(read_slice(bytes, offset, len)?)
                        .map_err(|e| e.to_string())?;
                    offset += len;
                    path.filter(|path| path[0] == name).map(|path| &path[1..])
                } else {
                    path
                };
                let header = read_slice(bytes, offset, 8)?;
                let child_kind = BinaryKind::from_tag(header[0])?;
                let is_null = header[1] & NULL_FLAG != 0 || child_kind == BinaryKind::Null;
                let len = read_u32(header, 4)? as usize;
                offset += 8;
                let payload = read_slice(bytes, offset, len)?;
                offset += len;
                if is_null {
                    if child_path.is_some_and(|path| path.is_empty()) {
                        visit(None)?;
                    }
                } else {
                    walk(child_kind, payload, child_path, visit)?;
                }
            }
            if offset != bytes.len() {
                return Err("nested value contains trailing bytes".into());
            }
        }
        BinaryKind::String | BinaryKind::Enum => {
            std::str::from_utf8(bytes).map_err(|e| e.to_string())?;
        }
        BinaryKind::Bool => {
            read_slice(bytes, 0, 1)?;
        }
        BinaryKind::Int | BinaryKind::DateTime | BinaryKind::Duration => {
            read_i64(bytes, 0)?;
        }
        BinaryKind::Double => {
            read_f64(bytes, 0)?;
        }
        BinaryKind::Null => {}
    }
    Ok(())
}
