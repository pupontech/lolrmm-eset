#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$ZipPath)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Packaged BAT proof requires Windows.' }
$base = Join-Path $env:RUNNER_TEMP ('eset-kit-proof-' + [guid]::NewGuid().ToString('N'))
$folder = Join-Path $base "Kit O'Brien [with spaces] & (symbols)"
$other = Join-Path $base 'Alternate package root'
[void](New-Item -ItemType Directory -Path $folder -Force)
[void](New-Item -ItemType Directory -Path $other -Force)
function Invoke-PackagedBat([string]$ExtraArguments, [string]$InputText = '') {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    $bat = Join-Path $folder 'Run-EsetHipsPoc.bat'
    $psi.Arguments = '/d /s /c ""' + $bat + '" ' + $ExtraArguments + '"'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEndAsync(); $stderr = $p.StandardError.ReadToEndAsync()
    $p.StandardInput.WriteLine($InputText); $p.StandardInput.WriteLine(''); $p.StandardInput.Close()
    if (-not $p.WaitForExit(30000)) { $p.Kill(); throw 'Packaged BAT timed out.' }
    $p.WaitForExit()
    $result = [pscustomobject]@{ Exit=$p.ExitCode; Text=$stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult() }
    $p.Dispose(); return $result
}
function Require([bool]$Good, [string]$Name, $Result) {
    if (-not $Good) { throw ($Name + ' FAILED. Captured output: ' + $Result.Text) }
    Write-Output ('PACKAGED_LAUNCH_PASS: ' + $Name)
}
try {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $folder
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $other
    $r = Invoke-PackagedBat '-ValidateOnly'
    Require ($r.Exit -eq 0 -and $r.Text.Contains('PACKAGE_PREFLIGHT_PASS') -and $r.Text.Contains('VALIDATION_ONLY_PASS')) 'actual BAT default root, spaces, apostrophe, brackets' $r
    $slashPath = $other.Replace('\','/')
    $r = Invoke-PackagedBat ('-ValidateOnly -KitDir "' + $slashPath + '"')
    Require ($r.Exit -eq 0 -and $r.Text.Contains('VALIDATION_ONLY_PASS')) 'explicit forward-slash alternate root' $r
    $r = Invoke-PackagedBat '' 'NO'
    Require ($r.Exit -eq 1 -and $r.Text.Contains('PACKAGE_PREFLIGHT_PASS') -and $r.Text.Contains('acknowledgment declined')) 'preflight then consent refusal; no controller started' $r
    $r = Invoke-PackagedBat '-ValidateOnly -KitDir "C:\OneDrive\kit"'
    Require ($r.Exit -eq 1 -and $r.Text.Contains('Kit directory path rejected [cloud-storage-path-component]')) 'precise cloud guard diagnostic' $r
    $readme = Join-Path $folder 'README.md'
    [IO.File]::AppendAllText($readme, 'TAMPER_FIXTURE')
    $r = Invoke-PackagedBat '-ValidateOnly'
    Require ($r.Exit -eq 1 -and $r.Text.Contains('Package hash mismatch: README.md') -and -not $r.Text.Contains('VALIDATION_ONLY_PASS')) 'real package tamper rejection' $r
    Write-Output 'All 5 packaged Windows launcher checks passed. No live ESET or rule changes were tested.'
} finally { Remove-Item -LiteralPath $base -Recurse -Force }
