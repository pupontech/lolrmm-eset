# Production export/version binding, using harmless fake export only.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../poc/quick-rules/Eset-QuickRules.ps1') -FunctionsOnly
$path=Join-Path ([IO.Path]::GetTempPath()) ('quick-version-'+[guid]::NewGuid().ToString('N')+'.xml')
$provider=@{ExpectedVersion='19.2.10.0';Export={param($p) [IO.File]::WriteAllText($p,'<ESET><PRODUCT NAME="home" VERSION="19.2.9.0"><ITEM NAME="plugins"><ITEM NAME="01000001"><ITEM NAME="settings"><ITEM NAME="rules"/></ITEM></ITEM></ITEM></PRODUCT></ESET>');return [pscustomobject]@{ExitCode=0}}}
try {
    $rejected=$false
    try { $null=Get-QuickProviderConfiguration $provider $path 'Fixture export' } catch { $rejected=$true }
    if(-not $rejected) { throw 'Export from different version accepted.' }
    $provider.ExpectedVersion='19.2.9.0'
    $null=Get-QuickProviderConfiguration $provider $path 'Fixture export'
    $provider.ExpectedVersion='19.not-a-version'
    $rejected=$false
    try { $null=Get-QuickProviderConfiguration $provider $path 'Fixture export' } catch { $rejected=$true }
    if(-not $rejected) { throw 'Malformed installed version accepted.' }
    Write-Output 'PASS: production export must exactly match valid installed consumer version; malformed/mismatch refused.'
} finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
