#requires -Version 5.1
# Real official signer, synthetic password, public vendor XML; NO ESET install/import.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows runner required for native signer probe.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[void](New-Item -ItemType Directory -Path $OutputDirectory)
$zip = Join-Path $OutputDirectory 'vendor-sample.zip'
$exe = Join-Path $OutputDirectory 'xmlsigntool.exe'
$xml = Join-Path $OutputDirectory 'vendor-sample.xml'
$ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri 'https://download.eset.com/com/eset/config/enable_screen_reader_access/mac/latest/screen_readers_config.zip' -OutFile $zip
Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri 'https://download.eset.com/com/eset/tools/installers/xmlsigntool/latest/xmlsigntool.exe' -OutFile $exe
$signature=Get-AuthenticodeSignature -LiteralPath $exe
if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch 'O=ESET, spol\. s r\.o\.') { throw ('Official signer Authenticode not trusted: ' + $signature.Status) }
$archive=[IO.Compression.ZipFile]::OpenRead($zip)
try {
    $entry=$archive.GetEntry('screen_readers_config.xml')
    if ($null -eq $entry -or $entry.Length -gt 1MB) { throw 'Unexpected vendor sample archive.' }
    $input=$entry.Open(); $output=[IO.File]::Create($xml)
    try { $input.CopyTo($output) } finally { $input.Dispose(); $output.Dispose() }
} finally { $archive.Dispose() }
$before=[IO.File]::ReadAllText($xml)
$start=New-Object Diagnostics.ProcessStartInfo
$start.FileName=$exe
$start.Arguments='/version 2 "'+$xml+'"'
$start.UseShellExecute=$false
$start.RedirectStandardInput=$true
$start.RedirectStandardOutput=$true
$start.RedirectStandardError=$true
$process=New-Object Diagnostics.Process
$process.StartInfo=$start
try {
    if (-not $process.Start()) { throw 'Signer did not start.' }
    $outTask=$process.StandardOutput.ReadToEndAsync(); $errTask=$process.StandardError.ReadToEndAsync()
    # This generated value belongs ONLY to the CI fixture, not a real ESET password.
    $fixtureInput='synthetic-ci-'+[guid]::NewGuid().ToString('N')
    $process.StandardInput.WriteLine($fixtureInput)
    $process.StandardInput.WriteLine($fixtureInput)
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(30000)) { $process.Kill(); [void]$process.WaitForExit(5000); throw 'Real signer cannot complete redirected-input fixture within 30 seconds.' }
    if ($process.ExitCode -ne 0) { throw ('Signer fixture exited '+$process.ExitCode+'; no live password used.') }
} finally { $process.Dispose() }
$after=[IO.File]::ReadAllText($xml)
if ($after -ceq $before) { throw 'Signer reported success but fixture bytes did not change.' }
$beforeDoc=New-Object Xml.XmlDocument; $beforeDoc.XmlResolver=$null; $beforeDoc.PreserveWhitespace=$true; $beforeDoc.LoadXml($before)
$afterDoc=New-Object Xml.XmlDocument; $afterDoc.XmlResolver=$null; $afterDoc.PreserveWhitespace=$true; $afterDoc.LoadXml($after)
$comments=@($afterDoc.SelectNodes('//comment()'))
Write-Output ('SIGNER_NATIVE_FIXTURE_PASS: added comments='+$comments.Count+'; element count='+$afterDoc.SelectNodes('//*').Count)
foreach ($comment in $comments) {
    if ($comment.Value -match '^\s*Signature:') { Write-Output 'Signature comment marker: Signature:' }
    elseif ($comment.Value -match ':: SIG ::') { Write-Output 'Signature comment marker: :: SIG ::' }
    else { Write-Output 'Unknown signer comment marker (value withheld).' }
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'signed-fixture.xml'),$after,(New-Object Text.UTF8Encoding($false)))
Write-Output 'Native ESET import/enforcement NOT TESTED; public accessibility sample was never imported.'
