param(
  [int] $Documents = 5000,
  [int] $QueryRepeats = 500,
  [ValidateSet("all", "sqlite", "mdbx")]
  [string] $Backend = "all",
  [ValidateSet("both", "native", "dart")]
  [string] $Suite = "both",
  [string] $CargoTargetDir = (Join-Path $env:TEMP "cindel_benchmark_target"),
  [string] $LibclangPath = "C:\Program Files\LLVM\bin",
  [string] $DartExe = "D:\WORK\INSTALL\flutter\bin\cache\dart-sdk\bin\dart.exe",
  [string] $NativeLibraryPath = ""
)

$ErrorActionPreference = "Stop"
$InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

$OutputDir = Join-Path $PSScriptRoot "out"
$NativeJsonPath = Join-Path $OutputDir "native_benchmark.json"
$DartJsonPath = Join-Path $OutputDir "dart_benchmark.json"
$CombinedJsonPath = Join-Path $OutputDir "cindel_benchmark.json"
$HtmlPath = Join-Path $OutputDir "cindel_benchmark.html"

function Format-Ratio {
  param([double] $Value)

  if ($Value -eq 0 -or [double]::IsNaN($Value) -or [double]::IsInfinity($Value)) {
    return "n/a"
  }

  return [string]::Format($InvariantCulture, "{0:N2}x", $Value)
}

function Format-Millis {
  param([double] $Value)

  if ($Value -ge 1000) {
    return [string]::Format($InvariantCulture, "{0:N2}s", ($Value / 1000))
  }

  return [string]::Format($InvariantCulture, "{0:N2}ms", $Value)
}

function Format-Number {
  param([double] $Value)

  return [string]::Format($InvariantCulture, "{0:N2}", $Value)
}

function Html-Escape {
  param([string] $Value)

  return [System.Net.WebUtility]::HtmlEncode($Value)
}

function Read-BenchmarkJson {
  param([string] $Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Benchmark JSON was not created: $Path"
  }

  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function New-ComparisonRows {
  param(
    [string] $SuiteName,
    [object] $Benchmark
  )

  $backendDefinitions = @(
    [pscustomobject]@{ key = "sqlite"; label = "SQLite"; class = "sqlite" }
    [pscustomobject]@{ key = "mdbx"; label = "MDBX"; class = "mdbx" }
    [pscustomobject]@{ key = "mdbx-v2-spike"; label = "MDBX v2"; class = "mdbx-v2" }
  )
  $reports = @{}
  foreach ($definition in $backendDefinitions) {
    $report = $Benchmark.reports |
      Where-Object backend -eq $definition.key |
      Select-Object -First 1
    if ($report) {
      $reports[$definition.key] = $report
    }
  }

  $operationNames = @(
    foreach ($report in $reports.Values) {
      @($report.measurements | ForEach-Object operation)
    }
  ) | Where-Object { $_ } | Sort-Object -Unique

  foreach ($operationName in $operationNames) {
    $series = @()
    foreach ($definition in $backendDefinitions) {
      if (-not $reports.ContainsKey($definition.key)) {
        continue
      }

      $measurement = $reports[$definition.key].measurements |
        Where-Object operation -eq $operationName |
        Select-Object -First 1
      if (-not $measurement) {
        continue
      }

      $series += [pscustomobject]@{
        key = $definition.key
        label = $definition.label
        class = $definition.class
        total_ms = [double]$measurement.total_ms
        ops_per_second = [double]$measurement.ops_per_second
        p50_us = $measurement.p50_us
        p95_us = $measurement.p95_us
      }
    }

    $winner = "n/a"
    $winnerClass = "tie"
    $speedupRatio = $null
    $mdbxVsSqlite = $null
    $mdbxV2VsSqlite = $null

    $ranked = @($series | Where-Object { $_.total_ms -gt 0 } | Sort-Object total_ms)
    if ($ranked.Count -gt 0) {
      $winner = $ranked[0].label
      $winnerClass = $ranked[0].class
      if ($ranked.Count -gt 1) {
        $speedupRatio = [double]$ranked[1].total_ms / [double]$ranked[0].total_ms
      } else {
        $speedupRatio = 1
      }
    }

    $sqliteSeries = $series | Where-Object key -eq "sqlite" | Select-Object -First 1
    $mdbxSeries = $series | Where-Object key -eq "mdbx" | Select-Object -First 1
    $mdbxV2Series = $series | Where-Object key -eq "mdbx-v2-spike" | Select-Object -First 1
    if ($sqliteSeries -and $mdbxSeries -and $sqliteSeries.total_ms -gt 0 -and $mdbxSeries.total_ms -gt 0) {
      $mdbxVsSqlite = $sqliteSeries.total_ms / $mdbxSeries.total_ms
    }
    if ($sqliteSeries -and $mdbxV2Series -and $sqliteSeries.total_ms -gt 0 -and $mdbxV2Series.total_ms -gt 0) {
      $mdbxV2VsSqlite = $sqliteSeries.total_ms / $mdbxV2Series.total_ms
    }

    [pscustomobject]@{
      suite = $SuiteName
      operation = $operationName
      items = if ($reports.Count -gt 0) {
        $firstReport = @($reports.Values)[0]
        $firstMeasurement = $firstReport.measurements |
          Where-Object operation -eq $operationName |
          Select-Object -First 1
        if ($firstMeasurement) { [int64]$firstMeasurement.items } else { 0 }
      } else { 0 }
      series = @($series)
      sqlite = $sqliteSeries
      mdbx = $mdbxSeries
      mdbx_v2 = $mdbxV2Series
      winner = $winner
      winner_class = $winnerClass
      speedup_ratio = $speedupRatio
      speedup_label = if ($speedupRatio -ne $null) { Format-Ratio $speedupRatio } else { "n/a" }
      mdbx_vs_sqlite_ratio = $mdbxVsSqlite
      mdbx_vs_sqlite_label = if ($mdbxVsSqlite -ne $null) { Format-Ratio $mdbxVsSqlite } else { "n/a" }
      mdbx_v2_vs_sqlite_ratio = $mdbxV2VsSqlite
      mdbx_v2_vs_sqlite_label = if ($mdbxV2VsSqlite -ne $null) { Format-Ratio $mdbxV2VsSqlite } else { "n/a" }
    }
  }
}

function New-CardHtml {
  param([object] $Comparison)

  $series = @($Comparison.series)
  $operationMaxMs = 0
  foreach ($item in $series) {
    $operationMaxMs = [Math]::Max($operationMaxMs, [double]$item.total_ms)
  }
  if ($operationMaxMs -le 0) {
    $operationMaxMs = 1
  }

  $barColumns = [Math]::Max(1, $series.Count)
  $bars = foreach ($item in $series) {
    $totalMs = [double]$item.total_ms
    $height = [Math]::Max(8, [Math]::Round(($totalMs / $operationMaxMs) * 176))
@"
          <div class="bar-wrap">
            <div class="value">$(Format-Millis $totalMs)</div>
            <div class="bar $($item.class)" style="height: ${height}px"></div>
            <div class="label">$(Html-Escape $item.label)</div>
          </div>
"@
  }

  $details = @()
  if ($Comparison.mdbx_vs_sqlite_ratio -ne $null) {
    $details += "<div><dt>MDBX vs SQLite</dt><dd>$(Html-Escape $Comparison.mdbx_vs_sqlite_label)</dd></div>"
  }
  if ($Comparison.mdbx_v2_vs_sqlite_ratio -ne $null) {
    $details += "<div><dt>MDBX v2 vs SQLite</dt><dd>$(Html-Escape $Comparison.mdbx_v2_vs_sqlite_label)</dd></div>"
  }
  foreach ($item in $series) {
    $details += "<div><dt>$(Html-Escape $item.label) ops/s</dt><dd>$(Format-Number ([double]$item.ops_per_second))</dd></div>"
  }
  foreach ($item in $series) {
    $p95 = if ($item.p95_us -ne $null) { "$(Format-Number ([double]$item.p95_us))us" } else { "n/a" }
    $details += "<div><dt>$(Html-Escape $item.label) p95</dt><dd>$p95</dd></div>"
  }

@"
      <section class="card">
        <div class="card-head">
          <div>
            <h2>$(Html-Escape $Comparison.operation)</h2>
            <p>$($Comparison.items) item(s)</p>
          </div>
          <div class="badge $($Comparison.winner_class)">$(Html-Escape $Comparison.winner) · $(Html-Escape $Comparison.speedup_label)</div>
        </div>
        <div class="bars" style="grid-template-columns: repeat($barColumns, minmax(0, 1fr));">
$($bars -join "`n")
        </div>
        <dl>
$($details -join "`n")
        </dl>
      </section>
"@
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$benchmarkRuns = @()

if ($Suite -eq "both" -or $Suite -eq "native") {
  $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
  $env:LIBCLANG_PATH = $LibclangPath
  $env:CARGO_TARGET_DIR = $CargoTargetDir

  Push-Location $repoRoot
  try {
    & cargo run --release --manifest-path packages/cindel/native/Cargo.toml --features benchmarks --bin cindel_bench -- --backend $Backend --documents $Documents --query-repeats $QueryRepeats --format json --output $NativeJsonPath
    if ($LASTEXITCODE -ne 0) {
      throw "Native benchmark command failed with exit code $LASTEXITCODE."
    }
  } finally {
    Pop-Location
  }

  $nativeBenchmark = Read-BenchmarkJson $NativeJsonPath
  $benchmarkRuns += [pscustomobject]@{
    suite = "Native storage"
    path = $NativeJsonPath
    benchmark = $nativeBenchmark
  }
}

if ($Suite -eq "both" -or $Suite -eq "dart") {
  if (-not (Test-Path -LiteralPath $DartExe)) {
    throw "Dart executable was not found: $DartExe"
  }

  if ([string]::IsNullOrWhiteSpace($NativeLibraryPath)) {
    $NativeLibraryPath = Join-Path $repoRoot "packages\cindel_flutter_libs\windows\cindel_native.dll"
  }

  $resolvedNativeLibrary = Resolve-Path $NativeLibraryPath
  $env:CINDEL_NATIVE_LIBRARY = $resolvedNativeLibrary.Path

  Push-Location (Join-Path $repoRoot "packages\cindel")
  try {
    & $DartExe run tool\perf_benchmark.dart --backend $Backend --documents $Documents --query-repeats $QueryRepeats --output $DartJsonPath
    if ($LASTEXITCODE -ne 0) {
      throw "Dart benchmark command failed with exit code $LASTEXITCODE."
    }
  } finally {
    Pop-Location
  }

  $dartBenchmark = Read-BenchmarkJson $DartJsonPath
  $benchmarkRuns += [pscustomobject]@{
    suite = "Dart API"
    path = $DartJsonPath
    benchmark = $dartBenchmark
  }
}

$comparisons = @()
foreach ($run in $benchmarkRuns) {
  $comparisons += @(New-ComparisonRows -SuiteName $run.suite -Benchmark $run.benchmark)
}

$result = [pscustomobject]@{
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  config = [pscustomobject]@{
    documents = $Documents
    query_repeats = $QueryRepeats
    backend = $Backend
    suite = $Suite
    cargo_target_dir = $CargoTargetDir
    dart_exe = $DartExe
  }
  sources = @($benchmarkRuns | ForEach-Object {
    [pscustomobject]@{
      suite = $_.suite
      path = $_.path
      database_sizes = @($_.benchmark.reports | ForEach-Object {
        [pscustomobject]@{
          backend = $_.backend
          database_size_bytes = $_.database_size_bytes
        }
      })
    }
  })
  comparisons = @($comparisons)
}

$result | ConvertTo-Json -Depth 10 | Set-Content -Path $CombinedJsonPath -Encoding UTF8

$sections = foreach ($suiteGroup in ($comparisons | Group-Object suite)) {
  $cards = foreach ($comparison in $suiteGroup.Group) {
    New-CardHtml $comparison
  }

@"
    <section class="suite">
      <div class="suite-head">
        <h2>$(Html-Escape $suiteGroup.Name)</h2>
      </div>
      <div class="grid">
$($cards -join "`n")
      </div>
    </section>
"@
}

$sourceLines = foreach ($source in $result.sources) {
  "<p>$(Html-Escape $source.suite): $(Html-Escape $source.path)</p>"
}

$html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Cindel Benchmark</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #111820;
      --panel: #1d2a36;
      --text: #e8edf5;
      --muted: #aeb9c7;
      --sqlite: #8fc4f5;
      --mdbx: #7ee0b2;
      --mdbx-v2: #d6b66f;
      --line: #334353;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      background: var(--bg);
      color: var(--text);
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      padding: 32px;
    }
    header, .suite {
      max-width: 1240px;
      margin: 0 auto;
    }
    header {
      margin-bottom: 26px;
    }
    h1 {
      margin: 0 0 8px;
      font-size: 32px;
      font-weight: 650;
      letter-spacing: 0;
    }
    header p {
      margin: 4px 0 0;
      color: var(--muted);
      font-size: 14px;
      overflow-wrap: anywhere;
    }
    .suite {
      margin-top: 26px;
    }
    .suite-head {
      margin-bottom: 12px;
      border-bottom: 1px solid var(--line);
      padding-bottom: 8px;
    }
    .suite-head h2 {
      margin: 0;
      font-size: 22px;
      font-weight: 650;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 16px;
    }
    .card {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 18px;
      overflow: hidden;
    }
    .card-head {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 12px;
      min-height: 68px;
    }
    .card-head h2 {
      margin: 0;
      font-size: 18px;
      font-weight: 640;
      line-height: 1.2;
      overflow-wrap: anywhere;
    }
    .card p {
      margin: 4px 0 0;
      color: var(--muted);
    }
    .badge {
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 5px 9px;
      font-size: 12px;
      color: var(--muted);
      white-space: nowrap;
    }
    .badge.mdbx { color: var(--mdbx); border-color: #60bd94; }
    .badge.mdbx-v2 { color: var(--mdbx-v2); border-color: #b8974d; }
    .badge.sqlite { color: var(--sqlite); border-color: #6fa8db; }
    .bars {
      height: 252px;
      display: grid;
      gap: 24px;
      align-items: end;
      padding-top: 24px;
    }
    .bar-wrap {
      min-width: 0;
      display: grid;
      justify-items: center;
      gap: 8px;
    }
    .value {
      color: #c9d7e8;
      font-weight: 700;
      font-size: 15px;
    }
    .bar {
      width: min(34px, 36%);
      min-height: 8px;
      border-radius: 999px 999px 6px 6px;
    }
    .bar.sqlite { background: var(--sqlite); }
    .bar.mdbx { background: var(--mdbx); }
    .bar.mdbx-v2 { background: var(--mdbx-v2); }
    .label {
      color: var(--muted);
      font-weight: 650;
      letter-spacing: 0;
    }
    dl {
      margin: 18px 0 0;
      display: grid;
      gap: 8px;
      border-top: 1px solid var(--line);
      padding-top: 14px;
    }
    dl div {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      font-size: 13px;
    }
    dt { color: var(--muted); }
    dd { margin: 0; font-weight: 650; text-align: right; }
  </style>
</head>
<body>
  <header>
    <h1>Cindel Benchmark</h1>
    <p>Documents: $Documents · Query repeats: $QueryRepeats · Backend: $Backend · Suite: $Suite · Generated: $($result.generated_at)</p>
    <p>Combined JSON: $(Html-Escape $CombinedJsonPath)</p>
$($sourceLines -join "`n")
  </header>
$($sections -join "`n")
</body>
</html>
"@

Set-Content -Path $HtmlPath -Value $html -Encoding UTF8

Write-Host "Benchmark complete."
Write-Host "Combined JSON: $CombinedJsonPath"
Write-Host "HTML: $HtmlPath"
