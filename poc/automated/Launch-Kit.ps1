#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$KitDir = $PSScriptRoot,
    [switch]$DryRun,
    [switch]$IAmOnATestMachine
)
$ErrorActionPreference = 'Stop'
try {
    $versions = @(Get-ChildItem -LiteralPath $PSScriptRoot -File | ForEach-Object {
        if ($_.Name -match '^Invoke-EsetHipsPoc\.v(\d{4}-\d{2}-\d{2})\.(\d+)\.ps1$') {
            [pscustomobject]@{ File = $_.FullName; Date = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', [cultureinfo]::InvariantCulture); Revision = [int]$Matches[2] }
        }
    } | Sort-Object Date, Revision -Descending)
    if ($versions.Count -eq 0) { throw 'No valid versioned Invoke-EsetHipsPoc script found.' }
    if (-not $IAmOnATestMachine) {
        Write-Host 'This kit is for an isolated test PC only, NOT production.'
        if ((Read-Host 'Type TEST to authorize this test kit') -cne 'TEST') { throw 'Test-machine acknowledgment declined.' }
        $IAmOnATestMachine = $true
    }
    $global:LASTEXITCODE = 1
    & $versions[0].File -KitDir $KitDir -DryRun:$DryRun -IAmOnATestMachine:$IAmOnATestMachine
    exit $LASTEXITCODE
} catch {
    Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
