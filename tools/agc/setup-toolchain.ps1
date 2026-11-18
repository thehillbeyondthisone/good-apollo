<# Portable, pinned LLVM-MinGW setup; no global PATH or system installs. #>
param([string]$DataRoot = 'D:\apollo-ref')
$ErrorActionPreference = 'Stop'
$name = 'llvm-mingw-20261104-ucrt-x86_64'
$expectedHash = '552191b5754c49a5a20723276a6fc56541ea1922c4c50b7b669022333fc1b40f'
$toolRoot = Join-Path $DataRoot 'toolchain'
New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
$archive = Join-Path $toolRoot "$name.zip"
$url = "https://github.com/mstorsjo/llvm-mingw/releases/download/20261104/$name.zip"
if (-not (Test-Path -LiteralPath $archive)) {
    curl.exe --location --fail --silent --show-error --retry 3 --connect-timeout 30 --max-time 1200 --continue-at - --output "$archive.part" $url
    if ($LASTEXITCODE -ne 0) { throw "Compiler download failed: $LASTEXITCODE" }
    $candidate = "$archive.part"
} else { $candidate = $archive }
$stream = [IO.File]::OpenRead($candidate); $sha = [Security.Cryptography.SHA256]::Create()
try { $actualHash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
finally { $sha.Dispose(); $stream.Dispose() }
if ($actualHash -ne $expectedHash) { throw 'Compiler archive differs from the pinned official GitHub release digest.' }
if ($candidate -ne $archive) { Move-Item -LiteralPath $candidate -Destination $archive }
Expand-Archive -LiteralPath $archive -DestinationPath $toolRoot -Force
& (Join-Path $toolRoot "$name\bin\x86_64-w64-mingw32-clang.exe") --version
if ($LASTEXITCODE -ne 0) { throw 'Portable compiler did not start.' }
