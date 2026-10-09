# Real subprocess proof, not live ESET. Descendant fixture runs on POSIX only.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../poc/quick-rules/Eset-QuickRules.ps1') -FunctionsOnly
$hostExe=(Get-Process -Id $PID).Path
$out=Invoke-QuickProcess -FilePath $hostExe -Arguments @('-NoProfile','-Command','[Console]::Write("out"); [Console]::Error.Write("err"); exit 7') -TimeoutSeconds 10
if($out.ExitCode -ne 7 -or $out.StdOut -cne 'out' -or $out.StdErr -cne 'err') { throw 'Real process exit/stdout/stderr contract failed.' }
Write-Output 'PASS: real process output and nonzero exit captured'
if($env:OS -ne 'Windows_NT') {
    $watch=[Diagnostics.Stopwatch]::StartNew(); $caught=$false
    try { $null=Invoke-QuickProcess -FilePath '/bin/sh' -Arguments @('-c','sleep 4 & exit 0') -TimeoutSeconds 1 } catch { $caught=$true }
    $watch.Stop()
    if(-not $caught -or $watch.Elapsed.TotalSeconds -gt 3) { throw ('Inherited output pipe exceeded deadline: '+$watch.Elapsed.TotalSeconds+' seconds; threw='+$caught) }
    Write-Output 'PASS: descendant-held output pipe cannot bypass caller deadline'
} else { Write-Output 'POSIX_DESCENDANT_FIXTURE_NOT_RUN: no Windows tree-termination claim.' }
