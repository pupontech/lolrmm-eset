#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][string]$CallerSid,
    [Parameter(Mandatory=$true)][string]$RuleName,
    [int]$RuleAppearTimeoutSeconds = 1800,
    [int]$RemovalTimeoutSeconds = 1800,
    [int]$PollSeconds = 20,
    [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Kit.Helpers.ps1')
# Elevated supervisor: performs ALL ecmd exports for one run under a single
# UAC approval. Detects the manually created test rule by polling exports,
# waits for the controller's block-done signal, then detects rule removal by
# requiring an after-removal export byte-identical to the baseline. Fail-closed
# on every unexpected state; never imports or modifies ESET configuration.
function Write-VerdictJson {
    param([string]$Folder, [string]$Name, [hashtable]$Payload)
    $path = Join-Path $Folder ($Name + '.json')
    $payload.schema = 1
    $payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8
}
function Test-SupervisorEnvironment {
    param([string]$RunId, [string]$CallerSid)
    if ($env:OS -ne 'Windows_NT') { throw 'Windows required.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'ESET export supervisor is not elevated.' }
    if ($identity.User.Value -cne $CallerSid) { throw 'UAC account differs from invoking account; refusing.' }
    if ($RunId -cnotmatch '^[0-9a-f]{32}$') { throw 'Invalid run identifier.' }
    $folder = Assert-SafeLocalPath (Join-Path (Join-Path $env:USERPROFILE 'LOLRMM-Evidence') $RunId)
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw 'Evidence folder missing.' }
    Set-PrivateAcl $folder $CallerSid
    return $folder
}
function Invoke-ExportSnapshot {
    param([string]$Folder, [string]$CallerSid, [string]$OutName)
    if (@(Get-Process -Name ecmd -ErrorAction SilentlyContinue).Count -gt 0) { throw 'ecmd still running; configuration state unknown.' }
    $ecmd = Assert-SafeLocalPath (Join-Path $env:ProgramFiles 'ESET\ESET Security\ecmd.exe')
    if (-not (Test-Path -LiteralPath $ecmd -PathType Leaf)) { throw 'ESET Security ecmd.exe not found.' }
    $sig = Get-AuthenticodeSignature -LiteralPath $ecmd
    if ($sig.Status -ne 'Valid' -or $null -eq $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch 'ESET') { throw 'ecmd does not have a valid ESET Authenticode signature.' }
    $temp = Join-Path $Folder ($OutName + '.tmp-' + [guid]::NewGuid().ToString('N'))
    try {
        $process = Invoke-CapturedProcess -FilePath $ecmd -ArgumentList @('/getcfg', $temp) -TimeoutSeconds 90
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $temp -PathType Leaf)) { throw ('ecmd export failed; details retained privately. Exit code: ' + $process.ExitCode) }
        $item = Get-Item -LiteralPath $temp
        if ($item.Length -eq 0 -or $item.Length -gt 16777216) { throw 'Export empty or exceeds 16 MiB.' }
        [void](Get-SafeXmlTree ([IO.File]::ReadAllText($temp)))
        Set-PrivateAcl $temp $CallerSid
        $dest = Join-Path $Folder $OutName
        Move-Item -LiteralPath $temp -Destination $dest -Force
        return $dest
    } catch {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
        throw
    }
}
function Get-HipsStateFromXml {
    param([System.Xml.XmlDocument]$Doc, [string]$RuleName)
    # Heuristic machine detection of HIPS state from the private baseline
    # export. Three evidence classes only:
    #   1. attribute values of an element whose LOCALNAME matches /hips/i
    #      (the rule-name value is always skipped);
    #   2. direct text/CDATA under an element whose LOCALNAME matches /hips/i;
    #   3. sibling pairing <NAME>HipsEnabled</NAME><VALUE>1</VALUE> where the
    #      NAME text matches /hips/i.
    # A conclusive state requires at least one boolean-ish value and no
    # contradicting one; anything else is UNDETECTABLE and the caller stops.
    # Values under unrelated child elements are deliberately NOT traversed:
    # an unrelated <SomethingElse>1</SomethingElse> under a hips-named element
    # must not count as HIPS state.
    $trueVals = @('1', 'true', 'enabled', 'on', 'yes')
    $falseVals = @('0', 'false', 'disabled', 'off', 'no')
    $sawTrue = $false; $sawFalse = $false
    $pendingName = $null
    $all = @($Doc.SelectNodes('//*'))
    for ($i = 0; $i -lt $all.Count; $i++) {
        $el = $all[$i]
        $local = [string]$el.LocalName
        $nameMatches = $local -imatch 'hips'
        if ($null -ne $el.Attributes) {
            foreach ($attr in $el.Attributes) {
                $av = [string]$attr.Value
                if ($av -ceq $RuleName) { continue }
                if ($nameMatches) {
                    $low = $av.ToLowerInvariant()
                    if ($trueVals -contains $low) { $sawTrue = $true }
                    elseif ($falseVals -contains $low) { $sawFalse = $true }
                }
            }
        }
        if ($nameMatches) {
            foreach ($child in @($el.ChildNodes)) {
                $type = [int]$child.NodeType
                if ($type -eq 3 -or $type -eq 4) {
                    $value = [string]$child.Value
                    if ($value -ceq $RuleName) { continue }
                    $low = $value.ToLowerInvariant()
                    if ($trueVals -contains $low) { $sawTrue = $true }
                    elseif ($falseVals -contains $low) { $sawFalse = $true }
                }
            }
        }
        if ($local -ieq 'name') {
            $text = ''
            foreach ($child in @($el.ChildNodes)) {
                if ([int]$child.NodeType -eq 3) { $text += [string]$child.Value }
            }
            if ($text -imatch 'hips') { $pendingName = $text } else { $pendingName = $null }
        } elseif ($local -ieq 'value') {
            if ($null -ne $pendingName) {
                $text = ''
                foreach ($child in @($el.ChildNodes)) {
                    $type = [int]$child.NodeType
                    if ($type -eq 3 -or $type -eq 4) { $text += [string]$child.Value }
                }
                $low = $text.ToLowerInvariant()
                if ($trueVals -contains $low) { $sawTrue = $true }
                elseif ($falseVals -contains $low) { $sawFalse = $true }
            }
            $pendingName = $null
        } else {
            $pendingName = $null
        }
    }
    if ($sawTrue -and -not $sawFalse) { return 'enabled' }
    if ($sawFalse -and -not $sawTrue) { return 'disabled' }
    return 'undetectable'
}
function Get-RuleNameCollisionCount {
    param([System.Xml.XmlDocument]$Doc, [string]$RuleName)
    $count = 0
    foreach ($el in $Doc.SelectNodes('//*')) {
        if ($null -ne $el.Attributes) {
            foreach ($attr in $el.Attributes) {
                if ([string]$attr.Value -ceq $RuleName) { $count++ }
            }
        }
    }
    return $count
}
function Test-RuleAppearance {
    param([string]$BaselinePath, [string]$CandidatePath, [string]$RuleName)
    $baseline = [IO.File]::ReadAllText($BaselinePath)
    $candidate = [IO.File]::ReadAllText($CandidatePath)
    if ($candidate -ceq $baseline) { return 'absent' }
    $diff = Compare-SafeXml $baseline $candidate
    $nameCount = Get-RuleNameCollisionCount (Get-SafeXmlTree $candidate) $RuleName
    if ($diff.Kind -eq 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE') {
        if ($nameCount -eq 1) { return 'ready' }
        return 'unexpected'
    }
    if ($nameCount -ge 1) { return 'unexpected' }
    return 'absent'
}
function Test-RuleRemoval {
    param([string]$BaselinePath, [string]$CandidatePath, [string]$RuleName)
    # Removal is proven when the candidate equals the baseline after volatile
    # counters (firewall HitCount/LastUseTime etc.) are stripped: the rule
    # name is gone AND nothing else structurally changed. Raw byte identity
    # is impossible on real ESET exports because usage counters churn.
    $baselineDoc = Remove-VolatileXmlNoise (Get-SafeXmlTree ([IO.File]::ReadAllText($BaselinePath)))
    $candidateDoc = Remove-VolatileXmlNoise (Get-SafeXmlTree ([IO.File]::ReadAllText($CandidatePath)))
    $baselineText = [string]$baselineDoc.OuterXml
    $candidateText = [string]$candidateDoc.OuterXml
    if ($candidateText -ceq $baselineText) { return 'done' }
    $diff = Compare-SafeXml $baselineText $candidateText
    if ($diff.Kind -eq 'NO_CHANGE' -or $diff.Kind -eq 'ORDER_OR_FORMATTING_ONLY_UNVERIFIED') { return 'done' }
    $nameCount = Get-RuleNameCollisionCount (Get-SafeXmlTree $candidateText) $RuleName
    if ($nameCount -gt 0) { return 'pending' }
    return 'pending'
}
if ($SelfTest) { return }
$script:CleanupUnresolved = $false
try {
    $folder = Test-SupervisorEnvironment -RunId $RunId -CallerSid $CallerSid
    $baseline = Invoke-ExportSnapshot -Folder $folder -CallerSid $CallerSid -OutName 'baseline.xml'
    $baselineDoc = Get-SafeXmlTree ([IO.File]::ReadAllText($baseline))
    $hipsState = Get-HipsStateFromXml -Doc $baselineDoc -RuleName $RuleName
    $collisions = Get-RuleNameCollisionCount -Doc $baselineDoc -RuleName $RuleName
    if ($collisions -gt 0) {
        $script:CleanupUnresolved = $false
        Write-VerdictJson -Folder $folder -Name 'baseline-verdict' -Payload @{ hips = $hipsState; ruleNameCollisions = $collisions }
        throw ('Baseline already contains ' + $collisions + ' occurrence(s) of the exact test rule name. Nothing was created by this kit.')
    }
    if ($hipsState -ne 'enabled') {
        $script:CleanupUnresolved = $false
        Write-VerdictJson -Folder $folder -Name 'baseline-verdict' -Payload @{ hips = $hipsState; ruleNameCollisions = $collisions }
        throw ('Machine detection could not confirm HIPS enabled (state: ' + $hipsState + '). Stopping before any rule work; no rule was created.')
    }
    Write-VerdictJson -Folder $folder -Name 'baseline-verdict' -Payload @{ hips = $hipsState; ruleNameCollisions = 0 }
    # Phase 2: wait for the owner to create the exact rule in the ESET UI.
    $deadline = (Get-Date).AddSeconds($RuleAppearTimeoutSeconds)
    $ready = $false
    $poll = 0
    while ((Get-Date) -lt $deadline) {
        $poll++
        $snapshot = Invoke-ExportSnapshot -Folder $folder -CallerSid $CallerSid -OutName ('poll-' + $poll + '.xml')
        $state = Test-RuleAppearance -BaselinePath $baseline -CandidatePath $snapshot -RuleName $RuleName
        if ($state -eq 'ready') {
            Move-Item -LiteralPath $snapshot -Destination (Join-Path $folder 'with-rule.xml') -Force
            Write-VerdictJson -Folder $folder -Name 'with-rule-verdict' -Payload @{ classification = 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE'; addedRootCount = 1; nameMatch = $true }
            $ready = $true
            break
        }
        if ($state -eq 'unexpected') {
            $script:CleanupUnresolved = $true
            Remove-Item -LiteralPath $snapshot -Force
            throw 'Unexpected configuration change detected while waiting for the test rule. Inspect the HIPS rules editor and remove ONLY what you created; manual cleanup required.'
        }
        Remove-Item -LiteralPath $snapshot -Force
        Start-Sleep -Seconds $PollSeconds
    }
    if (-not $ready) {
        $script:CleanupUnresolved = $false
        throw 'Rule was not created within the wait window. Nothing was created by this kit; baseline export retained privately.'
    }
    # Phase 3: wait for the controller's block-done signal while watching for
    # premature rule removal.
    $deadline = (Get-Date).AddSeconds($RuleAppearTimeoutSeconds)
    $blockDone = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath (Join-Path $folder 'block-done.json')) { $blockDone = $true; break }
        $poll++
        $snapshot = Invoke-ExportSnapshot -Folder $folder -CallerSid $CallerSid -OutName ('poll-' + $poll + '.xml')
        $state = Test-RuleAppearance -BaselinePath $baseline -CandidatePath $snapshot -RuleName $RuleName
        Remove-Item -LiteralPath $snapshot -Force
        if ($state -eq 'unexpected') { $script:CleanupUnresolved = $true; throw 'Unexpected configuration change while waiting for the block test to complete.' }
        if ($state -eq 'absent') { $script:CleanupUnresolved = $true; throw 'Rule disappeared before the block test completed; block evidence is invalid. Manual inspection required.' }
        Start-Sleep -Seconds $PollSeconds
    }
    if (-not $blockDone) {
        $script:CleanupUnresolved = $true
        throw 'Block test did not report completion in time. Manual inspection of the test rule is required.'
    }
    # Phase 4: wait for the owner to remove the rule; removal is proven by an
    # export byte-identical to the baseline.
    $deadline = (Get-Date).AddSeconds($RemovalTimeoutSeconds)
    $done = $false
    while ((Get-Date) -lt $deadline) {
        $poll++
        $snapshot = Invoke-ExportSnapshot -Folder $folder -CallerSid $CallerSid -OutName ('poll-' + $poll + '.xml')
        $state = Test-RuleRemoval -BaselinePath $baseline -CandidatePath $snapshot -RuleName $RuleName
        if ($state -eq 'done') {
            Move-Item -LiteralPath $snapshot -Destination (Join-Path $folder 'removed.xml') -Force
            Write-VerdictJson -Folder $folder -Name 'removed-verdict' -Payload @{ structurallyIdenticalAfterVolatileStrip = $true }
            $done = $true
            break
        }
        Remove-Item -LiteralPath $snapshot -Force
        Start-Sleep -Seconds $PollSeconds
    }
    if (-not $done) {
        $script:CleanupUnresolved = $true
        throw 'Removal was not proven within the wait window: no export structurally identical to the baseline after volatile-counter stripping. Manual inspection of the test rule is required.'
    }
    exit 0
} catch {
    Write-VerdictJson -Folder (Join-Path (Join-Path $env:USERPROFILE 'LOLRMM-Evidence') $RunId) -Name 'abort' -Payload @{ reason = $_.Exception.Message; cleanupUnresolved = $script:CleanupUnresolved }
    exit 1
}
