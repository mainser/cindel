#![allow(dead_code)]

const TAG_NULL: u8 = 0;
const TAG_BOOL: u8 = 1;
const TAG_INT: u8 = 2;
const TAG_DOUBLE: u8 = 3;
const TAG_STRING: u8 = 4;
const TAG_LIST: u8 = 5;
const TAG_OBJECT: u8 = 6;
const FILTER_TAG_FIELD: u8 = 1;
const FILTER_TAG_ALL: u8 = 2;
const FILTER_TAG_ANY: u8 = 3;
const FILTER_TAG_NOT: u8 = 4;
const FILTER_OP_EQUAL: u8 = 1;
const FILTER_OP_LESS_THAN: u8 = 2;
const FILTER_OP_LESS_THAN_OR_EQUAL: u8 = 3;
const FILTER_OP_GREATER_THAN: u8 = 4;
const FILTER_OP_GREATER_THAN_OR_EQUAL: u8 = 5;
const FILTER_OP_CONTAINS: u8 = 6;
const FILTER_OP_STARTS_WITH: u8 = 7;
const FILTER_OP_ENDS_WITH: u8 = 8;
const FILTER_OP_IS_NULL: u8 = 9;
const MAX_WIRE_COUNT: usize = 1_000_000;

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum WireIndexValue {
    Null,
    Bool(bool),
    Int(i64),
    Double(f64),
    String(String),
    List(Vec<WireIndexValue>),
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum WireScalar {
    Null,
    Bool(bool),
    Int(i64),
    Double(f64),
    String(String),
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum WireValue {
    Null,
    Bool(bool),
    Int(i64),
    Double(f64),
    String(String),
    List(Vec<WireValue>),
    Object(Vec<(String, WireValue)>),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum WireFilterOperation {
    Equal,
    LessThan,
    LessThanOrEqual,
    GreaterThan,
    GreaterThanOrEqual,
    Contains,
    StartsWith,
    EndsWith,
    IsNull,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum WireFilter {
    Field {
        field: String,
        operation: WireFilterOperation,
        value: WireValue,
    },
    All {
        predicates: Vec<WireFilter>,
    },
    Any {
        predicates: Vec<WireFilter>,
    },
    Not {
        predicate: Box<WireFilter>,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct WireDocumentWrite {
    pub(crate) id: u64,
    pub(crate) bytes: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct WireIndexedDocumentWrite {
    pub(crate) id: u64,
    pub(crate) bytes: Vec<u8>,
    pub(crate) indexes: Vec<WireIndexEntry>,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct WireProjectionRows {
    pub(crate) row_count: u32,
    pub(crate) column_count: u32,
    pub(crate) cells: Vec<WireValue>,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct WireSchemaManifest {
    pub(crate) version: u32,
    pub(crate) collections: Vec<WireCollectionSchema>,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct WireCollectionSchema {
    pub(crate) name: String,
    pub(crate) id_field: String,
    pub(crate) fields: Vec<WireFieldSchema>,
    pub(crate) indexes: Vec<WireIndexSchema>,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct WireFieldSchema {
    pub(crate) name: String,
    pub(crate) type_name: String,
    pub(crate) is_id: bool,
    pub(crate) is_indexed: bool,
    pub(crate) is_unique: bool,
    pub(crate) is_nullable: bool,
    pub(crate) case_sensitive: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct WireIndexSchema {
    pub(crate) name: String,
    pub(crate) fields: Vec<String>,
    pub(crate) is_unique: bool,
    pub(crate) case_sensitive: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct WireIndexEntry {
    pub(crate) document_id: u64,
    pub(crate) index_name: String,
    pub(crate) value: WireIndexValue,
}

pub(crate) fn encode_id_list(ids: &[u64]) -> Result<Vec<u8>, String> {
    let mut writer = Writer::new();
    writer.write_len(ids.len())?;
    for id in ids {
        writer.write_u64(*id);
    }
    Ok(writer.finish())
}

pub(crate) fn decode_id_list(bytes: &[u8]) -> Result<Vec<u64>, String> {
    let mut reader = Reader::new(bytes);
    let count = reader.read_len()?;
    reader.ensure_item_count(count, 8)?;
    let mut ids = Vec::with_capacity(count);
    for _ in 0..count {
        ids.push(reader.read_u64()?);
    }
    reader.finish()?;
    Ok(ids)
}

pub(crate) fn encode_index_value(value: &WireIndexValue) -> Result<Vec<u8>, String> {
    let mut writer = Writer::new();
    writer.write_index_value(value)?;
    Ok(writer.finish())
}

pub(crate) fn decode_index_value(bytes: &[u8]) -> Result<WireIndexValue, String> {
    let mut reader = Reader::new(bytes);
    let value = reader.read_index_value()?;
    reader.finish()?;
    Ok(value)
}

pub(crate) fn encode_scalar(value: &WireScalar) -> Result<Vec<u8>, String> {
    let mut writer = Writer::new();
    writer.write_scalar(value)?;
    Ok(writer.finish())
}

pub(crate) fn decode_scalar(bytes: &[u8]) -> Result<WireScalar, String> {
    let mut reader = Reader::new(bytes);
    let value = reader.read_scalar()?;
    reader.finish()?;
    Ok(value)
}

pub(crate) fn encode_filter(filter: &WireFilter) -> Result<Vec<u8>, String> {
    let mut writer = Writer::new();
    writer.write_filter(filter)?;
    Ok(writer.finish())
}

pub(crate) fn decode_filter(bytes: &[u8]) -> Result<WireFilter, String> {
    let mut reader = Reader::new(bytes);
    let filter = reader.read_filter()?;
    reader.finish()?;
    Ok(filter)
}

pub(crate) fn encode_document_write_batch(
    documents: &[WireDocumentWrite],
) -> Result<Vec<u8>, String> {
    let mut writer = Writer::new();
    writer.write_len(documents.len())?;
    for document in documents {
        writer.write_u64(document.id);
        writer.write_bytes(&document.bytes)?;
    }
    Ok(writer.finish())
}

pub(crate) fn decode_document_write_batch(bytes: &[u8]) -> Result<Vec<WireDocumentWrite>, String> {
    let mut reader = Reader::new(bytes);
    let count = reader.read_len()?;
    reader.ensure_item_count(count, 12)?;
    let mut documents = Vec::with_capacity(count);
    for _ in 0..count {
        let id = reader.read_u64()?;
        let bytes = reader.read_bytes()?.to_vec();
        documents.push(WireDocumentWrite { id, bytes });
    }
    reader.finish()?;
    Ok(documents)
}

pub(crate) fn encode_indexed_document_write_batch(
    documents: &[WireIndexedDocumentWrite],
) -> Result<Vec<u8>, String> {
    let mut writer = Writer::new();
    writer.write_len(documents.len())?;
    for document in documents {
        writer.write_u64(document.id);
        writer.write_bytes(&document.bytes)?;
        writer.write_len(document.indexes.len())?;
        for index in &document.indexes {
            writer.write_string(&index.index_name)?;
            writer.write_index_value(&index.value)?;
        }
    }
    Ok(writer.finish())
}

pub(crate) fn decode_indexed_document_write_batch(
    bytes: &[u8],
) -> Result<Vec<WireIndexedDocumentWrite>, String> {
    let mut reader = Reader::new(bytes);
    let count = reader.read_len()?;
    reader.ensure_item_count(count, 16)?;
    let mut documents = Vec::with_capacity(count);
    for _ in 0..count {
        let id = reader.read_u64()?;
        let bytes = reader.read_bytes()?.to_vec();
        let index_count = reader.read_len()?;
        reader.ensure_item_count(index_count, 5)?;
        let mut indexes = Vec::with_capacity(index_count);
        for _ in 0..index_count {
            indexes.push(WireIndexEntry {
                document_id: id,
                index_name: reader.read_string()?,
                value: reader.read_index_value()?,
            });
        }
        documents.push(WireIndexedDocumentWrite { id, bytes, indexes });
    }
    reader.finish()?;
    Ok(documents)
}

pub(crate) fn encode_projection_rows(rows: &WireProjectionRows) -> Result<Vec<u8>, String> {
    let expected_cells = (rows.row_count as usize)
        .checked_mul(rows.column_count as usize)
        .ok_or_else(|| "projection row/cell count overflow".to_string())?;
    if rows.cells.len() != expected_cells {
        return Err("projection cells do not match row_count * column_count".into());
    }

    let mut writer = Writer::new();
    writer.write_u32(rows.row_count);
    writer.write_u32(rows.column_count);
    for cell in &rows.cells {
        writer.write_value(cell)?;
    }
    Ok(writer.finish())
}

pub(crate) fn decode_projection_rows(bytes: &[u8]) -> Result<WireProjectionRows, String> {
    let mut reader = Reader::new(bytes);
    let row_count = reader.read_u32()?;
    let column_count = reader.read_u32()?;
    let cell_count = (row_count as usize)
        .checked_mul(column_count as usize)
        .ok_or_else(|| "projection row/cell count overflow".to_string())?;
    reader.ensure_item_count(cell_count, 1)?;
    let mut cells = Vec::with_capacity(cell_count);
    for _ in 0..cell_count {
        cells.push(reader.read_value()?);
    }
    reader.finish()?;
    Ok(WireProjectionRows {
        row_count,
        column_count,
        cells,
    })
}

pub(crate) fn encode_schema_manifest(manifest: &WireSchemaManifest) -> Result<Vec<u8>, String> {
    let mut writer = Writer::new();
    writer.write_u32(manifest.version);
    writer.write_len(manifest.collections.len())?;
    for collection in &manifest.collections {
        writer.write_string(&collection.name)?;
        writer.write_string(&collection.id_field)?;
        writer.write_len(collection.fields.len())?;
        for field in &collection.fields {
            writer.write_string(&field.name)?;
            writer.write_string(&field.type_name)?;
            writer.write_bool(field.is_id);
            writer.write_bool(field.is_indexed);
            writer.write_bool(field.is_unique);
            writer.write_bool(field.is_nullable);
            writer.write_bool(field.case_sensitive);
        }
        writer.write_len(collection.indexes.len())?;
        for index in &collection.indexes {
            writer.write_string(&index.name)?;
            writer.write_len(index.fields.len())?;
            for field in &index.fields {
                writer.write_string(field)?;
            }
            writer.write_bool(index.is_unique);
            writer.write_bool(index.case_sensitive);
        }
    }
    Ok(writer.finish())
}

pub(crate) fn decode_schema_manifest(bytes: &[u8]) -> Result<WireSchemaManifest, String> {
    let mut reader = Reader::new(bytes);
    let version = reader.read_u32()?;
    let collection_count = reader.read_len()?;
    reader.ensure_item_count(collection_count, 16)?;
    let mut collections = Vec::with_capacity(collection_count);
    for _ in 0..collection_count {
        let name = reader.read_string()?;
        let id_field = reader.read_string()?;
        let field_count = reader.read_len()?;
        reader.ensure_item_count(field_count, 13)?;
        let mut fields = Vec::with_capacity(field_count);
        for _ in 0..field_count {
            fields.push(WireFieldSchema {
                name: reader.read_string()?,
                type_name: reader.read_string()?,
                is_id: reader.read_bool()?,
                is_indexed: reader.read_bool()?,
                is_unique: reader.read_bool()?,
                is_nullable: reader.read_bool()?,
                case_sensitive: reader.read_bool()?,
            });
        }
        let index_count = reader.read_len()?;
        reader.ensure_item_count(index_count, 10)?;
        let mut indexes = Vec::with_capacity(index_count);
        for _ in 0..index_count {
            let name = reader.read_string()?;
            let field_count = reader.read_len()?;
            reader.ensure_item_count(field_count, 4)?;
            let mut fields = Vec::with_capacity(field_count);
            for _ in 0..field_count {
                fields.push(reader.read_string()?);
            }
            indexes.push(WireIndexSchema {
                name,
                fields,
                is_unique: reader.read_bool()?,
                case_sensitive: reader.read_bool()?,
            });
        }
        collections.push(WireCollectionSchema {
            name,
            id_field,
            fields,
            indexes,
        });
    }
    reader.finish()?;
    Ok(WireSchemaManifest {
        version,
        collections,
    })
}

pub(crate) fn encode_index_entry_list(entries: &[WireIndexEntry]) -> Result<Vec<u8>, String> {
    let mut writer = Writer::new();
    writer.write_len(entries.len())?;
    for entry in entries {
        writer.write_u64(entry.document_id);
        writer.write_string(&entry.index_name)?;
        writer.write_index_value(&entry.value)?;
    }
    Ok(writer.finish())
}

pub(crate) fn decode_index_entry_list(bytes: &[u8]) -> Result<Vec<WireIndexEntry>, String> {
    let mut reader = Reader::new(bytes);
    let count = reader.read_len()?;
    reader.ensure_item_count(count, 13)?;
    let mut entries = Vec::with_capacity(count);
    for _ in 0..count {
        entries.push(WireIndexEntry {
            document_id: reader.read_u64()?,
            index_name: reader.read_string()?,
            value: reader.read_index_value()?,
        });
    }
    reader.finish()?;
    Ok(entries)
}

struct Writer {
    bytes: Vec<u8>,
}

impl Writer {
    fn new() -> Self {
        Self { bytes: Vec::new() }
    }

    fn finish(self) -> Vec<u8> {
        self.bytes
    }

    fn write_u8(&mut self, value: u8) {
        self.bytes.push(value);
    }

    fn write_u32(&mut self, value: u32) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    fn write_u64(&mut self, value: u64) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    fn write_i64(&mut self, value: i64) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    fn write_f64(&mut self, value: f64) {
        let value = if value == 0.0 { 0.0 } else { value };
        let value = if value.is_nan() {
            f64::from_bits(0x7ff8_0000_0000_0000)
        } else {
            value
        };
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    fn write_bool(&mut self, value: bool) {
        self.write_u8(u8::from(value));
    }

    fn write_len(&mut self, len: usize) -> Result<(), String> {
        let len = u32::try_from(len).map_err(|_| "length exceeds u32::MAX".to_string())?;
        self.write_u32(len);
        Ok(())
    }

    fn write_bytes(&mut self, bytes: &[u8]) -> Result<(), String> {
        self.write_len(bytes.len())?;
        self.bytes.extend_from_slice(bytes);
        Ok(())
    }

    fn write_string(&mut self, value: &str) -> Result<(), String> {
        self.write_bytes(value.as_bytes())
    }

    fn write_index_value(&mut self, value: &WireIndexValue) -> Result<(), String> {
        match value {
            WireIndexValue::Null => self.write_u8(TAG_NULL),
            WireIndexValue::Bool(value) => {
                self.write_u8(TAG_BOOL);
                self.write_bool(*value);
            }
            WireIndexValue::Int(value) => {
                self.write_u8(TAG_INT);
                self.write_i64(*value);
            }
            WireIndexValue::Double(value) => {
                self.write_u8(TAG_DOUBLE);
                self.write_f64(*value);
            }
            WireIndexValue::String(value) => {
                self.write_u8(TAG_STRING);
                self.write_string(value)?;
            }
            WireIndexValue::List(values) => {
                self.write_u8(TAG_LIST);
                self.write_len(values.len())?;
                for value in values {
                    self.write_index_value(value)?;
                }
            }
        }
        Ok(())
    }

    fn write_scalar(&mut self, value: &WireScalar) -> Result<(), String> {
        match value {
            WireScalar::Null => self.write_u8(TAG_NULL),
            WireScalar::Bool(value) => {
                self.write_u8(TAG_BOOL);
                self.write_bool(*value);
            }
            WireScalar::Int(value) => {
                self.write_u8(TAG_INT);
                self.write_i64(*value);
            }
            WireScalar::Double(value) => {
                self.write_u8(TAG_DOUBLE);
                self.write_f64(*value);
            }
            WireScalar::String(value) => {
                self.write_u8(TAG_STRING);
                self.write_string(value)?;
            }
        }
        Ok(())
    }

    fn write_value(&mut self, value: &WireValue) -> Result<(), String> {
        match value {
            WireValue::Null => self.write_u8(TAG_NULL),
            WireValue::Bool(value) => {
                self.write_u8(TAG_BOOL);
                self.write_bool(*value);
            }
            WireValue::Int(value) => {
                self.write_u8(TAG_INT);
                self.write_i64(*value);
            }
            WireValue::Double(value) => {
                self.write_u8(TAG_DOUBLE);
                self.write_f64(*value);
            }
            WireValue::String(value) => {
                self.write_u8(TAG_STRING);
                self.write_string(value)?;
            }
            WireValue::List(values) => {
                self.write_u8(TAG_LIST);
                self.write_len(values.len())?;
                for value in values {
                    self.write_value(value)?;
                }
            }
            WireValue::Object(fields) => {
                self.write_u8(TAG_OBJECT);
                self.write_len(fields.len())?;
                for (name, value) in fields {
                    self.write_string(name)?;
                    self.write_value(value)?;
                }
            }
        }
        Ok(())
    }

    fn write_filter(&mut self, filter: &WireFilter) -> Result<(), String> {
        match filter {
            WireFilter::Field {
                field,
                operation,
                value,
            } => {
                self.write_u8(FILTER_TAG_FIELD);
                self.write_string(field)?;
                self.write_u8(filter_operation_tag(*operation));
                self.write_value(value)?;
            }
            WireFilter::All { predicates } => {
                self.write_u8(FILTER_TAG_ALL);
                self.write_len(predicates.len())?;
                for predicate in predicates {
                    self.write_filter(predicate)?;
                }
            }
            WireFilter::Any { predicates } => {
                self.write_u8(FILTER_TAG_ANY);
                self.write_len(predicates.len())?;
                for predicate in predicates {
                    self.write_filter(predicate)?;
                }
            }
            WireFilter::Not { predicate } => {
                self.write_u8(FILTER_TAG_NOT);
                self.write_filter(predicate)?;
            }
        }
        Ok(())
    }
}

struct Reader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> Reader<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, offset: 0 }
    }

    fn finish(&self) -> Result<(), String> {
        if self.offset == self.bytes.len() {
            Ok(())
        } else {
            Err("wire payload has trailing bytes".into())
        }
    }

    fn read_exact(&mut self, len: usize) -> Result<&'a [u8], String> {
        let end = self
            .offset
            .checked_add(len)
            .ok_or_else(|| "wire payload offset overflow".to_string())?;
        if end > self.bytes.len() {
            return Err("wire payload is truncated".into());
        }
        let bytes = &self.bytes[self.offset..end];
        self.offset = end;
        Ok(bytes)
    }

    fn remaining(&self) -> usize {
        self.bytes.len().saturating_sub(self.offset)
    }

    fn ensure_item_count(&self, count: usize, min_item_bytes: usize) -> Result<(), String> {
        if count > MAX_WIRE_COUNT {
            return Err("wire item count exceeds safety limit".into());
        }
        let minimum_bytes = count
            .checked_mul(min_item_bytes)
            .ok_or_else(|| "wire item count overflow".to_string())?;
        if minimum_bytes > self.remaining() {
            return Err("wire length exceeds remaining payload".into());
        }
        Ok(())
    }

    fn read_u8(&mut self) -> Result<u8, String> {
        Ok(self.read_exact(1)?[0])
    }

    fn read_u32(&mut self) -> Result<u32, String> {
        let mut bytes = [0_u8; 4];
        bytes.copy_from_slice(self.read_exact(4)?);
        Ok(u32::from_le_bytes(bytes))
    }

    fn read_u64(&mut self) -> Result<u64, String> {
        let mut bytes = [0_u8; 8];
        bytes.copy_from_slice(self.read_exact(8)?);
        Ok(u64::from_le_bytes(bytes))
    }

    fn read_i64(&mut self) -> Result<i64, String> {
        let mut bytes = [0_u8; 8];
        bytes.copy_from_slice(self.read_exact(8)?);
        Ok(i64::from_le_bytes(bytes))
    }

    fn read_f64(&mut self) -> Result<f64, String> {
        let mut bytes = [0_u8; 8];
        bytes.copy_from_slice(self.read_exact(8)?);
        Ok(f64::from_le_bytes(bytes))
    }

    fn read_bool(&mut self) -> Result<bool, String> {
        match self.read_u8()? {
            0 => Ok(false),
            1 => Ok(true),
            _ => Err("wire bool tag must be 0 or 1".into()),
        }
    }

    fn read_len(&mut self) -> Result<usize, String> {
        Ok(self.read_u32()? as usize)
    }

    fn read_bytes(&mut self) -> Result<&'a [u8], String> {
        let len = self.read_len()?;
        self.read_exact(len)
    }

    fn read_string(&mut self) -> Result<String, String> {
        std::str::from_utf8(self.read_bytes()?)
            .map(str::to_string)
            .map_err(|error| error.to_string())
    }

    fn read_index_value(&mut self) -> Result<WireIndexValue, String> {
        match self.read_u8()? {
            TAG_NULL => Ok(WireIndexValue::Null),
            TAG_BOOL => Ok(WireIndexValue::Bool(self.read_bool()?)),
            TAG_INT => Ok(WireIndexValue::Int(self.read_i64()?)),
            TAG_DOUBLE => Ok(WireIndexValue::Double(self.read_f64()?)),
            TAG_STRING => Ok(WireIndexValue::String(self.read_string()?)),
            TAG_LIST => {
                let count = self.read_len()?;
                self.ensure_item_count(count, 1)?;
                let mut values = Vec::with_capacity(count);
                for _ in 0..count {
                    values.push(self.read_index_value()?);
                }
                Ok(WireIndexValue::List(values))
            }
            tag => Err(format!("unknown wire index value tag {tag}")),
        }
    }

    fn read_scalar(&mut self) -> Result<WireScalar, String> {
        match self.read_u8()? {
            TAG_NULL => Ok(WireScalar::Null),
            TAG_BOOL => Ok(WireScalar::Bool(self.read_bool()?)),
            TAG_INT => Ok(WireScalar::Int(self.read_i64()?)),
            TAG_DOUBLE => Ok(WireScalar::Double(self.read_f64()?)),
            TAG_STRING => Ok(WireScalar::String(self.read_string()?)),
            tag => Err(format!("unknown wire scalar tag {tag}")),
        }
    }

    fn read_value(&mut self) -> Result<WireValue, String> {
        match self.read_u8()? {
            TAG_NULL => Ok(WireValue::Null),
            TAG_BOOL => Ok(WireValue::Bool(self.read_bool()?)),
            TAG_INT => Ok(WireValue::Int(self.read_i64()?)),
            TAG_DOUBLE => Ok(WireValue::Double(self.read_f64()?)),
            TAG_STRING => Ok(WireValue::String(self.read_string()?)),
            TAG_LIST => {
                let count = self.read_len()?;
                self.ensure_item_count(count, 1)?;
                let mut values = Vec::with_capacity(count);
                for _ in 0..count {
                    values.push(self.read_value()?);
                }
                Ok(WireValue::List(values))
            }
            TAG_OBJECT => {
                let count = self.read_len()?;
                self.ensure_item_count(count, 5)?;
                let mut fields = Vec::with_capacity(count);
                for _ in 0..count {
                    fields.push((self.read_string()?, self.read_value()?));
                }
                Ok(WireValue::Object(fields))
            }
            tag => Err(format!("unknown wire value tag {tag}")),
        }
    }

    fn read_filter(&mut self) -> Result<WireFilter, String> {
        match self.read_u8()? {
            FILTER_TAG_FIELD => Ok(WireFilter::Field {
                field: self.read_string()?,
                operation: self.read_filter_operation()?,
                value: self.read_value()?,
            }),
            FILTER_TAG_ALL => {
                let count = self.read_len()?;
                self.ensure_item_count(count, 1)?;
                let mut predicates = Vec::with_capacity(count);
                for _ in 0..count {
                    predicates.push(self.read_filter()?);
                }
                Ok(WireFilter::All { predicates })
            }
            FILTER_TAG_ANY => {
                let count = self.read_len()?;
                self.ensure_item_count(count, 1)?;
                let mut predicates = Vec::with_capacity(count);
                for _ in 0..count {
                    predicates.push(self.read_filter()?);
                }
                Ok(WireFilter::Any { predicates })
            }
            FILTER_TAG_NOT => Ok(WireFilter::Not {
                predicate: Box::new(self.read_filter()?),
            }),
            tag => Err(format!("unknown wire filter tag {tag}")),
        }
    }

    fn read_filter_operation(&mut self) -> Result<WireFilterOperation, String> {
        match self.read_u8()? {
            FILTER_OP_EQUAL => Ok(WireFilterOperation::Equal),
            FILTER_OP_LESS_THAN => Ok(WireFilterOperation::LessThan),
            FILTER_OP_LESS_THAN_OR_EQUAL => Ok(WireFilterOperation::LessThanOrEqual),
            FILTER_OP_GREATER_THAN => Ok(WireFilterOperation::GreaterThan),
            FILTER_OP_GREATER_THAN_OR_EQUAL => Ok(WireFilterOperation::GreaterThanOrEqual),
            FILTER_OP_CONTAINS => Ok(WireFilterOperation::Contains),
            FILTER_OP_STARTS_WITH => Ok(WireFilterOperation::StartsWith),
            FILTER_OP_ENDS_WITH => Ok(WireFilterOperation::EndsWith),
            FILTER_OP_IS_NULL => Ok(WireFilterOperation::IsNull),
            tag => Err(format!("unknown wire filter operation {tag}")),
        }
    }
}

fn filter_operation_tag(operation: WireFilterOperation) -> u8 {
    match operation {
        WireFilterOperation::Equal => FILTER_OP_EQUAL,
        WireFilterOperation::LessThan => FILTER_OP_LESS_THAN,
        WireFilterOperation::LessThanOrEqual => FILTER_OP_LESS_THAN_OR_EQUAL,
        WireFilterOperation::GreaterThan => FILTER_OP_GREATER_THAN,
        WireFilterOperation::GreaterThanOrEqual => FILTER_OP_GREATER_THAN_OR_EQUAL,
        WireFilterOperation::Contains => FILTER_OP_CONTAINS,
        WireFilterOperation::StartsWith => FILTER_OP_STARTS_WITH,
        WireFilterOperation::EndsWith => FILTER_OP_ENDS_WITH,
        WireFilterOperation::IsNull => FILTER_OP_IS_NULL,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const IDS_FIXTURE: &[u8] = &[
        3, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0,
    ];
    const INDEX_VALUE_FIXTURE: &[u8] = &[
        5, 3, 0, 0, 0, 1, 1, 2, 254, 255, 255, 255, 255, 255, 255, 255, 4, 2, 0, 0, 0, 104, 105,
    ];
    const SCALAR_FIXTURE: &[u8] = &[3, 0, 0, 0, 0, 0, 0, 248, 63];
    const FILTER_FIXTURE: &[u8] = &[
        2, 2, 0, 0, 0, 1, 6, 0, 0, 0, 97, 99, 116, 105, 118, 101, 1, 1, 1, 4, 1, 4, 0, 0, 0, 110,
        97, 109, 101, 7, 4, 1, 0, 0, 0, 65,
    ];
    const DOCUMENT_BATCH_FIXTURE: &[u8] = &[
        2, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 97, 98, 99, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0,
    ];
    const INDEXED_DOCUMENT_BATCH_FIXTURE: &[u8] = &[
        1, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 97, 98, 99, 1, 0, 0, 0, 5, 0, 0, 0, 101,
        109, 97, 105, 108, 4, 1, 0, 0, 0, 97,
    ];
    const PROJECTION_ROWS_FIXTURE: &[u8] = &[
        1, 0, 0, 0, 3, 0, 0, 0, 0, 4, 1, 0, 0, 0, 65, 5, 2, 0, 0, 0, 2, 5, 0, 0, 0, 0, 0, 0, 0, 1,
        0,
    ];
    const SCHEMA_MANIFEST_FIXTURE: &[u8] = &[
        1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 117, 2, 0, 0, 0, 105, 100, 1, 0, 0, 0, 2, 0, 0, 0, 105,
        100, 3, 0, 0, 0, 105, 110, 116, 1, 0, 0, 0, 1, 1, 0, 0, 0, 5, 0, 0, 0, 98, 121, 95, 105,
        100, 1, 0, 0, 0, 2, 0, 0, 0, 105, 100, 1, 1,
    ];
    const INDEX_ENTRY_LIST_FIXTURE: &[u8] = &[
        1, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 101, 109, 97, 105, 108, 4, 1, 0, 0, 0, 97,
    ];

    // Scenario: Dart sends a compact list of document ids to Rust.
    // Covers:
    // - IdList little-endian count and u64 element encoding.
    // - Byte-for-byte compatibility with the Dart codec fixture.
    // Expected: Rust encodes the exact fixture bytes and decodes them back.
    #[test]
    fn encodes_and_decodes_id_list_fixture() {
        // Arrange.
        let ids = vec![7, 255, 65536];

        // Act / Assert.
        assert_eq!(encode_id_list(&ids).unwrap(), IDS_FIXTURE);
        assert_eq!(decode_id_list(IDS_FIXTURE).unwrap(), ids);
    }

    // Scenario: Dart sends a nested tagged index value to Rust.
    // Covers:
    // - IndexValue list, bool, int, and string tags.
    // - Byte-for-byte compatibility with the Dart index-value fixture.
    // Expected: The canonical binary payload round-trips without JSON.
    #[test]
    fn encodes_and_decodes_index_value_fixture() {
        // Arrange.
        let value = WireIndexValue::List(vec![
            WireIndexValue::Bool(true),
            WireIndexValue::Int(-2),
            WireIndexValue::String("hi".to_string()),
        ]);

        // Act / Assert.
        assert_eq!(encode_index_value(&value).unwrap(), INDEX_VALUE_FIXTURE);
        assert_eq!(decode_index_value(INDEX_VALUE_FIXTURE).unwrap(), value);
    }

    // Scenario: Rust sends or receives a scalar query result.
    // Covers:
    // - Scalar double tag and little-endian f64 payload.
    // - Byte-for-byte compatibility with the Dart scalar fixture.
    // Expected: The scalar payload round-trips as 1.5.
    #[test]
    fn encodes_and_decodes_scalar_fixture() {
        // Arrange.
        let value = WireScalar::Double(1.5);

        // Act / Assert.
        assert_eq!(encode_scalar(&value).unwrap(), SCALAR_FIXTURE);
        assert_eq!(decode_scalar(SCALAR_FIXTURE).unwrap(), value);
    }

    // Scenario: Rust receives a native filter AST from Dart.
    // Covers:
    // - Filter all/not/field tags.
    // - Filter operation tags and nested scalar values.
    // - Byte-for-byte compatibility with the Dart filter fixture.
    // Expected: The filter payload round-trips without JSON.
    #[test]
    fn encodes_and_decodes_filter_fixture() {
        // Arrange.
        let filter = WireFilter::All {
            predicates: vec![
                WireFilter::Field {
                    field: "active".to_string(),
                    operation: WireFilterOperation::Equal,
                    value: WireValue::Bool(true),
                },
                WireFilter::Not {
                    predicate: Box::new(WireFilter::Field {
                        field: "name".to_string(),
                        operation: WireFilterOperation::StartsWith,
                        value: WireValue::String("A".to_string()),
                    }),
                },
            ],
        };

        // Act / Assert.
        assert_eq!(encode_filter(&filter).unwrap(), FILTER_FIXTURE);
        assert_eq!(decode_filter(FILTER_FIXTURE).unwrap(), filter);
    }

    // Scenario: Rust receives a batch of document writes from Dart.
    // Covers:
    // - DocumentWriteBatch count, id, byte length, and empty-byte handling.
    // - Byte-for-byte compatibility with the Dart document-batch fixture.
    // Expected: The batch round-trips with ids and document bytes preserved.
    #[test]
    fn encodes_and_decodes_document_batch_fixture() {
        // Arrange.
        let documents = vec![
            WireDocumentWrite {
                id: 9,
                bytes: b"abc".to_vec(),
            },
            WireDocumentWrite {
                id: 10,
                bytes: Vec::new(),
            },
        ];

        // Act / Assert.
        assert_eq!(
            encode_document_write_batch(&documents).unwrap(),
            DOCUMENT_BATCH_FIXTURE
        );
        assert_eq!(
            decode_document_write_batch(DOCUMENT_BATCH_FIXTURE).unwrap(),
            documents
        );
    }

    // Scenario: Rust receives indexed document writes from Dart.
    // Covers:
    // - Document bytes plus per-document index names and tagged values.
    // - Byte-for-byte compatibility with the Dart indexed-write fixture.
    // Expected: The indexed batch round-trips without a JSON envelope.
    #[test]
    fn encodes_and_decodes_indexed_document_batch_fixture() {
        // Arrange.
        let documents = vec![WireIndexedDocumentWrite {
            id: 9,
            bytes: b"abc".to_vec(),
            indexes: vec![WireIndexEntry {
                document_id: 9,
                index_name: "email".to_string(),
                value: WireIndexValue::String("a".to_string()),
            }],
        }];

        // Act / Assert.
        assert_eq!(
            encode_indexed_document_write_batch(&documents).unwrap(),
            INDEXED_DOCUMENT_BATCH_FIXTURE
        );
        assert_eq!(
            decode_indexed_document_write_batch(INDEXED_DOCUMENT_BATCH_FIXTURE).unwrap(),
            documents
        );
    }

    // Scenario: Rust returns projected cells without full document hydration.
    // Covers:
    // - ProjectionRows row/column counts.
    // - Nullable scalar and list cell encoding.
    // Expected: Projection rows decode with the same cell order and values.
    #[test]
    fn encodes_and_decodes_projection_rows_fixture() {
        // Arrange.
        let rows = WireProjectionRows {
            row_count: 1,
            column_count: 3,
            cells: vec![
                WireValue::Null,
                WireValue::String("A".to_string()),
                WireValue::List(vec![WireValue::Int(5), WireValue::Bool(false)]),
            ],
        };

        // Act / Assert.
        assert_eq!(
            encode_projection_rows(&rows).unwrap(),
            PROJECTION_ROWS_FIXTURE
        );
        assert_eq!(
            decode_projection_rows(PROJECTION_ROWS_FIXTURE).unwrap(),
            rows
        );
    }

    // Scenario: Rust stores schema metadata through a binary manifest.
    // Covers:
    // - Collection, field, and index schema binary encoding.
    // - Boolean option encoding for id/index/unique/nullability/case flags.
    // Expected: The schema manifest fixture matches Dart byte-for-byte.
    #[test]
    fn encodes_and_decodes_schema_manifest_fixture() {
        // Arrange.
        let manifest = WireSchemaManifest {
            version: 1,
            collections: vec![WireCollectionSchema {
                name: "u".to_string(),
                id_field: "id".to_string(),
                fields: vec![WireFieldSchema {
                    name: "id".to_string(),
                    type_name: "int".to_string(),
                    is_id: true,
                    is_indexed: false,
                    is_unique: false,
                    is_nullable: false,
                    case_sensitive: true,
                }],
                indexes: vec![WireIndexSchema {
                    name: "by_id".to_string(),
                    fields: vec!["id".to_string()],
                    is_unique: true,
                    case_sensitive: true,
                }],
            }],
        };

        // Act / Assert.
        assert_eq!(
            encode_schema_manifest(&manifest).unwrap(),
            SCHEMA_MANIFEST_FIXTURE
        );
        assert_eq!(
            decode_schema_manifest(SCHEMA_MANIFEST_FIXTURE).unwrap(),
            manifest
        );
    }

    // Scenario: Rust persists reverse index metadata in a binary list.
    // Covers:
    // - IndexEntryList document id, index name, and tagged value encoding.
    // - Byte-for-byte compatibility with the Dart index-entry fixture.
    // Expected: The entry list round-trips without JSON.
    #[test]
    fn encodes_and_decodes_index_entry_list_fixture() {
        // Arrange.
        let entries = vec![WireIndexEntry {
            document_id: 9,
            index_name: "email".to_string(),
            value: WireIndexValue::String("a".to_string()),
        }];

        // Act / Assert.
        assert_eq!(
            encode_index_entry_list(&entries).unwrap(),
            INDEX_ENTRY_LIST_FIXTURE
        );
        assert_eq!(
            decode_index_entry_list(INDEX_ENTRY_LIST_FIXTURE).unwrap(),
            entries
        );
    }

    // Scenario: Rust receives malformed wire payloads.
    // Covers:
    // - Truncated payloads.
    // - Unknown tags.
    // - Unsafe length counts.
    // - Trailing bytes.
    // Expected: Every malformed payload is rejected before use.
    #[test]
    fn rejects_truncated_invalid_and_trailing_payloads() {
        // Arrange / Act / Assert.
        assert!(decode_id_list(&IDS_FIXTURE[..IDS_FIXTURE.len() - 1]).is_err());
        assert!(decode_index_value(&[99]).is_err());
        assert!(decode_filter(&[99]).is_err());
        assert!(decode_filter(&[FILTER_TAG_FIELD, 1, 0, 0, 0, b'a', 99, TAG_NULL]).is_err());
        assert!(decode_id_list(&[255, 255, 255, 255]).is_err());

        let mut with_trailing = IDS_FIXTURE.to_vec();
        with_trailing.push(0);
        assert!(decode_id_list(&with_trailing).is_err());
    }

    // Scenario: Rust receives invalid primitive wire encodings.
    // Covers:
    // - Invalid UTF-8 string bytes.
    // - Non 0/1 bool payloads.
    // Expected: Invalid primitive encodings are rejected.
    #[test]
    fn rejects_invalid_utf8_and_bool_values() {
        // Arrange / Act / Assert.
        assert!(decode_index_value(&[TAG_STRING, 1, 0, 0, 0, 0xff]).is_err());
        assert!(decode_scalar(&[TAG_BOOL, 2]).is_err());
    }
}
