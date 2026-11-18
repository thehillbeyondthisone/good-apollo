<#
.SYNOPSIS
Builds yaYUL and an unmodified yaAGC CPU with a deterministic DSKY test fixture.
Source checkouts must already exist under DataRoot\source. No global installs.
.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File tools\agc\build-agc.ps1
#>
param(
    [string]$DataRoot = 'D:\apollo-ref',
    [string]$VcVars = 'C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
)
$ErrorActionPreference = 'Stop'
$sourceRoot = Join-Path $DataRoot 'source\virtualagc'
$buildRoot = Join-Path $DataRoot 'build\agc'
if (-not (Test-Path -LiteralPath $VcVars)) { throw "VS C compiler setup not found: $VcVars" }
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'LM131R1\MAIN.agc'))) { throw 'Virtual AGC checkout missing.' }
foreach ($name in @('assembler','assembler-source','core','LM131R1')) {
    New-Item -ItemType Directory -Path (Join-Path $buildRoot $name) -Force | Out-Null
}

function Get-Sha256($path) {
    $stream = [IO.File]::OpenRead($path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Invoke-CBuild($name, $options, $sources) {
    $responsePath = Join-Path $buildRoot "$name.rsp"
    $commandPath = Join-Path $buildRoot "build-$name.cmd"
    $logPath = Join-Path $buildRoot "build-$name.log"
    @('/nologo','/O2','/std:c11','/DWIN32','/D_CRT_SECURE_NO_WARNINGS','/wd4005','/wd5105') +
        $options + @($sources | ForEach-Object { '"' + $_ + '"' }) |
        Set-Content -LiteralPath $responsePath -Encoding ASCII
    @('@echo off', ('call "{0}" >nul' -f $VcVars), ('cl @"{0}"' -f $responsePath), 'exit /b %errorlevel%') |
        Set-Content -LiteralPath $commandPath -Encoding ASCII
    & $commandPath *> $logPath
    if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath $logPath; throw "$name compiler failed: $LASTEXITCODE" }
    Write-Output "BUILT $name"
}

# Current upstream MSVC macros contain invalid parenthesized bare initializers.
# Apply syntax-only fixes in a disposable build copy, never in the source checkout.
$assemblerSources = Join-Path $buildRoot 'assembler-source'
Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'yaYUL') -File |
    Where-Object { $_.Extension -in '.c','.h' } | Copy-Item -Destination $assemblerSources -Force
$headerPath = Join-Path $assemblerSources 'yaYUL.h'
$header = Get-Content -LiteralPath $headerPath -Raw
foreach ($macro in @('VALID_ADDRESS','REG(n)','CONSTANT(n)','FIXEDADD(n)')) {
    $header = $header.Replace("#define $macro ( {", "#define $macro ((Address_t) {")
}
Set-Content -LiteralPath $headerPath -Value $header -Encoding ASCII
$assemblerMain = Join-Path $assemblerSources 'yaYUL.c'
$mainText = Get-Content -LiteralPath $assemblerMain -Raw
$mainText = [regex]::Replace($mainText, '(static Address_t \w+ = )REG\((0[0-7]+)\);', '$1{0,0,1,$2,1,0,1,0,0,0,0,0,$2,0};')
Set-Content -LiteralPath $assemblerMain -Value $mainText -Encoding ASCII
$assemblerExe = Join-Path $buildRoot 'yaYUL.exe'
Invoke-CBuild 'assembler' @(
    ('/Fe:"{0}"' -f $assemblerExe),
    ('/Fo:"{0}\\"' -f (Join-Path $buildRoot 'assembler'))
) @(Get-ChildItem -LiteralPath $assemblerSources -File -Filter '*.c' | ForEach-Object FullName)

$flightBuild = Join-Path $buildRoot 'LM131R1'
Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'LM131R1') -File -Filter '*.agc' |
    Copy-Item -Destination $flightBuild -Force
Push-Location -LiteralPath $flightBuild
try {
    & $assemblerExe --parity MAIN.agc *> 'assembly.log'
    if ($LASTEXITCODE -ne 0) { throw "LM131R1 assembly failed: $LASTEXITCODE" }
} finally { Pop-Location }
$ropePath = Join-Path $flightBuild 'MAIN.agc.bin'
$referenceRope = Join-Path $sourceRoot 'LM131R1\Luminary131PlusLM131R1ModuleDump.bin'
$ropeHash = Get-Sha256 $ropePath
if ($ropeHash -ne (Get-Sha256 $referenceRope)) { throw 'Assembled LM131R1 differs from reconstructed reference rope.' }
Write-Output "MATCHED exact LM131R1 rope: $ropeHash"

$cpuRoot = Join-Path $sourceRoot 'yaAGC'
$testExe = Join-Path $buildRoot 'agc-lamp-test.exe'
Invoke-CBuild 'core' @(
    ('/I"{0}"' -f $cpuRoot), ('/Fe:"{0}"' -f $testExe),
    ('/Fo:"{0}\\"' -f (Join-Path $buildRoot 'core'))
) @((Join-Path $PSScriptRoot 'lamp-test.c'), (Join-Path $cpuRoot 'agc_engine.c'), (Join-Path $cpuRoot 'agc_engine_init.c'))
$tracePath = Join-Path $buildRoot 'lamp-test.csv'
$resultPath = Join-Path $buildRoot 'lamp-result.json'
$resultText = & $testExe $ropePath $tracePath
$testExit = $LASTEXITCODE
$resultText | Set-Content -LiteralPath $resultPath -Encoding UTF8
Write-Output $resultText
if ($testExit -ne 0) {
    Write-Warning "DSKY V35 test pending: fixture reset loop; see $tracePath. No mission padload has been applied."
    exit $testExit
}
'PASSED DSKY V35 lamp test.'
