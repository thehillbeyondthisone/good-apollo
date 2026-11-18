<# Build unchanged pinned CPU with explicit static-state linkage for checkpoints. #>
param([string]$DataRoot='D:\apollo-ref',[string]$BuildRoot)
$ErrorActionPreference='Stop'
$toolRoot=Join-Path $DataRoot 'toolchain\llvm-mingw-20261104-ucrt-x86_64\bin'
$compiler=Join-Path $toolRoot 'x86_64-w64-mingw32-clang.exe'
$cpuRoot=Join-Path $DataRoot 'source\virtualagc\yaAGC'
$dataBuildRoot=Join-Path $DataRoot 'build\agc'
$alternateBuild=[bool]$BuildRoot
if (-not $BuildRoot) { $BuildRoot=$dataBuildRoot }
$adapterBuild=Join-Path $buildRoot 'stepped'
New-Item -ItemType Directory -Path $adapterBuild -Force | Out-Null
function Hash-Bytes([byte[]]$bytes){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Aggregate-Hash($paths){
    $stream=[IO.MemoryStream]::new()
    foreach($path in $paths){
        $bytes=[IO.File]::ReadAllBytes($path);$stream.Write($bytes,0,$bytes.Length);$stream.WriteByte(0)
    }
    try{return Hash-Bytes $stream.ToArray()}finally{$stream.Dispose()}
}
function Compile($arguments){
    & $compiler @arguments
    if($LASTEXITCODE -ne 0){throw "Clang failed with $LASTEXITCODE"}
}
$sourceFiles=@('agc_engine.c','agc_engine.h','agc_engine_init.c','yaAGC.h')|ForEach-Object{Join-Path $cpuRoot $_}
$sourceHash=Aggregate-Hash $sourceFiles
if($sourceHash -ne 'fe91c8ca130eee089dea4c8db498bea949b781acff81c13292b536b74092883c'){
    throw 'Pinned upstream CPU/header/init source fingerprint changed; audit before building.'
}
$compilerVersion=(& $compiler --version | Out-String)
$compilerVersion | Set-Content (Join-Path $adapterBuild 'compiler-version.txt') -Encoding ASCII
$buildHash=Aggregate-Hash @((Join-Path $PSScriptRoot 'aquarius-agc.c'),(Join-Path $PSScriptRoot 'aquarius-agc.h'),$PSCommandPath,(Join-Path $adapterBuild 'compiler-version.txt'))
@("#define AAGC_SOURCE_HASH `"$sourceHash`"","#define AAGC_BUILD_HASH `"$buildHash`"") |
    Set-Content (Join-Path $adapterBuild 'aquarius-build.h') -Encoding ASCII
$flags=@('-std=c11','-O0','-fno-lto','-DWIN32','-Wno-typedef-redefinition','-Wno-deprecated-declarations')
$original=Join-Path $adapterBuild 'core-original.s'
$exported=Join-Path $adapterBuild 'core-state-linkage.s'
Compile ($flags+@('-S',(Join-Path $cpuRoot 'agc_engine.c'),'-o',$original))
$assembly=[IO.File]::ReadAllText($original)
$expected=@{DefaultClients=10360;DefaultSockets=40;TrapPIPA=4;GyroCount=4;OldChannel14=4;GyroTimer=4;ImuChannel14=4;ImuCduCount=8;CduFifos=1608;CduChecker=4;'BurstOutput.CountCDUX'=4;'BurstOutput.CountCDUY'=4;'BurstOutput.CountCDUZ'=4}
$found=@{}
foreach($match in [regex]::Matches($assembly,'(?m)^\s*\.lcomm\s+([^,]+),(\d+),')){$found[$match.Groups[1].Value]=[int]$match.Groups[2].Value}
if($found.Count -ne $expected.Count){throw 'Unexpected upstream local-data symbol set; audit checkpoint coverage.'}
foreach($name in $expected.Keys){if(-not $found.ContainsKey($name) -or $found[$name] -ne $expected[$name]){throw "Upstream local-data layout changed: $name"}}
$exposed=@($expected.Keys|Where-Object{$_ -notin @('DefaultClients','DefaultSockets')}|Sort-Object)
$directives=($exposed|ForEach-Object{".globl $_"}) -join "`n"
[IO.File]::WriteAllText($exported,$assembly+"`n"+$directives+"`n",[Text.Encoding]::ASCII)
$originalObject=Join-Path $adapterBuild 'core-original.o'
$exportedObject=Join-Path $adapterBuild 'core-state-linkage.o'
Compile @('-c',$original,'-o',$originalObject)
Compile @('-c',$exported,'-o',$exportedObject)
function Text-Section($path){
    $bytes=[IO.File]::ReadAllBytes($path);$sections=[BitConverter]::ToUInt16($bytes,2)
    for($i=0;$i -lt $sections;$i++){
        $offset=20+40*$i;$name=[Text.Encoding]::ASCII.GetString($bytes,$offset,8).TrimEnd([char]0)
        if($name -eq '.text'){
            $size=[BitConverter]::ToUInt32($bytes,$offset+16);$start=[BitConverter]::ToUInt32($bytes,$offset+20)
            $text=New-Object byte[] $size;[Array]::Copy($bytes,$start,$text,0,$size);return ,$text
        }
    }
    throw 'COFF text section absent'
}
$originalText=Hash-Bytes (Text-Section $originalObject)
$exportedText=Hash-Bytes (Text-Section $exportedObject)
if($originalText -ne $exportedText){throw 'CPU instruction bytes changed while exposing static data.'}
$dll=Join-Path $buildRoot 'AquariusAgc.dll'
Compile ($flags+@('-shared','-static-libgcc','-Wl,--no-insert-timestamp',('-I'+$cpuRoot),('-I'+$adapterBuild),
    (Join-Path $PSScriptRoot 'aquarius-agc.c'),$exportedObject,(Join-Path $cpuRoot 'agc_engine_init.c'),
    '-o',$dll,'-lbcrypt','-lws2_32'))
$metadata=[ordered]@{schemaVersion=1;abiVersion=1;upstreamCommit='938e88d11caea1d72af72e53e6005282023f94c2';
    sourceHash=$sourceHash;adapterBuildHash=$buildHash;dllSha256=(Hash-Bytes ([IO.File]::ReadAllBytes($dll)));
    cpuOriginalTextSha256=$originalText;cpuExposedTextSha256=$exportedText;cpuInstructionBytesUnchanged=$true;
    compiler=$compiler;flags=$flags;exposedStatics=$exposed;localDataSizes=$expected;singleActiveContext=$true;
    nanosecondsPerCycle='11718.75';quarterNanosecondsPerCycle=46875;flightPadloadApplied=$false}
$metadata|ConvertTo-Json -Depth 8|Set-Content (Join-Path $adapterBuild 'build.json') -Encoding UTF8
if ($alternateBuild) {
    $ropeDirectory=Join-Path $BuildRoot 'LM131R1'
    New-Item -ItemType Directory -Path $ropeDirectory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $dataBuildRoot 'LM131R1\MAIN.agc.bin') -Destination $ropeDirectory
} else {
    $repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $metadata|ConvertTo-Json -Depth 8|Set-Content (Join-Path $repoRoot 'reference\agc-stepped-build.json') -Encoding UTF8
}
Write-Output "Built AquariusAgc.dll ABI1; CPU .text unchanged ($originalText)."
