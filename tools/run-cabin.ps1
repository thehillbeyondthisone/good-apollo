<#
.SYNOPSIS
  Launches the Aquarius cabin study or its headless inventory/binding checks.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -Test
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-cabin.ps1 -XR
#>
param(
    [string]$GodotPath,
    [switch]$Test,
    [switch]$SystemsTest,
    [switch]$AgcTest,
    [switch]$NativeAgcTest,
    [switch]$CheckpointTest,
    [switch]$PowerDownTest,
    [switch]$DefaultTest,
    [switch]$XRTest,
    [switch]$Stepped,
    [switch]$ExternalAgc,
    [switch]$SkipBuild,
    [switch]$XR,
    [ValidateSet('Default','SteamVR','Meta')][string]$XRRuntime = 'Default',
    [ValidateSet('Mobile','Compatibility')][string]$XRRenderer = 'Mobile',
    [string]$XRReportPath,
    [ValidateRange(0,3600)][double]$XRDuration = 0,
    [switch]$Editor,
    [string]$CapturePath,
    [switch]$LampTest,
    [ValidateRange(1,4)][int]$View = 1,
    [ValidateRange(0.1,30.0)][double]$CaptureDelay = 1.0,
    [string]$Preset,
    [string]$ReportPath
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$projectRoot = Join-Path $repoRoot 'godot'

if (-not $GodotPath) {
    $installed = Get-Command godot.exe, godot4.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($installed) { $GodotPath = $installed.Source }
}
if (-not $GodotPath) {
    $workspaceRuntime = Join-Path $repoRoot '.cache\godot-runtime'
    if (Test-Path -LiteralPath (Join-Path $workspaceRuntime 'GodotSharp\Api\Debug\GodotSharp.dll') -PathType Leaf) {
        $localGodot = Get-ChildItem -LiteralPath $workspaceRuntime -Filter 'Godot*console.exe' -File |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($localGodot) { $GodotPath = $localGodot.FullName }
    }
}
if (-not $GodotPath) {
    $portableRoot = 'D:\apollo-ref\tools'
    if (Test-Path -LiteralPath $portableRoot) {
        $portable = Get-ChildItem -LiteralPath $portableRoot -Filter '*console.exe' -File -Recurse |
            Where-Object { $_.Name -like 'Godot*' } | Sort-Object FullName -Descending | Select-Object -First 1
        if ($portable) { $GodotPath = $portable.FullName }
    }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath)) {
    throw 'Godot was not found. Supply -GodotPath with a Godot 4 console executable.'
}
if ($Test -and ($XR -or $Editor -or $CapturePath)) { throw '-Test cannot be combined with -XR, -Editor or -CapturePath.' }
if ($Editor -and ($XR -or $CapturePath)) { throw '-Editor cannot be combined with -XR or -CapturePath.' }
if ((@($Test,$SystemsTest,$AgcTest,$NativeAgcTest,$CheckpointTest,$PowerDownTest,$DefaultTest,$XRTest) | Where-Object { $_ }).Count -gt 1) { throw 'Choose one test mode.' }
if (($Test -or $SystemsTest -or $AgcTest -or $NativeAgcTest -or $CheckpointTest -or $PowerDownTest -or $DefaultTest -or $XRTest) -and ($XR -or $Editor -or $CapturePath -or $LampTest)) { throw 'Test modes cannot be combined with visual modes.' }
if ($Stepped -and $ExternalAgc) { throw '-Stepped and -ExternalAgc select different CPU backends.' }
if (($Test -or $SystemsTest -or $AgcTest -or $NativeAgcTest -or $CheckpointTest -or $PowerDownTest -or $DefaultTest -or $XRTest) -and ($Stepped -or $ExternalAgc)) { throw 'Test modes select their own CPU backend; omit -Stepped and -ExternalAgc.' }
if (($XRReportPath -or $XRDuration -gt 0) -and -not $XR) { throw '-XRReportPath and -XRDuration require -XR.' }
if ($XRRuntime -ne 'Default' -and -not $XR) { throw '-XRRuntime requires -XR.' }
if ($PSBoundParameters.ContainsKey('XRRenderer') -and -not $XR) { throw '-XRRenderer requires -XR.' }
$xrRuntimeManifest = $null
if ($XRRuntime -eq 'SteamVR') {
    $xrRuntimeManifest = 'C:\Program Files (x86)\Steam\steamapps\common\SteamVR\steamxr_win64.json'
} elseif ($XRRuntime -eq 'Meta') {
    $metaRuntimeCandidates = @(
        'C:\Program Files\Meta Horizon\Support\oculus-runtime\oculus_openxr_64.json',
        'C:\Program Files\Oculus\Support\oculus-runtime\oculus_openxr_64.json'
    )
    if ($env:OculusBase) {
        $metaRuntimeCandidates = @((Join-Path $env:OculusBase 'Support\oculus-runtime\oculus_openxr_64.json')) + $metaRuntimeCandidates
    }
    $xrRuntimeManifest = $metaRuntimeCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $xrRuntimeManifest) { throw 'The Meta OpenXR runtime manifest was not found. Install/open Meta Horizon Link, or select -XRRuntime Default or SteamVR.' }
}
if ($xrRuntimeManifest -and -not (Test-Path -LiteralPath $xrRuntimeManifest -PathType Leaf)) {
    throw "OpenXR runtime manifest not found: $xrRuntimeManifest"
}
if (-not $SkipBuild) {
    if (-not ($ExternalAgc -or $SystemsTest -or $AgcTest -or $Test -or $XRTest)) {
        $agcBuildScript = Join-Path $PSScriptRoot 'agc\build-stepped.ps1'
        $agcBuildRoot = Join-Path $repoRoot '.cache\agc-power-cycle'
        $agcDll = Get-Item -LiteralPath (Join-Path $agcBuildRoot 'AquariusAgc.dll') -ErrorAction SilentlyContinue
        $agcInputs = Get-Item -LiteralPath @($agcBuildScript, (Join-Path $PSScriptRoot 'agc\aquarius-agc.c'), (Join-Path $PSScriptRoot 'agc\aquarius-agc.h'))
        if (-not $agcDll -or -not (Test-Path -LiteralPath (Join-Path $agcBuildRoot 'LM131R1\MAIN.agc.bin')) -or
            ($agcInputs | Where-Object { $_.LastWriteTimeUtc -gt $agcDll.LastWriteTimeUtc })) {
            try { & $agcBuildScript -BuildRoot $agcBuildRoot }
            catch { Write-Warning "Could not build the stepped AGC adapter: $($_.Exception.Message)" }
        }
    }
    & (Join-Path $PSScriptRoot 'build-godot.ps1') -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$engineArgs = @('--path', $projectRoot)
$userArgs = @()
if ($Test) {
    $engineArgs += @('--headless', '--script', 'res://tests/test_interaction.gd')
    $userArgs += '--self-test'
    if (-not $ReportPath) { $ReportPath = Join-Path $repoRoot 'reference\interaction-coverage.json' }
    $userArgs += "--report-path=$([IO.Path]::GetFullPath($ReportPath))"
}
if ($XR) {
    $engineArgs += @('--xr-mode', 'on')
    if ($XRRenderer -eq 'Mobile') {
        $engineArgs += @('--rendering-method', 'mobile', '--rendering-driver', 'vulkan')
    } else {
        $engineArgs += @('--rendering-method', 'gl_compatibility', '--rendering-driver', 'opengl3')
    }
    $userArgs += @('--xr', "--xr-duration=$XRDuration", "--xr-renderer=$XRRenderer")
    if ($XRReportPath) {
        if (-not [IO.Path]::IsPathRooted($XRReportPath)) { $XRReportPath = Join-Path $repoRoot $XRReportPath }
        $userArgs += "--xr-report=$([IO.Path]::GetFullPath($XRReportPath))"
    }
}
if ($XRTest) {
    $engineArgs += @('--headless', '--script', 'res://tests/test_xr.gd')
    $userArgs += '--self-test'
}
if ($SystemsTest) {
    $engineArgs += @('--headless', '--script', 'res://tests/test_systems.gd')
    $userArgs += @('--self-test', '--systems-test', '--external-agc', '--agc-port=19797')
}
if ($AgcTest) { $engineArgs += @('--headless', '--script', 'res://tests/test_agc.gd') }
if ($NativeAgcTest) { $engineArgs += @('--headless', '--script', 'res://tests/test_stepped_agc.gd') }
if ($CheckpointTest) {
    $engineArgs += @('--headless', '--script', 'res://tests/test_checkpoint.gd')
    $userArgs += @('--self-test','--systems-test','--stepped-agc','--manual-clock')
}
if ($PowerDownTest) {
    $engineArgs += @('--headless', '--script', 'res://tests/test_powerdown.gd')
    $userArgs += @('--self-test', '--systems-test', '--manual-clock')
}
if ($DefaultTest) {
    $engineArgs += @('--headless', '--script', 'res://tests/test_default.gd')
    $userArgs += @('--self-test','--systems-test')
}
if ($Stepped) { $userArgs += '--stepped-agc' }
if ($ExternalAgc) { $userArgs += '--external-agc' }
if ($Editor) { $engineArgs += '--editor' }
if ($LampTest) { $userArgs += '--capture-lamp-test' }
if ($View -ne 1) { $userArgs += "--capture-view=$View" }
if ($Preset) { $userArgs += "--preset=$Preset" }
if ($CapturePath) {
    if (-not [IO.Path]::IsPathRooted($CapturePath)) { $CapturePath = Join-Path $repoRoot $CapturePath }
    $resolvedCapture = [IO.Path]::GetFullPath($CapturePath)
    $captureDirectory = [IO.Path]::GetDirectoryName($resolvedCapture)
    New-Item -ItemType Directory -Path $captureDirectory -Force | Out-Null
    $userArgs += @("--capture-path=$resolvedCapture", '--quit-after-capture', '--self-test', "--capture-delay=$CaptureDelay")
}
if ($userArgs.Count) { $engineArgs += @('--') + $userArgs }
# Scope the portable SDK to this child process; no system settings are changed.
$previousDotnetRoot = $env:DOTNET_ROOT
$previousProcessPath = $env:PATH
$previousXrRuntime = $env:XR_RUNTIME_JSON
$exitCode = 1
try {
    if ($xrRuntimeManifest) {
        $env:XR_RUNTIME_JSON = $xrRuntimeManifest
        Write-Host "OpenXR runtime for this launch: $XRRuntime ($xrRuntimeManifest)"
    }
    $portableDotnetRoot = 'D:\apollo-ref\tools\dotnet-10'
    if (Test-Path -LiteralPath (Join-Path $portableDotnetRoot 'dotnet.exe')) {
        $env:DOTNET_ROOT = $portableDotnetRoot
        $env:PATH = "$portableDotnetRoot;$previousProcessPath"
    }
    & $GodotPath @engineArgs
    $exitCode = $LASTEXITCODE
} finally {
    $env:DOTNET_ROOT = $previousDotnetRoot
    $env:PATH = $previousProcessPath
    $env:XR_RUNTIME_JSON = $previousXrRuntime
}
exit $exitCode
