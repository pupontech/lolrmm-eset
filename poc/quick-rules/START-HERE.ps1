#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$ValidateOnly,
    [switch]$IAmOnATestMachine,
    [switch]$ElevatedChild,
    [string]$CallerSid
)
$ErrorActionPreference = 'Stop'
try {
    foreach ($name in @('Eset-QuickRules.ps1','rules.csv','LolrmmEsetTest.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name) -PathType Leaf)) { throw ('Missing package member: ' + $name + '. Extract the complete test ZIP.') }
    }
    $errors = $null; $tokens = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Eset-QuickRules.ps1'),[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw 'Main script failed PowerShell parsing.' }
    if ($ValidateOnly) { Write-Host 'PACKAGE_VALIDATION_PASS: no ESET access or configuration change.'; exit 0 }
    if ($env:OS -ne 'Windows_NT') { throw 'Live preview/apply requires Windows. Offline preview is available through Eset-QuickRules.ps1 -ConfigurationFile.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($ElevatedChild) {
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Child did not receive an administrator token.' }
        if ($CallerSid -cne $identity.User.Value) { throw 'UAC account differs from invoking account. Use same-account elevation; no ESET operation performed.' }
        $global:LASTEXITCODE = 1
        try {
            & (Join-Path $PSScriptRoot 'Eset-QuickRules.ps1') -RulesFile (Join-Path $PSScriptRoot 'rules.csv') -Apply:$Apply -IAmOnATestMachine:$IAmOnATestMachine
            $code = $LASTEXITCODE
        } catch { Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red; $code = 1 }
        Write-Host ('Script exit code: ' + $code)
        Write-Host 'Private evidence, when created: %LOCALAPPDATA%\LOLRMM-QuickRules\runs'
        [void](Read-Host 'Press Enter to close this window')
        exit $code
    }
    if ($Apply -and -not $IAmOnATestMachine) {
        Write-Host 'EXPERIMENTAL native HIPS append test. Isolated test PC only; ESET 19 compatibility is NOT certified.' -ForegroundColor Yellow
        Write-Host 'The default CSV targets only the harmless LolrmmEsetTest.exe. Do not use production RMM paths for the first test.'
        if ((Read-Host 'Type TEST to acknowledge this is an isolated test machine') -cne 'TEST') { throw 'Test-machine acknowledgment declined; no import.' }
        $IAmOnATestMachine = $true
    }
    function Quote-Argument([string]$Value) { return ('"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"') }
    $argsList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'START-HERE.ps1'),'-ElevatedChild','-CallerSid',$identity.User.Value)
    if ($Apply) { $argsList += '-Apply' }
    if ($IAmOnATestMachine) { $argsList += '-IAmOnATestMachine' }
    $line = (@($argsList | ForEach-Object { Quote-Argument $_ }) -join ' ')
    $hostExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $child = Start-Process -FilePath $hostExe -ArgumentList $line -Verb RunAs -Wait -PassThru
    if ($null -eq $child) { throw 'No elevated child was returned.' }
    $child.Refresh()
    exit $child.ExitCode
} catch {
    Write-Host ('FAILED AT LAUNCHER: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
