$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$nativeDir = Join-Path $repoRoot 'packages\cindel\native'
$outDir = Join-Path $repoRoot 'packages\cindel_flutter_libs\windows'
$targetDir = if ($env:CARGO_TARGET_DIR) {
  $env:CARGO_TARGET_DIR
} else {
  Join-Path $nativeDir 'target'
}

if (-not $env:LIBCLANG_PATH) {
  $defaultLibclangPath = 'C:\Program Files\LLVM\bin'
  if (Test-Path (Join-Path $defaultLibclangPath 'libclang.dll')) {
    $env:LIBCLANG_PATH = $defaultLibclangPath
  }
}

Set-Location $repoRoot
cargo build `
  --release `
  --manifest-path (Join-Path $nativeDir 'Cargo.toml') `
  --target x86_64-pc-windows-msvc

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Copy-Item `
  -LiteralPath (Join-Path $targetDir 'x86_64-pc-windows-msvc\release\cindel_native.dll') `
  -Destination (Join-Path $outDir 'cindel_native.dll') `
  -Force

Write-Host "Wrote packages\cindel_flutter_libs\windows\cindel_native.dll"
