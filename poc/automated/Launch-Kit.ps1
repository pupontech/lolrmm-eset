#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$KitDir,
    [switch]$DryRun,
    [switch]$IAmOnATestMachine,
    [switch]$ValidateOnly,
    [int]$RuleAppearTimeoutSeconds = 1800,
    [int]$RemovalTimeoutSeconds = 1800,
    [int]$PollSeconds = 20
)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'Kit.Helpers.ps1')
    if ([string]::IsNullOrWhiteSpace($KitDir)) { $KitDir = $PSScriptRoot }
    Write-Host ('Kit source: ' + (Format-PathForDiagnostic $KitDir))
    $versions = @(Get-ChildItem -LiteralPath $PSScriptRoot -File | ForEach-Object {
        if ($_.Name -match '^Invoke-EsetHipsPoc\.v(\d{4}-\d{2}-\d{2})\.(\d+)\.ps1$') {
            [pscustomobject]@{ File = $_.FullName; Date = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', [cultureinfo]::InvariantCulture); Revision = [int]$Matches[2] }
        }
    } | Sort-Object Date, Revision -Descending)
    if ($versions.Count -eq 0) { throw 'No valid versioned Invoke-EsetHipsPoc script found.' }
    $controllerName = [IO.Path]::GetFileName($versions[0].File)
    $checked = Test-KitIntegrity -KitDir $KitDir -ControllerName $controllerName
    $KitDir = $checked.KitPath
    Write-Host ('PACKAGE_PREFLIGHT_PASS: ' + $controllerName)
    if ($ValidateOnly) {
        Write-Host 'VALIDATION_ONLY_PASS: package path and hashes checked; no ESET access, EXE launch or configuration change.'
        exit 0
    }
    if (-not $IAmOnATestMachine) {
        Write-Host 'This kit is for an isolated test PC only, NOT production.'
        if ((Read-Host 'Type TEST to authorize this test kit') -cne 'TEST') { throw 'Test-machine acknowledgment declined.' }
        $IAmOnATestMachine = $true
    }
    $global:LASTEXITCODE = 1
    & $versions[0].File -KitDir $KitDir -DryRun:$DryRun -IAmOnATestMachine:$IAmOnATestMachine -RuleAppearTimeoutSeconds $RuleAppearTimeoutSeconds -RemovalTimeoutSeconds $RemovalTimeoutSeconds -PollSeconds $PollSeconds
    exit $LASTEXITCODE
} catch {
    Write-Host ('FAILED AT LAUNCHER: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Copy this precise error line; usernames are redacted in path-guard errors. No ESET settings changed by the launcher.'
    exit 1
}
