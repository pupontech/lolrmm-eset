# Focused regressions for boundaries missed by the initial helper suite.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../poc/quick-rules/Eset-QuickRules.ps1') -FunctionsOnly
$errors=New-Object 'System.Collections.Generic.List[string]'
function Check([string]$Name,[scriptblock]$Body) { try { & $Body; Write-Output ('PASS: '+$Name) } catch { $errors.Add(($Name+': '+$_.Exception.Message)); Write-Output ('FAIL: '+$Name+': '+$_.Exception.Message) } }
Check 'whitespace-only leaf values remain distinct' {
    $a=ConvertFrom-QuickXmlText '<Root><Value> </Value></Root>'
    $b=ConvertFrom-QuickXmlText '<Root><Value/></Root>'
    if ((Get-QuickCanonicalXml $a) -ceq (Get-QuickCanonicalXml $b)) { throw 'Preservation comparison erased a whitespace-only value.' }
}
Check 'xml:space significant whitespace remains distinct' {
    $a=ConvertFrom-QuickXmlText '<Root xml:space="preserve"><Value> </Value></Root>'
    $b=ConvertFrom-QuickXmlText '<Root xml:space="preserve"><Value/></Root>'
    if ((Get-QuickCanonicalXml $a) -ceq (Get-QuickCanonicalXml $b)) { throw 'Preservation comparison erased significant whitespace.' }
}
Check 'post-apply success presentation executes as PowerShell' {
    $file=Join-Path $PSScriptRoot '../poc/quick-rules/Eset-QuickRules.ps1'
    $ast=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file),[ref]$null,[ref]$null)
    $command=@($ast.FindAll({ param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Extent.Text.Contains('Transaction status: ') },$true))[0]
    $result=[pscustomobject]@{AddedCount=0}
    & ([scriptblock]::Create($command.Extent.Text))
}
Check 'successful script explicitly clears a caller stale native exit code' {
    $file=Join-Path $PSScriptRoot '../poc/quick-rules/Eset-QuickRules.ps1'
    $source=[IO.File]::ReadAllText((Resolve-Path $file))
    $tail=$source.Substring($source.IndexOf('if ($FunctionsOnly)'))
    $harness=Join-Path ([IO.Path]::GetTempPath()) ('quick-exit-'+[guid]::NewGuid().ToString('N')+'.ps1')
    $caller=$harness+'.caller.ps1'
    try {
        $setup='param(); $FunctionsOnly=$false; $RulesFile=""; $ConfigurationFile=""; $Apply=$false; $IAmOnATestMachine=$false; $SignToolPath=""; function Invoke-QuickRulesMain { }; $global:LASTEXITCODE=7; '+$tail
        [IO.File]::WriteAllText($harness,$setup)
        [IO.File]::WriteAllText($caller, ('& '''+$harness.Replace("'","''")+''' ; exit $LASTEXITCODE'))
        $hostExe=(Get-Process -Id $PID).Path
        & $hostExe -NoProfile -File $caller
        if ($LASTEXITCODE -ne 0) { throw ('Successful entrypoint retained native exit '+$LASTEXITCODE) }
    } finally { Remove-Item -LiteralPath $harness,$caller -Force }
}
if ($errors.Count) { throw ('Boundary regression failures: '+($errors -join '; ')) }
Write-Output 'All focused boundary regressions passed; synthetic/source execution only.'
