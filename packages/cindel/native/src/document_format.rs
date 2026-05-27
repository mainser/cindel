#![allow(dead_code)]

use std::ops::Range;
use std::str;

use crate::storage::{CollectionSchemaManifest, FieldSchemaManifest, IndexEntry, IndexValue};
use crate::wire::{decode_value, encode_index_value, WireIndexValue, WireValue};

const MAGIC: &[u8; 4] = b"CDBF";
const GENERIC_DOCUMENT_MAGIC: &[u8; 4] = b"CGD1";
const GENERIC_DOCUMENT_VERSION: u32 = 1;
const FORMAT_VERSION: u16 = 1;
const HEADER_LEN: usize = 24;
const SLOT_LEN: usize = 16;
const NULL_FLAG: u8 = 0x01;
const COMPACT_NULL_BOOL: u8 = 0xff;
const COMPACT_NULL_INT: i64 = i64::MIN;
const COMPACT_NULL_DOUBLE_BITS: u64 = 0x7ff8_0000_0000_0001;
const COMPACT_STRING_LIST_MARKER: u32 = u32::MAX;
const COMPACT_STRING_LIST_KIND: u8 = 1;
const COMPACT_STRING_LIST_HEADER_LEN: usize = 9;
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
    Object(Vec<(String, Option<BinaryValue>)>),
}

#[derive(Clone, Debug)]
pub(crate) enum BinarySortKey {
    Bool(bool),
    Int(i64),
    Double(f64),
    StringRange(Range<usize>),
    Owned(BinaryValue),
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct PreparedBinarySortField {
    index: usize,
    field_type: CompactFieldType,
    static_offset: usize,
    static_size: usize,
}

impl PreparedBinarySortField {
    pub(crate) fn is_compact_string(&self) -> bool {
        self.field_type == CompactFieldType::String
    }
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
    Object = 10,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum CompactFieldType {
    Bool,
    Int,
    Double,
    String,
    List,
    Object,
}

impl CompactFieldType {
    fn from_field(field: &FieldSchemaManifest) -> Result<Self, String> {
        let normalized = field
            .binary_type
            .strip_suffix('?')
            .unwrap_or(&field.binary_type);
        match normalized {
            "bool" => Ok(Self::Bool),
            "int" => Ok(Self::Int),
            "double" => Ok(Self::Double),
            "string" | "String" => Ok(Self::String),
            "list" => Ok(Self::List),
            "object" => Ok(Self::Object),
            other => Err(format!(
                "field `{}.{}` has unsupported binary type `{other}`",
                field.name, field.name
            )),
        }
    }

    fn static_size(self) -> usize {
        match self {
            Self::Bool => 1,
            Self::Int | Self::Double => 8,
            Self::String | Self::List | Self::Object => 3,
        }
    }
}

#[derive(Clone, Debug)]
pub(crate) struct PreparedBinaryFieldLayout {
    index: usize,
    field_type: CompactFieldType,
    static_offset: usize,
    static_size: usize,
    normalized_binary_type: &'static str,
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
            10 => Ok(Self::Object),
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
            BinaryKind::Object => Ok(Some(BinaryValue::Object(decode_object(
                self.dynamic_payload(slot)?,
            )?))),
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
            BinaryKind::String
            | BinaryKind::List
            | BinaryKind::Enum
            | BinaryKind::Embedded
            | BinaryKind::Object => Ok(Some(self.dynamic_range(slot)?)),
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

struct CompactBinaryDocument<'a> {
    bytes: &'a [u8],
    static_size: usize,
    field_offsets: Vec<Option<(CompactFieldType, usize)>>,
}

impl<'a> CompactBinaryDocument<'a> {
    fn parse(schema: &CollectionSchemaManifest, bytes: &'a [u8]) -> Result<Self, String> {
        if bytes.len() > MAX_OBJECT_SIZE {
            return Err("compact binary document exceeds the maximum object size".into());
        }
        if bytes.len() < 3 {
            return Err("compact binary document is shorter than the header".into());
        }
        let static_size = read_u24(bytes, 0)? as usize;
        let mut expected_static_size = 0usize;
        let mut field_offsets = Vec::with_capacity(schema.fields.len());
        for field in &schema.fields {
            if field.is_id {
                field_offsets.push(None);
                continue;
            }
            let field_type = CompactFieldType::from_field(field)?;
            field_offsets.push(Some((field_type, expected_static_size)));
            expected_static_size = expected_static_size
                .checked_add(field_type.static_size())
                .ok_or_else(|| "compact binary document static size overflows".to_string())?;
        }
        if static_size != expected_static_size {
            return Err("compact binary document static size does not match schema".into());
        }
        if bytes.len() < 3 + static_size {
            return Err("compact binary document static section is truncated".into());
        }
        Ok(Self {
            bytes,
            static_size,
            field_offsets,
        })
    }

    fn field_count(&self) -> usize {
        self.field_offsets.len()
    }

    fn field_value(&self, index: usize) -> Result<Option<BinaryValue>, String> {
        let Some(slot) = self.field_offsets.get(index).copied() else {
            return Err(format!("field index `{index}` is out of bounds"));
        };
        let Some((field_type, offset)) = slot else {
            return Ok(None);
        };
        let absolute = 3 + offset;
        match field_type {
            CompactFieldType::Bool => match self.bytes[absolute] {
                COMPACT_NULL_BOOL => Ok(None),
                0 => Ok(Some(BinaryValue::Bool(false))),
                1 => Ok(Some(BinaryValue::Bool(true))),
                value => Err(format!("invalid compact bool byte `{value}`")),
            },
            CompactFieldType::Int => {
                let value = read_i64(self.bytes, absolute)?;
                if value == COMPACT_NULL_INT {
                    Ok(None)
                } else {
                    Ok(Some(BinaryValue::Int(value)))
                }
            }
            CompactFieldType::Double => {
                let bits = read_u64(self.bytes, absolute)?;
                if bits == COMPACT_NULL_DOUBLE_BITS {
                    Ok(None)
                } else {
                    Ok(Some(BinaryValue::Double(f64::from_bits(bits))))
                }
            }
            CompactFieldType::String => {
                let Some(payload) = self.dynamic_payload(offset)? else {
                    return Ok(None);
                };
                Ok(Some(BinaryValue::String(decode_utf8(payload)?)))
            }
            CompactFieldType::List => {
                let Some(payload) = self.dynamic_payload(offset)? else {
                    return Ok(None);
                };
                Ok(Some(BinaryValue::List(decode_list(payload)?)))
            }
            CompactFieldType::Object => {
                let Some(payload) = self.dynamic_payload(offset)? else {
                    return Ok(None);
                };
                Ok(Some(BinaryValue::Object(decode_object(payload)?)))
            }
        }
    }

    fn field_sort_key(&self, index: usize) -> Result<Option<BinarySortKey>, String> {
        let Some(slot) = self.field_offsets.get(index).copied() else {
            return Err(format!("field index `{index}` is out of bounds"));
        };
        let Some((field_type, offset)) = slot else {
            return Ok(None);
        };
        let absolute = 3 + offset;
        match field_type {
            CompactFieldType::Bool => match self.bytes[absolute] {
                COMPACT_NULL_BOOL => Ok(None),
                0 => Ok(Some(BinarySortKey::Bool(false))),
                1 => Ok(Some(BinarySortKey::Bool(true))),
                value => Err(format!("invalid compact bool byte `{value}`")),
            },
            CompactFieldType::Int => {
                let value = read_i64(self.bytes, absolute)?;
                if value == COMPACT_NULL_INT {
                    Ok(None)
                } else {
                    Ok(Some(BinarySortKey::Int(value)))
                }
            }
            CompactFieldType::Double => {
                let bits = read_u64(self.bytes, absolute)?;
                if bits == COMPACT_NULL_DOUBLE_BITS {
                    Ok(None)
                } else {
                    Ok(Some(BinarySortKey::Double(f64::from_bits(bits))))
                }
            }
            CompactFieldType::String => {
                let Some(range) = self.dynamic_payload_range(offset)? else {
                    return Ok(None);
                };
                decode_utf8(&self.bytes[range.clone()])?;
                Ok(Some(BinarySortKey::StringRange(range)))
            }
            CompactFieldType::List | CompactFieldType::Object => {
                Ok(self.field_value(index)?.map(BinarySortKey::Owned))
            }
        }
    }

    fn string_payload(&self, index: usize) -> Result<Option<&'a str>, String> {
        let Some(slot) = self.field_offsets.get(index).copied() else {
            return Err(format!("field index `{index}` is out of bounds"));
        };
        let Some((field_type, offset)) = slot else {
            return Ok(None);
        };
        if field_type != CompactFieldType::String {
            return Err(format!("field index `{index}` is not a string field"));
        }
        let Some(payload) = self.dynamic_payload(offset)? else {
            return Ok(None);
        };
        str::from_utf8(payload)
            .map(Some)
            .map_err(|error| format!("invalid UTF-8 string: {error}"))
    }

    fn dynamic_payload_range(&self, static_offset: usize) -> Result<Option<Range<usize>>, String> {
        let relative = read_u24(self.bytes, 3 + static_offset)? as usize;
        if relative == 0 {
            return Ok(None);
        }
        if relative < self.static_size {
            return Err("compact dynamic field points into static section".into());
        }
        let length_offset = 3 + relative;
        let len = read_u24(self.bytes, length_offset)? as usize;
        let start = length_offset
            .checked_add(3)
            .ok_or_else(|| "compact dynamic field offset overflows".to_string())?;
        let end = start
            .checked_add(len)
            .ok_or_else(|| "compact dynamic field length overflows".to_string())?;
        if end > self.bytes.len() {
            return Err("compact dynamic field payload is truncated".into());
        }
        Ok(Some(start..end))
    }

    fn dynamic_payload(&self, static_offset: usize) -> Result<Option<&'a [u8]>, String> {
        Ok(self
            .dynamic_payload_range(static_offset)?
            .map(|range| &self.bytes[range]))
    }
}

pub(crate) struct PreparedBinaryFieldUpdates {
    static_size: usize,
    updates: Vec<PreparedBinaryFieldUpdate>,
}

struct PreparedBinaryFieldUpdate {
    field_name: String,
    field_type: CompactFieldType,
    static_offset: usize,
    nullable: bool,
    value: WireValue,
}

pub(crate) fn validate_generic_document(bytes: &[u8]) -> Result<(), String> {
    if bytes.len() < 8 {
        return Err("generic document is shorter than the header".into());
    }
    if &bytes[..4] != GENERIC_DOCUMENT_MAGIC {
        return Err("generic document has an invalid magic header".into());
    }
    let version = u32::from_le_bytes([bytes[4], bytes[5], bytes[6], bytes[7]]);
    if version != GENERIC_DOCUMENT_VERSION {
        return Err(format!("unsupported generic document version `{version}`"));
    }
    match decode_value(&bytes[8..])? {
        WireValue::Object(_) => Ok(()),
        _ => Err("generic document root must be an object".into()),
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
            BinaryValue::Object(entries) => {
                let bytes = encode_object(entries)?;
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

fn is_compact_string_list(bytes: &[u8]) -> bool {
    bytes.len() >= COMPACT_STRING_LIST_HEADER_LEN
        && read_u32(bytes, 0).ok() == Some(COMPACT_STRING_LIST_MARKER)
        && bytes[4] == COMPACT_STRING_LIST_KIND
}

fn decode_compact_string_list(bytes: &[u8]) -> Result<Vec<Option<BinaryValue>>, String> {
    if !is_compact_string_list(bytes) {
        return Err("binary list is not a compact string list".into());
    }
    let count = read_u32(bytes, 5)? as usize;
    let offsets_start = COMPACT_STRING_LIST_HEADER_LEN;
    let offsets_len = count
        .checked_mul(3)
        .ok_or_else(|| "compact string list offsets overflow".to_string())?;
    read_slice(bytes, offsets_start, offsets_len)?;
    let mut values = Vec::with_capacity(count);
    let mut max_end = offsets_start + offsets_len;
    for index in 0..count {
        let offset = read_u24(bytes, offsets_start + index * 3)? as usize;
        if offset == 0 {
            values.push(None);
            continue;
        }
        if offset < max_end {
            return Err("compact string list payload points into offsets".into());
        }
        let len = read_u24(bytes, offset)? as usize;
        let start = offset
            .checked_add(3)
            .ok_or_else(|| "compact string list payload offset overflow".to_string())?;
        let end = start
            .checked_add(len)
            .ok_or_else(|| "compact string list payload length overflow".to_string())?;
        let payload = read_slice(bytes, start, len)?;
        max_end = max_end.max(end);
        values.push(Some(BinaryValue::String(
            str::from_utf8(payload)
                .map_err(|_| "compact string list contains invalid utf-8".to_string())?
                .to_string(),
        )));
    }
    if max_end != bytes.len() {
        return Err("compact string list contains trailing bytes".into());
    }
    Ok(values)
}

fn decode_nested_string_list(bytes: &[u8]) -> Result<Vec<Option<BinaryValue>>, String> {
    if bytes.len() < 3 {
        return Err("nested string list is shorter than the header".into());
    }
    let static_size = read_u24(bytes, 0)? as usize;
    if static_size % 3 != 0 {
        return Err("nested string list static size is not aligned".into());
    }
    let static_end = 3usize
        .checked_add(static_size)
        .ok_or_else(|| "nested string list static section overflows".to_string())?;
    read_slice(bytes, 0, static_end)?;
    let count = static_size / 3;
    let mut values = Vec::with_capacity(count);
    let mut max_end = static_end;
    for index in 0..count {
        let offset = read_u24(bytes, 3 + index * 3)? as usize;
        if offset == 0 {
            values.push(None);
            continue;
        }
        if offset < static_size {
            return Err("nested string list payload points into offsets".into());
        }
        let absolute = 3usize
            .checked_add(offset)
            .ok_or_else(|| "nested string list payload offset overflow".to_string())?;
        let len = read_u24(bytes, absolute)? as usize;
        let start = absolute
            .checked_add(3)
            .ok_or_else(|| "nested string list payload offset overflow".to_string())?;
        let end = start
            .checked_add(len)
            .ok_or_else(|| "nested string list payload length overflow".to_string())?;
        let payload = read_slice(bytes, start, len)?;
        max_end = max_end.max(end);
        values.push(Some(BinaryValue::String(
            str::from_utf8(payload)
                .map_err(|_| "nested string list contains invalid utf-8".to_string())?
                .to_string(),
        )));
    }
    if max_end != bytes.len() {
        return Err("nested string list contains trailing bytes".into());
    }
    Ok(values)
}

fn encode_list(values: &[Option<BinaryValue>]) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    push_u32(&mut bytes, checked_u32(values.len(), "list length")?);
    for value in values {
        bytes.extend_from_slice(&encode_value_record(value)?);
    }
    Ok(bytes)
}

pub(crate) fn write_list(values: &[Option<BinaryValue>]) -> Result<Vec<u8>, String> {
    encode_list(values)
}

pub(crate) fn write_value_record(value: &Option<BinaryValue>) -> Result<Vec<u8>, String> {
    encode_value_record(value)
}

pub(crate) fn write_string_value_record(payload: &[u8]) -> Result<Vec<u8>, String> {
    let mut record = Vec::new();
    record.push(BinaryKind::String as u8);
    record.push(0);
    push_u16(&mut record, 0);
    push_u32(
        &mut record,
        checked_u32(payload.len(), "value payload length")?,
    );
    record.extend_from_slice(payload);
    Ok(record)
}

pub(crate) fn write_compact_string_list_records(
    records: &[Option<Vec<u8>>],
) -> Result<Vec<u8>, String> {
    let static_size = records
        .len()
        .checked_mul(3)
        .ok_or_else(|| "nested string list static size overflows".to_string())?;
    if static_size > 0x00ff_ffff {
        return Err("nested string list static size is too large".into());
    }
    let mut bytes = vec![0; 3 + static_size];
    write_u24(&mut bytes, 0, static_size)?;
    for (index, record) in records.iter().enumerate() {
        let Some(payload) = record else {
            continue;
        };
        let offset = checked_u32(bytes.len() - 3, "nested string list offset")?;
        if offset > 0x00ff_ffff {
            return Err("nested string list offset is too large".into());
        }
        write_u24(&mut bytes, 3 + index * 3, offset as usize)?;
        if payload.len() > 0x00ff_ffff {
            return Err("nested string list payload is too large".into());
        }
        let mut header = [0u8; 3];
        write_u24(&mut header, 0, payload.len())?;
        bytes.extend_from_slice(&header);
        bytes.extend_from_slice(payload);
    }
    Ok(bytes)
}

pub(crate) fn write_list_records(records: &[Option<Vec<u8>>]) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    push_u32(&mut bytes, checked_u32(records.len(), "list length")?);
    for record in records {
        match record {
            Some(record) => bytes.extend_from_slice(record),
            None => bytes.extend_from_slice(&encode_value_record(&None)?),
        }
    }
    Ok(bytes)
}

fn encode_object(entries: &[(String, Option<BinaryValue>)]) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    push_u32(
        &mut bytes,
        checked_u32(entries.len(), "object field count")?,
    );
    for (name, value) in entries {
        push_u32(
            &mut bytes,
            checked_u32(name.len(), "object field name length")?,
        );
        bytes.extend_from_slice(name.as_bytes());
        bytes.extend_from_slice(&encode_value_record(value)?);
    }
    Ok(bytes)
}

pub(crate) fn decode_list(bytes: &[u8]) -> Result<Vec<Option<BinaryValue>>, String> {
    if is_compact_string_list(bytes) {
        return decode_compact_string_list(bytes);
    }
    if let Ok(values) = decode_nested_string_list(bytes) {
        return Ok(values);
    }
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

fn decode_object(bytes: &[u8]) -> Result<Vec<(String, Option<BinaryValue>)>, String> {
    let count = read_u32(bytes, 0)? as usize;
    let mut offset = 4;
    let mut entries = Vec::with_capacity(count);
    for _ in 0..count {
        let name_len = read_u32(bytes, offset)? as usize;
        offset += 4;
        let name = decode_utf8(read_slice(bytes, offset, name_len)?)?;
        offset += name_len;
        let value = decode_value_record(bytes, &mut offset)?;
        entries.push((name, value));
    }
    if offset != bytes.len() {
        return Err("binary object contains trailing bytes".into());
    }
    Ok(entries)
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
        BinaryValue::Object(entries) => encode_object(entries),
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
        BinaryKind::Object => Ok(BinaryValue::Object(decode_object(payload)?)),
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
        BinaryValue::Object(_) => BinaryKind::Object,
    }
}

pub(crate) fn read_binary_field(
    schema: &CollectionSchemaManifest,
    bytes: &[u8],
    field: &str,
) -> Result<Option<BinaryValue>, String> {
    let Some(index) = schema
        .fields
        .iter()
        .position(|schema_field| schema_field.name == field)
    else {
        return Err(format!(
            "field `{field}` is not declared in schema `{}`",
            schema.name
        ));
    };
    read_binary_field_at(schema, bytes, index)
}

pub(crate) fn read_binary_field_payload<'a>(
    schema: &'a CollectionSchemaManifest,
    bytes: &'a [u8],
    field: &str,
) -> Result<Option<(&'static str, &'a [u8])>, String> {
    let layout = prepare_binary_field_layout(schema, field)?;
    read_binary_field_payload_prepared(bytes, &layout)
}

pub(crate) fn read_binary_field_payload_prepared<'a>(
    bytes: &'a [u8],
    layout: &PreparedBinaryFieldLayout,
) -> Result<Option<(&'static str, &'a [u8])>, String> {
    if bytes.starts_with(MAGIC) {
        let document = BinaryDocument::parse(bytes)?;
        let Some(range) = document.field_payload_range(layout.index)? else {
            return Ok(None);
        };
        return Ok(Some((layout.normalized_binary_type, &bytes[range])));
    }
    validate_prepared_compact_document(bytes, layout.static_size)?;
    let payload = match layout.field_type {
        CompactFieldType::Bool => match bytes[3 + layout.static_offset] {
            COMPACT_NULL_BOOL => return Ok(None),
            _ => &bytes[3 + layout.static_offset..3 + layout.static_offset + 1],
        },
        CompactFieldType::Int | CompactFieldType::Double => {
            let start = 3 + layout.static_offset;
            &bytes[start..start + 8]
        }
        CompactFieldType::String | CompactFieldType::List | CompactFieldType::Object => {
            let document = CompactBinaryDocument {
                bytes,
                static_size: layout.static_size,
                field_offsets: Vec::new(),
            };
            let Some(payload) = document.dynamic_payload(layout.static_offset)? else {
                return Ok(None);
            };
            payload
        }
    };
    Ok(Some((layout.normalized_binary_type, payload)))
}

pub(crate) fn read_binary_bool_field_prepared(
    bytes: &[u8],
    layout: &PreparedBinaryFieldLayout,
) -> Result<Option<bool>, String> {
    if bytes.starts_with(MAGIC) {
        let document = BinaryDocument::parse(bytes)?;
        return match document.field_value(layout.index)? {
            Some(BinaryValue::Bool(value)) => Ok(Some(value)),
            Some(_) => Err(format!(
                "field index `{}` is not a bool field",
                layout.index
            )),
            None => Ok(None),
        };
    }
    if layout.field_type != CompactFieldType::Bool {
        return Err(format!(
            "field index `{}` is not a bool field",
            layout.index
        ));
    }
    validate_prepared_compact_document(bytes, layout.static_size)?;
    match bytes[3 + layout.static_offset] {
        COMPACT_NULL_BOOL => Ok(None),
        0 => Ok(Some(false)),
        1 => Ok(Some(true)),
        value => Err(format!("invalid compact bool byte `{value}`")),
    }
}

pub(crate) fn read_binary_field_at(
    schema: &CollectionSchemaManifest,
    bytes: &[u8],
    index: usize,
) -> Result<Option<BinaryValue>, String> {
    if bytes.starts_with(MAGIC) {
        let document = BinaryDocument::parse(bytes)?;
        if index >= document.field_count() {
            return Ok(None);
        }
        return document.field_value(index);
    }
    let document = CompactBinaryDocument::parse(schema, bytes)?;
    if index >= document.field_count() {
        return Ok(None);
    }
    document.field_value(index)
}

pub(crate) fn prepare_binary_field_layout(
    schema: &CollectionSchemaManifest,
    field: &str,
) -> Result<PreparedBinaryFieldLayout, String> {
    let mut static_size = 0usize;
    let mut target = None;
    for (index, schema_field) in schema.fields.iter().enumerate() {
        if schema_field.is_id {
            if schema_field.name == field {
                target = None;
            }
            continue;
        }
        let field_type = CompactFieldType::from_field(schema_field)?;
        if schema_field.name == field {
            target = Some((
                index,
                field_type,
                static_size,
                normalized_binary_type_name(&schema_field.binary_type),
            ));
        }
        static_size = static_size
            .checked_add(field_type.static_size())
            .ok_or_else(|| "compact binary document static size overflows".to_string())?;
    }
    let Some((index, field_type, static_offset, normalized_binary_type)) = target else {
        return Err(format!("field `{field}` is not part of `{}`", schema.name));
    };
    Ok(PreparedBinaryFieldLayout {
        index,
        field_type,
        static_offset,
        static_size,
        normalized_binary_type,
    })
}

fn normalized_binary_type(binary_type: &str) -> &str {
    binary_type.strip_suffix('?').unwrap_or(binary_type)
}

fn normalized_binary_type_name(binary_type: &str) -> &'static str {
    match normalized_binary_type(binary_type) {
        "bool" => "bool",
        "int" => "int",
        "double" => "double",
        "string" => "string",
        "String" => "String",
        "list" => "list",
        "object" => "object",
        _ => "unknown",
    }
}

pub(crate) fn read_binary_sort_key_at(
    schema: &CollectionSchemaManifest,
    bytes: &[u8],
    index: usize,
) -> Result<Option<BinarySortKey>, String> {
    if bytes.starts_with(MAGIC) {
        let document = BinaryDocument::parse(bytes)?;
        if index >= document.field_count() {
            return Ok(None);
        }
        return document
            .field_value(index)
            .map(|value| value.map(BinarySortKey::Owned));
    }
    let document = CompactBinaryDocument::parse(schema, bytes)?;
    if index >= document.field_count() {
        return Ok(None);
    }
    document.field_sort_key(index)
}

pub(crate) fn prepare_binary_sort_field(
    schema: &CollectionSchemaManifest,
    index: usize,
) -> Result<PreparedBinarySortField, String> {
    let mut static_offset = 0usize;
    for (field_index, field) in schema.fields.iter().enumerate() {
        if field.is_id {
            if field_index == index {
                return Err("id is stored outside compact binary documents".into());
            }
            continue;
        }
        let field_type = CompactFieldType::from_field(field)?;
        let field_static_size = field_type.static_size();
        if field_index == index {
            return Ok(PreparedBinarySortField {
                index,
                field_type,
                static_offset,
                static_size: schema_binary_static_size(schema)?,
            });
        }
        static_offset = static_offset
            .checked_add(field_static_size)
            .ok_or_else(|| "compact binary document static size overflows".to_string())?;
    }
    Err(format!("field index `{index}` is out of bounds"))
}

pub(crate) fn read_prepared_binary_sort_key(
    schema: &CollectionSchemaManifest,
    bytes: &[u8],
    field: &PreparedBinarySortField,
) -> Result<Option<BinarySortKey>, String> {
    if bytes.starts_with(MAGIC) {
        return read_binary_sort_key_at(schema, bytes, field.index);
    }
    if bytes.len() > MAX_OBJECT_SIZE {
        return Err("compact binary document exceeds the maximum object size".into());
    }
    if bytes.len() < 3 {
        return Err("compact binary document is shorter than the header".into());
    }
    let static_size = read_u24(bytes, 0)? as usize;
    if static_size != field.static_size {
        return Err("compact binary document static size does not match schema".into());
    }
    if bytes.len() < 3 + static_size {
        return Err("compact binary document static section is truncated".into());
    }
    read_compact_prepared_sort_key(bytes, field)
}

pub(crate) fn read_prepared_binary_string_sort_range(
    bytes: &[u8],
    field: &PreparedBinarySortField,
) -> Result<Option<Option<Range<usize>>>, String> {
    if !field.is_compact_string() || bytes.starts_with(MAGIC) {
        return Ok(None);
    }
    validate_prepared_compact_document(bytes, field.static_size)?;
    let range = compact_dynamic_payload_range(bytes, field.static_size, field.static_offset)?;
    Ok(Some(range))
}

fn validate_prepared_compact_document(bytes: &[u8], static_size: usize) -> Result<(), String> {
    if bytes.len() > MAX_OBJECT_SIZE {
        return Err("compact binary document exceeds the maximum object size".into());
    }
    if bytes.len() < 3 {
        return Err("compact binary document is shorter than the header".into());
    }
    let document_static_size = read_u24(bytes, 0)? as usize;
    if document_static_size != static_size {
        return Err("compact binary document static size does not match schema".into());
    }
    if bytes.len() < 3 + static_size {
        return Err("compact binary document static section is truncated".into());
    }
    Ok(())
}

fn read_compact_prepared_sort_key(
    bytes: &[u8],
    field: &PreparedBinarySortField,
) -> Result<Option<BinarySortKey>, String> {
    let absolute = 3 + field.static_offset;
    match field.field_type {
        CompactFieldType::Bool => match bytes[absolute] {
            COMPACT_NULL_BOOL => Ok(None),
            0 => Ok(Some(BinarySortKey::Bool(false))),
            1 => Ok(Some(BinarySortKey::Bool(true))),
            value => Err(format!("invalid compact bool byte `{value}`")),
        },
        CompactFieldType::Int => {
            let value = read_i64(bytes, absolute)?;
            if value == COMPACT_NULL_INT {
                Ok(None)
            } else {
                Ok(Some(BinarySortKey::Int(value)))
            }
        }
        CompactFieldType::Double => {
            let bits = read_u64(bytes, absolute)?;
            if bits == COMPACT_NULL_DOUBLE_BITS {
                Ok(None)
            } else {
                Ok(Some(BinarySortKey::Double(f64::from_bits(bits))))
            }
        }
        CompactFieldType::String => {
            let Some(range) =
                compact_dynamic_payload_range(bytes, field.static_size, field.static_offset)?
            else {
                return Ok(None);
            };
            decode_utf8(&bytes[range.clone()])?;
            Ok(Some(BinarySortKey::StringRange(range)))
        }
        CompactFieldType::List | CompactFieldType::Object => {
            read_binary_field_at_placeholder(bytes, field)
        }
    }
}

fn read_binary_field_at_placeholder(
    bytes: &[u8],
    field: &PreparedBinarySortField,
) -> Result<Option<BinarySortKey>, String> {
    let document = CompactBinaryDocument {
        bytes,
        static_size: field.static_size,
        field_offsets: Vec::new(),
    };
    match field.field_type {
        CompactFieldType::List => {
            let Some(payload) = document.dynamic_payload(field.static_offset)? else {
                return Ok(None);
            };
            Ok(Some(BinarySortKey::Owned(BinaryValue::List(decode_list(
                payload,
            )?))))
        }
        CompactFieldType::Object => {
            let Some(payload) = document.dynamic_payload(field.static_offset)? else {
                return Ok(None);
            };
            Ok(Some(BinarySortKey::Owned(BinaryValue::Object(
                decode_object(payload)?,
            ))))
        }
        CompactFieldType::Bool
        | CompactFieldType::Int
        | CompactFieldType::Double
        | CompactFieldType::String => unreachable!("scalar compact sort keys are handled directly"),
    }
}

fn compact_dynamic_payload_range(
    bytes: &[u8],
    static_size: usize,
    static_offset: usize,
) -> Result<Option<Range<usize>>, String> {
    let relative = read_u24(bytes, 3 + static_offset)? as usize;
    if relative == 0 {
        return Ok(None);
    }
    if relative < static_size {
        return Err("compact dynamic field points into static section".into());
    }
    let length_offset = 3 + relative;
    let len = read_u24(bytes, length_offset)? as usize;
    let start = length_offset
        .checked_add(3)
        .ok_or_else(|| "compact dynamic field offset overflows".to_string())?;
    let end = start
        .checked_add(len)
        .ok_or_else(|| "compact dynamic field length overflows".to_string())?;
    if end > bytes.len() {
        return Err("compact dynamic field payload is truncated".into());
    }
    Ok(Some(start..end))
}

fn schema_binary_static_size(schema: &CollectionSchemaManifest) -> Result<usize, String> {
    let mut static_size = 0usize;
    for field in &schema.fields {
        if field.is_id {
            continue;
        }
        let field_type = CompactFieldType::from_field(field)?;
        static_size = static_size
            .checked_add(field_type.static_size())
            .ok_or_else(|| "compact binary document static size overflows".to_string())?;
    }
    Ok(static_size)
}

pub(crate) fn validate_binary_document(
    schema: &CollectionSchemaManifest,
    bytes: &[u8],
) -> Result<(), String> {
    if bytes.starts_with(MAGIC) {
        BinaryDocument::parse(bytes).map(|_| ())
    } else {
        CompactBinaryDocument::parse(schema, bytes).map(|_| ())
    }
}

pub(crate) fn update_binary_fields(
    schema: &CollectionSchemaManifest,
    bytes: &mut [u8],
    updates: &[(String, WireValue)],
) -> Result<(), String> {
    let prepared = prepare_binary_field_updates(schema, updates)?;
    apply_prepared_binary_field_updates(bytes, &prepared)
}

pub(crate) fn prepare_binary_field_updates(
    schema: &CollectionSchemaManifest,
    updates: &[(String, WireValue)],
) -> Result<PreparedBinaryFieldUpdates, String> {
    let mut static_size = 0usize;
    let mut field_offsets = Vec::with_capacity(schema.fields.len());
    for field in &schema.fields {
        if field.is_id {
            field_offsets.push(None);
            continue;
        }
        let field_type = CompactFieldType::from_field(field)?;
        field_offsets.push(Some((field_type, static_size)));
        static_size = static_size
            .checked_add(field_type.static_size())
            .ok_or_else(|| "compact binary document static size overflows".to_string())?;
    }
    let mut prepared = Vec::with_capacity(updates.len());
    for (field_name, value) in updates {
        let Some((field_index, field)) = schema
            .fields
            .iter()
            .enumerate()
            .find(|(_, field)| &field.name == field_name)
        else {
            return Err(format!(
                "field `{field_name}` is not declared in schema `{}`",
                schema.name
            ));
        };
        if field.is_id {
            return Err(format!(
                "query updates cannot change id field `{}`",
                field.name
            ));
        }
        let (field_type, static_offset) = field_offsets
            .get(field_index)
            .copied()
            .flatten()
            .ok_or_else(|| format!("field `{field_name}` is out of bounds"))?;
        validate_prepared_binary_update(field, field_type, value)?;
        prepared.push(PreparedBinaryFieldUpdate {
            field_name: field_name.clone(),
            field_type,
            static_offset,
            nullable: is_nullable_field(field),
            value: value.clone(),
        });
    }
    Ok(PreparedBinaryFieldUpdates {
        static_size,
        updates: prepared,
    })
}

pub(crate) fn apply_prepared_binary_field_updates(
    bytes: &mut [u8],
    prepared: &PreparedBinaryFieldUpdates,
) -> Result<(), String> {
    if bytes.starts_with(MAGIC) {
        return Err("query updates require compact Cindel binary documents".into());
    }
    if bytes.len() < 3 {
        return Err("compact binary document is shorter than the header".into());
    }
    let static_size = read_u24(bytes, 0)? as usize;
    if static_size != prepared.static_size {
        return Err("compact binary document static size does not match schema".into());
    }
    if bytes.len() < 3 + static_size {
        return Err("compact binary document static section is truncated".into());
    }
    for update in &prepared.updates {
        let absolute = 3 + update.static_offset;
        match (update.field_type, &update.value) {
            (CompactFieldType::Bool, WireValue::Null) if update.nullable => {
                bytes[absolute] = COMPACT_NULL_BOOL;
            }
            (CompactFieldType::Bool, WireValue::Bool(value)) => {
                bytes[absolute] = u8::from(*value);
            }
            (CompactFieldType::Int, WireValue::Null) if update.nullable => {
                bytes[absolute..absolute + 8].copy_from_slice(&COMPACT_NULL_INT.to_le_bytes());
            }
            (CompactFieldType::Int, WireValue::Int(value)) => {
                bytes[absolute..absolute + 8].copy_from_slice(&value.to_le_bytes());
            }
            (CompactFieldType::Double, WireValue::Null) if update.nullable => {
                bytes[absolute..absolute + 8]
                    .copy_from_slice(&COMPACT_NULL_DOUBLE_BITS.to_le_bytes());
            }
            (CompactFieldType::Double, WireValue::Double(value)) if value.is_finite() => {
                bytes[absolute..absolute + 8].copy_from_slice(&value.to_le_bytes());
            }
            (CompactFieldType::String | CompactFieldType::List | CompactFieldType::Object, _) => {
                return Err(format!(
                    "query updates for dynamic field `{}` are not supported yet",
                    update.field_name
                ));
            }
            (_, WireValue::Null) => {
                return Err(format!("field `{}` is not nullable", update.field_name));
            }
            _ => {
                return Err(format!(
                    "query update value does not match field `{}`",
                    update.field_name
                ));
            }
        }
    }
    Ok(())
}

fn validate_prepared_binary_update(
    field: &FieldSchemaManifest,
    field_type: CompactFieldType,
    value: &WireValue,
) -> Result<(), String> {
    match (field_type, value) {
        (CompactFieldType::Bool, WireValue::Null)
        | (CompactFieldType::Int, WireValue::Null)
        | (CompactFieldType::Double, WireValue::Null)
            if is_nullable_field(field) =>
        {
            Ok(())
        }
        (CompactFieldType::Bool, WireValue::Bool(_))
        | (CompactFieldType::Int, WireValue::Int(_)) => Ok(()),
        (CompactFieldType::Double, WireValue::Double(value)) if value.is_finite() => Ok(()),
        (CompactFieldType::String | CompactFieldType::List | CompactFieldType::Object, _) => {
            Err(format!(
                "query updates for dynamic field `{}` are not supported yet",
                field.name
            ))
        }
        (_, WireValue::Null) => Err(format!("field `{}` is not nullable", field.name)),
        _ => Err(format!(
            "query update value does not match field `{}`",
            field.name
        )),
    }
}

fn is_nullable_field(field: &FieldSchemaManifest) -> bool {
    field.dart_type.ends_with('?') || field.binary_type.ends_with('?')
}

pub(crate) fn binary_to_wire_value(value: Option<&BinaryValue>) -> Result<WireValue, String> {
    let Some(value) = value else {
        return Ok(WireValue::Null);
    };
    Ok(match value {
        BinaryValue::Bool(value) => WireValue::Bool(*value),
        BinaryValue::Int(value)
        | BinaryValue::DateTimeMicros(value)
        | BinaryValue::DurationMicros(value) => WireValue::Int(*value),
        BinaryValue::Double(value) if value.is_finite() => WireValue::Double(*value),
        BinaryValue::Double(_) => return Err("binary double cannot be represented on wire".into()),
        BinaryValue::String(value) | BinaryValue::Enum(value) => WireValue::String(value.clone()),
        BinaryValue::List(values) => WireValue::List(
            values
                .iter()
                .map(|value| binary_to_wire_value(value.as_ref()))
                .collect::<Result<Vec<_>, String>>()?,
        ),
        BinaryValue::Embedded(fields) => WireValue::List(
            fields
                .iter()
                .map(|value| binary_to_wire_value(value.as_ref()))
                .collect::<Result<Vec<_>, String>>()?,
        ),
        BinaryValue::Object(entries) => WireValue::Object(
            entries
                .iter()
                .map(|(name, value)| Ok((name.clone(), binary_to_wire_value(value.as_ref())?)))
                .collect::<Result<Vec<_>, String>>()?,
        ),
    })
}

pub(crate) fn index_entries_from_binary_document(
    schema: &CollectionSchemaManifest,
    bytes: &[u8],
) -> Result<Vec<IndexEntry>, String> {
    if bytes.starts_with(MAGIC) {
        let document = BinaryDocument::parse(bytes)?;
        return index_entries_from_binary_reader(schema, |index| {
            if index >= document.field_count() {
                Ok(None)
            } else {
                document.field_value(index)
            }
        });
    }
    let document = CompactBinaryDocument::parse(schema, bytes)?;
    index_entries_from_compact_binary_document(schema, &document)
}

pub(crate) fn for_each_index_entry_from_binary_document(
    schema: &CollectionSchemaManifest,
    bytes: &[u8],
    mut callback: impl FnMut(&str, IndexValue) -> Result<(), String>,
) -> Result<(), String> {
    if bytes.starts_with(MAGIC) {
        for entry in index_entries_from_binary_document(schema, bytes)? {
            callback(&entry.name, entry.value)?;
        }
        return Ok(());
    }

    let document = CompactBinaryDocument::parse(schema, bytes)?;
    for (index, field) in schema.fields.iter().enumerate() {
        if !field.is_indexed {
            continue;
        }
        if field.index_type == "words" {
            let Some(text) = document.string_payload(index)? else {
                continue;
            };
            for_each_word_index_value(text, field.index_case_sensitive, |value| {
                callback(&field.name, IndexValue::String(value))
            })?;
            continue;
        }
        if compact_field_is_string(field) && field.index_type != "multiEntry" {
            let Some(text) = document.string_payload(index)? else {
                continue;
            };
            callback(&field.name, string_index_value(field, text)?)?;
            continue;
        }
        let Some(value) = document.field_value(index)? else {
            continue;
        };
        for_each_field_index_value(schema, field, value, |value| callback(&field.name, value))?;
    }
    for composite in &schema.composite_indexes {
        let mut values = Vec::new();
        for field_name in &composite.fields {
            let Some((field_index, field)) = schema
                .fields
                .iter()
                .enumerate()
                .find(|(_, field)| &field.name == field_name)
            else {
                return Err(format!(
                    "composite index `{}` references missing field `{}`",
                    composite.name, field_name
                ));
            };
            let mut indexed_field = field.clone();
            indexed_field.index_case_sensitive = composite.case_sensitive;
            if compact_field_is_string(field) {
                let Some(text) = document.string_payload(field_index)? else {
                    values.clear();
                    break;
                };
                values.push(string_index_value(&indexed_field, text)?);
            } else {
                let Some(value) = document.field_value(field_index)? else {
                    values.clear();
                    break;
                };
                values.push(binary_to_index_value(&indexed_field, &value)?);
            }
        }
        if values.len() == composite.fields.len() {
            callback(&composite.name, IndexValue::List(values))?;
        }
    }
    Ok(())
}

fn index_entries_from_compact_binary_document(
    schema: &CollectionSchemaManifest,
    document: &CompactBinaryDocument<'_>,
) -> Result<Vec<IndexEntry>, String> {
    let mut entries = Vec::new();
    for (index, field) in schema.fields.iter().enumerate() {
        if !field.is_indexed {
            continue;
        }
        if field.index_type == "words" {
            let Some(text) = document.string_payload(index)? else {
                continue;
            };
            push_word_index_entries(&mut entries, &field.name, text, field.index_case_sensitive);
            continue;
        }
        if compact_field_is_string(field) && field.index_type != "multiEntry" {
            let Some(text) = document.string_payload(index)? else {
                continue;
            };
            entries.push(IndexEntry {
                name: field.name.clone(),
                value: string_index_value(field, text)?,
            });
            continue;
        }
        let Some(value) = document.field_value(index)? else {
            continue;
        };
        push_field_index_entry(schema, field, value, &mut entries)?;
    }
    for composite in &schema.composite_indexes {
        let mut values = Vec::new();
        for field_name in &composite.fields {
            let Some((field_index, field)) = schema
                .fields
                .iter()
                .enumerate()
                .find(|(_, field)| &field.name == field_name)
            else {
                return Err(format!(
                    "composite index `{}` references missing field `{}`",
                    composite.name, field_name
                ));
            };
            let mut indexed_field = field.clone();
            indexed_field.index_case_sensitive = composite.case_sensitive;
            if compact_field_is_string(field) {
                let Some(text) = document.string_payload(field_index)? else {
                    values.clear();
                    break;
                };
                values.push(string_index_value(&indexed_field, text)?);
            } else {
                let Some(value) = document.field_value(field_index)? else {
                    values.clear();
                    break;
                };
                values.push(binary_to_index_value(&indexed_field, &value)?);
            }
        }
        if values.len() == composite.fields.len() {
            entries.push(IndexEntry {
                name: composite.name.clone(),
                value: IndexValue::List(values),
            });
        }
    }
    Ok(entries)
}

fn index_entries_from_binary_reader(
    schema: &CollectionSchemaManifest,
    mut read_field: impl FnMut(usize) -> Result<Option<BinaryValue>, String>,
) -> Result<Vec<IndexEntry>, String> {
    let mut entries = Vec::new();
    for (index, field) in schema.fields.iter().enumerate() {
        if !field.is_indexed {
            continue;
        }
        let Some(value) = read_field(index)? else {
            continue;
        };
        push_field_index_entry(schema, field, value, &mut entries)?;
    }
    for composite in &schema.composite_indexes {
        let mut values = Vec::new();
        for field_name in &composite.fields {
            let Some((field_index, field)) = schema
                .fields
                .iter()
                .enumerate()
                .find(|(_, field)| &field.name == field_name)
            else {
                return Err(format!(
                    "composite index `{}` references missing field `{}`",
                    composite.name, field_name
                ));
            };
            let Some(value) = read_field(field_index)? else {
                values.clear();
                break;
            };
            let mut indexed_field = field.clone();
            indexed_field.index_case_sensitive = composite.case_sensitive;
            values.push(binary_to_index_value(&indexed_field, &value)?);
        }
        if values.len() == composite.fields.len() {
            entries.push(IndexEntry {
                name: composite.name.clone(),
                value: IndexValue::List(values),
            });
        }
    }
    Ok(entries)
}

fn push_field_index_entry(
    schema: &CollectionSchemaManifest,
    field: &FieldSchemaManifest,
    value: BinaryValue,
    entries: &mut Vec<IndexEntry>,
) -> Result<(), String> {
    for_each_field_index_value(schema, field, value, |value| {
        entries.push(IndexEntry {
            name: field.name.clone(),
            value,
        });
        Ok(())
    })
}

fn for_each_field_index_value(
    schema: &CollectionSchemaManifest,
    field: &FieldSchemaManifest,
    value: BinaryValue,
    mut emit: impl FnMut(IndexValue) -> Result<(), String>,
) -> Result<(), String> {
    if field.index_type == "words" {
        let BinaryValue::String(text) = value else {
            return Err(format!(
                "word index `{}.{}` requires a string value",
                schema.name, field.name
            ));
        };
        return for_each_word_index_value(&text, field.index_case_sensitive, |value| {
            emit(IndexValue::String(value))
        });
    }
    if field.index_type == "multiEntry" {
        let BinaryValue::List(values) = value else {
            return Err(format!(
                "multi-entry index `{}.{}` requires a list value",
                schema.name, field.name
            ));
        };
        for value in values.into_iter().flatten() {
            emit(binary_to_index_value(field, &value)?)?;
        }
        return Ok(());
    }
    let mut index_value = binary_to_index_value(field, &value)?;
    if field.index_type == "hash" {
        index_value = IndexValue::Int(stable_hash_bytes(&stable_index_bytes(&index_value)?));
    }
    emit(index_value)
}

fn push_word_index_entries(
    entries: &mut Vec<IndexEntry>,
    name: &str,
    text: &str,
    case_sensitive: bool,
) {
    let mut seen = std::collections::HashSet::new();
    let mut current = String::new();
    for character in text.chars() {
        if character.is_alphanumeric() {
            if case_sensitive {
                current.push(character);
            } else {
                current.extend(character.to_lowercase());
            }
        } else if !current.is_empty() {
            if seen.insert(current.clone()) {
                entries.push(IndexEntry {
                    name: name.to_string(),
                    value: IndexValue::String(std::mem::take(&mut current)),
                });
            } else {
                current.clear();
            }
        }
    }
    if !current.is_empty() && seen.insert(current.clone()) {
        entries.push(IndexEntry {
            name: name.to_string(),
            value: IndexValue::String(current),
        });
    }
}

fn for_each_word_index_value(
    text: &str,
    case_sensitive: bool,
    mut emit: impl FnMut(String) -> Result<(), String>,
) -> Result<(), String> {
    if text.is_ascii() {
        return for_each_ascii_word_index_value(text, case_sensitive, emit);
    }

    let mut seen: Vec<String> = Vec::new();
    let mut current = String::new();
    for character in text.chars() {
        if character.is_alphanumeric() {
            if case_sensitive {
                current.push(character);
            } else {
                current.extend(character.to_lowercase());
            }
        } else if !current.is_empty() {
            if !seen.iter().any(|word| word == &current) {
                seen.push(current.clone());
                emit(std::mem::take(&mut current))?;
            } else {
                current.clear();
            }
        }
    }
    if !current.is_empty() && !seen.iter().any(|word| word == &current) {
        emit(current)?;
    }
    Ok(())
}

fn for_each_ascii_word_index_value(
    text: &str,
    case_sensitive: bool,
    mut emit: impl FnMut(String) -> Result<(), String>,
) -> Result<(), String> {
    let mut seen: Vec<String> = Vec::new();
    let bytes = text.as_bytes();
    let mut start = None;
    for (index, byte) in bytes.iter().copied().enumerate() {
        if byte.is_ascii_alphanumeric() {
            start.get_or_insert(index);
            continue;
        }
        if let Some(word_start) = start.take() {
            emit_ascii_word(
                text,
                word_start,
                index,
                case_sensitive,
                &mut seen,
                &mut emit,
            )?;
        }
    }
    if let Some(word_start) = start {
        emit_ascii_word(
            text,
            word_start,
            bytes.len(),
            case_sensitive,
            &mut seen,
            &mut emit,
        )?;
    }
    Ok(())
}

fn emit_ascii_word(
    text: &str,
    start: usize,
    end: usize,
    case_sensitive: bool,
    seen: &mut Vec<String>,
    emit: &mut impl FnMut(String) -> Result<(), String>,
) -> Result<(), String> {
    let word = &text[start..end];
    let value = if case_sensitive {
        word.to_string()
    } else if word.as_bytes().iter().any(u8::is_ascii_uppercase) {
        word.to_ascii_lowercase()
    } else {
        word.to_string()
    };
    if seen.iter().any(|existing| existing == &value) {
        return Ok(());
    }
    seen.push(value.clone());
    emit(value)
}

fn binary_to_index_value(
    field: &FieldSchemaManifest,
    value: &BinaryValue,
) -> Result<IndexValue, String> {
    let normalized = non_nullable_type(&field.dart_type);
    match (normalized, value) {
        ("bool", BinaryValue::Bool(value)) => Ok(IndexValue::Bool(*value)),
        ("int", BinaryValue::Int(value))
        | ("DateTime", BinaryValue::DateTimeMicros(value))
        | ("Duration", BinaryValue::DurationMicros(value)) => Ok(IndexValue::Int(*value)),
        ("double", BinaryValue::Double(value)) if value.is_finite() => {
            Ok(IndexValue::Double(*value))
        }
        ("String", BinaryValue::String(value)) => Ok(IndexValue::String(indexed_string(
            value,
            field.index_case_sensitive,
        ))),
        (_, BinaryValue::Bool(value)) => Ok(IndexValue::Bool(*value)),
        (_, BinaryValue::Int(value))
        | (_, BinaryValue::DateTimeMicros(value))
        | (_, BinaryValue::DurationMicros(value)) => Ok(IndexValue::Int(*value)),
        (_, BinaryValue::Double(value)) if value.is_finite() => Ok(IndexValue::Double(*value)),
        (_, BinaryValue::String(value)) | (_, BinaryValue::Enum(value)) => Ok(IndexValue::String(
            indexed_string(value, field.index_case_sensitive),
        )),
        _ => Err(format!(
            "field `{}` cannot be represented as an index value",
            field.name
        )),
    }
}

fn indexed_string(value: &str, case_sensitive: bool) -> String {
    if case_sensitive {
        value.to_string()
    } else {
        value.to_lowercase()
    }
}

fn string_index_value(field: &FieldSchemaManifest, value: &str) -> Result<IndexValue, String> {
    let mut index_value = IndexValue::String(indexed_string(value, field.index_case_sensitive));
    if field.index_type == "hash" {
        index_value = IndexValue::Int(stable_hash_bytes(&stable_index_bytes(&index_value)?));
    }
    Ok(index_value)
}

fn compact_field_is_string(field: &FieldSchemaManifest) -> bool {
    matches!(non_nullable_type(&field.binary_type), "string" | "String")
}

fn non_nullable_type(dart_type: &str) -> &str {
    dart_type.strip_suffix('?').unwrap_or(dart_type)
}

fn stable_index_bytes(value: &IndexValue) -> Result<Vec<u8>, String> {
    encode_index_value(&wire_index_value(value)?)
}

fn wire_index_value(value: &IndexValue) -> Result<WireIndexValue, String> {
    match value {
        IndexValue::Bool(value) => Ok(WireIndexValue::Bool(*value)),
        IndexValue::Int(value) => Ok(WireIndexValue::Int(*value)),
        IndexValue::Double(value) if value.is_finite() => Ok(WireIndexValue::Double(*value)),
        IndexValue::Double(_) => Err("hash index double values must be finite".into()),
        IndexValue::String(value) => Ok(WireIndexValue::String(value.clone())),
        IndexValue::List(values) => values
            .iter()
            .map(wire_index_value)
            .collect::<Result<Vec<_>, _>>()
            .map(WireIndexValue::List),
    }
}

fn stable_hash_bytes(value: &[u8]) -> i64 {
    const OFFSET_BASIS: u64 = 0xcbf2_9ce4_8422_2325;
    const PRIME: u64 = 0x0000_0100_0000_01b3;
    const MASK: u64 = 0x7fff_ffff_ffff_ffff;
    let mut hash = OFFSET_BASIS;
    for byte in value {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(PRIME) & MASK;
    }
    hash as i64
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

fn push_u32_at(bytes: &mut [u8], offset: usize, value: u32) -> Result<(), String> {
    let target = bytes
        .get_mut(offset..offset + 4)
        .ok_or_else(|| "binary document u32 write is out of range".to_string())?;
    target.copy_from_slice(&value.to_le_bytes());
    Ok(())
}

fn write_u24(bytes: &mut [u8], offset: usize, value: usize) -> Result<(), String> {
    if value > 0x00ff_ffff {
        return Err("binary document u24 value is too large".into());
    }
    let target = bytes
        .get_mut(offset..offset + 3)
        .ok_or_else(|| "binary document u24 write is out of range".to_string())?;
    target[0] = (value & 0xff) as u8;
    target[1] = ((value >> 8) & 0xff) as u8;
    target[2] = ((value >> 16) & 0xff) as u8;
    Ok(())
}

fn read_u16(bytes: &[u8], offset: usize) -> Result<u16, String> {
    let bytes = read_slice(bytes, offset, 2)?;
    Ok(u16::from_le_bytes([bytes[0], bytes[1]]))
}

fn read_u32(bytes: &[u8], offset: usize) -> Result<u32, String> {
    let bytes = read_slice(bytes, offset, 4)?;
    Ok(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
}

fn read_u24(bytes: &[u8], offset: usize) -> Result<u32, String> {
    let bytes = read_slice(bytes, offset, 3)?;
    Ok(bytes[0] as u32 | ((bytes[1] as u32) << 8) | ((bytes[2] as u32) << 16))
}

fn read_u64(bytes: &[u8], offset: usize) -> Result<u64, String> {
    let bytes = read_slice(bytes, offset, 8)?;
    Ok(u64::from_le_bytes(bytes.try_into().map_err(|_| {
        "binary u64 value must be 8 bytes".to_string()
    })?))
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
    fn compact_string_lists_decode_like_value_records() {
        // Scenario: Native typed writers store string lists with an Isar-like
        // offset table instead of one generic value record per element.
        // Expected: Readers still expose the same BinaryValue list shape.
        let legacy = write_list(&[
            Some(BinaryValue::String("time".to_string())),
            Some(BinaryValue::String("river".to_string())),
            None,
        ])
        .unwrap();
        let compact = write_compact_string_list_records(&[
            Some(b"time".to_vec()),
            Some(b"river".to_vec()),
            None,
        ])
        .unwrap();

        assert!(compact.len() < legacy.len());
        assert_eq!(
            decode_list(&compact).unwrap(),
            decode_list(&legacy).unwrap()
        );
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
    fn projects_one_binary_field_without_building_a_document_map() {
        // Scenario: PERF-09 native projections need one field from a binary
        // document without materializing the full document.
        // Covers: Schema field lookup and binary value conversion to wire.
        // Expected: The requested field is returned and null fields stay null.
        let schema = CollectionSchemaManifest {
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
            ],
            composite_indexes: Vec::new(),
        };
        let bytes = write_document(&[
            Some(BinaryValue::Int(7)),
            Some(BinaryValue::String("Ana".to_string())),
            None,
        ])
        .unwrap();

        assert_eq!(
            binary_to_wire_value(read_binary_field(&schema, &bytes, "name").unwrap().as_ref())
                .unwrap(),
            WireValue::String("Ana".to_string())
        );
        assert_eq!(
            binary_to_wire_value(
                read_binary_field(&schema, &bytes, "nickname")
                    .unwrap()
                    .as_ref()
            )
            .unwrap(),
            WireValue::Null
        );
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

    #[test]
    fn validates_generic_document_envelope() {
        // Scenario: Manual documents use GenericDocumentV1 instead of JSON.
        // Covers: Header/version validation, root object validation, and
        // trailing-payload rejection through the shared wire reader.
        // Expected: Only a complete object-valued GenericDocumentV1 payload is
        // accepted by native storage.
        let valid = [
            0x43, 0x47, 0x44, 0x31, // CGD1
            1, 0, 0, 0, // version
            6, 0, 0, 0, 0, // empty object
        ];
        let trailing = [
            0x43, 0x47, 0x44, 0x31, // CGD1
            1, 0, 0, 0, // version
            6, 0, 0, 0, 0, 0,
        ];
        let scalar_root = [
            0x43, 0x47, 0x44, 0x31, // CGD1
            1, 0, 0, 0, // version
            4, 0, 0, 0, 0, // empty string
        ];

        assert!(validate_generic_document(&valid).is_ok());
        assert!(validate_generic_document(b"{\"name\":\"Ana\"}").is_err());
        assert!(validate_generic_document(&valid[..7]).is_err());
        assert!(validate_generic_document(&trailing).is_err());
        assert!(validate_generic_document(&scalar_root).is_err());
    }
}
