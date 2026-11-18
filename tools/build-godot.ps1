<#
.SYNOPSIS
  Builds the Godot C# bridge against the official packages bundled with the portable editor.
#>
param(
    [string]$GodotPath,
    [string]$DotnetRoot = 'D:\apollo-ref\tools\dotnet-10'
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$projectRoot = Join-Path $repoRoot 'godot'
if (-not $GodotPath) {
    $GodotPath = (Get-ChildItem -LiteralPath 'D:\apollo-ref\tools' -File -Recurse -Filter 'Godot*console.exe' |
        Sort-Object FullName -Descending | Select-Object -First 1).FullName
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath)) { throw 'Supply -GodotPath to a Godot .NET console executable.' }
$dotnetPath = Join-Path $DotnetRoot 'dotnet.exe'
if (-not (Test-Path -LiteralPath $dotnetPath)) { throw 'Supply -DotnetRoot to a .NET SDK installation.' }
$bundledFeed = Join-Path ([IO.Path]::GetDirectoryName($GodotPath)) 'GodotSharp\Tools\nupkgs'
if (-not (Test-Path -LiteralPath $bundledFeed)) { throw "Bundled Godot packages missing: $bundledFeed" }
$localFeed = Join-Path $projectRoot '.godot\local-feed'
New-Item -ItemType Directory -Force -Path $localFeed | Out-Null
foreach ($packageName in @('Godot.NET.Sdk.4.7.2.nupkg','Godot.SourceGenerators.4.7.2.nupkg','GodotSharp.4.7.2.nupkg','GodotSharpEditor.4.7.2.nupkg')) {
    $sourcePackage = Join-Path $bundledFeed $packageName
    if (-not (Test-Path -LiteralPath $sourcePackage)) { throw "Required bundled package missing: $sourcePackage" }
    Copy-Item -LiteralPath $sourcePackage -Destination (Join-Path $localFeed $packageName) -Force
}
$previousDotnetRoot = $env:DOTNET_ROOT
$previousProcessPath = $env:PATH
$previousCliHome = $env:DOTNET_CLI_HOME
$previousTelemetry = $env:DOTNET_CLI_TELEMETRY_OPTOUT
$previousLogo = $env:DOTNET_NOLOGO
$previousCertificate = $env:DOTNET_GENERATE_ASPNET_CERTIFICATE
$previousToolsPath = $env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH
$exitCode = 1
try {
    $env:DOTNET_ROOT = $DotnetRoot
    $env:PATH = "$DotnetRoot;$previousProcessPath"
    $env:DOTNET_CLI_HOME = Join-Path $projectRoot '.godot\dotnet-cli'
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    $env:DOTNET_NOLOGO = '1'
    $env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
    $env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH = 'false'
    & $dotnetPath restore (Join-Path $projectRoot 'Aquarius.csproj') --configfile (Join-Path $projectRoot 'NuGet.Config') --verbosity minimal
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $dotnetPath build (Join-Path $projectRoot 'Aquarius.csproj') --no-restore --configuration Debug --verbosity minimal
    $exitCode = $LASTEXITCODE
} finally {
    $env:DOTNET_ROOT = $previousDotnetRoot
    $env:PATH = $previousProcessPath
    $env:DOTNET_CLI_HOME = $previousCliHome
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = $previousTelemetry
    $env:DOTNET_NOLOGO = $previousLogo
    $env:DOTNET_GENERATE_ASPNET_CERTIFICATE = $previousCertificate
    $env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH = $previousToolsPath
}
exit $exitCode
