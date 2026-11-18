<# Starts a real yaAGC process; prints its owned-session record as JSON. #>
param([string]$DataRoot = 'D:\apollo-ref', [ValidateRange(1024,65526)][int]$Port = 19697)
$ErrorActionPreference = 'Stop'
$buildRoot = [IO.Path]::GetFullPath((Join-Path $DataRoot 'build\agc'))
$executable = Join-Path $buildRoot 'yaAGC.exe'
$rope = Join-Path $buildRoot 'LM131R1\MAIN.agc.bin'
if (-not (Test-Path -LiteralPath $executable)) { throw 'yaAGC is not built. Run tools/agc/build-cli.ps1.' }
$stream = [IO.File]::OpenRead($rope); $sha = [Security.Cryptography.SHA256]::Create()
try { $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
finally { $sha.Dispose(); $stream.Dispose() }
if ($hash -ne 'ae4f9e51ac9491c3da6462233936daeffc16277cd302c43a70b8459ebcd6cca5') { throw 'The rope is not the verified LM131R1 image.' }
$occupied = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() |
    Where-Object { $_.Port -ge $Port -and $_.Port -lt ($Port + 10) }
if ($occupied) { throw "yaAGC port range $Port-$($Port+9) is in use. Stop its owner or select another base port." }
$runtime = Join-Path $buildRoot ('runtime\' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$arguments = @(('--exec="' + $rope + '"'), ('--port=' + $Port), '--nodebug', '--no-resume', '--quiet', '--dump-time=86400')
$process = Start-Process -FilePath $executable -ArgumentList $arguments -WorkingDirectory $runtime -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime 'stdout.log') -RedirectStandardError (Join-Path $runtime 'stderr.log')
$record = [ordered]@{
    schemaVersion=1; processId=$process.Id; startTimeUtc=$process.StartTime.ToUniversalTime().ToString('o')
    executable=$executable; rope=$rope; ropeSha256=$hash; host='127.0.0.1'; port=$Port
    workingDirectory=$runtime; arguments=$arguments; mode='live LM131R1 rope, no DSKY debug mode'
    padloadStatus='emulator defaults; flight erasable padload pending'
}
$sessionPath = Join-Path $runtime 'session.json'
$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sessionPath -Encoding UTF8
$record.sessionPath = $sessionPath
$record | ConvertTo-Json -Depth 5
