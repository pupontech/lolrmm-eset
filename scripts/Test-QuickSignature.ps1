# Offline signer-format regressions. Format/content checks, not crypto validation.
[CmdletBinding()]
param([string]$BeforeFixture,[string]$SignedFixture)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../poc/quick-rules/Eset-QuickRules.ps1') -FunctionsOnly
$base=ConvertFrom-QuickXmlText '<ESET><VALUE> </VALUE></ESET>'
$signature=[Convert]::ToBase64String((New-Object byte[] 64))
function Reject([string]$Xml) {
    $rejected=$false
    try { Assert-QuickSignedPayload -Before $base -Signed (ConvertFrom-QuickXmlText $Xml) } catch { $rejected=$true }
    if(-not $rejected) { throw 'Unsafe signature/payload change accepted.' }
}
Assert-QuickSignedPayload -Before $base -Signed (ConvertFrom-QuickXmlText ($base.OuterXml+'<!-- Signature: '+$signature+' -->'))
Reject $base.OuterXml
Reject ($base.OuterXml+'<!-- unrelated -->')
Reject ($base.OuterXml+'<!-- Signature: AAAA -->')
Reject ($base.OuterXml+'<!-- Signature: '+$signature+' --><!-- Signature: '+$signature+' -->')
Reject ('<ESET><VALUE/></ESET><!-- Signature: '+$signature+' -->')
Reject ('<ESET><!-- Signature: '+$signature+' --><VALUE> </VALUE></ESET>')
Reject ($base.OuterXml+'<!-- changed --><!-- Signature: '+$signature+' -->')
if($BeforeFixture -or $SignedFixture) {
    if(-not ($BeforeFixture -and $SignedFixture)) { throw 'Both fixture paths required.' }
    Assert-QuickSignedPayload -Before (Read-QuickXmlFile $BeforeFixture) -Signed (Read-QuickXmlFile $SignedFixture)
    Write-Output 'REAL_SIGNED_PUBLIC_FIXTURE_CONTENT_PASS: vendor content unchanged except exact signature comment.'
}
Write-Output 'PASS: signature required, exactly one trailing observed-format comment, all other XML preserved.'
