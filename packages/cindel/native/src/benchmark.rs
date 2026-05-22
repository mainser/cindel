use std::env;
use std::fs;
use std::path::PathBuf;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[cfg(feature = "mdbx")]
use crate::storage::MdbxStorage;
use crate::storage::{
    CollectionSchemaManifest, FieldSchemaManifest, IndexEntry, IndexValue, SchemaManifest,
    SqliteStorage, StorageEngine,
};

const DEFAULT_DOCUMENTS: u64 = 10_000;
const DEFAULT_QUERY_REPEATS: u64 = 1_000;

pub fn run_cli(args: impl Iterator<Item = String>) -> Result<(), String> {
    let config = BenchmarkConfig::from_args(args)?;
    let reports = run_benchmarks(&config)?;

    println!("backend,operation,items,total_ms,ops_per_second");
    for report in reports {
        for measurement in report.measurements {
            println!(
                "{},{},{},{:.3},{:.2}",
                report.backend,
                measurement.operation,
                measurement.items,
                measurement.elapsed.as_secs_f64() * 1000.0,
                measurement.ops_per_second()
            );
        }
    }

    Ok(())
}

fn run_benchmarks(config: &BenchmarkConfig) -> Result<Vec<BenchmarkReport>, String> {
    match config.backend {
        BackendSelection::Sqlite => Ok(vec![run_sqlite_benchmark(config)?]),
        BackendSelection::Mdbx => Ok(vec![run_mdbx_benchmark(config)?]),
        BackendSelection::All => Ok(vec![
            run_sqlite_benchmark(config)?,
            run_mdbx_benchmark(config)?,
        ]),
    }
}

fn run_sqlite_benchmark(config: &BenchmarkConfig) -> Result<BenchmarkReport, String> {
    let directory = TemporaryDirectory::new("sqlite_bench")?;
    let storage = SqliteStorage::open(directory.path())?;

    run_storage_benchmark("sqlite", storage, config)
}

#[cfg(feature = "mdbx")]
fn run_mdbx_benchmark(config: &BenchmarkConfig) -> Result<BenchmarkReport, String> {
    let directory = TemporaryDirectory::new("mdbx_bench")?;
    let storage = MdbxStorage::open(directory.path())?;

    run_storage_benchmark("mdbx", storage, config)
}

#[cfg(not(feature = "mdbx"))]
fn run_mdbx_benchmark(_config: &BenchmarkConfig) -> Result<BenchmarkReport, String> {
    Err("MDBX benchmark requires building with `--features mdbx`.".into())
}

fn run_storage_benchmark(
    backend: &'static str,
    mut storage: impl StorageEngine,
    config: &BenchmarkConfig,
) -> Result<BenchmarkReport, String> {
    storage.register_schemas(&schema_manifest())?;

    let put = measure("put_indexed", config.documents, || {
        for id in 0..config.documents {
            storage.put_indexed(
                "users",
                id,
                document_bytes(id).as_bytes(),
                &[
                    IndexEntry {
                        name: "email".to_string(),
                        value: IndexValue::String(format!("user-{id}@example.com")),
                    },
                    IndexEntry {
                        name: "score".to_string(),
                        value: IndexValue::Int((id % 1_000) as i64),
                    },
                ],
            )?;
        }
        Ok(())
    })?;

    let get = measure("get", config.documents, || {
        for id in 0..config.documents {
            let Some(bytes) = storage.get("users", id)? else {
                return Err(format!("missing document {id}"));
            };
            if bytes.is_empty() {
                return Err(format!("empty document {id}"));
            }
        }
        Ok(())
    })?;

    let equality_query = measure("query_equal", config.query_repeats, || {
        for repeat in 0..config.query_repeats {
            let id = repeat % config.documents;
            let ids = storage.query_index_equal(
                "users",
                "email",
                &IndexValue::String(format!("user-{id}@example.com")),
            )?;
            if ids != vec![id] {
                return Err(format!("unexpected equality result for {id}: {ids:?}"));
            }
        }
        Ok(())
    })?;

    let range_upper = config.documents.min(100) as i64 - 1;
    let range_query = measure("query_range", config.query_repeats, || {
        for _ in 0..config.query_repeats {
            let ids = storage.query_index_range(
                "users",
                "score",
                Some(&IndexValue::Int(0)),
                Some(&IndexValue::Int(range_upper)),
            )?;
            if ids.is_empty() {
                return Err("range query returned no ids".into());
            }
        }
        Ok(())
    })?;

    Ok(BenchmarkReport {
        backend,
        measurements: vec![put, get, equality_query, range_query],
    })
}

fn measure(
    operation: &'static str,
    items: u64,
    action: impl FnOnce() -> Result<(), String>,
) -> Result<Measurement, String> {
    let started_at = Instant::now();
    action()?;
    Ok(Measurement {
        operation,
        items,
        elapsed: started_at.elapsed(),
    })
}

fn document_bytes(id: u64) -> String {
    format!(
        r#"{{"id":{id},"name":"User {id}","email":"user-{id}@example.com","score":{}}}"#,
        id % 1_000
    )
}

fn schema_manifest() -> SchemaManifest {
    SchemaManifest {
        collections: vec![CollectionSchemaManifest {
            name: "users".to_string(),
            id_field: "id".to_string(),
            fields: vec![
                FieldSchemaManifest {
                    name: "email".to_string(),
                    dart_type: "String".to_string(),
                    is_id: false,
                    is_indexed: true,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
                FieldSchemaManifest {
                    name: "id".to_string(),
                    dart_type: "int".to_string(),
                    is_id: true,
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
                    name: "score".to_string(),
                    dart_type: "int".to_string(),
                    is_id: false,
                    is_indexed: true,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
            ],
        }],
    }
}

struct BenchmarkConfig {
    documents: u64,
    query_repeats: u64,
    backend: BackendSelection,
}

impl BenchmarkConfig {
    fn from_args(args: impl Iterator<Item = String>) -> Result<Self, String> {
        let mut documents = DEFAULT_DOCUMENTS;
        let mut query_repeats = DEFAULT_QUERY_REPEATS;
        let mut backend = BackendSelection::Sqlite;
        let mut pending_flag: Option<String> = None;

        for arg in args {
            if let Some(flag) = pending_flag.take() {
                match flag.as_str() {
                    "--documents" => documents = parse_positive_u64(&flag, &arg)?,
                    "--query-repeats" => query_repeats = parse_positive_u64(&flag, &arg)?,
                    "--backend" => backend = BackendSelection::parse(&arg)?,
                    _ => unreachable!("unexpected benchmark flag"),
                }
                continue;
            }

            match arg.as_str() {
                "--backend" | "--documents" | "--query-repeats" => pending_flag = Some(arg),
                "--help" | "-h" => {
                    print_help();
                    std::process::exit(0);
                }
                _ => {
                    print_help();
                    return Err(format!("unknown argument `{arg}`"));
                }
            }
        }

        if let Some(flag) = pending_flag {
            return Err(format!("missing value for `{flag}`"));
        }

        Ok(Self {
            documents,
            query_repeats,
            backend,
        })
    }
}

#[derive(Clone, Copy)]
enum BackendSelection {
    Sqlite,
    Mdbx,
    All,
}

impl BackendSelection {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "sqlite" => Ok(Self::Sqlite),
            "mdbx" => Ok(Self::Mdbx),
            "all" => Ok(Self::All),
            _ => Err(format!(
                "`--backend` must be one of `sqlite`, `mdbx`, or `all`; got `{value}`"
            )),
        }
    }
}

fn parse_positive_u64(flag: &str, value: &str) -> Result<u64, String> {
    match value.parse::<u64>() {
        Ok(parsed) if parsed > 0 => Ok(parsed),
        _ => Err(format!("`{flag}` must be a positive integer")),
    }
}

fn print_help() {
    println!(
        "Usage: cargo run --manifest-path packages/cindel/native/Cargo.toml --bin cindel_bench -- [--backend sqlite|mdbx|all] [--documents N] [--query-repeats N]"
    );
}

struct BenchmarkReport {
    backend: &'static str,
    measurements: Vec<Measurement>,
}

struct Measurement {
    operation: &'static str,
    items: u64,
    elapsed: Duration,
}

impl Measurement {
    fn ops_per_second(&self) -> f64 {
        self.items as f64 / self.elapsed.as_secs_f64()
    }
}

struct TemporaryDirectory {
    path: PathBuf,
}

impl TemporaryDirectory {
    fn new(name: &str) -> Result<Self, String> {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|error| error.to_string())?
            .as_nanos();
        let path = env::temp_dir().join(format!("cindel_{name}_{nonce}"));
        Ok(Self { path })
    }

    fn path(&self) -> &str {
        self.path.to_str().expect("temporary path must be UTF-8")
    }
}

impl Drop for TemporaryDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}
