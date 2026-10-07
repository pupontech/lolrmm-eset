param(
    [Parameter(Mandatory = $true)]
    [string]$ExecutablePath
)

if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
    throw "Executable not found: $ExecutablePath"
}

$processInfo = [System.Diagnostics.ProcessStartInfo]::new()
$processInfo.FileName = (Resolve-Path -LiteralPath $ExecutablePath).Path
$processInfo.UseShellExecute = $false
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $processInfo
if (-not $process.Start()) {
    throw "Failed to start executable: $ExecutablePath"
}

$standardOutput = $process.StandardOutput.ReadToEnd()
$standardError = $process.StandardError.ReadToEnd()
$process.WaitForExit()

if ($process.ExitCode -ne 0) {
    throw "Expected exit code 0, got $($process.ExitCode). stderr: $standardError"
}

$actualOutput = $standardOutput.TrimEnd([char[]]@("`r", "`n"))
if ($actualOutput -cne 'Test Application') {
    throw "Expected stdout 'Test Application', got '$actualOutput'."
}

if ($standardError.Length -ne 0) {
    throw "Expected empty stderr, got '$standardError'."
}

Write-Output 'Smoke test passed.'
