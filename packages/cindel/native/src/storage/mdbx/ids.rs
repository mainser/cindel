use libmdbx::{NoWriteMap, Transaction, WriteFlags, RW};

use super::{decode_u64, max_document_id, open_documents_table, MdbxTables};
use crate::storage::mdbx_key::encode_collection_key;

pub(super) fn next_id_from_storage<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
) -> Result<u64, String>
where
    K: libmdbx::TransactionKind,
{
    let persisted_next_id = read_persisted_next_id(transaction, tables, collection)?;
    let documents_next_id = match open_documents_table(transaction, collection) {
        Ok(documents) => max_document_id(transaction, &documents)?
            .and_then(|id| id.checked_add(1))
            .unwrap_or(1),
        Err(_) => 1,
    };
    Ok(persisted_next_id.unwrap_or(1).max(documents_next_id))
}

fn read_persisted_next_id<K>(
    transaction: &Transaction<'_, K, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
) -> Result<Option<u64>, String>
where
    K: libmdbx::TransactionKind,
{
    let key = encode_collection_key(collection);
    transaction
        .get::<Vec<u8>>(&tables.id_counters, &key)
        .map_err(|error| error.to_string())?
        .map(|bytes| decode_u64(&bytes))
        .transpose()
}

pub(super) fn set_persisted_next_id_at_least(
    transaction: &Transaction<'_, RW, NoWriteMap>,
    tables: &MdbxTables<'_>,
    collection: &str,
    next_id: u64,
) -> Result<(), String> {
    let key = encode_collection_key(collection);
    let current = transaction
        .get::<Vec<u8>>(&tables.id_counters, &key)
        .map_err(|error| error.to_string())?
        .map(|bytes| decode_u64(&bytes))
        .transpose()?
        .unwrap_or(1);
    if current >= next_id {
        return Ok(());
    }
    transaction
        .put(
            &tables.id_counters,
            &key,
            next_id.to_be_bytes(),
            WriteFlags::UPSERT,
        )
        .map_err(|error| error.to_string())?;
    Ok(())
}
