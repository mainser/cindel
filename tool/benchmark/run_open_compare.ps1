param(
  [int] $Repeats = 25,
  [string] $NativeLibrary = "",
  [string] $IsarLibrary = ""
)

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$benchDir = Join-Path $repo "tool\benchmark\backend_get_compare"
$outDir = Join-Path $repo "tool\benchmark\out"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outFile = Join-Path $outDir "open_compare_$stamp.csv"
$dart = "D:\WORK\INSTALL\flutter\bin\cache\dart-sdk\bin\dart.exe"
$sourceNativeLibrary = Join-Path $repo "packages\cindel\native\target\release\cindel_native.dll"
$isarCacheLibrary = Join-Path $env:LOCALAPPDATA "Pub\Cache\hosted\pub.dev\isar_flutter_libs-4.0.0-dev.14\windows\isar.dll"
$nativeLibrary = if ($NativeLibrary) {
  $NativeLibrary
} elseif (Test-Path $sourceNativeLibrary) {
  $sourceNativeLibrary
} elseif ($env:CINDEL_NATIVE_LIBRARY) {
  $env:CINDEL_NATIVE_LIBRARY
} else {
  throw "Open benchmark requires a source-current native DLL. Build it with `cargo build --release --manifest-path packages/cindel/native/Cargo.toml` or pass -NativeLibrary."
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
Copy-Item -Path $isarLibrary -Destination (Join-Path $benchDir "isar.dll") -Force

Write-Host "Native library: $nativeLibrary"
Write-Host "Isar library: $isarLibrary"
Write-Host "Running open compare..."

Push-Location $benchDir
try {
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $output = & $dart run bin\open_compare.dart --repeats $Repeats 2>&1
  $dartExitCode = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previousErrorActionPreference
  Pop-Location
}
if ($dartExitCode -ne 0) {
  throw "Open benchmark failed: $($output -join [Environment]::NewLine)"
}

$joinedOutput = $output -join [Environment]::NewLine
$csvStart = $joinedOutput.IndexOf("profile,")
if ($csvStart -lt 0) {
  throw "Unexpected open benchmark output: $joinedOutput"
}
$lines = $joinedOutput.Substring($csvStart) -split '\r?\n' |
  Where-Object {
    $_ -and (
      $_.StartsWith("profile,") -or
      $_.StartsWith("cindel-empty,") -or
      $_.StartsWith("cindel-schema,") -or
      $_.StartsWith("isar-schema,")
    )
  }

if ($lines.Count -lt 4) {
  throw "Unexpected open benchmark output: $($output -join [Environment]::NewLine)"
}
$lines | Set-Content -Path $outFile

Write-Host "Open evidence written to: $outFile"

$rows = Import-Csv -Path $outFile
$invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
$summary = $rows |
  Group-Object profile |
  ForEach-Object {
    $group = $_.Group
    [pscustomobject]@{
      Profile = $_.Name
      Repeats = $group.Count
      OpenMs = ([math]::Round(($group | Measure-Object open_ms -Average).Average, 2)).ToString("0.00", $invariantCulture)
      SizeBytes = [int64](($group | Measure-Object size_bytes -Average).Average)
    }
  }

Write-Host ""
Write-Host "Open compare summary:"
$summary | Format-Table -AutoSize
