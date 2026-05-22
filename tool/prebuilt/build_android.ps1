$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$nativeDir = Join-Path $repoRoot 'packages\cindel\native'
$jniDir = Join-Path $repoRoot 'packages\cindel_flutter_libs\android\src\main\jniLibs'
$targetDir = if ($env:CARGO_TARGET_DIR) {
  $env:CARGO_TARGET_DIR
} else {
  Join-Path $nativeDir 'target'
}

$targets = @(
  @{ RustTarget = 'aarch64-linux-android'; Abi = 'arm64-v8a' },
  @{ RustTarget = 'armv7-linux-androideabi'; Abi = 'armeabi-v7a' },
  @{ RustTarget = 'x86_64-linux-android'; Abi = 'x86_64' }
)

if (-not (Get-Command cargo-ndk -ErrorAction SilentlyContinue)) {
  throw 'cargo-ndk is required. Install it with: cargo install cargo-ndk'
}

$ndkHome = if ($env:ANDROID_NDK_HOME) {
  $env:ANDROID_NDK_HOME
} elseif ($env:ANDROID_NDK_ROOT) {
  $env:ANDROID_NDK_ROOT
} else {
  $sdkRoots = @(
    $env:ANDROID_HOME,
    $env:ANDROID_SDK_ROOT,
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
    'D:\WORK\INSTALL\sdk'
  ) | Where-Object { $_ -and (Test-Path $_) }

  $sdkRoots |
    ForEach-Object { Join-Path $_ 'ndk' } |
    Where-Object { Test-Path $_ } |
    ForEach-Object { Get-ChildItem -Path $_ -Directory } |
    Sort-Object Name -Descending |
    Select-Object -First 1 -ExpandProperty FullName
}

if (-not $ndkHome -or -not (Test-Path $ndkHome)) {
  throw 'Android NDK was not found. Install it with Android Studio or set ANDROID_NDK_HOME.'
}

$env:ANDROID_NDK_HOME = $ndkHome
Set-Location $nativeDir

foreach ($entry in $targets) {
  cargo ndk `
    --target $($entry.Abi) `
    --platform 23 `
    build --release
  if ($LASTEXITCODE -ne 0) {
    throw "cargo ndk failed for $($entry.Abi)"
  }

  $abiDir = Join-Path $jniDir $entry.Abi
  New-Item -ItemType Directory -Force -Path $abiDir | Out-Null
  Copy-Item `
    -LiteralPath (Join-Path $targetDir "$($entry.RustTarget)\release\libcindel_native.so") `
    -Destination (Join-Path $abiDir 'libcindel_native.so') `
    -Force
}

Write-Host "Wrote Android libraries under packages\cindel_flutter_libs\android\src\main\jniLibs"
