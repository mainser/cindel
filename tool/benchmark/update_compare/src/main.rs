use std::borrow::Cow;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use libmdbx::{
    Database, DatabaseOptions, Mode, NoWriteMap, ReadWriteOptions, SyncMode, TableFlags, WriteFlags,
};

const MIB: isize = 1 << 20;
const MAX_SIZE: isize = 1024 * MIB;
const DOCUMENT_TABLE: &str = "d:bench";
const COMPLETED_INDEX_TABLE: &str = "i:bench:completed";
const STATIC_SIZE: usize = 26;
const COMPLETED_OFFSET: usize = 0;
const CREATED_AT_OFFSET: usize = 1;
const ID_OFFSET: usize = 9;
const PAYLOAD_OFFSET: usize = 17;
const TITLE_OFFSET: usize = 20;
const TITLE_WORDS_OFFSET: usize = 23;

fn main() {
    if let Err(error) = run() {
        eprintln!("update compare failed: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let config = Config::from_args(env::args().skip(1))?;
    let rows = [
        benchmark_profile(Profile::CurrentLike, &config)?,
        benchmark_profile(Profile::DirectUpsert, &config)?,
        benchmark_profile(Profile::DirectCurrent, &config)?,
    ];

    println!(
        "profile,documents,update_count,payload_bytes,prepare_ms,insert_ms,update_ms,updated_items,size_bytes,path"
    );
    for row in rows {
        println!(
            "{},{},{},{},{:.3},{:.3},{:.3},{},{},{}",
            row.profile.name(),
            config.documents,
            config.update_count,
            config.payload_bytes,
            row.prepare.as_secs_f64() * 1000.0,
            row.insert.as_secs_f64() * 1000.0,
            row.update.as_secs_f64() * 1000.0,
            row.updated_items,
            row.size_bytes,
            csv_cell(&row.path.display().to_string()),
        );
    }

    Ok(())
}

fn benchmark_profile(profile: Profile, config: &Config) -> Result<BenchRow, String> {
    let root = temp_root(profile.name())?;
    let database_path = root.join("bench.mdbx");
    fs::create_dir_all(&root).map_err(|error| error.to_string())?;
    let database = open_database(&database_path)?;
    create_tables(&database)?;

    let prepare = measure(|| {
        let _ = stable_payload(config.payload_bytes);
        Ok(())
    })?;
    let payload = stable_payload(config.payload_bytes);
    let insert = measure(|| load_documents_and_index(&database, config.documents, &payload))?;
    let update = measure_value(|| match profile {
        Profile::CurrentLike => update_current_like(&database),
        Profile::DirectUpsert => update_direct(&database, false),
        Profile::DirectCurrent => update_direct(&database, true),
    })?;
    let (update, updated_items) = (update.0, update.1);

    let expected = config.update_count;
    if updated_items != expected {
        return Err(format!(
            "{} updated {updated_items}, expected {expected}",
            profile.name(),
        ));
    }
    verify_index_counts(&database, 0, config.documents)?;
    let size_bytes = directory_size(&root)?;
    drop(database);
    if !config.keep {
        let _ = fs::remove_dir_all(&root);
    }
    Ok(BenchRow {
        profile,
        prepare,
        insert,
        update,
        updated_items,
        size_bytes,
        path: root,
    })
}

#[derive(Clone, Copy)]
enum Profile {
    CurrentLike,
    DirectUpsert,
    DirectCurrent,
}

impl Profile {
    fn name(self) -> &'static str {
        match self {
            Self::CurrentLike => "cindel-current-like-indexed-bool-update",
            Self::DirectUpsert => "cindel-direct-upsert-indexed-bool-update",
            Self::DirectCurrent => "cindel-direct-current-indexed-bool-update",
        }
    }
}

struct Config {
    documents: u64,
    update_count: u64,
    payload_bytes: usize,
    keep: bool,
}

impl Config {
    fn from_args(args: impl Iterator<Item = String>) -> Result<Self, String> {
        let mut documents = 50_000u64;
        let mut update_count = 25_000u64;
        let mut payload_bytes = 1024usize;
        let mut keep = false;
        let mut args = args.peekable();
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--documents" => {
                    let value = args
                        .next()
                        .ok_or_else(|| "--documents requires a value".to_string())?;
                    documents = value
                        .parse()
                        .map_err(|_| format!("invalid --documents value `{value}`"))?;
                }
                "--update-count" => {
                    let value = args
                        .next()
                        .ok_or_else(|| "--update-count requires a value".to_string())?;
                    update_count = value
                        .parse()
                        .map_err(|_| format!("invalid --update-count value `{value}`"))?;
                }
                "--payload-bytes" => {
                    let value = args
                        .next()
                        .ok_or_else(|| "--payload-bytes requires a value".to_string())?;
                    payload_bytes = value
                        .parse()
                        .map_err(|_| format!("invalid --payload-bytes value `{value}`"))?;
                }
                "--keep" => keep = true,
                "--help" | "-h" => {
                    println!(
                        "Usage: cargo run --release -- --documents N --update-count N --payload-bytes N [--keep]"
                    );
                    std::process::exit(0);
                }
                _ => return Err(format!("unknown argument `{arg}`")),
            }
        }
        if update_count.saturating_mul(2) != documents {
            return Err(
                "--update-count must be half of --documents for this bool-index lab".into(),
            );
        }
        Ok(Self {
            documents,
            update_count,
            payload_bytes,
            keep,
        })
    }
}

struct BenchRow {
    profile: Profile,
    prepare: Duration,
    insert: Duration,
    update: Duration,
    updated_items: u64,
    size_bytes: u64,
    path: PathBuf,
}

fn open_database(path: &Path) -> Result<Database<NoWriteMap>, String> {
    Database::<NoWriteMap>::open_with_options(
        path,
        DatabaseOptions {
            permissions: Some(0o600),
            max_tables: Some(512),
            no_sub_dir: true,
            accede: false,
            coalesce: true,
            mode: Mode::ReadWrite(ReadWriteOptions {
                sync_mode: SyncMode::NoMetaSync,
                min_size: Some(MIB),
                max_size: Some(MAX_SIZE),
                growth_step: Some(5 * MIB),
                shrink_threshold: Some(20 * MIB),
            }),
            ..Default::default()
        },
    )
    .map_err(|error| error.to_string())
}

fn create_tables(database: &Database<NoWriteMap>) -> Result<(), String> {
    let transaction = database.begin_rw_txn().map_err(|error| error.to_string())?;
    transaction
        .create_table(Some(DOCUMENT_TABLE), TableFlags::INTEGER_KEY)
        .map_err(|error| error.to_string())?;
    transaction
        .create_table(Some(COMPLETED_INDEX_TABLE), TableFlags::DUP_SORT)
        .map_err(|error| error.to_string())?;
    transaction.commit().map_err(|error| error.to_string())?;
    Ok(())
}

fn load_documents_and_index(
    database: &Database<NoWriteMap>,
    documents: u64,
    payload: &[u8],
) -> Result<(), String> {
    let transaction = database.begin_rw_txn().map_err(|error| error.to_string())?;
    let documents_table = transaction
        .open_table(Some(DOCUMENT_TABLE))
        .map_err(|error| error.to_string())?;
    let index_table = transaction
        .open_table(Some(COMPLETED_INDEX_TABLE))
        .map_err(|error| error.to_string())?;
    for id in 0..documents {
        let bytes = encode_doc(id as usize, payload);
        transaction
            .put(
                &documents_table,
                document_table_key(id),
                &bytes,
                WriteFlags::UPSERT,
            )
            .map_err(|error| error.to_string())?;
        transaction
            .put(
                &index_table,
                completed_key(id % 2 == 0),
                document_id_key(id),
                WriteFlags::UPSERT,
            )
            .map_err(|error| error.to_string())?;
    }
    transaction.commit().map_err(|error| error.to_string())?;
    Ok(())
}

fn update_current_like(database: &Database<NoWriteMap>) -> Result<u64, String> {
    let ids = scan_completed_ids(database, true)?;
    let documents = {
        let transaction = database.begin_ro_txn().map_err(|error| error.to_string())?;
        let documents_table = transaction
            .open_table(Some(DOCUMENT_TABLE))
            .map_err(|error| error.to_string())?;
        let mut cursor = transaction
            .cursor(&documents_table)
            .map_err(|error| error.to_string())?;
        let mut documents = Vec::with_capacity(ids.len());
        for id in &ids {
            let mut bytes = cursor
                .set::<Vec<u8>>(&document_table_key(*id))
                .map_err(|error| error.to_string())?
                .ok_or_else(|| format!("missing document {id}"))?;
            bytes[3 + COMPLETED_OFFSET] = 0;
            documents.push((*id, bytes));
        }
        drop(cursor);
        transaction.commit().map_err(|error| error.to_string())?;
        documents
    };

    let transaction = database.begin_rw_txn().map_err(|error| error.to_string())?;
    let documents_table = transaction
        .open_table(Some(DOCUMENT_TABLE))
        .map_err(|error| error.to_string())?;
    let index_table = transaction
        .open_table(Some(COMPLETED_INDEX_TABLE))
        .map_err(|error| error.to_string())?;
    let mut documents_cursor = transaction
        .cursor(&documents_table)
        .map_err(|error| error.to_string())?;
    let mut index_cursor = transaction
        .cursor(&index_table)
        .map_err(|error| error.to_string())?;
    let mut updated = 0u64;

    for (id, bytes) in documents {
        let previous = documents_cursor
            .set::<Vec<u8>>(&document_table_key(id))
            .map_err(|error| error.to_string())?
            .ok_or_else(|| format!("missing previous document {id}"))?;
        let old_key = completed_key(read_completed(&previous));
        let new_key = completed_key(read_completed(&bytes));
        if old_key != new_key {
            move_index_entry(&mut index_cursor, old_key, new_key, id)?;
        }
        documents_cursor
            .put(&document_table_key(id), &bytes, WriteFlags::UPSERT)
            .map_err(|error| error.to_string())?;
        updated += 1;
    }
    drop(index_cursor);
    drop(documents_cursor);
    transaction.commit().map_err(|error| error.to_string())?;
    Ok(updated)
}

fn update_direct(database: &Database<NoWriteMap>, use_current: bool) -> Result<u64, String> {
    let ids = scan_completed_ids(database, true)?;
    let transaction = database.begin_rw_txn().map_err(|error| error.to_string())?;
    let documents_table = transaction
        .open_table(Some(DOCUMENT_TABLE))
        .map_err(|error| error.to_string())?;
    let index_table = transaction
        .open_table(Some(COMPLETED_INDEX_TABLE))
        .map_err(|error| error.to_string())?;
    let mut documents_cursor = transaction
        .cursor(&documents_table)
        .map_err(|error| error.to_string())?;
    let mut index_cursor = transaction
        .cursor(&index_table)
        .map_err(|error| error.to_string())?;
    let mut updated = 0u64;

    for id in ids {
        let key = document_table_key(id);
        let Some(mut bytes) = documents_cursor
            .set::<Vec<u8>>(&key)
            .map_err(|error| error.to_string())?
        else {
            continue;
        };
        if !read_completed(&bytes) {
            continue;
        }
        bytes[3 + COMPLETED_OFFSET] = 0;
        if use_current {
            documents_cursor
                .put(&key, &bytes, WriteFlags::CURRENT)
                .map_err(|error| error.to_string())?;
        } else {
            documents_cursor
                .put(&key, &bytes, WriteFlags::UPSERT)
                .map_err(|error| error.to_string())?;
        }
        move_index_entry(
            &mut index_cursor,
            completed_key(true),
            completed_key(false),
            id,
        )?;
        updated += 1;
    }
    drop(index_cursor);
    drop(documents_cursor);
    transaction.commit().map_err(|error| error.to_string())?;
    Ok(updated)
}

fn scan_completed_ids(
    database: &Database<NoWriteMap>,
    completed: bool,
) -> Result<Vec<u64>, String> {
    let transaction = database.begin_ro_txn().map_err(|error| error.to_string())?;
    let index_table = transaction
        .open_table(Some(COMPLETED_INDEX_TABLE))
        .map_err(|error| error.to_string())?;
    let mut cursor = transaction
        .cursor(&index_table)
        .map_err(|error| error.to_string())?;
    let key = completed_key(completed);
    let mut ids = Vec::new();
    for row in cursor.iter_from::<Cow<'_, [u8]>, Cow<'_, [u8]>>(&key) {
        let (entry_key, value) = row.map_err(|error| error.to_string())?;
        if entry_key.as_ref() != key {
            break;
        }
        ids.push(decode_u64(&value)?);
    }
    drop(cursor);
    transaction.commit().map_err(|error| error.to_string())?;
    Ok(ids)
}

fn move_index_entry(
    index_cursor: &mut libmdbx::Cursor<'_, libmdbx::RW>,
    old_key: [u8; 1],
    new_key: [u8; 1],
    id: u64,
) -> Result<(), String> {
    let document_id = document_id_key(id);
    if index_cursor
        .get_both::<Vec<u8>>(&old_key, &document_id)
        .map_err(|error| error.to_string())?
        .is_some()
    {
        index_cursor
            .del(WriteFlags::empty())
            .map_err(|error| error.to_string())?;
    }
    index_cursor
        .put(&new_key, &document_id, WriteFlags::UPSERT)
        .map_err(|error| error.to_string())
}

fn verify_index_counts(
    database: &Database<NoWriteMap>,
    true_count: u64,
    documents: u64,
) -> Result<(), String> {
    let false_count = documents - true_count;
    let observed_true = scan_completed_ids(database, true)?.len() as u64;
    let observed_false = scan_completed_ids(database, false)?.len() as u64;
    if observed_true != true_count || observed_false != false_count {
        return Err(format!(
            "unexpected index counts true={observed_true} false={observed_false}"
        ));
    }
    Ok(())
}

fn encode_doc(id: usize, payload: &[u8]) -> Vec<u8> {
    let title = format!("title-{}", id % 10000);
    let title_words = format!("title {} group {}", id % 10000, id % 37);
    let mut bytes = vec![0u8; 3 + STATIC_SIZE];
    write_u24(&mut bytes, 0, STATIC_SIZE as u32);
    bytes[3 + COMPLETED_OFFSET] = if id % 2 == 0 { 1 } else { 0 };
    write_i64_at(
        &mut bytes,
        3 + CREATED_AT_OFFSET,
        1_773_779_200_000_000i64 + id as i64,
    );
    write_i64_at(&mut bytes, 3 + ID_OFFSET, id as i64);
    write_dynamic(&mut bytes, PAYLOAD_OFFSET, payload);
    write_dynamic(&mut bytes, TITLE_OFFSET, title.as_bytes());
    write_dynamic(&mut bytes, TITLE_WORDS_OFFSET, title_words.as_bytes());
    bytes
}

fn read_completed(bytes: &[u8]) -> bool {
    bytes[3 + COMPLETED_OFFSET] == 1
}

fn completed_key(value: bool) -> [u8; 1] {
    [if value { 2 } else { 1 }]
}

fn document_table_key(id: u64) -> [u8; 8] {
    id.to_ne_bytes()
}

fn document_id_key(id: u64) -> [u8; 8] {
    id.to_be_bytes()
}

fn decode_u64(bytes: &[u8]) -> Result<u64, String> {
    let bytes = bytes
        .try_into()
        .map_err(|_| "expected eight-byte id".to_string())?;
    Ok(u64::from_be_bytes(bytes))
}

fn stable_payload(bytes: usize) -> Vec<u8> {
    let mut payload = vec![0u8; bytes.max(1)];
    for (index, byte) in payload.iter_mut().enumerate() {
        *byte = b'a' + (index % 23) as u8;
    }
    payload
}

fn write_dynamic(bytes: &mut Vec<u8>, offset: usize, payload: &[u8]) {
    let dynamic_offset = bytes.len() - 3;
    write_u24(bytes, 3 + offset, dynamic_offset as u32);
    let start = bytes.len();
    bytes.resize(start + 3 + payload.len(), 0);
    write_u24(bytes, start, payload.len() as u32);
    bytes[start + 3..start + 3 + payload.len()].copy_from_slice(payload);
}

fn write_u24(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset] = value as u8;
    bytes[offset + 1] = (value >> 8) as u8;
    bytes[offset + 2] = (value >> 16) as u8;
}

fn write_i64_at(bytes: &mut [u8], offset: usize, value: i64) {
    bytes[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
}

fn measure(action: impl FnOnce() -> Result<(), String>) -> Result<Duration, String> {
    let started = Instant::now();
    action()?;
    Ok(started.elapsed())
}

fn measure_value<T>(action: impl FnOnce() -> Result<T, String>) -> Result<(Duration, T), String> {
    let started = Instant::now();
    let value = action()?;
    Ok((started.elapsed(), value))
}

fn temp_root(label: &str) -> Result<PathBuf, String> {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_nanos();
    Ok(env::temp_dir().join(format!("cindel_update_compare_{label}_{stamp}")))
}

fn directory_size(path: &Path) -> Result<u64, String> {
    let mut size = 0u64;
    for entry in fs::read_dir(path).map_err(|error| error.to_string())? {
        let entry = entry.map_err(|error| error.to_string())?;
        let metadata = entry.metadata().map_err(|error| error.to_string())?;
        if metadata.is_file() {
            size += metadata.len();
        }
    }
    Ok(size)
}

fn csv_cell(value: &str) -> String {
    if value.contains(',') || value.contains('"') {
        format!("\"{}\"", value.replace('"', "\"\""))
    } else {
        value.to_string()
    }
}
