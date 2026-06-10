param(
  [string]$ClangPath = 'C:\Program Files\LLVM\bin\clang.exe',
  [string]$WasmBindgen = 'wasm-bindgen'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$nativeDir = Join-Path $repoRoot 'packages\cindel\native'
$workerSource = Join-Path $repoRoot 'packages\cindel\web\cindel_worker.js'
$webDir = Join-Path $repoRoot 'packages\cindel_flutter_libs\web'
$outDir = Join-Path $webDir 'pkg'
$target = 'wasm32-unknown-unknown'
$targetDir = if ($env:CARGO_TARGET_DIR) {
  $env:CARGO_TARGET_DIR
} else {
  Join-Path $nativeDir 'target'
}

if (-not (Test-Path $ClangPath)) {
  throw "clang was not found at $ClangPath. Install LLVM or pass -ClangPath."
}
if (-not (Test-Path $workerSource)) {
  throw "Cindel Web worker source was not found at $workerSource."
}

$wasmBindgenCommand = Get-Command $WasmBindgen -ErrorAction SilentlyContinue
if (-not $wasmBindgenCommand) {
  throw "wasm-bindgen was not found. Install it with: cargo install wasm-bindgen-cli"
}

$previousCc = $env:CC

try {
  $env:CC = (Resolve-Path $ClangPath).Path

  Set-Location $repoRoot
  cargo build `
    --release `
    --manifest-path (Join-Path $nativeDir 'Cargo.toml') `
    --target $target `
    --no-default-features `
    --features web
  if ($LASTEXITCODE -ne 0) {
    throw "Web cargo build failed with exit code $LASTEXITCODE"
  }

  $wasmPath = Join-Path $targetDir "$target\release\cindel_native.wasm"
  if (-not (Test-Path $wasmPath)) {
    throw "Could not find Web Wasm output at $wasmPath"
  }

  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $resolvedWebDir = (Resolve-Path $webDir).Path
  $resolvedOutDir = (Resolve-Path $outDir).Path
  if (-not $resolvedOutDir.StartsWith($resolvedWebDir, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean unexpected output directory: $resolvedOutDir"
  }
  Get-ChildItem -LiteralPath $resolvedOutDir -Force | Remove-Item -Recurse -Force

  & $wasmBindgenCommand.Source `
    $wasmPath `
    --target web `
    --out-dir $outDir `
    --out-name cindel_native
  if ($LASTEXITCODE -ne 0) {
    throw "wasm-bindgen failed with exit code $LASTEXITCODE"
  }

  Copy-Item `
    -LiteralPath $workerSource `
    -Destination (Join-Path $webDir 'cindel_worker.js') `
    -Force
}
finally {
  $env:CC = $previousCc
}

Write-Host "Wrote Web Wasm assets under packages\cindel_flutter_libs\web\pkg"
Write-Host "Wrote Web worker under packages\cindel_flutter_libs\web\cindel_worker.js"
