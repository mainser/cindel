use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crate::storage::{
    CollectionSchemaManifest, CompositeIndexSchemaManifest, DocumentWrite, FieldSchemaManifest,
    IndexEntry, IndexValue, SchemaManifest, SqliteStorage, StorageEngine,
};
#[cfg(feature = "mdbx")]
use crate::storage::{MdbxLayoutV2Storage, MdbxStorage};

const DEFAULT_DOCUMENTS: u64 = 10_000;
const DEFAULT_QUERY_REPEATS: u64 = 1_000;

pub fn run_cli(args: impl Iterator<Item = String>) -> Result<(), String> {
    let config = BenchmarkConfig::from_args(args)?;
    let reports = run_benchmarks(&config)?;
    let run = BenchmarkRun::new(&config, reports);

    let output = match config.output_format {
        OutputFormat::Csv => run.to_csv(),
        OutputFormat::Json => run.to_json()?,
    };

    if let Some(output_path) = &config.output_path {
        fs::write(output_path, output).map_err(|error| error.to_string())?;
    } else {
        print!("{output}");
    }

    Ok(())
}

fn run_benchmarks(config: &BenchmarkConfig) -> Result<Vec<BenchmarkReport>, String> {
    match config.backend {
        BackendSelection::Sqlite => Ok(vec![run_sqlite_benchmark(config)?]),
        BackendSelection::Mdbx => Ok(vec![run_mdbx_benchmark(config)?]),
        BackendSelection::MdbxV2 => Ok(vec![run_mdbx_v2_benchmark(config)?]),
        BackendSelection::All => Ok(vec![
            run_sqlite_benchmark(config)?,
            run_mdbx_benchmark(config)?,
        ]),
        BackendSelection::AllWithSpike => Ok(vec![
            run_sqlite_benchmark(config)?,
            run_mdbx_benchmark(config)?,
            run_mdbx_v2_benchmark(config)?,
        ]),
    }
}

fn run_sqlite_benchmark(config: &BenchmarkConfig) -> Result<BenchmarkReport, String> {
    let directory = TemporaryDirectory::new("sqlite_bench")?;
    let (storage, open) = measure_value("open", 1, || SqliteStorage::open(directory.path()))?;

    run_storage_benchmark("sqlite", storage, open, directory.path_buf(), config)
}

#[cfg(feature = "mdbx")]
fn run_mdbx_benchmark(config: &BenchmarkConfig) -> Result<BenchmarkReport, String> {
    let directory = TemporaryDirectory::new("mdbx_bench")?;
    let (storage, open) = measure_value("open", 1, || MdbxStorage::open(directory.path()))?;

    run_storage_benchmark("mdbx", storage, open, directory.path_buf(), config)
}

#[cfg(not(feature = "mdbx"))]
fn run_mdbx_benchmark(_config: &BenchmarkConfig) -> Result<BenchmarkReport, String> {
    Err("MDBX benchmark requires building with `--features benchmarks`.".into())
}

#[cfg(feature = "mdbx")]
fn run_mdbx_v2_benchmark(config: &BenchmarkConfig) -> Result<BenchmarkReport, String> {
    let directory = TemporaryDirectory::new("mdbx_v2_bench")?;
    let (storage, open) = measure_value("open", 1, || MdbxLayoutV2Storage::open(directory.path()))?;

    run_storage_benchmark("mdbx-v2-spike", storage, open, directory.path_buf(), config)
}

#[cfg(not(feature = "mdbx"))]
fn run_mdbx_v2_benchmark(_config: &BenchmarkConfig) -> Result<BenchmarkReport, String> {
    Err("MDBX layout v2 benchmark requires building with `--features benchmarks`.".into())
}

fn run_storage_benchmark(
    backend: &'static str,
    mut storage: impl StorageEngine,
    open: Measurement,
    database_path: &Path,
    config: &BenchmarkConfig,
) -> Result<BenchmarkReport, String> {
    let register_schemas = measure("register_schemas", 1, || {
        storage.register_schemas(&schema_manifest())
    })?;

    let put = measure_iterations("put_indexed", config.documents, |id| {
        storage.put_indexed(
            "users",
            id,
            document_bytes(id).as_bytes(),
            &benchmark_indexes(id),
        )
    })?;

    let get = measure_iterations("get", config.documents, |id| {
        let Some(bytes) = storage.get("users", id)? else {
            return Err(format!("missing document {id}"));
        };
        if bytes.is_empty() {
            return Err(format!("empty document {id}"));
        }
        Ok(())
    })?;

    let get_stored = measure_iterations("get_stored", config.documents, |id| {
        let Some(bytes) = storage.get_stored("users", id)? else {
            return Err(format!("missing stored document {id}"));
        };
        if bytes.is_empty() {
            return Err(format!("empty stored document {id}"));
        }
        Ok(())
    })?;

    let all_ids = (0..config.documents).collect::<Vec<_>>();
    let get_many = measure("get_many", config.documents, || {
        let documents = storage.get_many("users", &all_ids)?;
        if documents.len() != all_ids.len() {
            return Err(format!(
                "get_many returned {} documents for {} ids",
                documents.len(),
                all_ids.len()
            ));
        }
        if documents.iter().any(Option::is_none) {
            return Err("get_many returned missing documents".into());
        }
        Ok(())
    })?;

    let get_many_1 = measure_batched_reads("get_many_1", &all_ids, 1, |ids| {
        storage.get_many("users", ids)
    })?;
    let get_many_10 = measure_batched_reads("get_many_10", &all_ids, 10, |ids| {
        storage.get_many("users", ids)
    })?;
    let get_many_100 = measure_batched_reads("get_many_100", &all_ids, 100, |ids| {
        storage.get_many("users", ids)
    })?;
    let get_many_1000 = measure_batched_reads("get_many_1000", &all_ids, 1000, |ids| {
        storage.get_many("users", ids)
    })?;
    let get_many_stored = measure("get_many_stored", config.documents, || {
        let documents = storage.get_many_stored("users", &all_ids)?;
        if documents.len() != all_ids.len() {
            return Err(format!(
                "get_many_stored returned {} documents for {} ids",
                documents.len(),
                all_ids.len()
            ));
        }
        if documents.iter().any(Option::is_none) {
            return Err("get_many_stored returned missing documents".into());
        }
        Ok(())
    })?;
    let get_many_stored_1 = measure_batched_reads("get_many_stored_1", &all_ids, 1, |ids| {
        storage.get_many_stored("users", ids)
    })?;
    let get_many_stored_10 = measure_batched_reads("get_many_stored_10", &all_ids, 10, |ids| {
        storage.get_many_stored("users", ids)
    })?;
    let get_many_stored_100 = measure_batched_reads("get_many_stored_100", &all_ids, 100, |ids| {
        storage.get_many_stored("users", ids)
    })?;
    let get_many_stored_1000 =
        measure_batched_reads("get_many_stored_1000", &all_ids, 1000, |ids| {
            storage.get_many_stored("users", ids)
        })?;

    let document_ids = measure("document_ids", config.documents, || {
        let ids = storage.document_ids("users")?;
        if ids.len() != config.documents as usize {
            return Err(format!(
                "document_ids returned {} ids for {} documents",
                ids.len(),
                config.documents
            ));
        }
        Ok(())
    })?;

    let equality_query = measure_iterations("query_equal", config.query_repeats, |repeat| {
        let id = repeat % config.documents;
        let ids = storage.query_index_equal(
            "users",
            "email",
            &IndexValue::String(format!("user-{id}@example.com")),
        )?;
        if ids != vec![id] {
            return Err(format!("unexpected equality result for {id}: {ids:?}"));
        }
        Ok(())
    })?;

    let equality_query_with_get = measure_iterations(
        "query_equal_with_get_many",
        config.query_repeats,
        |repeat| {
            let id = repeat % config.documents;
            let ids = storage.query_index_equal(
                "users",
                "email",
                &IndexValue::String(format!("user-{id}@example.com")),
            )?;
            let documents = storage.get_many("users", &ids)?;
            if documents.len() != 1 || documents[0].is_none() {
                return Err(format!("unexpected equality documents for {id}"));
            }
            Ok(())
        },
    )?;

    let range_upper = config.documents.min(100) as i64 - 1;
    let range_query = measure_iterations("query_range", config.query_repeats, |_| {
        let ids = storage.query_index_range(
            "users",
            "score",
            Some(&IndexValue::Int(0)),
            Some(&IndexValue::Int(range_upper)),
        )?;
        if ids.is_empty() {
            return Err("range query returned no ids".into());
        }
        Ok(())
    })?;

    let range_query_with_get =
        measure_iterations("query_range_with_get_many", config.query_repeats, |_| {
            let ids = storage.query_index_range(
                "users",
                "score",
                Some(&IndexValue::Int(0)),
                Some(&IndexValue::Int(range_upper)),
            )?;
            let documents = storage.get_many("users", &ids)?;
            if documents.is_empty() || documents.iter().any(Option::is_none) {
                return Err("range query returned missing documents".into());
            }
            Ok(())
        })?;

    let filter_query = if backend == "mdbx" {
        Some(measure_iterations(
            "query_filter_score_lte_99",
            config.query_repeats,
            |_| {
                let ids = storage.query_filter(
                    "users",
                    &all_ids,
                    br#"{"type":"field","field":"score","operation":"less_than_or_equal_to","value":99}"#,
                )?;
                if ids.is_empty() {
                    return Err("filter query returned no ids".into());
                }
                Ok(())
            },
        )?)
    } else {
        None
    };

    let projection_name = if backend == "mdbx" {
        Some(measure_iterations(
            "projection_name",
            config.query_repeats,
            |_| {
                let result = storage.query_project("users", &all_ids, "name")?;
                if result.is_empty() {
                    return Err("projection returned empty bytes".into());
                }
                Ok(())
            },
        )?)
    } else {
        None
    };

    let aggregate_average =
        measure_iterations("aggregate_score_average", config.query_repeats, |_| {
            let result = storage.query_aggregate("users", &all_ids, "score", "average")?;
            if result.is_empty() {
                return Err("aggregate average returned empty bytes".into());
            }
            Ok(())
        })?;

    let aggregate_max = measure_iterations("aggregate_name_max", config.query_repeats, |_| {
        let result = storage.query_aggregate("users", &all_ids, "name", "max")?;
        if result.is_empty() {
            return Err("aggregate max returned empty bytes".into());
        }
        Ok(())
    })?;

    let composite_query =
        measure_iterations("query_composite_equal", config.query_repeats, |repeat| {
            let id = repeat % config.documents;
            let ids = storage.query_index_equal(
                "users",
                "email_active",
                &IndexValue::List(vec![
                    IndexValue::String(format!("user-{id}@example.com")),
                    IndexValue::Bool(id % 2 == 0),
                ]),
            )?;
            if ids != vec![id] {
                return Err(format!("unexpected composite result for {id}: {ids:?}"));
            }
            Ok(())
        })?;

    let multi_entry_query = measure_iterations("query_multi_entry", config.query_repeats, |_| {
        let ids = storage.query_index_equal("users", "tags", &IndexValue::String("even".into()))?;
        if ids.is_empty() {
            return Err("multi-entry query returned no ids".into());
        }
        Ok(())
    })?;

    let collection_revision =
        measure_iterations("collection_revision", config.query_repeats, |_| {
            let revision = storage.collection_revision("users")?;
            if revision == 0 {
                return Err("collection revision was not advanced".into());
            }
            Ok(())
        })?;

    let batch_start_id = config.documents;
    let batch_documents = (0..config.documents)
        .map(|offset| {
            let id = batch_start_id + offset;
            DocumentWrite {
                id,
                bytes: document_bytes(id).into_bytes(),
                indexes: benchmark_indexes(id),
            }
        })
        .collect::<Vec<_>>();
    let batch_put = measure("put_many_indexed", config.documents, || {
        storage.put_many_indexed("users", &batch_documents)
    })?;

    let batch_ids = (batch_start_id..batch_start_id + config.documents).collect::<Vec<_>>();
    let delete_many = measure("delete_many", config.documents, || {
        storage.delete_many("users", &batch_ids)
    })?;

    let delete_start_id = batch_start_id + config.documents;
    let delete_documents = (0..config.query_repeats)
        .map(|offset| {
            let id = delete_start_id + offset;
            DocumentWrite {
                id,
                bytes: document_bytes(id).into_bytes(),
                indexes: benchmark_indexes(id),
            }
        })
        .collect::<Vec<_>>();
    storage.put_many_indexed("users", &delete_documents)?;
    let delete = measure_iterations("delete", config.query_repeats, |offset| {
        storage.delete("users", delete_start_id + offset)
    })?;

    let allocate_id = measure_iterations("allocate_id", config.query_repeats, |_| {
        storage.allocate_id("users").map(|_| ())
    })?;

    let auto_increment_put =
        measure_iterations("put_indexed_auto_increment", config.query_repeats, |_| {
            let id = storage.allocate_id("users")?;
            storage.put_indexed(
                "users",
                id,
                document_bytes(id).as_bytes(),
                &benchmark_indexes(id),
            )
        })?;

    let database_size_bytes = directory_size_bytes(database_path)?;

    let mut measurements = vec![
        open,
        register_schemas,
        put,
        get,
        get_stored,
        get_many,
        get_many_1,
        get_many_10,
        get_many_100,
        get_many_1000,
        get_many_stored,
        get_many_stored_1,
        get_many_stored_10,
        get_many_stored_100,
        get_many_stored_1000,
        document_ids,
        equality_query,
        equality_query_with_get,
        range_query,
        range_query_with_get,
    ];
    if let Some(filter_query) = filter_query {
        measurements.push(filter_query);
    }
    if let Some(projection_name) = projection_name {
        measurements.push(projection_name);
    }
    measurements.extend([
        aggregate_average,
        aggregate_max,
        composite_query,
        multi_entry_query,
        collection_revision,
        batch_put,
        delete_many,
        delete,
        allocate_id,
        auto_increment_put,
    ]);

    Ok(BenchmarkReport {
        backend,
        database_size_bytes,
        measurements,
    })
}

fn measure(
    operation: &'static str,
    items: u64,
    action: impl FnOnce() -> Result<(), String>,
) -> Result<Measurement, String> {
    let started_at = Instant::now();
    action()?;
    let elapsed = started_at.elapsed();
    Ok(Measurement {
        operation,
        items,
        elapsed,
        samples: vec![elapsed],
    })
}

fn measure_iterations(
    operation: &'static str,
    items: u64,
    mut action: impl FnMut(u64) -> Result<(), String>,
) -> Result<Measurement, String> {
    let mut samples = Vec::with_capacity(items as usize);
    let started_at = Instant::now();
    for index in 0..items {
        let sample_started_at = Instant::now();
        action(index)?;
        samples.push(sample_started_at.elapsed());
    }
    Ok(Measurement {
        operation,
        items,
        elapsed: started_at.elapsed(),
        samples,
    })
}

fn measure_batched_reads(
    operation: &'static str,
    ids: &[u64],
    batch_size: usize,
    mut read: impl FnMut(&[u64]) -> Result<Vec<Option<Vec<u8>>>, String>,
) -> Result<Measurement, String> {
    let batch_size = batch_size.max(1);
    let mut samples = Vec::with_capacity(ids.len().div_ceil(batch_size));
    let started_at = Instant::now();
    for batch in ids.chunks(batch_size) {
        let sample_started_at = Instant::now();
        let documents = read(batch)?;
        samples.push(sample_started_at.elapsed());
        if documents.len() != batch.len() {
            return Err(format!(
                "{operation} returned {} documents for {} ids",
                documents.len(),
                batch.len()
            ));
        }
        if documents.iter().any(Option::is_none) {
            return Err(format!("{operation} returned missing documents"));
        }
    }
    Ok(Measurement {
        operation,
        items: ids.len() as u64,
        elapsed: started_at.elapsed(),
        samples,
    })
}

fn measure_value<T>(
    operation: &'static str,
    items: u64,
    action: impl FnOnce() -> Result<T, String>,
) -> Result<(T, Measurement), String> {
    let started_at = Instant::now();
    let value = action()?;
    let elapsed = started_at.elapsed();
    Ok((
        value,
        Measurement {
            operation,
            items,
            elapsed,
            samples: vec![elapsed],
        },
    ))
}

fn directory_size_bytes(path: &Path) -> Result<u64, String> {
    if !path.exists() {
        return Ok(0);
    }
    let mut size = 0;
    let mut pending = vec![path.to_path_buf()];
    while let Some(path) = pending.pop() {
        let metadata = fs::metadata(&path).map_err(|error| error.to_string())?;
        if metadata.is_file() {
            size += metadata.len();
        } else if metadata.is_dir() {
            for entry in fs::read_dir(&path).map_err(|error| error.to_string())? {
                pending.push(entry.map_err(|error| error.to_string())?.path());
            }
        }
    }
    Ok(size)
}

fn document_bytes(id: u64) -> String {
    format!(
        r#"{{"id":{id},"name":"User {id}","email":"user-{id}@example.com","score":{},"active":{},"tags":["{}","user-{}"]}}"#,
        id % 1_000,
        id % 2 == 0,
        if id % 2 == 0 { "even" } else { "odd" },
        id % 100,
    )
}

fn benchmark_indexes(id: u64) -> Vec<IndexEntry> {
    vec![
        IndexEntry {
            name: "email".to_string(),
            value: IndexValue::String(format!("user-{id}@example.com")),
        },
        IndexEntry {
            name: "score".to_string(),
            value: IndexValue::Int((id % 1_000) as i64),
        },
        IndexEntry {
            name: "email_active".to_string(),
            value: IndexValue::List(vec![
                IndexValue::String(format!("user-{id}@example.com")),
                IndexValue::Bool(id % 2 == 0),
            ]),
        },
        IndexEntry {
            name: "tags".to_string(),
            value: IndexValue::String(if id % 2 == 0 { "even" } else { "odd" }.to_string()),
        },
        IndexEntry {
            name: "tags".to_string(),
            value: IndexValue::String(format!("user-{}", id % 100)),
        },
    ]
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
                FieldSchemaManifest {
                    name: "active".to_string(),
                    dart_type: "bool".to_string(),
                    is_id: false,
                    is_indexed: false,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "value".to_string(),
                },
                FieldSchemaManifest {
                    name: "tags".to_string(),
                    dart_type: "List<String>".to_string(),
                    is_id: false,
                    is_indexed: true,
                    is_index_unique: false,
                    index_case_sensitive: true,
                    index_type: "multiEntry".to_string(),
                },
            ],
            composite_indexes: vec![CompositeIndexSchemaManifest {
                name: "email_active".to_string(),
                fields: vec!["email".to_string(), "active".to_string()],
                is_unique: false,
                case_sensitive: true,
            }],
        }],
    }
}

struct BenchmarkRun {
    generated_at_unix_ms: u128,
    config: BenchmarkConfigSnapshot,
    reports: Vec<BenchmarkReport>,
}

impl BenchmarkRun {
    fn new(config: &BenchmarkConfig, reports: Vec<BenchmarkReport>) -> Self {
        let generated_at_unix_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_millis())
            .unwrap_or_default();
        Self {
            generated_at_unix_ms,
            config: BenchmarkConfigSnapshot {
                backend: config.backend.as_str().to_string(),
                documents: config.documents,
                query_repeats: config.query_repeats,
            },
            reports,
        }
    }

    fn to_csv(&self) -> String {
        let mut output =
            String::from("backend,operation,items,total_ms,ops_per_second,p50_us,p95_us\n");
        for report in &self.reports {
            for measurement in &report.measurements {
                output.push_str(&format!(
                    "{},{},{},{:.3},{:.2},{},{}\n",
                    report.backend,
                    measurement.operation,
                    measurement.items,
                    measurement.elapsed.as_secs_f64() * 1000.0,
                    measurement.ops_per_second(),
                    format_optional_f64(measurement.percentile_us(0.50)),
                    format_optional_f64(measurement.percentile_us(0.95)),
                ));
            }
        }
        output
    }

    fn to_json(&self) -> Result<String, String> {
        serde_json::to_string_pretty(&BenchmarkRunJson::from(self))
            .map_err(|error| error.to_string())
            .map(|json| format!("{json}\n"))
    }
}

fn format_optional_f64(value: Option<f64>) -> String {
    value.map(|value| format!("{value:.3}")).unwrap_or_default()
}

#[derive(serde::Serialize)]
struct BenchmarkRunJson {
    generated_at_unix_ms: u128,
    config: BenchmarkConfigSnapshot,
    reports: Vec<BenchmarkReportJson>,
}

impl From<&BenchmarkRun> for BenchmarkRunJson {
    fn from(run: &BenchmarkRun) -> Self {
        Self {
            generated_at_unix_ms: run.generated_at_unix_ms,
            config: run.config.clone(),
            reports: run.reports.iter().map(BenchmarkReportJson::from).collect(),
        }
    }
}

#[derive(Clone, serde::Serialize)]
struct BenchmarkConfigSnapshot {
    backend: String,
    documents: u64,
    query_repeats: u64,
}

#[derive(serde::Serialize)]
struct BenchmarkReportJson {
    backend: &'static str,
    database_size_bytes: u64,
    measurements: Vec<MeasurementJson>,
}

impl From<&BenchmarkReport> for BenchmarkReportJson {
    fn from(report: &BenchmarkReport) -> Self {
        Self {
            backend: report.backend,
            database_size_bytes: report.database_size_bytes,
            measurements: report
                .measurements
                .iter()
                .map(MeasurementJson::from)
                .collect(),
        }
    }
}

#[derive(serde::Serialize)]
struct MeasurementJson {
    operation: &'static str,
    items: u64,
    total_ms: f64,
    ops_per_second: f64,
    p50_us: Option<f64>,
    p95_us: Option<f64>,
}

impl From<&Measurement> for MeasurementJson {
    fn from(measurement: &Measurement) -> Self {
        Self {
            operation: measurement.operation,
            items: measurement.items,
            total_ms: measurement.elapsed.as_secs_f64() * 1000.0,
            ops_per_second: measurement.ops_per_second(),
            p50_us: measurement.percentile_us(0.50),
            p95_us: measurement.percentile_us(0.95),
        }
    }
}

struct BenchmarkReport {
    backend: &'static str,
    database_size_bytes: u64,
    measurements: Vec<Measurement>,
}

struct Measurement {
    operation: &'static str,
    items: u64,
    elapsed: Duration,
    samples: Vec<Duration>,
}

impl Measurement {
    fn ops_per_second(&self) -> f64 {
        self.items as f64 / self.elapsed.as_secs_f64()
    }

    fn percentile_us(&self, percentile: f64) -> Option<f64> {
        if self.samples.is_empty() {
            return None;
        }
        let mut samples = self.samples.clone();
        samples.sort_unstable();
        let index = ((samples.len().saturating_sub(1)) as f64 * percentile).round() as usize;
        samples
            .get(index)
            .map(|duration| duration.as_secs_f64() * 1_000_000.0)
    }
}

#[derive(Clone, Copy)]
enum OutputFormat {
    Csv,
    Json,
}

impl OutputFormat {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "csv" => Ok(Self::Csv),
            "json" => Ok(Self::Json),
            _ => Err(format!(
                "`--format` must be one of `csv` or `json`; got `{value}`"
            )),
        }
    }
}

struct BenchmarkConfig {
    documents: u64,
    query_repeats: u64,
    backend: BackendSelection,
    output_format: OutputFormat,
    output_path: Option<PathBuf>,
}

impl BenchmarkConfig {
    fn from_args(args: impl Iterator<Item = String>) -> Result<Self, String> {
        let mut documents = DEFAULT_DOCUMENTS;
        let mut query_repeats = DEFAULT_QUERY_REPEATS;
        let mut backend = BackendSelection::Sqlite;
        let mut output_format = OutputFormat::Csv;
        let mut output_path = None;
        let mut pending_flag: Option<String> = None;

        for arg in args {
            if let Some(flag) = pending_flag.take() {
                match flag.as_str() {
                    "--documents" => documents = parse_positive_u64(&flag, &arg)?,
                    "--query-repeats" => query_repeats = parse_positive_u64(&flag, &arg)?,
                    "--backend" => backend = BackendSelection::parse(&arg)?,
                    "--format" => output_format = OutputFormat::parse(&arg)?,
                    "--output" => output_path = Some(PathBuf::from(arg)),
                    _ => unreachable!("unexpected benchmark flag"),
                }
                continue;
            }

            match arg.as_str() {
                "--backend" | "--documents" | "--query-repeats" | "--format" | "--output" => {
                    pending_flag = Some(arg)
                }
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
            output_format,
            output_path,
        })
    }
}

#[derive(Clone, Copy)]
enum BackendSelection {
    Sqlite,
    Mdbx,
    MdbxV2,
    All,
    AllWithSpike,
}

impl BackendSelection {
    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "sqlite" => Ok(Self::Sqlite),
            "mdbx" => Ok(Self::Mdbx),
            "mdbx-v2" | "mdbx-v2-spike" => Ok(Self::MdbxV2),
            "all" => Ok(Self::All),
            "all-with-spike" | "all-experimental" => Ok(Self::AllWithSpike),
            _ => Err(format!(
                "`--backend` must be one of `sqlite`, `mdbx`, `mdbx-v2`, `all`, or `all-with-spike`; got `{value}`"
            )),
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Sqlite => "sqlite",
            Self::Mdbx => "mdbx",
            Self::MdbxV2 => "mdbx-v2",
            Self::All => "all",
            Self::AllWithSpike => "all-with-spike",
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
        "Usage: cargo run --manifest-path packages/cindel/native/Cargo.toml --bin cindel_bench -- [--backend sqlite|mdbx|mdbx-v2|all|all-with-spike] [--documents N] [--query-repeats N] [--format csv|json] [--output PATH]"
    );
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

    fn path_buf(&self) -> &Path {
        &self.path
    }
}

impl Drop for TemporaryDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}
