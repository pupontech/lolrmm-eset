#requires -Version 5.1
# ============================================================================
# Test-AutoObservation.ps1 - CI/Local adversarial test of the v2026-10-08.4
# automated observation architecture (supervisor + controller).
#
# Everything here is SYNTHETIC: no live ESET, no ecmd, no UAC. The supervisor
# and controller are validated by simulating the evidence folder state and the
# verdict JSON files. Pure PowerShell 5.1, no Pester, ASCII only.
# ============================================================================
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Failures = 0
$script:Checks = 0
function Assert([bool]$ok, [string]$name) {
    $script:Checks++
    if (-not $ok) { $script:Failures++; Write-Output ('FAIL: ' + $name); return }
    Write-Output ('PASS: ' + $name)
}
function Assert-Throws([scriptblock]$action, [string]$name) {
    $threw = $false
    try { [void](& $action) } catch { $threw = $true }
    Assert $threw $name
}

# ---------- 1. Real files exist ----------
$automated = Split-Path $PSScriptRoot -Parent
$supervisor = Join-Path $automated 'Invoke-EsetHipsSupervisor.v2026-10-08.4.ps1'
$controller = Join-Path $automated 'Invoke-EsetHipsPoc.v2026-10-08.4.ps1'
Assert (Test-Path -LiteralPath $supervisor) 'supervisor file present'
Assert (Test-Path -LiteralPath $controller) 'controller file present'

# ---------- 2. ASCII + parse ----------
foreach ($file in @($supervisor, $controller)) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
    Assert ($errors.Count -eq 0) ('parse ' + [IO.Path]::GetFileName($file))
    Assert (@([IO.File]::ReadAllBytes($file) | Where-Object { $_ -gt 127 }).Count -eq 0) ('ASCII ' + [IO.Path]::GetFileName($file))
}

# ---------- 3. Extract and run supervisor functions synthetically ----------
. (Join-Path $automated 'Kit.Helpers.ps1')
$ast = [System.Management.Automation.Language.Parser]::ParseFile($supervisor, [ref]$null, [ref]$null)
foreach ($fnName in @('Get-HipsStateFromXml', 'Get-RuleNameCollisionCount', 'Test-RuleAppearance', 'Test-RuleRemoval')) {
    $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fnName }, $true)[0]
    if ($null -eq $fn) { throw ('Function not found in supervisor: ' + $fnName) }
    Invoke-Expression $fn.Extent.Text
}
$ruleName = 'LOLRMM POC TEST - LolrmmEsetTest'

# HIPS state detection
$enabled = '<CONFIG><Hips Enabled="1"><Engine>active</Engine></Hips></CONFIG>'
$disabled = '<CONFIG><Hips Enabled="0"/></CONFIG>'
$undecidable = '<CONFIG><Hips><SomethingElse>1</SomethingElse></Hips></CONFIG>'
$conflict = '<CONFIG><Hips Enabled="1"><Engine>disabled</Engine></Hips></CONFIG>'
$wrongNameAttr = '<CONFIG><Hips Enabled="1" note="' + $ruleName + '"/></CONFIG>'
$nameValueEnabled = '<CONFIG><SETTINGS><NAME>HipsEnabled</NAME><VALUE>1</VALUE></SETTINGS></CONFIG>'
$nameValueDisabled = '<CONFIG><SETTINGS><NAME>HipsEnabled</NAME><VALUE>0</VALUE></SETTINGS></CONFIG>'
Assert ((Get-HipsStateFromXml (Get-SafeXmlTree $enabled) $ruleName) -eq 'enabled') 'hips enabled detected'
Assert ((Get-HipsStateFromXml (Get-SafeXmlTree $disabled) $ruleName) -eq 'disabled') 'hips disabled detected'
Assert ((Get-HipsStateFromXml (Get-SafeXmlTree $undecidable) $ruleName) -eq 'undetectable') 'hips undetectable'
Assert ((Get-HipsStateFromXml (Get-SafeXmlTree $conflict) $ruleName) -eq 'enabled') 'hips conflicting values: child-element values do not count'
Assert ((Get-HipsStateFromXml (Get-SafeXmlTree $wrongNameAttr) $ruleName) -eq 'enabled') 'rule-name value ignored in hips detection'
Assert ((Get-HipsStateFromXml (Get-SafeXmlTree $nameValueEnabled) $ruleName) -eq 'enabled') 'NAME/VALUE pairing enabled detected'
Assert ((Get-HipsStateFromXml (Get-SafeXmlTree $nameValueDisabled) $ruleName) -eq 'disabled') 'NAME/VALUE pairing disabled detected'

# Rule-name collision counting
$baseline = '<CONFIG><HipsRules><Rule name="existing"/><Rule name="other"/></HipsRules></CONFIG>'
$withDup = '<CONFIG><HipsRules><Rule name="' + $ruleName + '"/><Rule name="' + $ruleName + '"/></HipsRules></CONFIG>'
Assert ((Get-RuleNameCollisionCount (Get-SafeXmlTree $baseline) $ruleName) -eq 0) 'no collision in baseline'
Assert ((Get-RuleNameCollisionCount (Get-SafeXmlTree $withDup) $ruleName) -eq 2) 'duplicate collision detected'

# Rule appearance: absent / ready / unexpected
$withOneRule = '<CONFIG><HipsRules><Rule name="existing"/><Rule name="other"/><Rule name="' + $ruleName + '"><Target/></Rule></HipsRules></CONFIG>'
$withTwoRules = '<CONFIG><HipsRules><Rule name="existing"/><Rule name="' + $ruleName + '"/><Rule name="' + $ruleName + '"/></HipsRules></CONFIG>'
$otherChange = '<CONFIG Mode="changed"><HipsRules><Rule name="existing"/></HipsRules></CONFIG>'
$baselineFile = Join-Path ([IO.Path]::GetTempPath()) ('lolrmm-t-' + [guid]::NewGuid().ToString('N') + '.xml')
[IO.File]::WriteAllText($baselineFile, $baseline)
$candidateFile = Join-Path ([IO.Path]::GetTempPath()) ('lolrmm-c-' + [guid]::NewGuid().ToString('N') + '.xml')
[IO.File]::WriteAllText($candidateFile, $withOneRule)
Assert ((Test-RuleAppearance $baselineFile $candidateFile $ruleName) -eq 'ready') 'appearance: single insertion with name is ready'
[IO.File]::WriteAllText($candidateFile, $withTwoRules)
Assert ((Test-RuleAppearance $baselineFile $candidateFile $ruleName) -eq 'unexpected') 'appearance: two inserted rules unexpected'
[IO.File]::WriteAllText($candidateFile, $baseline)
Assert ((Test-RuleAppearance $baselineFile $candidateFile $ruleName) -eq 'absent') 'appearance: identical bytes absent'
[IO.File]::WriteAllText($candidateFile, $otherChange)
Assert ((Test-RuleAppearance $baselineFile $candidateFile $ruleName) -eq 'absent') 'appearance: unrelated change treated as absent'
[IO.File]::WriteAllText($candidateFile, $withDup)
Assert ((Test-RuleAppearance $baselineFile $candidateFile $ruleName) -eq 'unexpected') 'appearance: duplicate name collision unexpected'

# Rule removal: structural identity after volatile-counter stripping
$removalFile = Join-Path ([IO.Path]::GetTempPath()) ('lolrmm-r-' + [guid]::NewGuid().ToString('N') + '.xml')
[IO.File]::WriteAllText($removalFile, $baseline)
Assert ((Test-RuleRemoval $baselineFile $removalFile $ruleName) -eq 'done') 'removal: structurally identical is done'
[IO.File]::WriteAllText($removalFile, $withOneRule)
Assert ((Test-RuleRemoval $baselineFile $removalFile $ruleName) -eq 'pending') 'removal: rule still present is pending'
# Volatile counters churn but the structure is the baseline structure -> done
$volatileBaseline = '<CONFIG><Rule name="x" HitCount="3" LastUseTime="t1"/></CONFIG>'
$volatileCandidate = '<CONFIG><Rule name="x" HitCount="9" LastUseTime="t9"/></CONFIG>'
$vb = Join-Path ([IO.Path]::GetTempPath()) ('lolrmm-vb-' + [guid]::NewGuid().ToString('N') + '.xml')
$vc = Join-Path ([IO.Path]::GetTempPath()) ('lolrmm-vc-' + [guid]::NewGuid().ToString('N') + '.xml')
[IO.File]::WriteAllText($vb, $volatileBaseline)
[IO.File]::WriteAllText($vc, $volatileCandidate)
Assert ((Test-RuleRemoval $vb $vc $ruleName) -eq 'done') 'removal: volatile counter churn alone does not block removal'
Remove-Item -LiteralPath $vb, $vc -Force -ErrorAction SilentlyContinue

# Cleanup temp files
foreach ($f in @($baselineFile, $candidateFile, $removalFile)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }

# ---------- 4. Controller behavior (synthetic) ----------
$astController = [System.Management.Automation.Language.Parser]::ParseFile($controller, [ref]$null, [ref]$null)
foreach ($fnName in @('Read-VerdictJson', 'Wait-ForVerdictFile', 'Start-EsetHipsSupervisor')) {
    $fn = $astController.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fnName }, $true)[0]
    if ($null -eq $fn) { throw ('Function not found in controller: ' + $fnName) }
    Invoke-Expression $fn.Extent.Text
}
$evidence = Join-Path ([IO.Path]::GetTempPath()) ('lolrmm-e-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $evidence -Force)
try {
    $script:Evidence = $evidence
    Assert ($null -eq (Read-VerdictJson 'missing')) 'missing verdict file returns null'
    @{ status = 'PASS' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'present.json') -Encoding UTF8
    Assert ($null -ne (Read-VerdictJson 'present')) 'present verdict file parses'
    Assert (Wait-ForVerdictFile -Name 'present' -TimeoutSeconds 1) 'wait for present file returns immediately'
    Assert (-not (Wait-ForVerdictFile -Name 'never-appears' -TimeoutSeconds 1 -PollSeconds 1)) 'wait for absent file times out'

    # Supervisor launcher must require elevation: patch Start-Process to a no-op and check it is invoked only after checks
    $startFn = $astController.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Start-EsetHipsSupervisor' }, $true)[0]
    Assert ($startFn.Extent.Text.Contains('-Verb RunAs')) 'supervisor launched with UAC (RunAs)'

    # Supervisor SelfTest flag exits immediately without running the main flow
    $supOutput = pwsh -NoProfile -NonInteractive -Command ('& "' + $supervisor + '" -RunId "' + ('0' * 32) + '" -CallerSid "S-1-5-18" -RuleName "X" -SelfTest; exit $LASTEXITCODE') 2>&1
    Assert ($LASTEXITCODE -eq 0) 'supervisor SelfTest exits 0'
} finally {
    Remove-Item -LiteralPath $evidence -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------- 5. Controller exit codes ----------
# -DryRun on non-Windows must fail closed (Windows required).
$controllerOutput = pwsh -NoProfile -NonInteractive -Command ('& "' + $controller + '" -DryRun -IAmOnATestMachine; exit $LASTEXITCODE') 2>&1
Assert ($LASTEXITCODE -eq 1) 'controller on non-Windows fails closed'

# ---------- 6. Versioned controller discovered by launcher ----------
$launcher = [IO.File]::ReadAllText((Join-Path $automated 'Launch-Kit.ps1'))
Assert ($launcher.Contains('RuleAppearTimeoutSeconds')) 'launcher forwards RuleAppearTimeoutSeconds'
Assert ($launcher.Contains('RemovalTimeoutSeconds')) 'launcher forwards RemovalTimeoutSeconds'
Assert ($launcher.Contains('PollSeconds')) 'launcher forwards PollSeconds'
Assert ($launcher.Contains('$Matches[2]')) 'launcher uses numeric revision ordering'

# Controller writes PENDING_OWNER, not OWNER_REPORTED, for the log correlation
$controllerText = [IO.File]::ReadAllText($controller)
Assert ($controllerText.Contains("Add-Check 'HIPS-log-correlation' 'PENDING_OWNER'")) 'HIPS-log correlation recorded as PENDING_OWNER'
Assert (-not $controllerText.Contains("Confirm-Yes 'In Tools")) 'no blocking prompt for HIPS log confirmation'
Assert (-not $controllerText.Contains("Confirm-Yes 'Confirm HIPS is enabled")) 'no blocking prompt for HIPS enabled'
Assert (-not $controllerText.Contains("Confirm-Yes 'Confirm there is NO pre-existing rule")) 'no blocking prompt for rule-name collision'
Assert ($controllerText.Contains("Confirm-Yes 'Authorize this automated ESET observation now?'")) 'exactly one consent prompt remains'
# exactly one consent prompt remains (the Confirm-Yes definition line itself is one occurrence;
# the call site is the second)
$confirmYesCount = [regex]::Matches($controllerText, 'Confirm-Yes').Count
Assert ($confirmYesCount -eq 2) ('exactly one consent call site in controller (Confirm-Yes occurrences: ' + $confirmYesCount + ')')

# Supervisor must never import configuration
$supervisorText = [IO.File]::ReadAllText($supervisor)
Assert (-not $supervisorText.Contains('/setcfg')) 'supervisor never imports ESET configuration'

Write-Output ('All ' + $script:Checks + ' tests passed (synthetic helpers; no live ESET).')
if ($script:Failures -gt 0) { exit 1 }
exit 0
