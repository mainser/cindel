param(
  [int] $Documents = 50000,
  [int] $PayloadBytes = 1024,
  [int] $GetCount = 25000,
  [int] $Repeats = 5,
  [string] $NativeLibrary = "",
  [string] $IsarLibrary = "",
  [switch] $IncludeRaw
)

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$benchDir = Join-Path $repo "tool\benchmark\backend_get_compare"
$outDir = Join-Path $repo "tool\benchmark\out"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outFile = Join-Path $outDir "backend_get_compare_$stamp.csv"
$dart = "D:\WORK\INSTALL\flutter\bin\cache\dart-sdk\bin\dart.exe"
$sourceNativeLibrary = Join-Path $repo "packages\cindel\native\target\release\cindel_native.dll"
$bundledNativeLibrary = Join-Path $repo "packages\cindel_flutter_libs\windows\cindel_native.dll"
$isarCacheLibrary = Join-Path $env:LOCALAPPDATA "Pub\Cache\hosted\pub.dev\isar_flutter_libs-4.0.0-dev.14\windows\isar.dll"
$nativeLibrary = if ($NativeLibrary) {
  $NativeLibrary
} elseif (Test-Path $sourceNativeLibrary) {
  $sourceNativeLibrary
} elseif ($env:CINDEL_NATIVE_LIBRARY) {
  $env:CINDEL_NATIVE_LIBRARY
} else {
  throw "Backend benchmark requires a source-current native DLL. Build it with `cargo build --release --manifest-path packages/cindel/native/Cargo.toml` or pass -NativeLibrary. Refusing to use bundled DLL: $bundledNativeLibrary"
}
$isarLibrary = if ($IsarLibrary) {
  $IsarLibrary
} elseif (Test-Path $isarCacheLibrary) {
  $isarCacheLibrary
} else {
  throw "Isar DLL not found. Install/run a project with isar_flutter_libs 4.0.0-dev.14 first, or pass -IsarLibrary."
}

New-Item -ItemType Directory -Force $outDir | Out-Null

if (-not (Test-Path $nativeLibrary)) {
  throw "Native library not found: $nativeLibrary"
}
if (-not (Test-Path $isarLibrary)) {
  throw "Isar library not found: $isarLibrary"
}

if (-not (Test-Path (Join-Path $benchDir ".dart_tool\package_config.json"))) {
  Push-Location $benchDir
  try {
    & $dart pub get | Out-Host
    if ($LASTEXITCODE -ne 0) {
      throw "dart pub get failed"
    }
  } finally {
    Pop-Location
  }
}

$env:CINDEL_NATIVE_LIBRARY = $nativeLibrary
Write-Host "Native library: $nativeLibrary"
Write-Host "Isar library: $isarLibrary"
if ((Resolve-Path $nativeLibrary).Path -eq (Resolve-Path $bundledNativeLibrary -ErrorAction SilentlyContinue).Path) {
  throw "Backend benchmark cannot use the bundled Windows DLL. Build native and pass -NativeLibrary for source-current evidence."
}
Copy-Item -Path $isarLibrary -Destination (Join-Path $benchDir "isar.dll") -Force

Write-Host "Running backend compare..."
Push-Location $benchDir
try {
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $arguments = @(
    "run",
    "bin\backend_get_compare.dart",
    "--documents",
    $Documents,
    "--payload-bytes",
    $PayloadBytes,
    "--get-count",
    $GetCount,
    "--repeats",
    $Repeats
  )
  if ($IncludeRaw) {
    $arguments += "--include-raw"
  }
  $output = & $dart @arguments 2>&1
  $dartExitCode = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previousErrorActionPreference
  Pop-Location
}
if ($dartExitCode -ne 0) {
  throw "Backend benchmark failed: $($output -join [Environment]::NewLine)"
}

$joinedOutput = $output -join [Environment]::NewLine
$csvStart = $joinedOutput.IndexOf("profile,")
if ($csvStart -lt 0) {
  throw "Unexpected backend benchmark output: $joinedOutput"
}
$lines = $joinedOutput.Substring($csvStart) -split '\r?\n' |
  Where-Object {
    $_ -and (
      $_.StartsWith("profile,") -or
      $_.StartsWith("cindel-raw-bytes,") -or
      $_.StartsWith("cindel-typed,") -or
      $_.StartsWith("isar-typed,")
    )
  }

if ($lines.Count -lt 3) {
  throw "Unexpected backend benchmark output: $($output -join [Environment]::NewLine)"
}
$lines | Set-Content -Path $outFile

Write-Host "Backend benchmark evidence written to: $outFile"

$rows = Import-Csv -Path $outFile
$invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
$summary = $rows |
  Group-Object profile |
  ForEach-Object {
    $group = $_.Group
    [pscustomobject]@{
      Profile = $_.Name
      Repeats = $group.Count
      Documents = [int]$group[0].documents
      GetCount = [int]$group[0].get_count
      PrepareMs = ([math]::Round(($group | Measure-Object prepare_ms -Average).Average, 2)).ToString("0.00", $invariantCulture)
      OpenMs = ([math]::Round(($group | Measure-Object open_ms -Average).Average, 2)).ToString("0.00", $invariantCulture)
      InsertMs = ([math]::Round(($group | Measure-Object insert_ms -Average).Average, 2)).ToString("0.00", $invariantCulture)
      GetMs = ([math]::Round(($group | Measure-Object get_ms -Average).Average, 2)).ToString("0.00", $invariantCulture)
      UpdateMs = ([math]::Round(($group | Measure-Object update_ms -Average).Average, 2)).ToString("0.00", $invariantCulture)
      DeleteMs = ([math]::Round(($group | Measure-Object delete_ms -Average).Average, 2)).ToString("0.00", $invariantCulture)
      FilterMs = ([math]::Round(($group | Measure-Object filter_query_ms -Average).Average, 2)).ToString("0.00", $invariantCulture)
      FilterSortMs = ([math]::Round(($group | Measure-Object filter_sort_query_ms -Average).Average, 2)).ToString("0.00", $invariantCulture)
      GetItems = [int64](($group | Measure-Object get_items -Average).Average)
      UpdateItems = [int64](($group | Measure-Object update_items -Average).Average)
      DeleteItems = [int64](($group | Measure-Object delete_items -Average).Average)
      FilterItems = [int64](($group | Measure-Object filter_items -Average).Average)
      FilterSortItems = [int64](($group | Measure-Object filter_sort_items -Average).Average)
      SizeBytes = [int64]$group[0].database_size_bytes
    }
  }

Write-Host ""
Write-Host "Backend compare summary:"

$cindel = $summary | Where-Object { $_.Profile -eq "cindel-typed" } | Select-Object -First 1
$isar = $summary | Where-Object { $_.Profile -eq "isar-typed" } | Select-Object -First 1
if ($cindel -and $isar) {
  function New-CompareRow {
    param(
      [string] $Metric,
      [string] $Column,
      [string] $Unit = "ms"
    )
    $cindelValue = [double]::Parse($cindel.$Column, $invariantCulture)
    $isarValue = [double]::Parse($isar.$Column, $invariantCulture)
    $delta = $cindelValue - $isarValue
    $ratio = if ($isarValue -eq 0) { 0 } else { $cindelValue / $isarValue }
    [pscustomobject]@{
      Metric = $Metric
      Cindel = $cindelValue.ToString("0.00", $invariantCulture)
      Isar = $isarValue.ToString("0.00", $invariantCulture)
      Delta = $delta.ToString("+0.00;-0.00;0.00", $invariantCulture)
      Ratio = ($ratio.ToString("0.00", $invariantCulture) + "x")
      Unit = $Unit
    }
  }

  $comparison = @(
    New-CompareRow "prepare" "PrepareMs"
    New-CompareRow "open" "OpenMs"
    New-CompareRow "insert" "InsertMs"
    New-CompareRow "get" "GetMs"
    New-CompareRow "update" "UpdateMs"
    New-CompareRow "delete" "DeleteMs"
    New-CompareRow "filter query" "FilterMs"
    New-CompareRow "filter + sort" "FilterSortMs"
  )
  $sizeDelta = [int64]$cindel.SizeBytes - [int64]$isar.SizeBytes
  $sizeRatio = if ([int64]$isar.SizeBytes -eq 0) { 0 } else { [double]$cindel.SizeBytes / [double]$isar.SizeBytes }
  $comparison += [pscustomobject]@{
    Metric = "database size"
    Cindel = [string]$cindel.SizeBytes
    Isar = [string]$isar.SizeBytes
    Delta = $sizeDelta.ToString("+0;-0;0", $invariantCulture)
    Ratio = ($sizeRatio.ToString("0.00", $invariantCulture) + "x")
    Unit = "bytes"
  }

  Write-Host ""
  Write-Host "Cindel vs Isar:"
  Write-Host ""
  Write-Host ("{0,-18} {1,14} {2,14} {3,14} {4,8} {5,-6}" -f "Metric", "Cindel", "Isar", "Delta", "Ratio", "Unit") -ForegroundColor Green
  Write-Host ("{0,-18} {1,14} {2,14} {3,14} {4,8} {5,-6}" -f ("-" * 6), ("-" * 6), ("-" * 4), ("-" * 5), ("-" * 5), ("-" * 4)) -ForegroundColor Green
  foreach ($row in $comparison) {
    "{0,-18} {1,14} {2,14} {3,14} {4,8} {5,-6}" -f $row.Metric, $row.Cindel, $row.Isar, $row.Delta, $row.Ratio, $row.Unit | Write-Host
  }

  Write-Host ""
  Write-Host "Counts:"
  $counts = @(
    [pscustomobject]@{ Metric = "get items"; Cindel = $cindel.GetItems; Isar = $isar.GetItems }
    [pscustomobject]@{ Metric = "update items"; Cindel = $cindel.UpdateItems; Isar = $isar.UpdateItems }
    [pscustomobject]@{ Metric = "delete items"; Cindel = $cindel.DeleteItems; Isar = $isar.DeleteItems }
    [pscustomobject]@{ Metric = "filter items"; Cindel = $cindel.FilterItems; Isar = $isar.FilterItems }
    [pscustomobject]@{ Metric = "filter + sort items"; Cindel = $cindel.FilterSortItems; Isar = $isar.FilterSortItems }
  )
  Write-Host ("{0,-22} {1,12} {2,12}" -f "Metric", "Cindel", "Isar") -ForegroundColor Green
  Write-Host ("{0,-22} {1,12} {2,12}" -f ("-" * 6), ("-" * 6), ("-" * 4)) -ForegroundColor Green
  foreach ($row in $counts) {
    "{0,-22} {1,12} {2,12}" -f $row.Metric, $row.Cindel, $row.Isar | Write-Host
  }
} else {
  Write-Host ""
  Write-Host "Operation timings:"
  $summary |
    Select-Object Profile,Repeats,Documents,GetCount,PrepareMs,OpenMs,InsertMs,GetMs,UpdateMs,DeleteMs |
    Format-Table -AutoSize
  Write-Host ""
  Write-Host "Filter timings, counts, and size:"
  $summary |
    Select-Object Profile,FilterMs,FilterSortMs,GetItems,UpdateItems,DeleteItems,FilterItems,FilterSortItems,SizeBytes |
    Format-Table -AutoSize
}

$raw = $summary | Where-Object { $_.Profile -eq "cindel-raw-bytes" } | Select-Object -First 1
if ($raw) {
  Write-Host ""
  Write-Host "Cindel raw bytes:"
  $raw |
    Select-Object Profile,Repeats,Documents,GetCount,PrepareMs,OpenMs,InsertMs,GetMs,GetItems,SizeBytes |
    Format-Table -AutoSize
}
