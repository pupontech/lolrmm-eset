#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ZipPath,[Parameter(Mandatory=$true)][string]$SourceCommit)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.IO.Compression.FileSystem
if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$') { throw 'Full lower-case source SHA required.' }
$expected = @('Eset-QuickRules.ps1','START-HERE.bat','START-HERE.ps1','rules.csv','README.md','VERSION','LolrmmEsetTest.exe','PROVENANCE.txt')
$zip = [IO.Compression.ZipFile]::OpenRead((Get-Item -LiteralPath $ZipPath).FullName)
$members = @{}
try {
    foreach ($entry in $zip.Entries) {
        if ($entry.FullName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $members.ContainsKey($entry.FullName)) { throw 'Unsafe, nested or duplicate ZIP member.' }
        if ($entry.Length -gt 268435456) { throw 'ZIP member exceeds 256 MiB limit.' }
        $stream = $entry.Open(); $memory = New-Object IO.MemoryStream
        try { $stream.CopyTo($memory); $members[$entry.FullName] = $memory.ToArray() } finally { $stream.Dispose(); $memory.Dispose() }
    }
} finally { $zip.Dispose() }
if ((@($members.Keys | Sort-Object) -join '|') -cne (@(($expected+@('SHA256SUMS.txt')) | Sort-Object) -join '|')) { throw 'ZIP differs from exact package allowlist.' }
$manifest = [Text.Encoding]::ASCII.GetString($members['SHA256SUMS.txt'])
$hashes = @{}
foreach ($line in ($manifest -split "`r?`n")) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -cnotmatch '^([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._-]*)$') { throw 'Malformed package hash line.' }
    $digest = $Matches[1]; $name = $Matches[2]
    if ($hashes.ContainsKey($name)) { throw 'Duplicate hash entry.' }
    $hashes[$name] = $digest
}
if ((@($hashes.Keys | Sort-Object) -join '|') -cne (@($expected | Sort-Object) -join '|')) { throw 'Hash manifest does not cover exact payload.' }
$sha = [Security.Cryptography.SHA256]::Create()
try {
    foreach ($name in $expected) {
        $actual = [BitConverter]::ToString($sha.ComputeHash($members[$name])).Replace('-','').ToLowerInvariant()
        if ($actual -cne $hashes[$name]) { throw ('Hash mismatch for ' + $name) }
    }
} finally { $sha.Dispose() }
$provenance = [Text.Encoding]::ASCII.GetString($members['PROVENANCE.txt'])
$sourceLines = @($provenance -split "`r?`n" | Where-Object { $_.StartsWith('Source SHA: ') })
if ($sourceLines.Count -ne 1 -or $sourceLines[0] -cne ('Source SHA: ' + $SourceCommit)) { throw 'Wrong or ambiguous ZIP source provenance.' }
foreach ($name in @('Eset-QuickRules.ps1','START-HERE.ps1','START-HERE.bat')) {
    if (@($members[$name] | Where-Object { $_ -gt 127 }).Count) { throw ('Non-ASCII source: ' + $name) }
}
$batText = [Text.Encoding]::ASCII.GetString($members['START-HERE.bat'])
if ($batText.Replace("`r`n",'').Contains("`n")) { throw 'BAT requires CRLF.' }
Write-Output ('PACKAGE_BYTES_PASS: exact member set, all hashes, full source SHA ' + $SourceCommit)
function Invoke-PackageBat([string]$Launcher) {
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$env:ComSpec
    # Raw CreateProcess argument string avoids PS 5.1 native quoting transformation.
    $start.Arguments='/d /s /c ""'+$Launcher+'" -ValidateOnly"'
    $start.UseShellExecute=$false
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process
    $process.StartInfo=$start
    try {
        if(-not $process.Start()) { throw 'Packaged BAT did not start.' }
        $out=$process.StandardOutput.ReadToEndAsync(); $err=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Packaged BAT timed out.' }
        if(-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($out,$err),5000)) { throw 'Packaged BAT output timed out.' }
        return [pscustomobject]@{ExitCode=$process.ExitCode;Text=($out.Result+$err.Result)}
    } finally { $process.Dispose() }
}
$folder = Join-Path ([IO.Path]::GetTempPath()) ('ESET quick package '+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $folder)
try {
    foreach ($name in $members.Keys) { [IO.File]::WriteAllBytes((Join-Path $folder $name),$members[$name]) }
    foreach ($name in @('Eset-QuickRules.ps1','START-HERE.ps1')) {
        $tokens=$null; $errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $folder $name),[ref]$tokens,[ref]$errors)
        if ($errors.Count) { throw ('Extracted parse failed: ' + $name) }
    }
    if ($env:OS -eq 'Windows_NT') {
        $launcher = Join-Path $folder 'START-HERE.bat'
        $result=Invoke-PackageBat $launcher
        $out=$result.Text; $code=$result.ExitCode
        if ($code -ne 0 -or ($out -join "`n") -notmatch 'PACKAGE_VALIDATION_PASS') { throw ('Actual extracted BAT validation failed; exit ' + $code + ': ' + ($out -join ' ')) }
        $exe = Join-Path $folder 'LolrmmEsetTest.exe'
        $text = & $exe
        $code = $LASTEXITCODE
        if ($code -ne 0 -or $text -cne 'Test Application') { throw 'Packaged harmless EXE failed.' }
        # Real error propagation: remove only this owned extraction's entrypoint.
        Remove-Item -LiteralPath (Join-Path $folder 'Eset-QuickRules.ps1')
        $result=Invoke-PackageBat $launcher
        $out=$result.Text; $code=$result.ExitCode
        if ($code -ne 1 -or ($out -join "`n") -notmatch 'Missing package member') { throw 'Extracted BAT concealed the missing-script failure.' }
        Write-Output 'WINDOWS_PACKAGE_SMOKE_PASS: actual BAT, space path, EXE output, missing-member exit propagation; no ESET access.'
    } else { Write-Output 'WINDOWS_PACKAGE_SMOKE_NOT_RUN: host is not Windows.' }
} finally { Remove-Item -LiteralPath $folder -Recurse -Force }
