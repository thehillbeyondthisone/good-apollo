<# Read-only Windows OCR for reviewed padload page images; emits text and word boxes. #>
param([Parameter(Mandatory=$true)][string[]]$Images)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
$null = [Windows.Storage.FileAccessMode,Windows.Storage,ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrResult,Windows.Foundation,ContentType=WindowsRuntime]
$null = [Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime]
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
function Wait-Operation($operation, $resultType) {
    $task = $asTask.MakeGenericMethod($resultType).Invoke($null,@($operation))
    try { $task.Wait() } catch { throw $task.Exception.ToString() }
    return $task.Result
}
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('en-US'))
if (-not $engine) { throw 'English Windows OCR language is unavailable.' }
$resolvedImages = @($Images | ForEach-Object {
    if (Test-Path -LiteralPath $_ -PathType Container) { Get-ChildItem -LiteralPath $_ -Filter '*.png' -File | ForEach-Object FullName }
    else { $_ }
})
foreach ($imagePath in $resolvedImages) {
    $absolutePath = (Resolve-Path -LiteralPath $imagePath).Path
    $file = Wait-Operation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($absolutePath)) ([Windows.Storage.StorageFile])
    $stream = Wait-Operation ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    try {
        $decoder = Wait-Operation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap = Wait-Operation ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        try {
            $result = Wait-Operation ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
            $lines = @($result.Lines | ForEach-Object {
                [ordered]@{text=$_.Text; words=@($_.Words | ForEach-Object {
                    [ordered]@{text=$_.Text; x=$_.BoundingRect.X; y=$_.BoundingRect.Y; width=$_.BoundingRect.Width; height=$_.BoundingRect.Height}
                })}
            })
            [ordered]@{image=$absolutePath; text=$result.Text; lines=$lines} | ConvertTo-Json -Depth 8 |
                Set-Content -LiteralPath ($absolutePath+'.ocr.json') -Encoding UTF8
            $result.Text | Set-Content -LiteralPath ($absolutePath+'.ocr.txt') -Encoding UTF8
            "OCR $absolutePath ($($lines.Count) lines)"
        } finally { $bitmap.Dispose() }
    } finally { $stream.Dispose() }
}
