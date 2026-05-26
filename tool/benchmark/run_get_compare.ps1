param(
  [int] $Documents = 50000,
  [int] $GetCount = 25000,
  [int] $PayloadBytes = 1024,
  [int] $Repeats = 6
)

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$benchManifest = Join-Path $repo "tool\benchmark\get_compare\Cargo.toml"
$outDir = Join-Path $repo "tool\benchmark\out"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outFile = Join-Path $outDir "get_compare_$stamp.csv"

New-Item -ItemType Directory -Force $outDir | Out-Null

$env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
$env:CARGO_TARGET_DIR = Join-Path $PSScriptRoot "get_compare\target"

$wroteHeader = $false
$invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

for ($i = 1; $i -le $Repeats; $i++) {
  Write-Host "Running get compare repeat $i/$Repeats..."
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = cargo run --release --manifest-path $benchManifest -- --documents $Documents --get-count $GetCount --payload-bytes $PayloadBytes 2>&1
    $cargoExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($cargoExitCode -ne 0) {
    throw "Get benchmark failed: $($output -join [Environment]::NewLine)"
  }
  $lines = $output |
    ForEach-Object { $_.ToString() } |
    Where-Object {
      $_ -and (
        $_.StartsWith("profile,") -or
        $_.StartsWith("cindel-transaction-get-owned,") -or
        $_.StartsWith("cindel-cursor-set-owned,") -or
        $_.StartsWith("cindel-cursor-set-borrowed-checked,") -or
        $_.StartsWith("cindel-cursor-set-borrowed-trusted,") -or
        $_.StartsWith("isar-cursor-set-borrowed,")
      )
    }
  if ($lines.Count -lt 6) {
    throw "Unexpected get benchmark output: $($output -join [Environment]::NewLine)"
  }
  if (-not $wroteHeader) {
    "repeat,$($lines[0])" | Add-Content -Path $outFile
    $wroteHeader = $true
  }
  foreach ($line in $lines | Select-Object -Skip 1) {
    "$i,$line" | Add-Content -Path $outFile
  }
}

Write-Host "Get evidence written to: $outFile"

$rows = Import-Csv -Path $outFile
$summary = $rows |
  Group-Object profile |
  ForEach-Object {
    $group = $_.Group
    [pscustomobject]@{
      Profile = $_.Name
      Documents = [int]$group[0].documents
      GetCount = [int]$group[0].get_count
      PayloadBytes = [int]$group[0].payload_bytes
      Repeats = $group.Count
      LoadMs = ([math]::Round(($group | Measure-Object load_ms -Average).Average, 2)).ToString("0.00", $invariantCulture)
      GetMs = ([math]::Round(($group | Measure-Object get_ms -Average).Average, 2)).ToString("0.00", $invariantCulture)
      Items = [int]$group[0].items
      SizeBytes = [int64]$group[0].size_bytes
    }
  }

Write-Host ""
Write-Host "Get compare summary:"
$summary | Format-Table -AutoSize
