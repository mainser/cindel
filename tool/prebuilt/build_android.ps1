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
  @{
    RustTarget = 'aarch64-linux-android'
    Abi = 'arm64-v8a'
    ClangTarget = 'aarch64-linux-android23'
    IncludeTarget = 'aarch64-linux-android'
  },
  @{
    RustTarget = 'armv7-linux-androideabi'
    Abi = 'armeabi-v7a'
    ClangTarget = 'armv7a-linux-androideabi23'
    IncludeTarget = 'arm-linux-androideabi'
  },
  @{
    RustTarget = 'x86_64-linux-android'
    Abi = 'x86_64'
    ClangTarget = 'x86_64-linux-android23'
    IncludeTarget = 'x86_64-linux-android'
  }
)

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

if (-not $env:LIBCLANG_PATH) {
  $defaultLibclangPath = 'C:\Program Files\LLVM\bin'
  if (Test-Path (Join-Path $defaultLibclangPath 'libclang.dll')) {
    $env:LIBCLANG_PATH = $defaultLibclangPath
  }
}

$env:ANDROID_NDK_HOME = $ndkHome
$toolchainRoot = Join-Path $ndkHome 'toolchains\llvm\prebuilt\windows-x86_64'
$clangPath = Join-Path $toolchainRoot 'bin\clang.exe'
$clangxxPath = Join-Path $toolchainRoot 'bin\clang++.exe'
$arPath = Join-Path $toolchainRoot 'bin\llvm-ar.exe'
$ranlibPath = Join-Path $toolchainRoot 'bin\llvm-ranlib.exe'
$sysroot = Join-Path $toolchainRoot 'sysroot'
$includeRoot = Join-Path $sysroot 'usr\include'
if (-not (Test-Path $clangPath)) {
  throw "Android NDK clang was not found at $clangPath."
}

Set-Location $nativeDir

foreach ($entry in $targets) {
  $rustEnvTarget = $entry.RustTarget.Replace('-', '_')
  $cargoEnvTarget = $entry.RustTarget.ToUpperInvariant().Replace('-', '_')
  $sysrootArg = $sysroot.Replace('\', '/')
  $includeRootArg = $includeRoot.Replace('\', '/')
  $targetInclude = (Join-Path $includeRoot $entry.IncludeTarget).Replace('\', '/')
  $clangArgs = "--target=$($entry.ClangTarget) --sysroot=$sysrootArg -I$includeRootArg -I$targetInclude"

  $env:CLANG_PATH = $clangPath
  $env:BINDGEN_EXTRA_CLANG_ARGS = $clangArgs
  Set-Item -Path "env:CC_$rustEnvTarget" -Value $clangPath
  Set-Item -Path "env:CFLAGS_$rustEnvTarget" -Value $clangArgs
  Set-Item -Path "env:CXX_$rustEnvTarget" -Value $clangxxPath
  Set-Item -Path "env:CXXFLAGS_$rustEnvTarget" -Value $clangArgs
  Set-Item -Path "env:AR_$rustEnvTarget" -Value $arPath
  Set-Item -Path "env:RANLIB_$rustEnvTarget" -Value $ranlibPath
  Set-Item -Path "env:CARGO_TARGET_${cargoEnvTarget}_LINKER" -Value $clangPath

  $rustFlags = "-Clink-arg=--target=$($entry.ClangTarget) -Clink-arg=--sysroot=$sysrootArg"
  if ($entry.Abi -eq 'arm64-v8a' -or $entry.Abi -eq 'x86_64') {
    $rustFlags = "$rustFlags -Clink-arg=-Wl,-z,max-page-size=16384"
  }
  $env:RUSTFLAGS = $rustFlags

  cargo build `
    --release `
    --manifest-path (Join-Path $nativeDir 'Cargo.toml') `
    --target $($entry.RustTarget)
  if ($LASTEXITCODE -ne 0) {
    throw "Android cargo build failed for $($entry.Abi)"
  }

  $abiDir = Join-Path $jniDir $entry.Abi
  New-Item -ItemType Directory -Force -Path $abiDir | Out-Null
  Copy-Item `
    -LiteralPath (Join-Path $targetDir "$($entry.RustTarget)\release\libcindel_native.so") `
    -Destination (Join-Path $abiDir 'libcindel_native.so') `
    -Force
}

Write-Host "Wrote Android libraries under packages\cindel_flutter_libs\android\src\main\jniLibs"
