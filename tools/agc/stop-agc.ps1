<# Stops only the exact yaAGC process identified by an owned session receipt. #>
param([Parameter(Mandatory=$true)][string]$SessionPath)
$ErrorActionPreference = 'Stop'
$record = Get-Content -LiteralPath $SessionPath -Raw | ConvertFrom-Json
$ownedProcess = Get-Process -Id $record.processId -ErrorAction SilentlyContinue
if (-not $ownedProcess) { 'The recorded process has already stopped.'; exit 0 }
if (-not [string]::Equals($ownedProcess.Path,$record.executable,[StringComparison]::OrdinalIgnoreCase) -or
    $ownedProcess.StartTime.ToUniversalTime().Ticks -ne ([DateTime]$record.startTimeUtc).ToUniversalTime().Ticks) {
    throw 'The PID no longer identifies the exact recorded executable/start time. No process was stopped.'
}
Stop-Process -Id $ownedProcess.Id
"Stopped owned yaAGC process $($ownedProcess.Id)."
