# Additional behavioral regression cases; all XML/providers are synthetic.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../poc/quick-rules/Eset-QuickRules.ps1') -FunctionsOnly
function Config { return (ConvertFrom-QuickXmlText '<ESET><PRODUCT NAME="home" VERSION="19.99.synthetic"><ITEM NAME="plugins"><ITEM NAME="01000001"><ITEM NAME="settings"><ITEM NAME="rules"/></ITEM></ITEM></ITEM></PRODUCT></ESET>') }
$fail=0
$doc=Config
$want=@([pscustomobject]@{Name='Tool';Path='C:\Tools\One.exe'})
$plan=Get-QuickRulesPlan -Desired $want -Configuration $doc
$payload=New-QuickAppendPayload -Configuration $doc -Additions $plan.Additions
$rules=(Get-QuickHipsContext $doc).Collection
foreach($node in (Get-QuickHipsContext $payload).Rules) { [void]$rules.AppendChild($doc.ImportNode($node,$true)) }
try {
    $again=Get-QuickRulesPlan -Desired @([pscustomobject]@{Name='Tool';Path='c:\tools\one.EXE'}) -Configuration $doc
    if($again.Additions.Count -ne 0 -or $again.Unchanged.Count -ne 1) { throw 'Case-only rerun did not produce a no-op.' }
    Write-Output 'PASS: case-only target spelling remains UNCHANGED'
} catch { $fail++; Write-Output ('FAIL: case-only target spelling: '+$_.Exception.Message) }
$root=Join-Path ([IO.Path]::GetTempPath()) ('quick-integrity-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try {
    $state=@{Xml=(Config).OuterXml;Exports=0;Imports=0;Root=$root}
    $providers=@{
        Export={param($path)
            $state.Exports++
            if($state.Exports -eq 2) {
                $p=Join-Path $state.Root 'append-payload.xml'
                [IO.File]::AppendAllText($p,"`n<!-- changed after signing check -->")
            }
            [IO.File]::WriteAllText($path,$state.Xml)
            return [pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}
        }.GetNewClosure()
        Sign={param($path) return [pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}}
        Import={param($path) $state.Imports++; return [pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}}.GetNewClosure()
    }
    try { $null=Invoke-QuickApplyTransaction -Desired $want -Providers $providers -RunRoot $root -TestOnlyProvider } catch { }
    if($state.Exports -lt 2 -or $state.Imports -ne 0) { $fail++; Write-Output ('FAIL: modified payload reached import; exports='+$state.Exports+'; imports='+$state.Imports) }
    else { Write-Output 'PASS: signed payload mutation during concurrency export prevents import' }
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
if($fail) { throw ('Additional regression failures: '+$fail) }
Write-Output 'All additional regressions passed; no real ESET commands executed.'
