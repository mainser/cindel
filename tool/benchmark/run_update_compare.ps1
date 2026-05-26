param(
  [int] $Documents = 50000,
  [int] $UpdateCount = 25000,
  [int] $PayloadBytes = 1024,
  [int] $Repeats = 6
)

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$benchManifest = Join-Path $repo "tool\benchmark\update_compare\Cargo.toml"
$outDir = Join-Path $repo "tool\benchmark\out"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outFile = Join-Path $outDir "update_compare_$stamp.csv"

New-Item -ItemType Directory -Force $outDir | Out-Null

$env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
$env:CARGO_TARGET_DIR = Join-Path $PSScriptRoot "update_compare\target"

$wroteHeader = $false
$invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

for ($i = 1; $i -le $Repeats; $i++) {
  Write-Host "Running update compare repeat $i/$Repeats..."
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = cargo run --release --manifest-path $benchManifest -- --documents $Documents --update-count $UpdateCount --payload-bytes $PayloadBytes 2>&1
    $cargoExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($cargoExitCode -ne 0) {
    throw "Update benchmark failed: $($output -join [Environment]::NewLine)"
  }
  $lines = $output |
    ForEach-Object { $_.ToString() } |
    Where-Object {
      $_ -and (
        $_.StartsWith("profile,") -or
        $_.StartsWith("cindel-current-like-indexed-bool-update,") -or
        $_.StartsWith("cindel-direct-upsert-indexed-bool-update,") -or
        $_.StartsWith("cindel-direct-current-indexed-bool-update,")
      )
    }
  if ($lines.Count -lt 4) {
    throw "Unexpected update benchmark output: $($output -join [Environment]::NewLine)"
  }
  if (-not $wroteHeader) {
    "repeat,$($lines[0])" | Add-Content -Path $outFile
    $wroteHeader = $true
  }
  foreach ($line in $lines | Select-Object -Skip 1) {
    "$i,$line" | Add-Content -Path $outFile
  }
}

Write-Host "Update evidence written to: $outFile"

$rows = Import-Csv -Path $outFile
$summary = $rows |
  Group-Object profile |
  ForEach-Object {
    $group = $_.Group
    [pscustomobject]@{
      Profile = $_.Name
      Documents = [int]$group[0].documents
      UpdateCount = [int]$group[0].update_count
      PayloadBytes = [int]$group[0].payload_bytes
      Repeats = $group.Count
      PrepareMs = ([math]::Round(($group | Measure-Object prepare_ms -Average).Average, 2)).ToString("0.00", $invariantCulture)
      InsertMs = ([math]::Round(($group | Measure-Object insert_ms -Average).Average, 2)).ToString("0.00", $invariantCulture)
      UpdateMs = ([math]::Round(($group | Measure-Object update_ms -Average).Average, 2)).ToString("0.00", $invariantCulture)
      UpdatedItems = [int]$group[0].updated_items
      SizeBytes = [int64]$group[0].size_bytes
    }
  }

Write-Host ""
Write-Host "Update compare summary:"
$summary | Format-Table -AutoSize
