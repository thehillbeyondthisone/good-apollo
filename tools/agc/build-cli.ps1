<#
.SYNOPSIS
Builds the complete, unchanged upstream yaAGC CLI and yaYUL with portable LLVM-MinGW.
#>
param(
    [string]$DataRoot = 'D:\apollo-ref',
    [string]$Compiler = ''
)
$ErrorActionPreference = 'Stop'
$sourceRoot = Join-Path $DataRoot 'source\virtualagc'
$buildRoot = Join-Path $DataRoot 'build\agc'
if (-not $Compiler) { $Compiler = Join-Path $DataRoot 'toolchain\llvm-mingw-20261104-ucrt-x86_64\bin\x86_64-w64-mingw32-clang.exe' }
if (-not (Test-Path -LiteralPath $Compiler)) { throw 'Portable compiler missing; run tools/agc/setup-toolchain.ps1 first.' }
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'LM131R1\MAIN.agc'))) { throw 'Virtual AGC source checkout missing.' }
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
function Quote-GnuPath($value) { return '"' + $value.Replace('\','/') + '"' }
function Hash-File($path) {
    $stream = [IO.File]::OpenRead($path); $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}
function Compile-Target($name, $flags, $sources) {
    $rsp = Join-Path $buildRoot "$name-clang.rsp"
    $log = Join-Path $buildRoot "build-$name-clang.log"
    @('-std=c99','-O2','-DWIN32','-DNVER=\"2026-03-26\"','-Wno-deprecated-declarations','-Wno-deprecated-non-prototype','-Wno-typedef-redefinition') +
        $flags + @($sources | ForEach-Object { Quote-GnuPath $_ }) |
        Set-Content -LiteralPath $rsp -Encoding ASCII
    & $Compiler ('@' + $rsp.Replace('\','/')) *> $log
    if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath $log -Tail 50; throw "$name build failed: $LASTEXITCODE" }
    Write-Output "BUILT $name from unchanged upstream source"
}
$assemblerPath = Join-Path $buildRoot 'yaYUL.exe'
Compile-Target 'assembler' @('-o',(Quote-GnuPath $assemblerPath)) @(
    Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'yaYUL') -Filter '*.c' -File | ForEach-Object FullName
)
$flightBuild = Join-Path $buildRoot 'LM131R1'
New-Item -ItemType Directory -Path $flightBuild -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'LM131R1') -Filter '*.agc' -File | Copy-Item -Destination $flightBuild -Force
Push-Location -LiteralPath $flightBuild
try {
    & $assemblerPath --parity MAIN.agc *> 'assembly.log'
    if ($LASTEXITCODE -ne 0) { throw "LM131R1 assembly failed: $LASTEXITCODE" }
} finally { Pop-Location }
$ropePath = Join-Path $flightBuild 'MAIN.agc.bin'
$referencePath = Join-Path $sourceRoot 'LM131R1\Luminary131PlusLM131R1ModuleDump.bin'
$ropeHash = Hash-File $ropePath
if ($ropeHash -ne (Hash-File $referencePath)) { throw 'Assembled rope differs from reconstructed reference image.' }
if ($ropeHash -ne 'ae4f9e51ac9491c3da6462233936daeffc16277cd302c43a70b8459ebcd6cca5') { throw 'Rope differs from the pinned verified build.' }
Write-Output "MATCHED LM131R1 rope: $ropeHash"
$cpuRoot = Join-Path $sourceRoot 'yaAGC'
$names = @('main.c','agc_cli.c','agc_simulator.c','agc_debugger.c','agc_gdbmi.c','agc_disassembler.c','agc_help.c','nbfgets.c','agc_symtab.c','NormalizeSourceName.c','agc_engine_init.c','agc_engine.c','agc_utilities.c','rfopen.c','Backtrace.c','SocketAPI.c','DecodeDigitalDownlink.c','random.c','regex.c')
Compile-Target 'cli' @('-DSTDC_HEADERS','-DGDBMI','-DNOREADLINE','-pthread','-static','-Wno-pointer-sign','-Wno-int-conversion','-Wno-incompatible-pointer-types','-o',(Quote-GnuPath (Join-Path $buildRoot 'yaAGC.exe')),'-lws2_32','-lwsock32','-liphlpapi','-lwinmm') @(
    @($names | ForEach-Object { Join-Path $cpuRoot $_ }) + (Join-Path $sourceRoot 'Tools\checkdec.c')
)
Compile-Target 'fixture' @(('-I'+(Quote-GnuPath $cpuRoot)),'-o',(Quote-GnuPath (Join-Path $buildRoot 'agc-lamp-test-clang.exe')),'-lws2_32') @(
    (Join-Path $PSScriptRoot 'lamp-test.c'), (Join-Path $cpuRoot 'agc_engine.c'), (Join-Path $cpuRoot 'agc_engine_init.c')
)
$result = & (Join-Path $buildRoot 'agc-lamp-test-clang.exe') $ropePath (Join-Path $buildRoot 'lamp-test.csv')
$testExit = $LASTEXITCODE
$result | Set-Content -LiteralPath (Join-Path $buildRoot 'lamp-result.json') -Encoding UTF8
Write-Output $result
if ($testExit -ne 0) { throw "Deterministic V35 test failed: $testExit" }
'PASSED deterministic LM131R1 V35 lamp test.'
