#![allow(dead_code)]

use std::ops::Range;
use std::str;

use crate::storage::{CollectionSchemaManifest, FieldSchemaManifest, IndexEntry, IndexValue};
use crate::wire::{decode_value, encode_index_value, WireIndexValue, WireValue};

const GENERIC_DOCUMENT_MAGIC: &[u8; 4] = b"CGD1";
const GENERIC_DOCUMENT_VERSION: u32 = 1;
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
            10 => Ok(Self::Object),
            _ => Err(format!("unknown binary field kind `{tag}`")),
        }
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
    _schema: &CollectionSchemaManifest,
    bytes: &[u8],
    field: &PreparedBinarySortField,
) -> Result<Option<BinarySortKey>, String> {
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
    if !field.is_compact_string() {
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
    CompactBinaryDocument::parse(schema, bytes).map(|_| ())
}

#[cfg(test)]
pub(crate) fn write_compact_document_for_test(
    schema: &CollectionSchemaManifest,
    fields: &[Option<BinaryValue>],
) -> Result<Vec<u8>, String> {
    let mut static_size = 0usize;
    let mut field_layout = Vec::with_capacity(schema.fields.len());
    for field in &schema.fields {
        if field.is_id {
            field_layout.push(None);
            continue;
        }
        let field_type = CompactFieldType::from_field(field)?;
        field_layout.push(Some((field_type, static_size)));
        static_size = static_size
            .checked_add(field_type.static_size())
            .ok_or_else(|| "compact binary document static size overflows".to_string())?;
    }
    if fields.len() != schema.fields.len() {
        return Err("test compact document field count does not match schema".into());
    }
    if static_size > 0x00ff_ffff {
        return Err("test compact document static size exceeds u24".into());
    }
    let mut bytes = vec![0; 3 + static_size];
    write_u24(&mut bytes, 0, static_size)?;
    let mut dynamic = Vec::new();
    for (field, layout) in fields.iter().zip(field_layout) {
        let Some((field_type, static_offset)) = layout else {
            continue;
        };
        let absolute = 3 + static_offset;
        match (field_type, field) {
            (CompactFieldType::Bool, Some(BinaryValue::Bool(value))) => {
                bytes[absolute] = *value as u8
            }
            (CompactFieldType::Bool, None) => bytes[absolute] = COMPACT_NULL_BOOL,
            (CompactFieldType::Int, Some(BinaryValue::Int(value))) => {
                bytes[absolute..absolute + 8].copy_from_slice(&value.to_le_bytes());
            }
            (CompactFieldType::Int, None) => {
                bytes[absolute..absolute + 8].copy_from_slice(&COMPACT_NULL_INT.to_le_bytes());
            }
            (CompactFieldType::Double, Some(BinaryValue::Double(value))) if value.is_finite() => {
                bytes[absolute..absolute + 8].copy_from_slice(&value.to_le_bytes());
            }
            (CompactFieldType::Double, None) => {
                bytes[absolute..absolute + 8]
                    .copy_from_slice(&COMPACT_NULL_DOUBLE_BITS.to_le_bytes());
            }
            (CompactFieldType::String, Some(BinaryValue::String(value)))
            | (CompactFieldType::String, Some(BinaryValue::Enum(value))) => {
                write_test_dynamic(
                    &mut bytes,
                    &mut dynamic,
                    static_size,
                    static_offset,
                    value.as_bytes(),
                )?;
            }
            (CompactFieldType::String, None) => write_u24(&mut bytes, absolute, 0)?,
            (CompactFieldType::List, Some(BinaryValue::List(values))) => {
                let payload = encode_list(values)?;
                write_test_dynamic(
                    &mut bytes,
                    &mut dynamic,
                    static_size,
                    static_offset,
                    &payload,
                )?;
            }
            (CompactFieldType::List, None) => write_u24(&mut bytes, absolute, 0)?,
            (CompactFieldType::Object, Some(BinaryValue::Object(entries))) => {
                let payload = encode_object(entries)?;
                write_test_dynamic(
                    &mut bytes,
                    &mut dynamic,
                    static_size,
                    static_offset,
                    &payload,
                )?;
            }
            (CompactFieldType::Object, None) => write_u24(&mut bytes, absolute, 0)?,
            _ => return Err("test compact document value does not match schema".into()),
        }
    }
    bytes.extend_from_slice(&dynamic);
    Ok(bytes)
}

#[cfg(test)]
fn write_test_dynamic(
    bytes: &mut [u8],
    dynamic: &mut Vec<u8>,
    static_size: usize,
    static_offset: usize,
    payload: &[u8],
) -> Result<(), String> {
    if payload.len() > 0x00ff_ffff {
        return Err("test compact dynamic payload exceeds u24".into());
    }
    let relative = static_size
        .checked_add(dynamic.len())
        .ok_or_else(|| "test compact dynamic offset overflows".to_string())?;
    if relative > 0x00ff_ffff {
        return Err("test compact dynamic offset exceeds u24".into());
    }
    write_u24(bytes, 3 + static_offset, relative)?;
    push_u24(dynamic, payload.len())?;
    dynamic.extend_from_slice(payload);
    Ok(())
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
    let document = CompactBinaryDocument::parse(schema, bytes)?;
    index_entries_from_compact_binary_document(schema, &document)
}

pub(crate) fn for_each_index_entry_from_binary_document(
    schema: &CollectionSchemaManifest,
    bytes: &[u8],
    mut callback: impl FnMut(&str, IndexValue) -> Result<(), String>,
) -> Result<(), String> {
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

#[cfg(test)]
fn push_u24(bytes: &mut Vec<u8>, value: usize) -> Result<(), String> {
    if value > 0x00ff_ffff {
        return Err("binary document u24 value exceeds range".into());
    }
    bytes.push((value & 0xff) as u8);
    bytes.push(((value >> 8) & 0xff) as u8);
    bytes.push(((value >> 16) & 0xff) as u8);
    Ok(())
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

    fn test_field(name: &str, binary_type: &str, is_id: bool) -> FieldSchemaManifest {
        FieldSchemaManifest {
            name: name.to_string(),
            dart_type: binary_type.to_string(),
            binary_type: binary_type.to_string(),
            is_id,
            is_indexed: false,
            is_index_unique: false,
            index_case_sensitive: true,
            index_type: "value".to_string(),
        }
    }

    #[test]
    fn round_trips_all_supported_value_shapes() {
        // Scenario: PERF-04 compact binary format covers every field shape
        // Cindel currently supports in generated models.
        // Covers:
        // - Compact binary encoding for scalar, list, null, and object values.
        // - Field-by-field decoding through the schema slot table.
        // Expected: A compact document can be decoded without JSON.
        let schema = CollectionSchemaManifest {
            name: "users".to_string(),
            id_field: "id".to_string(),
            fields: vec![
                test_field("flag", "bool", false),
                test_field("count", "int", false),
                test_field("score", "double", false),
                test_field("name", "string", false),
                test_field("tags", "list", false),
                test_field("state", "string", false),
                test_field("missing", "string", false),
                test_field("profile", "object", false),
            ],
            composite_indexes: Vec::new(),
        };
        let fields = vec![
            Some(BinaryValue::Bool(true)),
            Some(BinaryValue::Int(-42)),
            Some(BinaryValue::Double(12.5)),
            Some(BinaryValue::String("Cindel".to_string())),
            Some(BinaryValue::List(vec![
                Some(BinaryValue::Int(7)),
                Some(BinaryValue::String("tag".to_string())),
                None,
            ])),
            Some(BinaryValue::String("done".to_string())),
            None,
            Some(BinaryValue::Object(vec![(
                "label".to_string(),
                Some(BinaryValue::String("nested".to_string())),
            )])),
        ];

        let bytes = write_compact_document_for_test(&schema, &fields).unwrap();

        for (index, expected) in fields.iter().enumerate() {
            assert_eq!(
                &read_binary_field_at(&schema, &bytes, index).unwrap(),
                expected
            );
        }
    }

    #[test]
    fn compact_string_lists_decode_like_value_records() {
        // Scenario: Native typed writers store string lists with an Isar-like
        // offset table instead of one generic value record per element.
        // Covers:
        // - Compact string-list records.
        // - Compatibility with the shared list decoder output shape.
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
    fn reads_one_compact_field_without_decoding_other_dynamic_fields() {
        // Scenario: Query/index extraction should be able to read one field by
        // offset without materializing unrelated values.
        // Covers: Slot table offsets and lazy field decoding.
        // Expected: A corrupt unrelated string payload does not affect reading
        // a fixed int field, but fails when that string field is requested.
        let schema = CollectionSchemaManifest {
            name: "users".to_string(),
            id_field: "id".to_string(),
            fields: vec![
                test_field("score", "int", false),
                test_field("name", "string", false),
            ],
            composite_indexes: Vec::new(),
        };
        let fields = vec![
            Some(BinaryValue::Int(99)),
            Some(BinaryValue::String("valid".to_string())),
        ];
        let mut bytes = write_compact_document_for_test(&schema, &fields).unwrap();
        let layout = prepare_binary_field_layout(&schema, "name").unwrap();
        let (_, string_payload) = read_binary_field_payload_prepared(&bytes, &layout)
            .unwrap()
            .unwrap();
        let string_start = string_payload.as_ptr() as usize - bytes.as_ptr() as usize;
        bytes[string_start] = 0xFF;

        assert_eq!(
            read_binary_field(&schema, &bytes, "score").unwrap(),
            Some(BinaryValue::Int(99))
        );
        assert!(read_binary_field(&schema, &bytes, "name").is_err());
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
        let bytes = write_compact_document_for_test(
            &schema,
            &[None, Some(BinaryValue::String("Ana".to_string())), None],
        )
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
        let schema = CollectionSchemaManifest {
            name: "scores".to_string(),
            id_field: "id".to_string(),
            fields: vec![test_field("score", "double", false)],
            composite_indexes: Vec::new(),
        };
        assert!(validate_binary_document(&schema, b"not-a-document").is_err());
        assert!(
            write_compact_document_for_test(&schema, &[Some(BinaryValue::Double(f64::NAN))])
                .is_err()
        );
        assert!(write_compact_document_for_test(
            &schema,
            &[Some(BinaryValue::Double(f64::INFINITY))]
        )
        .is_err());
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
