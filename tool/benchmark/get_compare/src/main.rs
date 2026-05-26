use std::borrow::Cow;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use libmdbx::{
    Database, DatabaseOptions, Mode, NoWriteMap, ReadWriteOptions, SyncMode, TableFlags, WriteFlags,
};

const MIB: isize = 1 << 20;
const MAX_SIZE: isize = 128 * MIB;
const DOCUMENT_TABLE: &str = "d:todos";
const ISAR_DOCUMENT_TABLE: &str = "todos";
const STATIC_SIZE: usize = 26;
const COMPLETED_OFFSET: usize = 0;
const CREATED_AT_OFFSET: usize = 1;
const ID_OFFSET: usize = 9;
const PAYLOAD_OFFSET: usize = 17;
const TITLE_OFFSET: usize = 20;
const TITLE_WORDS_OFFSET: usize = 23;
const SIGN_BIT: u64 = 0x8000_0000_0000_0000;

fn main() {
    if let Err(error) = run() {
        eprintln!("get compare failed: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let config = Config::from_args(env::args().skip(1))?;
    let rows = benchmark_all(&config)?;

    println!(
        "profile,documents,get_count,payload_bytes,load_ms,get_ms,items,checksum,size_bytes,path"
    );
    for row in rows {
        println!(
            "{},{},{},{},{:.3},{:.3},{},{},{},{}",
            row.profile,
            config.documents,
            config.get_count,
            config.payload_bytes,
            row.load.as_secs_f64() * 1000.0,
            row.get.as_secs_f64() * 1000.0,
            row.items,
            row.checksum,
            row.size_bytes,
            csv_cell(&row.path.display().to_string()),
        );
    }
    Ok(())
}

fn benchmark_all(config: &Config) -> Result<Vec<BenchRow>, String> {
    let payload = stable_payload(config.payload_bytes);
    let docs = (0..config.documents as usize)
        .map(|id| encode_doc(id, &payload))
        .collect::<Vec<_>>();
    let ids = (0..config.get_count)
        .map(|index| index * 2)
        .collect::<Vec<_>>();

    let cindel = LoadedDatabase::create(Profile::cindel(), config, &docs)?;
    let isar = LoadedDatabase::create(Profile::isar_like(), config, &docs)?;

    let (transaction_get_time, transaction_get_result) =
        measure_value(|| get_transaction_get_owned(&cindel.database, cindel.profile, &ids))?;
    let (cursor_owned_time, cursor_owned_result) =
        measure_value(|| get_cursor_set_owned(&cindel.database, cindel.profile, &ids))?;
    let (cursor_borrowed_checked_time, cursor_borrowed_checked_result) =
        measure_value(|| get_cursor_set_borrowed(&cindel.database, cindel.profile, &ids, false))?;
    let (cursor_borrowed_trusted_time, cursor_borrowed_trusted_result) =
        measure_value(|| get_cursor_set_borrowed(&cindel.database, cindel.profile, &ids, true))?;
    let (isar_cursor_time, isar_cursor_result) =
        measure_value(|| get_cursor_set_borrowed(&isar.database, isar.profile, &ids, true))?;

    let expected_items = config.get_count;
    let expected_checksum = transaction_get_result.checksum;
    for (name, result) in [
        ("cursor-owned", &cursor_owned_result),
        ("cursor-borrowed-checked", &cursor_borrowed_checked_result),
        ("cursor-borrowed-trusted", &cursor_borrowed_trusted_result),
        ("isar-cursor-trusted", &isar_cursor_result),
    ] {
        if result.items != expected_items {
            return Err(format!("{name} returned {} items", result.items));
        }
        if result.checksum != expected_checksum {
            return Err(format!(
                "{name} checksum differs: {} != {}",
                result.checksum, expected_checksum
            ));
        }
    }

    let rows = vec![
        cindel.row(
            "cindel-transaction-get-owned",
            transaction_get_time,
            transaction_get_result,
        )?,
        cindel.row(
            "cindel-cursor-set-owned",
            cursor_owned_time,
            cursor_owned_result,
        )?,
        cindel.row(
            "cindel-cursor-set-borrowed-checked",
            cursor_borrowed_checked_time,
            cursor_borrowed_checked_result,
        )?,
        cindel.row(
            "cindel-cursor-set-borrowed-trusted",
            cursor_borrowed_trusted_time,
            cursor_borrowed_trusted_result,
        )?,
        isar.row(
            "isar-cursor-set-borrowed",
            isar_cursor_time,
            isar_cursor_result,
        )?,
    ];

    if !config.keep {
        cindel.cleanup();
        isar.cleanup();
    }

    Ok(rows)
}

struct Config {
    documents: u64,
    get_count: u64,
    payload_bytes: usize,
    keep: bool,
}

impl Config {
    fn from_args(args: impl Iterator<Item = String>) -> Result<Self, String> {
        let mut documents = 50_000u64;
        let mut get_count = 25_000u64;
        let mut payload_bytes = 1024;
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
                "--get-count" => {
                    let value = args
                        .next()
                        .ok_or_else(|| "--get-count requires a value".to_string())?;
                    get_count = value
                        .parse()
                        .map_err(|_| format!("invalid --get-count value `{value}`"))?;
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
                        "Usage: cargo run --release -- --documents N --get-count N --payload-bytes N [--keep]"
                    );
                    std::process::exit(0);
                }
                _ => return Err(format!("unknown argument `{arg}`")),
            }
        }
        if get_count.saturating_mul(2) > documents {
            return Err("--get-count reads even ids and must fit inside --documents".into());
        }
        Ok(Self {
            documents,
            get_count,
            payload_bytes,
            keep,
        })
    }
}

#[derive(Clone, Copy)]
struct Profile {
    docs_table: &'static str,
    doc_key: fn(u64) -> [u8; 8],
}

impl Profile {
    fn cindel() -> Self {
        Self {
            docs_table: DOCUMENT_TABLE,
            doc_key: u64::to_ne_bytes,
        }
    }

    fn isar_like() -> Self {
        Self {
            docs_table: ISAR_DOCUMENT_TABLE,
            doc_key: isar_key,
        }
    }
}

struct LoadedDatabase {
    profile: Profile,
    root: PathBuf,
    database: Database<NoWriteMap>,
    load: Duration,
}

impl LoadedDatabase {
    fn create(profile: Profile, config: &Config, docs: &[Vec<u8>]) -> Result<Self, String> {
        let root = temp_root(profile.docs_table)?;
        let database_path = root.join("bench.mdbx");
        fs::create_dir_all(&root).map_err(|error| error.to_string())?;
        let database = open_database(&database_path)?;
        create_tables(&database, profile)?;
        let load = measure(|| load_documents(&database, profile, docs))?;
        if docs.len() != config.documents as usize {
            return Err("prepared document count changed unexpectedly".to_string());
        }
        Ok(Self {
            profile,
            root,
            database,
            load,
        })
    }

    fn row(
        &self,
        profile: &'static str,
        get: Duration,
        result: QueryResult,
    ) -> Result<BenchRow, String> {
        Ok(BenchRow {
            profile,
            load: self.load,
            get,
            items: result.items,
            checksum: result.checksum,
            size_bytes: directory_size(&self.root)?,
            path: self.root.clone(),
        })
    }

    fn cleanup(self) {
        drop(self.database);
        let _ = fs::remove_dir_all(self.root);
    }
}

struct BenchRow {
    profile: &'static str,
    load: Duration,
    get: Duration,
    items: u64,
    checksum: u64,
    size_bytes: u64,
    path: PathBuf,
}

#[derive(Clone, Copy, Default)]
struct QueryResult {
    items: u64,
    checksum: u64,
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

fn create_tables(database: &Database<NoWriteMap>, profile: Profile) -> Result<(), String> {
    let transaction = database.begin_rw_txn().map_err(|error| error.to_string())?;
    transaction
        .create_table(Some(profile.docs_table), TableFlags::INTEGER_KEY)
        .map_err(|error| error.to_string())?;
    transaction
        .commit()
        .map(|_| ())
        .map_err(|error| error.to_string())
}

fn load_documents(
    database: &Database<NoWriteMap>,
    profile: Profile,
    docs: &[Vec<u8>],
) -> Result<(), String> {
    let transaction = database.begin_rw_txn().map_err(|error| error.to_string())?;
    let docs_table = transaction
        .open_table(Some(profile.docs_table))
        .map_err(|error| error.to_string())?;
    for (id, doc) in docs.iter().enumerate() {
        let id = id as u64;
        transaction
            .put(&docs_table, (profile.doc_key)(id), doc, WriteFlags::UPSERT)
            .map_err(|error| error.to_string())?;
    }
    transaction.commit().map_err(|error| error.to_string())?;
    Ok(())
}

fn get_transaction_get_owned(
    database: &Database<NoWriteMap>,
    profile: Profile,
    ids: &[u64],
) -> Result<QueryResult, String> {
    let transaction = database.begin_ro_txn().map_err(|error| error.to_string())?;
    let docs_table = transaction
        .open_table(Some(profile.docs_table))
        .map_err(|error| error.to_string())?;
    let mut result = QueryResult::default();
    for id in ids {
        let bytes = transaction
            .get::<Vec<u8>>(&docs_table, &(profile.doc_key)(*id))
            .map_err(|error| error.to_string())?
            .ok_or_else(|| format!("missing document {id}"))?;
        consume_checked(&mut result, *id, &bytes)?;
    }
    transaction.commit().map_err(|error| error.to_string())?;
    Ok(result)
}

fn get_cursor_set_owned(
    database: &Database<NoWriteMap>,
    profile: Profile,
    ids: &[u64],
) -> Result<QueryResult, String> {
    let transaction = database.begin_ro_txn().map_err(|error| error.to_string())?;
    let docs_table = transaction
        .open_table(Some(profile.docs_table))
        .map_err(|error| error.to_string())?;
    let mut cursor = transaction
        .cursor(&docs_table)
        .map_err(|error| error.to_string())?;
    let mut result = QueryResult::default();
    for id in ids {
        let bytes = cursor
            .set::<Vec<u8>>(&(profile.doc_key)(*id))
            .map_err(|error| error.to_string())?
            .ok_or_else(|| format!("missing document {id}"))?;
        consume_checked(&mut result, *id, &bytes)?;
    }
    drop(cursor);
    transaction.commit().map_err(|error| error.to_string())?;
    Ok(result)
}

fn get_cursor_set_borrowed(
    database: &Database<NoWriteMap>,
    profile: Profile,
    ids: &[u64],
    trusted_static_size: bool,
) -> Result<QueryResult, String> {
    let transaction = database.begin_ro_txn().map_err(|error| error.to_string())?;
    let docs_table = transaction
        .open_table(Some(profile.docs_table))
        .map_err(|error| error.to_string())?;
    let mut cursor = transaction
        .cursor(&docs_table)
        .map_err(|error| error.to_string())?;
    let mut result = QueryResult::default();
    for id in ids {
        let bytes = cursor
            .set::<Cow<'_, [u8]>>(&(profile.doc_key)(*id))
            .map_err(|error| error.to_string())?
            .ok_or_else(|| format!("missing document {id}"))?;
        if trusted_static_size {
            consume_trusted(&mut result, *id, &bytes)?;
        } else {
            consume_checked(&mut result, *id, &bytes)?;
        }
    }
    drop(cursor);
    transaction.commit().map_err(|error| error.to_string())?;
    Ok(result)
}

fn consume_checked(result: &mut QueryResult, id: u64, bytes: &[u8]) -> Result<(), String> {
    let completed = read_bool_checked(bytes, id, COMPLETED_OFFSET)? as u64;
    let created_at = read_i64_checked(bytes, id, CREATED_AT_OFFSET)? as u64;
    let stored_id = read_i64_checked(bytes, id, ID_OFFSET)? as u64;
    let payload_len = read_dynamic_checked(bytes, id, PAYLOAD_OFFSET)?.len() as u64;
    let title_len = read_dynamic_checked(bytes, id, TITLE_OFFSET)?.len() as u64;
    let title_words_len = read_dynamic_checked(bytes, id, TITLE_WORDS_OFFSET)?.len() as u64;
    result.items += 1;
    result.checksum = checksum_values(
        result.checksum,
        id,
        stored_id,
        completed,
        created_at,
        payload_len,
        title_len,
        title_words_len,
    );
    Ok(())
}

fn consume_trusted(result: &mut QueryResult, id: u64, bytes: &[u8]) -> Result<(), String> {
    let completed = bytes[3 + COMPLETED_OFFSET] as u64;
    let created_at = read_i64_at(bytes, 3 + CREATED_AT_OFFSET) as u64;
    let stored_id = read_i64_at(bytes, 3 + ID_OFFSET) as u64;
    result.items += 1;
    result.checksum = checksum_values(
        result.checksum,
        id,
        stored_id,
        completed,
        created_at,
        dynamic_payload(bytes, PAYLOAD_OFFSET).len() as u64,
        dynamic_payload(bytes, TITLE_OFFSET).len() as u64,
        dynamic_payload(bytes, TITLE_WORDS_OFFSET).len() as u64,
    );
    Ok(())
}

fn checksum_values(
    seed: u64,
    id: u64,
    stored_id: u64,
    completed: u64,
    created_at: u64,
    payload_len: u64,
    title_len: u64,
    title_words_len: u64,
) -> u64 {
    seed.wrapping_mul(31)
        .wrapping_add(id)
        .wrapping_mul(31)
        .wrapping_add(stored_id)
        .wrapping_mul(31)
        .wrapping_add(completed)
        .wrapping_mul(31)
        .wrapping_add(created_at)
        .wrapping_mul(31)
        .wrapping_add(payload_len)
        .wrapping_mul(31)
        .wrapping_add(title_len)
        .wrapping_mul(31)
        .wrapping_add(title_words_len)
}

fn read_bool_checked(bytes: &[u8], id: u64, offset: usize) -> Result<bool, String> {
    validate_static_size(bytes, id)?;
    Ok(bytes[3 + offset] == 1)
}

fn read_i64_checked(bytes: &[u8], id: u64, offset: usize) -> Result<i64, String> {
    validate_static_size(bytes, id)?;
    Ok(read_i64_at(bytes, 3 + offset))
}

fn read_dynamic_checked(bytes: &[u8], id: u64, offset: usize) -> Result<&[u8], String> {
    validate_static_size(bytes, id)?;
    Ok(dynamic_payload(bytes, offset))
}

fn validate_static_size(bytes: &[u8], id: u64) -> Result<(), String> {
    if read_u24(bytes, 0) as usize != STATIC_SIZE {
        return Err(format!("document {id} has unexpected static size"));
    }
    if bytes.len() < 3 + STATIC_SIZE {
        return Err(format!("document {id} is truncated"));
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

fn dynamic_payload(bytes: &[u8], offset: usize) -> &[u8] {
    let dynamic_offset = read_u24(bytes, 3 + offset) as usize;
    let len = read_u24(bytes, 3 + dynamic_offset) as usize;
    &bytes[3 + dynamic_offset + 3..3 + dynamic_offset + 3 + len]
}

fn isar_key(id: u64) -> [u8; 8] {
    ((id as i64 as u64) ^ SIGN_BIT).to_le_bytes()
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

fn read_u24(bytes: &[u8], offset: usize) -> u32 {
    bytes[offset] as u32 | ((bytes[offset + 1] as u32) << 8) | ((bytes[offset + 2] as u32) << 16)
}

fn write_u24(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset] = value as u8;
    bytes[offset + 1] = (value >> 8) as u8;
    bytes[offset + 2] = (value >> 16) as u8;
}

fn write_i64_at(bytes: &mut [u8], offset: usize, value: i64) {
    bytes[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
}

fn read_i64_at(bytes: &[u8], offset: usize) -> i64 {
    i64::from_le_bytes(bytes[offset..offset + 8].try_into().unwrap())
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
    let safe_label = label.replace([':', '\\', '/'], "_");
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_nanos();
    Ok(env::temp_dir().join(format!("cindel_get_compare_{safe_label}_{stamp}")))
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
