<#
.SYNOPSIS
  Downloads (or just verifies) the reference library listed in reference/manifest.json.

.EXAMPLE
  # Check every URL and total the sizes; downloads nothing.
  powershell -ExecutionPolicy Bypass -File tools\fetch-reference.ps1 -DryRun

.EXAMPLE
  # Download only priority-0 documents and ephemeris (no repository clones).
  powershell -ExecutionPolicy Bypass -File tools\fetch-reference.ps1 -DataRoot D:\apollo-ref -MaxPriority 0 -FilesOnly
#>
param(
    [string]$DataRoot = 'D:\apollo-ref',
    [ValidateRange(0, 2)][int]$MaxPriority = 2,
    [switch]$DryRun,
    [switch]$FilesOnly,
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..\reference\manifest.json')
)

$ErrorActionPreference = 'Stop'
$ua = 'Mozilla/5.0 (reference-fetch)'
$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$DataRoot = [IO.Path]::GetFullPath($DataRoot)

function Get-ItemUrl($item) {
    if ($item.url) { return $item.url }
    return $manifest.bases.($item.base) + $item.path
}

function Get-RemoteInfo($url) {
    $result = & curl.exe --head --location --fail --silent --show-error -A $ua --retry 3 --connect-timeout 30 --max-time 120 -o NUL -w '%{http_code}|%header{content-length}|%{content_type}|%{url_effective}' $url
    if ($LASTEXITCODE -ne 0) { throw "HEAD request failed (curl $LASTEXITCODE): $url" }
    $parts = ("$result".Trim()) -split '\|', 4
    if ($parts[0] -ne '200') { throw "Unexpected HTTP status $($parts[0]): $url" }
    $length = 0L
    if ($parts[1]) { $length = [long]$parts[1] }
    [pscustomobject]@{ bytes = $length; contentType = $parts[2]; effectiveUrl = $parts[3] }
}

function Test-ReferenceFile($path, $expectedBytes, $extension) {
    $actualBytes = (Get-Item -LiteralPath $path).Length
    if ($actualBytes -eq 0) { throw "Empty file: $path" }
    if ($expectedBytes -gt 0 -and $actualBytes -ne $expectedBytes) {
        throw "Size mismatch: $path (expected $expectedBytes; got $actualBytes)"
    }
    $stream = [IO.File]::OpenRead($path)
    try {
        $buffer = New-Object byte[] 1024
        $count = $stream.Read($buffer, 0, $buffer.Length)
        $header = [Text.Encoding]::ASCII.GetString($buffer, 0, $count)
        if ($extension -eq '.pdf' -and $header -notmatch '%PDF-') { throw "Not a PDF: $path" }
        if ($extension -eq '.bsp' -and -not $header.StartsWith('DAF/SPK ')) { throw "Not an SPK kernel: $path" }
        if ($extension -eq '.pdf') {
            $stream.Position = [Math]::Max(0, $stream.Length - 1024)
            $count = $stream.Read($buffer, 0, $buffer.Length)
            if ([Text.Encoding]::ASCII.GetString($buffer, 0, $count) -notmatch '%%EOF') {
                throw "PDF has no final EOF marker: $path"
            }
        }
    } finally { $stream.Dispose() }
}

function Get-ReferenceHash($path) {
    $stream = [IO.File]::OpenRead($path)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        ([BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
}

$items = @($manifest.items | Where-Object { $_.p -le $MaxPriority -and (-not $FilesOnly -or $_.kind -eq 'file') })
$totalBytes = 0L
$bad = @()
$hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
$receipts = @()
$receiptPath = Join-Path $DataRoot 'download-receipt.json'
if (-not $DryRun -and (Test-Path -LiteralPath $receiptPath)) {
    $receipts = @((Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json).files)
}
$checked = 0
$downloaded = 0
$verified = 0

foreach ($item in $items) {
    $url = Get-ItemUrl $item
    try {
        if ($item.kind -eq 'git') {
            if ($DryRun) {
                $null = Get-RemoteInfo ($url -replace '\.git$', '')
                "CHECKED P$($item.p) git $url"
                $checked++
                continue
            }
            if (-not $hasGit) { throw "git not available: $url" }
            $name = [IO.Path]::GetFileNameWithoutExtension($url)
            $dest = Join-Path (Join-Path $DataRoot $item.cat) $name
            if (Test-Path -LiteralPath $dest) { git -C $dest pull --ff-only } else { git clone --depth 1 $url $dest }
            if ($LASTEXITCODE -ne 0) { throw "git failed ($LASTEXITCODE): $url" }
            $downloaded++
            continue
        }

        $remote = Get-RemoteInfo $url
        if ($item.kind -eq 'file') { $totalBytes += $remote.bytes }
        if ($DryRun -or $item.kind -eq 'page') {
            'CHECKED P{0} {1,-5} {2,8:N1} MiB  {3}' -f $item.p, $item.kind, ($remote.bytes / 1MB), $url
            $checked++
            continue
        }

        $dir = [IO.Path]::GetFullPath((Join-Path $DataRoot $item.cat))
        if (-not $dir.StartsWith($DataRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Category escapes data root: $($item.cat)"
        }
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $file = Join-Path $dir ([IO.Path]::GetFileName([uri]::UnescapeDataString(([uri]$url).AbsolutePath)))
        $extension = [IO.Path]::GetExtension($file).ToLowerInvariant()
        $previous = @($receipts | Where-Object { $_.url -eq $url -and $_.path -eq $file })
        if (Test-Path -LiteralPath $file) {
            Test-ReferenceFile $file $remote.bytes $extension
            $hash = Get-ReferenceHash $file
            if ($previous.Count -gt 0 -and $hash -ne $previous[-1].sha256) { throw "SHA256 mismatch against previous receipt: $file" }
            "VERIFIED $file"
            $verified++
        } else {
            $partial = "$file.part"
            "DOWNLOADING $file ($([Math]::Round($remote.bytes / 1MB, 1)) MiB)"
            $partialComplete = (Test-Path -LiteralPath $partial) -and $remote.bytes -gt 0 -and (Get-Item -LiteralPath $partial).Length -eq $remote.bytes
            if (-not $partialComplete) {
                $curlArgs = @('--location', '--fail', '--silent', '--show-error', '-A', $ua, '--retry', '3', '--connect-timeout', '30', '--max-time', '1800', '--speed-time', '90', '--speed-limit', '1024', '--header', 'Accept-Encoding: identity', '--output', $partial, '--write-out', '%{http_code}')
                $status = & curl.exe @curlArgs --continue-at - $url
                $curlExit = $LASTEXITCODE
                if ($curlExit -eq 33) {
                    Write-Warning 'Server does not support resume; restarting this partial download.'
                    $status = & curl.exe @curlArgs $url
                    $curlExit = $LASTEXITCODE
                }
                if ($curlExit -ne 0) { throw "Download failed (curl $curlExit, HTTP $status): $url" }
                if ("$status" -notmatch '^(200|206)$') { throw "Unexpected download HTTP status ${status}: $url" }
            }
            Test-ReferenceFile $partial $remote.bytes $extension
            $hash = Get-ReferenceHash $partial
            Move-Item -LiteralPath $partial -Destination $file
            $downloaded++
            "SAVED $file"
        }
        $receipts = @($receipts | Where-Object { $_.url -ne $url -or $_.path -ne $file })
        $receipts += [pscustomobject]@{
            title = $item.title; url = $url; effectiveUrl = $remote.effectiveUrl; path = $file
            bytes = (Get-Item -LiteralPath $file).Length; sha256 = $hash
            contentType = $remote.contentType; verifiedUtc = [DateTime]::UtcNow.ToString('o')
        }
        [pscustomobject]@{ schemaVersion = 1; hashNote = 'Local integrity hashes, not publisher-provided checksums.'; files = $receipts } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    } catch {
        $bad += [pscustomobject]@{ url = $url; error = $_.Exception.Message }
        Write-Warning $_.Exception.Message
    }
}

''
'Selected: {0}; downloaded: {1}; existing verified: {2}; URLs checked: {3}; failed: {4}' -f $items.Count, $downloaded, $verified, $checked, $bad.Count
'Direct-file size from server headers: {0:N2} GiB' -f ($totalBytes / 1GB)
if ($bad.Count) { $bad | Format-Table -Wrap; exit 1 }
'All selected entries OK.'
