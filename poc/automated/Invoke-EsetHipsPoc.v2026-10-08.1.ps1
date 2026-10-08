#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$KitDir = $PSScriptRoot,
    [ValidateSet('LOLRMM POC TEST - LolrmmEsetTest')][string]$RuleName = 'LOLRMM POC TEST - LolrmmEsetTest',
    [switch]$DryRun,
    [switch]$IAmOnATestMachine,
    [switch]$Worker,
    [string]$RunId,
    [string]$CallerSid,
    [ValidateSet('baseline','with-manual-rule','after-removal')][string]$Stage = 'baseline'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Kit.Helpers.ps1')
function Add-Check([string]$Name, [string]$Status, [string]$Detail) {
    $script:Checks.Add([pscustomobject]@{ name=$Name; status=$Status; detail=$Detail })
    Write-Host ($Status + ' : ' + $Name + ' : ' + $Detail)
}
function Confirm-Yes([string]$Message) { return ((Read-Host ($Message + ' [yes/NO]')) -ceq 'yes') }
function Save-Evidence {
    $script:Report.steps = $script:Checks.ToArray()
    $script:Report.status = (Get-OverallTruth @($script:Checks | ForEach-Object { $_.status })).Overall
    $script:Report.finished = (Get-Date).ToString('o')
    $script:Report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $script:Evidence 'result.json') -Encoding UTF8
    $share = @('LOLRMM ESET Phase 1 - guided observation', ('Overall: ' + $script:Report.status), 'Architecture gate: UNVERIFIED', ('Cleanup unresolved: ' + $script:Report.cleanup_unresolved), 'Raw XML and diagnostics are PRIVATE. Do not share result.json.')
    foreach ($check in $script:Checks) { $share += ($check.name + ': ' + $check.status + ' - ' + $check.detail) }
    $share | Set-Content -LiteralPath (Join-Path $script:Evidence 'RESULTS.txt') -Encoding ASCII
    @('Raw XML deliberately withheld pending schema review.', ('Rule name: ' + $RuleName), 'Target: <USER_LOCAL_RUN>\LolrmmEsetTest.exe', 'No wildcard, folder, allow rule, exclusion or import generated.', 'Only share RESULTS.txt and this file. Keep all other evidence private.') | Set-Content -LiteralPath (Join-Path $script:Evidence 'sanitized-rule-diff.txt') -Encoding ASCII
    $share | Set-Content -LiteralPath (Join-Path $script:Evidence 'run-status.txt') -Encoding ASCII
}
function Export-Configuration([string]$ExportStage) {
    [void](Assert-SafeLocalPath $script:Evidence 'Private evidence directory')
    Set-PrivateAcl $script:Evidence $script:Sid
    if (@(Get-Process -Name ecmd -ErrorAction SilentlyContinue).Count -gt 0) { throw 'ecmd still running; configuration state unknown. No concurrent export attempted.' }
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-Worker','-RunId',$script:RunId,'-CallerSid',$script:Sid,'-Stage',$ExportStage)
    $line = (@($arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $line -Verb RunAs -Wait -PassThru
    if ($null -eq $p -or $p.ExitCode -ne 0) { throw 'UAC export worker failed or was declined. See private worker status; no import attempted.' }
    $path = Join-Path $script:Evidence ($ExportStage + '.xml')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Export worker did not produce its expected file.' }
    $file = Get-Item -LiteralPath $path
    if ($file.Length -eq 0 -or $file.Length -gt 16777216) { throw 'Export file empty or exceeds 16 MiB.' }
    [void](Get-SafeXmlTree ([IO.File]::ReadAllText($path)))
    Set-PrivateAcl $path $script:Sid
    return $path
}
function Test-HarmlessLaunch {
    [void](Assert-SafeLocalPath $script:Exe 'Copied test executable')
    if ((Get-FileHash -LiteralPath $script:Exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $script:ExpectedExeHash) { throw 'Test executable changed since package verification.' }
    return (Invoke-CapturedProcess -FilePath $script:Exe -TimeoutSeconds 15 -KillOnTimeout)
}
function Assert-HarmlessSuccess($Outcome) {
    if ($Outcome.ExitCode -ne 0 -or $Outcome.Stdout.TrimEnd([char[]]@("`r","`n")) -cne 'Test Application' -or $Outcome.Stderr.Length -ne 0) { throw 'Harmless executable did not produce exact expected stdout, empty stderr and exit 0.' }
}
# Worker can only export to a fresh predetermined stage under this user's evidence run.
if ($Worker) {
    $workerStatus = $null
    try {
        if ($env:OS -ne 'Windows_NT') { throw 'Windows required.' }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Export worker is not elevated.' }
        if ($identity.User.Value -cne $CallerSid) { throw 'UAC account differs from invoking account; refusing.' }
        if ($RunId -cnotmatch '^[0-9a-f]{32}$') { throw 'Invalid run identifier.' }
        $folder = Assert-SafeLocalPath (Join-Path (Join-Path $env:USERPROFILE 'LOLRMM-Evidence') $RunId)
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw 'Evidence folder missing.' }
        Set-PrivateAcl $folder $CallerSid
        $workerStatus = Join-Path $folder ('worker-' + $Stage + '.json')
        $ecmd = Assert-SafeLocalPath (Join-Path $env:ProgramFiles 'ESET\ESET Security\ecmd.exe')
        if (-not (Test-Path -LiteralPath $ecmd -PathType Leaf)) { throw 'ESET Security ecmd.exe not found.' }
        $sig = Get-AuthenticodeSignature -LiteralPath $ecmd
        if ($sig.Status -ne 'Valid' -or $null -eq $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch 'ESET') { throw 'ecmd does not have a valid ESET Authenticode signature.' }
        if (@(Get-Process -Name ecmd -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Existing ecmd process; state unknown.' }
        $dest = Join-Path $folder ($Stage + '.xml')
        if (Test-Path -LiteralPath $dest) { throw 'Refusing to overwrite export.' }
        $process = Invoke-CapturedProcess -FilePath $ecmd -ArgumentList @('/getcfg',$dest) -TimeoutSeconds 90
        $process | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $workerStatus -Encoding UTF8
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $dest -PathType Leaf)) { throw 'ecmd export failed; details retained privately.' }
        if ((Get-Item -LiteralPath $dest).Length -eq 0 -or (Get-Item -LiteralPath $dest).Length -gt 16777216) { throw 'Export empty or too large.' }
        [void](Get-SafeXmlTree ([IO.File]::ReadAllText($dest)))
        Set-PrivateAcl $dest $CallerSid
        exit 0
    } catch {
        Write-Host ('EXPORT FAILED: ' + $_.Exception.Message) -ForegroundColor Red
        if ($workerStatus) { @{ status='FAIL'; message=$_.Exception.Message } | ConvertTo-Json | Set-Content -LiteralPath $workerStatus -Encoding UTF8 }
        exit 1
    }
}
$script:Checks = New-Object 'System.Collections.Generic.List[object]'
$script:Evidence = $null; $script:PotentialRule = $false; $script:Exe = $null
$script:Report = [ordered]@{ status='UNVERIFIED'; architecture_gate='UNVERIFIED'; cleanup_unresolved=$false; started=(Get-Date).ToString('o'); timezone=[TimeZoneInfo]::Local.Id; environment=@{}; steps=@(); diagnostics=@(); finished=$null }
try {
    if ($env:OS -ne 'Windows_NT') { throw 'Windows required; live ESET cannot be exercised here.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Start the BAT normally, NOT as administrator. The test controller must be non-elevated.' }
    $script:Sid = $identity.User.Value
    $computer = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    if ($computer.PartOfDomain -or $os.ProductType -ne 1) { throw 'Domain-joined or server machine refused; use an isolated client test PC.' }
    if (-not $IAmOnATestMachine) { throw 'Explicit -IAmOnATestMachine acknowledgment required; use Launch-Kit.ps1 for typed consent.' }
    $verified = Test-KitIntegrity -KitDir $KitDir -ControllerName ([IO.Path]::GetFileName($PSCommandPath))
    $kit = $verified.KitPath
    $manifest = $verified.Manifest
    Add-Check 'package-integrity' 'PASS' 'Exact member set and SHA256 hashes match; internal consistency, not publisher authentication.'
    $script:RunId = [guid]::NewGuid().ToString('N')
    $runRoot = Assert-SafeLocalPath (Join-Path $env:LOCALAPPDATA 'LOLRMM-POC') 'Private run root'
    $evidenceRoot = Assert-SafeLocalPath (Join-Path $env:USERPROFILE 'LOLRMM-Evidence') 'Private evidence root'
    foreach ($root in @($runRoot,$evidenceRoot)) { [void](New-Item -ItemType Directory -Path $root -Force) }
    $runFolder = Join-Path $runRoot $script:RunId
    $script:Evidence = Join-Path $evidenceRoot $script:RunId
    [void](New-Item -ItemType Directory -Path $runFolder)
    [void](New-Item -ItemType Directory -Path $script:Evidence)
    Set-PrivateAcl $runFolder $script:Sid; Set-PrivateAcl $script:Evidence $script:Sid
    [void](Assert-SafeLocalPath $runFolder); [void](Assert-SafeLocalPath $script:Evidence 'Private evidence directory')
    $script:ExpectedExeHash = $manifest['LolrmmEsetTest.exe']
    $script:Exe = Join-Path $runFolder 'LolrmmEsetTest.exe'
    Copy-Item -LiteralPath (Join-Path $kit 'LolrmmEsetTest.exe') -Destination $script:Exe
    Set-PrivateAcl $script:Exe $script:Sid
    if ((Get-FileHash -LiteralPath $script:Exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $manifest['LolrmmEsetTest.exe']) { throw 'Copied executable hash mismatch.' }
    $service = Get-Service -Name ekrn -ErrorAction SilentlyContinue
    if ($null -eq $service -or $service.Status -ne 'Running') { throw 'ekrn missing or not running; do not change service/protection.' }
    $ecmd = Assert-SafeLocalPath (Join-Path $env:ProgramFiles 'ESET\ESET Security\ecmd.exe')
    if (-not (Test-Path -LiteralPath $ecmd -PathType Leaf)) { throw 'Expected ESET Security ecmd.exe missing; compatibility unresolved.' }
    $script:Report.environment = @{ windows=$os.Caption; version=$os.Version; build=$os.BuildNumber; ecmd_version=(Get-Item -LiteralPath $ecmd).VersionInfo.FileVersion; ecmd_path=$ecmd; controller_sid=$script:Sid }
    $kernelPath = Join-Path (Split-Path $ecmd -Parent) 'ekrn.exe'
    if (Test-Path -LiteralPath $kernelPath -PathType Leaf) {
        [void](Assert-SafeLocalPath $kernelPath)
        $kernelInfo = (Get-Item -LiteralPath $kernelPath).VersionInfo
        $script:Report.environment.eset_product = $kernelInfo.ProductName
        $script:Report.environment.eset_product_version = $kernelInfo.ProductVersion
        Write-Host ('Detected ESET file metadata: ' + $kernelInfo.ProductName + ' ' + $kernelInfo.ProductVersion + ' (compatibility candidate only)')
    }
    Write-Host ('Detected Windows: ' + $os.Caption + ' build ' + $os.BuildNumber)
    Write-Host ('Detected ecmd FileVersion: ' + $script:Report.environment.ecmd_version)
    if (-not (Confirm-Yes 'Confirm HIPS is enabled in ESET UI (unknown/no means stop)')) { throw 'HIPS not confirmed enabled; stopping.' }
    Add-Check 'HIPS-readiness' 'OWNER_REPORTED' 'Owner confirmed HIPS enabled; not independently machine-verified.'
    $mode = Read-Host 'ESET CMD authorization MODE only: None, Password, Disabled, Unknown (NEVER type a password)'
    if ($mode -notin @('None','Password','Disabled','Unknown')) { throw 'Unexpected authorization mode input.' }
    $script:Report.environment.ecmd_mode_owner_reported = $mode
    Add-Check 'ESET-CMD-mode' 'OWNER_REPORTED' ('Mode=' + $mode + '; export allowed even when disabled; no import attempted.')
    if ($DryRun) {
        Add-Check 'dry-run' 'UNVERIFIED' 'Preflight and private folders completed; no export, executable launch or ESET change.'
    } else {
        Assert-HarmlessSuccess (Test-HarmlessLaunch)
        Add-Check 'baseline-launch' 'PASS' 'Non-elevated executable: exact Test Application, empty stderr, exit 0.'
        $baseline = Export-Configuration 'baseline'
        $script:Report.baseline_sha256 = (Get-FileHash $baseline -Algorithm SHA256).Hash
        Add-Check 'baseline-export' 'PASS' 'Elevated ecmd export created securely parsed local baseline.'
        Write-Host ('EXACT TEST EXE: ' + $script:Exe)
        Write-Host ('MANUAL RULE: ' + $RuleName)
        Write-Host 'Enabled; Block; Start new application; All source applications; Specific exact file target; logging + notification.'
        Write-Host 'If a rule with this name already exists, STOP. Do not edit it or delete it.'
        if (-not (Confirm-Yes 'Confirm there is NO pre-existing rule with this name')) { throw 'Rule-name collision or unknown ownership.' }
        $script:PotentialRule = $true; $script:Report.cleanup_unresolved = $true
        if (-not (Confirm-Yes 'Now create only that exact rule in ESET UI, then confirm complete (no/unknown triggers cleanup)')) { throw 'Manual creation not confirmed.' }
        $withRule = Export-Configuration 'with-manual-rule'
        $diff = Compare-SafeXml ([IO.File]::ReadAllText($baseline)) ([IO.File]::ReadAllText($withRule))
        if ($diff.Kind -ne 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE') { throw 'Export change is not exactly one inserted structural subtree; XML mapping unresolved.' }
        Add-Check 'single-rule-structure' 'UNVERIFIED' 'One inserted structural subtree candidate; HIPS semantics require schema review.'
        $script:Report.block_attempt_time = (Get-Date).ToString('o')
        Write-Host ('Block test starting at: ' + $script:Report.block_attempt_time)
        $launchFailed = $false; $outcome = $null
        try { $outcome = Test-HarmlessLaunch; $script:Report.block_launch_classification = 'PROCESS_EXITED' } catch { $launchFailed = $true; $script:Report.block_launch_classification = 'LAUNCH_ERROR_OR_TIMEOUT_UNRESOLVED'; $script:Report.diagnostics += $_.Exception.Message }
        $ranNormally = $false
        if ($outcome) { $script:Report.block_launch = $outcome; $ranNormally = ($outcome.ExitCode -eq 0 -and $outcome.Stdout.TrimEnd([char[]]@("`r","`n")) -ceq 'Test Application') }
        if ($ranNormally) { throw 'Executable ran normally while rule present; blocking test FAILED.' }
        Add-Check 'blocked-launch' 'UNVERIFIED' 'Launch was not a normal successful run; this alone does NOT prove ESET blocking.'
        if (-not (Confirm-Yes 'In Tools > Log files > HIPS, confirm exact rule AND exact test EXE AND denied result at the printed test time')) { throw 'Matching HIPS denied log entry missing or ambiguous.' }
        Add-Check 'HIPS-log-correlation' 'OWNER_REPORTED' 'Owner confirmed exact rule, exact target, denied result and corresponding attempt time.'
        $notification = Confirm-Yes 'Was an ESET block notification observed for this attempt?'
        if ($notification) { Add-Check 'notification' 'OWNER_REPORTED' 'Owner observed notification.' } else { Add-Check 'notification' 'UNVERIFIED' 'Notification not confirmed.' }
        Add-Check 'add-twice-idempotency' 'UNVERIFIED' 'No programmatic adapter; add-twice test intentionally not attempted.'
    }
} catch {
    $script:Report.diagnostics += $_.Exception.Message
    Add-Check 'controller' 'FAIL' 'Operation failed; see console/private diagnostics. No configuration import performed.'
    Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red
} finally {
    if ($script:PotentialRule) {
        try {
            Write-Warning ('CLEANUP REQUIRED: Remove ONLY ' + $RuleName + ' targeting ' + $script:Exe)
            if (-not (Confirm-Yes 'Inspect exact name/target in HIPS UI; remove only the new test rule; confirm removed')) { throw 'Cleanup not confirmed.' }
            $post = Export-Configuration 'after-removal'
            $baselinePath = Join-Path $script:Evidence 'baseline.xml'
            $sameBytes = ((Get-FileHash $baselinePath -Algorithm SHA256).Hash -ceq (Get-FileHash $post -Algorithm SHA256).Hash)
            $cleanupComparison = Compare-SafeXml ([IO.File]::ReadAllText($baselinePath)) ([IO.File]::ReadAllText($post))
            $script:Report.cleanup_comparison = $cleanupComparison.Kind
            if (-not $sameBytes) { throw 'After-removal export is not byte-identical to baseline. No volatile-field exceptions assumed.' }
            Assert-HarmlessSuccess (Test-HarmlessLaunch)
            Add-Check 'cleanup-preservation' 'PASS' 'Post-removal export byte-identical to baseline; normal executable output/exit restored.'
            Add-Check 'rule-removal' 'OWNER_REPORTED' 'Owner removed only exact new rule; export preservation and launch checked automatically.'
            $script:PotentialRule = $false; $script:Report.cleanup_unresolved = $false
        } catch {
            $script:Report.diagnostics += $_.Exception.Message
            Add-Check 'cleanup' 'FAIL' 'Rule or configuration state unresolved. Manual inspection/removal required; no blind baseline import.'
            Write-Warning ('CLEANUP UNRESOLVED: ' + $_.Exception.Message + '. Inspect ONLY exact new rule: ' + $RuleName)
        }
    }
    Add-Check 'programmatic-architecture-gate' 'UNVERIFIED' 'No programmatic insert/sign/import or automated HIPS-log proof; Phase 1 NOT passed.'
    if ($script:Evidence) {
        try { Save-Evidence; Write-Host ('Evidence: ' + $script:Evidence) } catch { Write-Warning ('Evidence write failed: ' + $_.Exception.Message); Add-Check 'report-write' 'FAIL' 'Could not persist complete evidence.' }
    }
}
if (@($script:Checks | Where-Object { $_.status -eq 'FAIL' }).Count -gt 0) { exit 1 }
if ($DryRun) { exit 0 }
exit 2
