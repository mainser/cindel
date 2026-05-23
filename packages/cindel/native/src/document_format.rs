#![allow(dead_code)]

use std::ops::Range;

const MAGIC: &[u8; 4] = b"CDBF";
const FORMAT_VERSION: u16 = 1;
const HEADER_LEN: usize = 24;
const SLOT_LEN: usize = 16;
const NULL_FLAG: u8 = 0x01;
const MAX_OBJECT_SIZE: usize = 64 * 1024 * 1024;

#[derive(Clone, Debug, PartialEq)]
pub(crate) enum BinaryValue {
    Bool(bool),
    Int(i64),
    Double(f64),
    String(String),
    DateTimeMicros(i64),
    DurationMicros(i64),
    List(Vec<Option<BinaryValue>>),
    Enum(String),
    Embedded(Vec<Option<BinaryValue>>),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum BinaryKind {
    Null = 0,
    Bool = 1,
    Int = 2,
    Double = 3,
    String = 4,
    DateTime = 5,
    Duration = 6,
    List = 7,
    Enum = 8,
    Embedded = 9,
}

impl BinaryKind {
    fn from_tag(tag: u8) -> Result<Self, String> {
        match tag {
            0 => Ok(Self::Null),
            1 => Ok(Self::Bool),
            2 => Ok(Self::Int),
            3 => Ok(Self::Double),
            4 => Ok(Self::String),
            5 => Ok(Self::DateTime),
            6 => Ok(Self::Duration),
            7 => Ok(Self::List),
            8 => Ok(Self::Enum),
            9 => Ok(Self::Embedded),
            _ => Err(format!("unknown binary field kind `{tag}`")),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct FieldSlot {
    kind: BinaryKind,
    flags: u8,
    static_offset: u32,
    dynamic_offset: u32,
    dynamic_len: u32,
}

impl FieldSlot {
    fn null() -> Self {
        Self {
            kind: BinaryKind::Null,
            flags: NULL_FLAG,
            static_offset: 0,
            dynamic_offset: 0,
            dynamic_len: 0,
        }
    }

    fn is_null(self) -> bool {
        self.flags & NULL_FLAG != 0 || self.kind == BinaryKind::Null
    }
}

pub(crate) struct BinaryDocument<'a> {
    bytes: &'a [u8],
    field_count: usize,
    static_start: usize,
    dynamic_start: usize,
    static_len: usize,
    dynamic_len: usize,
}

impl<'a> BinaryDocument<'a> {
    pub(crate) fn parse(bytes: &'a [u8]) -> Result<Self, String> {
        if bytes.len() > MAX_OBJECT_SIZE {
            return Err("binary document exceeds the maximum object size".into());
        }
        if bytes.len() < HEADER_LEN {
            return Err("binary document is shorter than the header".into());
        }
        if &bytes[0..4] != MAGIC {
            return Err("binary document has an invalid magic header".into());
        }
        let version = read_u16(bytes, 4)?;
        if version != FORMAT_VERSION {
            return Err(format!("unsupported binary document version `{version}`"));
        }
        let header_len = read_u16(bytes, 6)? as usize;
        let field_count = read_u16(bytes, 8)? as usize;
        let static_len = read_u32(bytes, 12)? as usize;
        let dynamic_len = read_u32(bytes, 16)? as usize;
        let total_len = read_u32(bytes, 20)? as usize;
        let expected_header_len = HEADER_LEN + field_count.saturating_mul(SLOT_LEN);
        if header_len != expected_header_len {
            return Err("binary document header length does not match field count".into());
        }
        if total_len != bytes.len() {
            return Err("binary document total length does not match buffer length".into());
        }
        let static_start = header_len;
        let dynamic_start = static_start
            .checked_add(static_len)
            .ok_or_else(|| "binary document static section overflows".to_string())?;
        let expected_len = dynamic_start
            .checked_add(dynamic_len)
            .ok_or_else(|| "binary document dynamic section overflows".to_string())?;
        if expected_len != total_len {
            return Err("binary document sections do not match total length".into());
        }
        Ok(Self {
            bytes,
            field_count,
            static_start,
            dynamic_start,
            static_len,
            dynamic_len,
        })
    }

    pub(crate) fn field_count(&self) -> usize {
        self.field_count
    }

    pub(crate) fn field_value(&self, index: usize) -> Result<Option<BinaryValue>, String> {
        let slot = self.slot(index)?;
        if slot.is_null() {
            return Ok(None);
        }
        match slot.kind {
            BinaryKind::Bool => {
                let bytes = self.static_payload(slot, 1)?;
                Ok(Some(BinaryValue::Bool(bytes[0] != 0)))
            }
            BinaryKind::Int => Ok(Some(BinaryValue::Int(read_i64(
                self.static_payload(slot, 8)?,
                0,
            )?))),
            BinaryKind::Double => Ok(Some(BinaryValue::Double(read_f64(
                self.static_payload(slot, 8)?,
                0,
            )?))),
            BinaryKind::String => Ok(Some(BinaryValue::String(decode_utf8(
                self.dynamic_payload(slot)?,
            )?))),
            BinaryKind::DateTime => Ok(Some(BinaryValue::DateTimeMicros(read_i64(
                self.static_payload(slot, 8)?,
                0,
            )?))),
            BinaryKind::Duration => Ok(Some(BinaryValue::DurationMicros(read_i64(
                self.static_payload(slot, 8)?,
                0,
            )?))),
            BinaryKind::List => Ok(Some(BinaryValue::List(decode_list(
                self.dynamic_payload(slot)?,
            )?))),
            BinaryKind::Enum => Ok(Some(BinaryValue::Enum(decode_utf8(
                self.dynamic_payload(slot)?,
            )?))),
            BinaryKind::Embedded => {
                let nested = BinaryDocument::parse(self.dynamic_payload(slot)?)?;
                Ok(Some(BinaryValue::Embedded(nested.decode_all()?)))
            }
            BinaryKind::Null => Ok(None),
        }
    }

    pub(crate) fn field_payload_range(&self, index: usize) -> Result<Option<Range<usize>>, String> {
        let slot = self.slot(index)?;
        if slot.is_null() {
            return Ok(None);
        }
        match slot.kind {
            BinaryKind::Bool => Ok(Some(self.static_range(slot, 1)?)),
            BinaryKind::Int | BinaryKind::Double | BinaryKind::DateTime | BinaryKind::Duration => {
                Ok(Some(self.static_range(slot, 8)?))
            }
            BinaryKind::String | BinaryKind::List | BinaryKind::Enum | BinaryKind::Embedded => {
                Ok(Some(self.dynamic_range(slot)?))
            }
            BinaryKind::Null => Ok(None),
        }
    }

    fn decode_all(&self) -> Result<Vec<Option<BinaryValue>>, String> {
        (0..self.field_count)
            .map(|index| self.field_value(index))
            .collect()
    }

    fn slot(&self, index: usize) -> Result<FieldSlot, String> {
        if index >= self.field_count {
            return Err(format!("field index `{index}` is out of bounds"));
        }
        let offset = HEADER_LEN + index * SLOT_LEN;
        let kind = BinaryKind::from_tag(self.bytes[offset])?;
        Ok(FieldSlot {
            kind,
            flags: self.bytes[offset + 1],
            static_offset: read_u32(self.bytes, offset + 4)?,
            dynamic_offset: read_u32(self.bytes, offset + 8)?,
            dynamic_len: read_u32(self.bytes, offset + 12)?,
        })
    }

    fn static_range(&self, slot: FieldSlot, len: usize) -> Result<Range<usize>, String> {
        let relative = slot.static_offset as usize;
        let end = relative
            .checked_add(len)
            .ok_or_else(|| "binary static field offset overflows".to_string())?;
        if end > self.static_len {
            return Err("binary static field is outside the static section".into());
        }
        let start = self.static_start + relative;
        Ok(start..start + len)
    }

    fn static_payload(&self, slot: FieldSlot, len: usize) -> Result<&'a [u8], String> {
        let range = self.static_range(slot, len)?;
        Ok(&self.bytes[range])
    }

    fn dynamic_range(&self, slot: FieldSlot) -> Result<Range<usize>, String> {
        let relative = slot.dynamic_offset as usize;
        let len = slot.dynamic_len as usize;
        let end = relative
            .checked_add(len)
            .ok_or_else(|| "binary dynamic field offset overflows".to_string())?;
        if end > self.dynamic_len {
            return Err("binary dynamic field is outside the dynamic section".into());
        }
        let start = self.dynamic_start + relative;
        Ok(start..start + len)
    }

    fn dynamic_payload(&self, slot: FieldSlot) -> Result<&'a [u8], String> {
        let range = self.dynamic_range(slot)?;
        Ok(&self.bytes[range])
    }
}

pub(crate) fn write_document(fields: &[Option<BinaryValue>]) -> Result<Vec<u8>, String> {
    let header_len = HEADER_LEN + fields.len() * SLOT_LEN;
    if fields.len() > u16::MAX as usize {
        return Err("binary document cannot contain more than 65535 fields".into());
    }

    let mut slots = Vec::with_capacity(fields.len());
    let mut static_section = Vec::new();
    let mut dynamic_section = Vec::new();

    for field in fields {
        let Some(value) = field else {
            slots.push(FieldSlot::null());
            continue;
        };
        let kind = value_kind(value);
        match value {
            BinaryValue::Bool(value) => {
                let offset = push_static(&mut static_section, &[*value as u8])?;
                slots.push(static_slot(kind, offset));
            }
            BinaryValue::Int(value)
            | BinaryValue::DateTimeMicros(value)
            | BinaryValue::DurationMicros(value) => {
                let offset = push_static(&mut static_section, &value.to_le_bytes())?;
                slots.push(static_slot(kind, offset));
            }
            BinaryValue::Double(value) => {
                if !value.is_finite() {
                    return Err("binary document double values must be finite".into());
                }
                let offset = push_static(&mut static_section, &value.to_le_bytes())?;
                slots.push(static_slot(kind, offset));
            }
            BinaryValue::String(value) | BinaryValue::Enum(value) => {
                let (offset, len) = push_dynamic(&mut dynamic_section, value.as_bytes())?;
                slots.push(dynamic_slot(kind, offset, len));
            }
            BinaryValue::List(values) => {
                let bytes = encode_list(values)?;
                let (offset, len) = push_dynamic(&mut dynamic_section, &bytes)?;
                slots.push(dynamic_slot(kind, offset, len));
            }
            BinaryValue::Embedded(fields) => {
                let bytes = write_document(fields)?;
                let (offset, len) = push_dynamic(&mut dynamic_section, &bytes)?;
                slots.push(dynamic_slot(kind, offset, len));
            }
        }
    }

    let total_len = header_len
        .checked_add(static_section.len())
        .and_then(|len| len.checked_add(dynamic_section.len()))
        .ok_or_else(|| "binary document size overflows".to_string())?;
    if total_len > MAX_OBJECT_SIZE {
        return Err("binary document exceeds the maximum object size".into());
    }

    let mut bytes = Vec::with_capacity(total_len);
    bytes.extend_from_slice(MAGIC);
    push_u16(&mut bytes, FORMAT_VERSION);
    push_u16(&mut bytes, checked_u16(header_len, "header length")?);
    push_u16(&mut bytes, checked_u16(fields.len(), "field count")?);
    push_u16(&mut bytes, 0);
    push_u32(
        &mut bytes,
        checked_u32(static_section.len(), "static section length")?,
    );
    push_u32(
        &mut bytes,
        checked_u32(dynamic_section.len(), "dynamic section length")?,
    );
    push_u32(&mut bytes, checked_u32(total_len, "total length")?);
    for slot in slots {
        bytes.push(slot.kind as u8);
        bytes.push(slot.flags);
        push_u16(&mut bytes, 0);
        push_u32(&mut bytes, slot.static_offset);
        push_u32(&mut bytes, slot.dynamic_offset);
        push_u32(&mut bytes, slot.dynamic_len);
    }
    bytes.extend_from_slice(&static_section);
    bytes.extend_from_slice(&dynamic_section);
    Ok(bytes)
}

fn encode_value_record(value: &Option<BinaryValue>) -> Result<Vec<u8>, String> {
    let mut record = Vec::new();
    let Some(value) = value else {
        record.push(BinaryKind::Null as u8);
        record.push(NULL_FLAG);
        push_u16(&mut record, 0);
        push_u32(&mut record, 0);
        return Ok(record);
    };
    let kind = value_kind(value);
    let payload = value_payload(value)?;
    record.push(kind as u8);
    record.push(0);
    push_u16(&mut record, 0);
    push_u32(
        &mut record,
        checked_u32(payload.len(), "value payload length")?,
    );
    record.extend_from_slice(&payload);
    Ok(record)
}

fn decode_value_record(bytes: &[u8], offset: &mut usize) -> Result<Option<BinaryValue>, String> {
    let header = read_slice(bytes, *offset, 8)?;
    let kind = BinaryKind::from_tag(header[0])?;
    let flags = header[1];
    let len = read_u32(header, 4)? as usize;
    *offset += 8;
    let payload = read_slice(bytes, *offset, len)?;
    *offset += len;
    if flags & NULL_FLAG != 0 || kind == BinaryKind::Null {
        return Ok(None);
    }
    decode_payload(kind, payload).map(Some)
}

fn encode_list(values: &[Option<BinaryValue>]) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    push_u32(&mut bytes, checked_u32(values.len(), "list length")?);
    for value in values {
        bytes.extend_from_slice(&encode_value_record(value)?);
    }
    Ok(bytes)
}

fn decode_list(bytes: &[u8]) -> Result<Vec<Option<BinaryValue>>, String> {
    let count = read_u32(bytes, 0)? as usize;
    let mut offset = 4;
    let mut values = Vec::with_capacity(count);
    for _ in 0..count {
        values.push(decode_value_record(bytes, &mut offset)?);
    }
    if offset != bytes.len() {
        return Err("binary list contains trailing bytes".into());
    }
    Ok(values)
}

fn value_payload(value: &BinaryValue) -> Result<Vec<u8>, String> {
    match value {
        BinaryValue::Bool(value) => Ok(vec![*value as u8]),
        BinaryValue::Int(value)
        | BinaryValue::DateTimeMicros(value)
        | BinaryValue::DurationMicros(value) => Ok(value.to_le_bytes().to_vec()),
        BinaryValue::Double(value) => {
            if !value.is_finite() {
                return Err("binary document double values must be finite".into());
            }
            Ok(value.to_le_bytes().to_vec())
        }
        BinaryValue::String(value) | BinaryValue::Enum(value) => Ok(value.as_bytes().to_vec()),
        BinaryValue::List(values) => encode_list(values),
        BinaryValue::Embedded(fields) => write_document(fields),
    }
}

fn decode_payload(kind: BinaryKind, payload: &[u8]) -> Result<BinaryValue, String> {
    match kind {
        BinaryKind::Bool => Ok(BinaryValue::Bool(read_slice(payload, 0, 1)?[0] != 0)),
        BinaryKind::Int => Ok(BinaryValue::Int(read_i64(payload, 0)?)),
        BinaryKind::Double => Ok(BinaryValue::Double(read_f64(payload, 0)?)),
        BinaryKind::String => Ok(BinaryValue::String(decode_utf8(payload)?)),
        BinaryKind::DateTime => Ok(BinaryValue::DateTimeMicros(read_i64(payload, 0)?)),
        BinaryKind::Duration => Ok(BinaryValue::DurationMicros(read_i64(payload, 0)?)),
        BinaryKind::List => Ok(BinaryValue::List(decode_list(payload)?)),
        BinaryKind::Enum => Ok(BinaryValue::Enum(decode_utf8(payload)?)),
        BinaryKind::Embedded => {
            let nested = BinaryDocument::parse(payload)?;
            Ok(BinaryValue::Embedded(nested.decode_all()?))
        }
        BinaryKind::Null => Err("null payload cannot be decoded as a value".into()),
    }
}

fn value_kind(value: &BinaryValue) -> BinaryKind {
    match value {
        BinaryValue::Bool(_) => BinaryKind::Bool,
        BinaryValue::Int(_) => BinaryKind::Int,
        BinaryValue::Double(_) => BinaryKind::Double,
        BinaryValue::String(_) => BinaryKind::String,
        BinaryValue::DateTimeMicros(_) => BinaryKind::DateTime,
        BinaryValue::DurationMicros(_) => BinaryKind::Duration,
        BinaryValue::List(_) => BinaryKind::List,
        BinaryValue::Enum(_) => BinaryKind::Enum,
        BinaryValue::Embedded(_) => BinaryKind::Embedded,
    }
}

fn static_slot(kind: BinaryKind, static_offset: u32) -> FieldSlot {
    FieldSlot {
        kind,
        flags: 0,
        static_offset,
        dynamic_offset: 0,
        dynamic_len: 0,
    }
}

fn dynamic_slot(kind: BinaryKind, dynamic_offset: u32, dynamic_len: u32) -> FieldSlot {
    FieldSlot {
        kind,
        flags: 0,
        static_offset: 0,
        dynamic_offset,
        dynamic_len,
    }
}

fn push_static(section: &mut Vec<u8>, payload: &[u8]) -> Result<u32, String> {
    let offset = checked_u32(section.len(), "static field offset")?;
    section.extend_from_slice(payload);
    Ok(offset)
}

fn push_dynamic(section: &mut Vec<u8>, payload: &[u8]) -> Result<(u32, u32), String> {
    let offset = checked_u32(section.len(), "dynamic field offset")?;
    let len = checked_u32(payload.len(), "dynamic field length")?;
    section.extend_from_slice(payload);
    Ok((offset, len))
}

fn checked_u16(value: usize, name: &str) -> Result<u16, String> {
    value
        .try_into()
        .map_err(|_| format!("binary document {name} exceeds u16"))
}

fn checked_u32(value: usize, name: &str) -> Result<u32, String> {
    value
        .try_into()
        .map_err(|_| format!("binary document {name} exceeds u32"))
}

fn push_u16(bytes: &mut Vec<u8>, value: u16) {
    bytes.extend_from_slice(&value.to_le_bytes());
}

fn push_u32(bytes: &mut Vec<u8>, value: u32) {
    bytes.extend_from_slice(&value.to_le_bytes());
}

fn read_u16(bytes: &[u8], offset: usize) -> Result<u16, String> {
    let bytes = read_slice(bytes, offset, 2)?;
    Ok(u16::from_le_bytes([bytes[0], bytes[1]]))
}

fn read_u32(bytes: &[u8], offset: usize) -> Result<u32, String> {
    let bytes = read_slice(bytes, offset, 4)?;
    Ok(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
}

fn read_i64(bytes: &[u8], offset: usize) -> Result<i64, String> {
    let bytes = read_slice(bytes, offset, 8)?;
    Ok(i64::from_le_bytes(bytes.try_into().map_err(|_| {
        "binary i64 value must be 8 bytes".to_string()
    })?))
}

fn read_f64(bytes: &[u8], offset: usize) -> Result<f64, String> {
    let bytes = read_slice(bytes, offset, 8)?;
    Ok(f64::from_le_bytes(bytes.try_into().map_err(|_| {
        "binary f64 value must be 8 bytes".to_string()
    })?))
}

fn read_slice(bytes: &[u8], offset: usize, len: usize) -> Result<&[u8], String> {
    let end = offset
        .checked_add(len)
        .ok_or_else(|| "binary read offset overflows".to_string())?;
    bytes
        .get(offset..end)
        .ok_or_else(|| "binary read is outside the buffer".to_string())
}

fn decode_utf8(bytes: &[u8]) -> Result<String, String> {
    String::from_utf8(bytes.to_vec()).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_all_supported_value_shapes() {
        // Scenario: PERF-04 binary format covers every field shape Cindel
        // currently supports in generated models.
        // Covers: fixed primitives, strings, dates, durations, nullable
        // values, primitive lists, enums, embedded objects, and embedded lists.
        // Expected: A document can be decoded without JSON.
        let fields = vec![
            Some(BinaryValue::Bool(true)),
            Some(BinaryValue::Int(-42)),
            Some(BinaryValue::Double(12.5)),
            Some(BinaryValue::String("Cindel".to_string())),
            Some(BinaryValue::DateTimeMicros(1_773_779_200_000_000)),
            Some(BinaryValue::DurationMicros(123_456)),
            Some(BinaryValue::List(vec![
                Some(BinaryValue::Int(7)),
                Some(BinaryValue::String("tag".to_string())),
                None,
            ])),
            Some(BinaryValue::Enum("done".to_string())),
            None,
            Some(BinaryValue::Embedded(vec![
                Some(BinaryValue::String("nested".to_string())),
                Some(BinaryValue::Bool(false)),
            ])),
            Some(BinaryValue::List(vec![
                Some(BinaryValue::Embedded(vec![Some(BinaryValue::Int(1))])),
                Some(BinaryValue::Embedded(vec![Some(BinaryValue::Int(2))])),
            ])),
        ];

        let bytes = write_document(&fields).unwrap();
        let document = BinaryDocument::parse(&bytes).unwrap();

        assert_eq!(document.field_count(), fields.len());
        for (index, expected) in fields.iter().enumerate() {
            assert_eq!(&document.field_value(index).unwrap(), expected);
        }
    }

    #[test]
    fn reads_one_field_without_decoding_other_dynamic_fields() {
        // Scenario: Query/index extraction should be able to read one field by
        // offset without materializing unrelated values.
        // Covers: Slot table offsets and lazy field decoding.
        // Expected: A corrupt unrelated string payload does not affect reading
        // a fixed int field, but fails when that string field is requested.
        let fields = vec![
            Some(BinaryValue::Int(99)),
            Some(BinaryValue::String("valid".to_string())),
        ];
        let mut bytes = write_document(&fields).unwrap();
        let string_range = BinaryDocument::parse(&bytes)
            .unwrap()
            .field_payload_range(1)
            .unwrap()
            .unwrap();
        bytes[string_range.start] = 0xFF;

        let document = BinaryDocument::parse(&bytes).unwrap();
        assert_eq!(document.field_value(0).unwrap(), Some(BinaryValue::Int(99)));
        assert!(document.field_value(1).is_err());
    }

    #[test]
    fn rejects_invalid_headers_and_non_finite_doubles() {
        // Scenario: Format boundaries must fail closed before storage adopts
        // binary documents.
        // Covers: Header magic and unsupported double values.
        // Expected: Invalid format/version inputs are rejected.
        assert!(BinaryDocument::parse(b"not-a-document").is_err());
        assert!(write_document(&[Some(BinaryValue::Double(f64::NAN))]).is_err());
        assert!(write_document(&[Some(BinaryValue::Double(f64::INFINITY))]).is_err());
    }
}
