$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Kit.Helpers.ps1')
$count = 0
function Assert([bool]$ok, [string]$name) {
    if (-not $ok) { throw ('FAIL: ' + $name) }
    $script:count++; Write-Output ('PASS: ' + $name)
}
function Assert-Throws([scriptblock]$action, [string]$name) {
    $threw = $false
    try { & $action | Out-Null } catch { $threw = $true }
    Assert $threw $name
}
$h = 'a' * 64
$m = ConvertFrom-SafeManifest "$h  a.txt`n" @('a.txt')
Assert ($m['a.txt'] -eq $h) 'valid manifest'
foreach ($bad in @("$h  ../a.txt", "$h  C:\a.txt", "$h  a.txt`n$h  a.txt", "$h  a.txt`n$h  extra.txt", 'bogus')) {
    Assert-Throws { ConvertFrom-SafeManifest $bad @('a.txt') } 'reject unsafe/duplicate/extra manifest'
}
Assert-Throws { ConvertFrom-SafeManifest "$h  a.txt" @('a.txt','missing.txt') } 'reject missing member'
$a = '<Root><Rules/><Keep>one</Keep></Root>'
$b = '<Root><Rules><Rule name="test"><Target path="C:\Test\x.exe"/></Rule></Rules><Keep>one</Keep></Root>'
$c = '<Root><Rules/><Keep>two</Keep></Root>'
Assert ((Compare-SafeXml $a $a).Kind -eq 'NO_CHANGE') 'exact XML equality'
Assert ((Compare-SafeXml $a $b).Kind -eq 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE') 'inserted complete subtree candidate'
Assert ((Compare-SafeXml $a $c).Kind -eq 'UNEXPLAINED_DIFFERENCE') 'unrelated change rejected'
Assert ((Compare-SafeXml '<x><![CDATA[a]]></x>' '<x><![CDATA[b]]></x>').Kind -eq 'UNEXPLAINED_DIFFERENCE') 'CDATA change not silently ignored'
Assert ((Compare-SafeXml '<x xmlns="urn:a"/>' '<x xmlns="urn:b"/>').Kind -eq 'UNEXPLAINED_DIFFERENCE') 'namespace change not silently ignored'
Assert-Throws { Get-SafeXmlTree '<!DOCTYPE x [<!ENTITY e SYSTEM "file:///not-read">]><x>&e;</x>' } 'DTD prohibited'
Assert ((Get-OverallTruth @('PASS')).Overall -eq 'UNVERIFIED') 'observations never architecture PASS'
Assert ((Get-OverallTruth @('FAIL','UNVERIFIED')).Overall -eq 'FAIL') 'failure preserved'
Assert ((Get-OverallTruth @()).Overall -eq 'UNVERIFIED') 'empty evidence not pass'
foreach ($f in @(Get-ChildItem $root -Filter '*.ps1') + @(Get-Item $PSCommandPath)) {
    $tok = $null; $err = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tok,[ref]$err)
    Assert ($err.Count -eq 0) ('parse ' + $f.Name)
    Assert (@([IO.File]::ReadAllBytes($f.FullName) | Where-Object { $_ -gt 127 }).Count -eq 0) ('ASCII ' + $f.Name)
}
$bat = [IO.File]::ReadAllText((Join-Path $root 'Run-EsetHipsPoc.bat'))
Assert (-not $bat.Replace("`r`n",'').Contains("`n")) 'BAT all CRLF'
Assert (-not $bat.Contains('AllSigned')) 'unsigned owner kit launcher usable'
$exe = (Get-Process -Id $PID).Path
$out = Invoke-CapturedProcess -FilePath $exe -ArgumentList @('-NoProfile','-Command','[Console]::Write("out"); [Console]::Error.Write("err"); exit 7') -TimeoutSeconds 15
Assert ($out.ExitCode -eq 7 -and $out.Stdout -eq 'out' -and $out.Stderr -eq 'err') 'real process stdout stderr exit captured'
Assert-Throws { Invoke-CapturedProcess -FilePath $exe -ArgumentList @('-NoProfile','-Command','Start-Sleep 5') -TimeoutSeconds 1 -KillOnTimeout } 'real process timeout fails'
Assert ((ConvertTo-NativeArgument 'with space') -eq '"with space"') 'native argument space quoting'
$launcher = [IO.File]::ReadAllText((Join-Path $root 'Launch-Kit.ps1'))
Assert ($launcher.Contains('Revision = [int]')) 'numeric revision ordering'
$case = Join-Path $PSScriptRoot ('case-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $case)
try {
    if ($env:OS -eq 'Windows_NT') {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        Set-PrivateAcl $case $sid
        $file = Join-Path $case 'private.txt'
        'synthetic' | Set-Content -LiteralPath $file -Encoding ASCII
        Set-PrivateAcl $file $sid
        Assert ((Get-Acl -LiteralPath $case).AreAccessRulesProtected) 'real Windows private directory ACL'
        Assert ((Get-Acl -LiteralPath $file).AreAccessRulesProtected) 'real Windows private file ACL'
        Assert-Throws { Assert-SafeLocalPath '\\server\share\x' } 'UNC rejected'
        Assert-Throws { Assert-SafeLocalPath 'C:\OneDrive\x' } 'synced path rejected'
    }
    $controller = Join-Path $root 'Invoke-EsetHipsPoc.v2026-10-08.4.ps1'
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($controller,[ref]$tokens,[ref]$errors)
    $save = $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Save-Evidence'},$true)[0]
    Invoke-Expression $save.Extent.Text
    $script:Evidence = $case; $RuleName = 'LOLRMM POC TEST - LolrmmEsetTest'
    $script:Checks = New-Object 'System.Collections.Generic.List[object]'
    $script:Checks.Add([pscustomobject]@{name='fixture';status='OWNER_REPORTED';detail='Safe fixed message.'})
    $script:Report = [ordered]@{environment=@{private='SECRET_FIXTURE_USERNAME'};diagnostics=@('SECRET_FIXTURE_PASSWORD');cleanup_unresolved=$false;steps=@();status='UNVERIFIED';finished=$null}
    $script:XmlDiffKind = 'NOT_COMPUTED'; $script:RuleDiffWritten = $false
    Save-Evidence
    $share = [IO.File]::ReadAllText((Join-Path $case 'RESULTS.txt')) + [IO.File]::ReadAllText((Join-Path $case 'sanitized-rule-diff.txt'))
    Assert (-not $share.Contains('SECRET_FIXTURE')) 'real report writer excludes private fixture fields'
    $json = Get-Content -LiteralPath (Join-Path $case 'result.json') -Raw | ConvertFrom-Json
    Assert ($json.status -eq 'UNVERIFIED' -and $json.steps.Count -eq 1) 'real report writer serializes truthful result'
} finally { Remove-Item -LiteralPath $case -Recurse -Force }
Write-Output ('All ' + $count + ' tests passed (synthetic helpers; no live ESET).')
