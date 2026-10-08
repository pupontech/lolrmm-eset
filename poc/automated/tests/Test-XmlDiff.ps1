#requires -Version 5.1
Set-StrictMode -Version 2.0
# Self-contained verification for the O(n) Compare-SafeXml replacement.
# Exits nonzero on any failure; prints PASS lines; no Pester.
$ErrorActionPreference = 'Stop'

$helpersPath = Join-Path $PSScriptRoot '../Kit.Helpers.ps1'
if (-not (Test-Path -LiteralPath $helpersPath)) { throw ('Helpers not found: ' + $helpersPath) }
. $helpersPath

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

# ---------- test 1: existing Test-Kit.ps1 assertions still hold ----------
$a = '<Root><Rules/><Keep>one</Keep></Root>'
$b = '<Root><Rules><Rule name="test"><Target path="C:\Test\x.exe"/></Rule></Rules><Keep>one</Keep></Root>'
$c = '<Root><Rules/><Keep>two</Keep></Root>'
Assert ((Compare-SafeXml $a $a).Kind -eq 'NO_CHANGE') 't1 same-document NO_CHANGE'
Assert ((Compare-SafeXml $a $b).Kind -eq 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE') 't1 single complete-subtree insertion'
Assert ((Compare-SafeXml $a $c).Kind -eq 'UNEXPLAINED_DIFFERENCE') 't1 one->two text change UNEXPLAINED'
Assert ((Compare-SafeXml '<x><![CDATA[a]]></x>' '<x><![CDATA[b]]></x>').Kind -eq 'UNEXPLAINED_DIFFERENCE') 't1 CDATA a->b UNEXPLAINED'
Assert ((Compare-SafeXml '<x xmlns="urn:a"/>' '<x xmlns="urn:b"/>').Kind -eq 'UNEXPLAINED_DIFFERENCE') 't1 xmlns urn:a->urn:b UNEXPLAINED'

$d = Compare-SafeXml $a $b
Assert ($d.AddedElements -eq 2) 't1 single insertion counts 2 element instances'
Assert ($d.RemovedElements -eq 0 -and $d.ChangedElements -eq 0) 't1 zero removals/modifications'
Assert ($d.AddedRootCount -eq 1) 't1 AddedRootCount is 1'
Assert ($d.AddedRoots[0].Path -eq '/Root/Rules/Rule') 't1 AddedRoot path is name-only'
Assert (@($d.AddedRoots[0].AttributeNames) -join ',' -eq 'name') 't1 AttributeNames carries names only'
Assert ($d.AddedRoots[0].LineHint -eq '') 't1 LineHint reserved empty'
Assert ($d.ElementsBefore -eq 3 -and $d.ElementsAfter -eq 5) 't1 element totals'

# ---------- fixture builder: large document with several sibling rule-like subtrees ----------
function New-LargeXml([bool]$withInsert) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0" encoding="utf-8"?>')
    [void]$sb.Append('<EsetExport>')
    [void]$sb.Append('<Settings><Version>11.0</Version><Language>en-US</Language></Settings>')
    [void]$sb.Append('<HipsRules>')
    for ($i = 0; $i -lt 8000; $i++) {
        [void]$sb.Append('<HipsRule name="L0' + $i + '" enabled="1"><Source>any</Source><Target>C:\Program\L' + $i + '.exe</Target></HipsRule>')
    }
    for ($i = 0; $i -lt 17000; $i++) {
        [void]$sb.Append('<Exclusion signature="S' + $i + '"><Path>C:\Temp\s' + $i + '</Path></Exclusion>')
    }
    if ($withInsert) {
        [void]$sb.Append('<HipsRule name="LOLRMM POC TEST - LolrmmEsetTest" enabled="1"><Source>any</Source><Target>C:\Users\Public\lolrmm-eset-test.exe</Target></HipsRule>')
    }
    [void]$sb.Append('</HipsRules>')
    [void]$sb.Append('<Log><Entries>')
    for ($i = 0; $i -lt 12000; $i++) {
        [void]$sb.Append('<Entry id="' + $i + '" level="info"><Message>log record ' + $i + '</Message></Entry>')
    }
    [void]$sb.Append('</Entries></Log>')
    [void]$sb.Append('<Nested>')
    for ($i = 0; $i -lt 220; $i++) { [void]$sb.Append('<Level>') }
    [void]$sb.Append('<Leaf/>')
    for ($i = 0; $i -lt 220; $i++) { [void]$sb.Append('</Level>') }
    [void]$sb.Append('</Nested>')
    [void]$sb.Append('</EsetExport>')
    return $sb.ToString()
}
$largeBefore = New-LargeXml $false
$largeWithInsert = New-LargeXml $true
Assert ($largeWithInsert.Length -lt 16777216) 't2 fixture under 16 MiB cap'
# prove the fixture would be rejected by the old 2000-element cap
$treeCount = [regex]::Matches($largeBefore, '<[A-Za-z][^>/]*>').Count
Assert ($treeCount -gt 2000) 't2 fixture exceeds 2000 elements (old cap would reject)'

# ---------- test 2: single inserted subtree inside a large document ----------
$d = Compare-SafeXml -Before $largeBefore -After $largeWithInsert
Assert ($d.Kind -eq 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE') 't2 large single insertion classified'
Assert ($d.AddedRootCount -eq 1) 't2 exactly one added root'
Assert ($d.AddedRoots[0].Path -eq '/EsetExport/HipsRules/HipsRule') 't2 added root path'
Assert ($d.AddedRoots[0].LocalName -eq 'HipsRule') 't2 added root local name'
Assert ($d.ElementsAfter -gt 2000) 't2 ElementsAfter exceeds 2000 (cap-free proof)'
Assert ($d.AddedElements -eq 3 -and $d.RemovedElements -eq 0 -and $d.ChangedElements -eq 0) 't2 counts one added subtree (3 element instances)'
$largeWithInsertDiffResult = $d

# ---------- test 3: whitespace/indentation change only ----------
function New-IndentedXml([string]$indent) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0" encoding="utf-8"?>' + $indent)
    [void]$sb.Append('<EsetExport>' + $indent)
    [void]$sb.Append('<Settings><Version>11.0</Version></Settings>' + $indent)
    [void]$sb.Append('<HipsRules>')
    for ($i = 0; $i -lt 9000; $i++) {
        [void]$sb.Append('<HipsRule name="L0' + $i + '"><Source>any</Source><Target>C:\Program\L' + $i + '</Target></HipsRule>' + $indent)
    }
    [void]$sb.Append('</HipsRules>' + $indent)
    [void]$sb.Append('</EsetExport>')
    return $sb.ToString()
}
$plain = New-IndentedXml ''
$pretty = New-IndentedXml "`n  "
Assert ($plain -cne $pretty) 't3 fixtures genuinely differ as bytes'
$d = Compare-SafeXml -Before $plain -After $pretty
Assert ($d.Kind -eq 'ORDER_OR_FORMATTING_ONLY_UNVERIFIED') 't3 whitespace-only diff classified'
Assert ($d.AddedElements -eq 0 -and $d.RemovedElements -eq 0 -and $d.ChangedElements -eq 0) 't3 zero structural delta'

# ---------- test 4: one existing attribute value changed ----------
# NOTE: a [string] parameter coerces $false to 'False' (truthy!). Use [bool].
function New-AttrChangedXml([bool]$rename) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<EsetExport><HipsRules>')
    for ($i = 0; $i -lt 9000; $i++) {
        $name = 'L0' + $i
        if ($rename -and $i -eq 4500) { $name = $name + '-X' }
        [void]$sb.Append('<HipsRule name="' + $name + '"><Source>any</Source></HipsRule>')
    }
    [void]$sb.Append('</HipsRules></EsetExport>')
    return $sb.ToString()
}
$attrBefore = New-AttrChangedXml $false
$attrAfter  = New-AttrChangedXml $true
$d = Compare-SafeXml -Before $attrBefore -After $attrAfter
Assert ($d.Kind -eq 'UNEXPLAINED_DIFFERENCE') 't4 attribute value change UNEXPLAINED'
Assert ($d.ChangedElements -ge 1) 't4 ChangedElements >= 1'
Assert ($d.AddedElements -gt 0 -and $d.RemovedElements -gt 0) 't4 modification counts added+removed'

# ---------- test 5: one subtree deleted ----------
function New-DeletionXml([bool]$withTarget) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<EsetExport><HipsRules>')
    for ($i = 0; $i -lt 9000; $i++) {
        [void]$sb.Append('<HipsRule name="L0' + $i + '"><Source>any</Source></HipsRule>')
    }
    if ($withTarget) {
        [void]$sb.Append('<HipsRule name="TARGET"><Source>any</Source><Target>C:\x.exe</Target></HipsRule>')
    }
    [void]$sb.Append('</HipsRules></EsetExport>')
    return $sb.ToString()
}
$delBefore = New-DeletionXml $true
$delAfter  = New-DeletionXml $false
$d = Compare-SafeXml -Before $delBefore -After $delAfter
Assert ($d.Kind -eq 'UNEXPLAINED_DIFFERENCE') 't5 deletion UNEXPLAINED'
Assert ($d.AddedRootCount -eq 0) 't5 AddedRootCount 0 on deletion'
Assert ($d.RemovedElements -gt 0) 't5 RemovedElements > 0'

# ---------- test 6: two subtrees inserted ----------
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append('<EsetExport><HipsRules>')
for ($i = 0; $i -lt 9000; $i++) {
    [void]$sb.Append('<HipsRule name="L0' + $i + '"><Source>any</Source></HipsRule>')
}
[void]$sb.Append('</HipsRules></EsetExport>')
$twoBefore = $sb.ToString()
$sb2 = New-Object System.Text.StringBuilder
[void]$sb2.Append('<EsetExport><HipsRules>')
for ($i = 0; $i -lt 9000; $i++) {
    [void]$sb2.Append('<HipsRule name="L0' + $i + '"><Source>any</Source></HipsRule>')
}
[void]$sb2.Append('<HipsRule name="NEW1"><Source>any</Source></HipsRule>')
[void]$sb2.Append('<HipsRule name="NEW2"><Source>any</Source></HipsRule>')
[void]$sb2.Append('</HipsRules></EsetExport>')
$twoAfter = $sb2.ToString()
$d = Compare-SafeXml -Before $twoBefore -After $twoAfter
Assert ($d.Kind -eq 'MULTIPLE_SUBTREE_INSERTIONS') 't6 two insertions classified'
Assert ($d.AddedRootCount -eq 2) 't6 AddedRootCount is 2'

# ---------- test 7: insert then remove -> NO_CHANGE (determinism) ----------
$insertedRemoved = $twoBefore
Assert ($insertedRemoved -ceq $twoBefore) 't7 round-trip bytes identical'
$d = Compare-SafeXml -Before $twoBefore -After $insertedRemoved
Assert ($d.Kind -eq 'NO_CHANGE') 't7 insert-then-remove NO_CHANGE'

# ---------- test 8: attribute values are never leaked ----------
$insRoots = @($largeWithInsertDiffResult.AddedRoots)
$flat = @()
foreach ($r in $insRoots) {
    $flat += [string]$r.Path
    $flat += @([string[]]$r.AttributeNames)
    $flat += @([string[]]$r.ChildElementNames)
}
Assert ($flat.Count -gt 0) 't8 flattened added-root data present'
Assert (@($flat | Where-Object { $_ -match 'C:\\' }).Count -eq 0) 't8 no attribute values leaked (no C:\ strings)'
Assert (@($flat | Where-Object { $_ -match '=' }).Count -eq 0) 't8 no "=" characters in added-root data'
$paths = @($insRoots | ForEach-Object { $_.Path })
Assert (@($paths | Where-Object { $_ -eq '/EsetExport/HipsRules/HipsRule' }).Count -eq 1) 't8 path strings are name-only'

# ---------- test 9: duplicate sibling shapes still yield one AddedRoot ----------
$dupBefore = '<Root><Rules><Rule name="A"/><Rule name="A"/></Rules></Root>'
$dupAfter  = '<Root><Rules><Rule name="A"/><Rule name="A"/><Rule name="A"/></Rules></Root>'
$d = Compare-SafeXml -Before $dupBefore -After $dupAfter
Assert ($d.Kind -eq 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE') 't9 duplicate sibling insertion classified'
Assert ($d.AddedRootCount -eq 1) 't9 duplicate sibling yields one added root'
Assert ($d.AddedElements -eq 1) 't9 one added element instance'

# ---------- test 10: deep nesting (>200 levels) without stack overflow ----------
$deepSb = New-Object System.Text.StringBuilder
[void]$deepSb.Append('<Root>')
for ($i = 0; $i -lt 300; $i++) { [void]$deepSb.Append('<L' + $i + '>') }
[void]$deepSb.Append('<X/>')
for ($i = 299; $i -ge 0; $i--) { [void]$deepSb.Append('</L' + $i + '>') }
[void]$deepSb.Append('</Root>')
$deepBefore = $deepSb.ToString()
$deepAfter = $deepBefore.Replace('<X/>', '<X/><X2/>')
$d = Compare-SafeXml -Before $deepBefore -After $deepAfter
Assert ($d.Kind -eq 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE') 't10 deep nesting single insertion'
Assert ($d.AddedRootCount -eq 1) 't10 deep nesting one added root'

# ---------- extras: malformed XML throws; repeated run deterministic ----------
Assert-Throws { Compare-SafeXml '<a><b></a>' '<a><b></a>' } 'extra malformed XML throws'
$mal = Compare-SafeXml -Before $largeBefore -After $largeWithInsert
Assert ($mal.Kind -eq 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE') 'extra repeat run deterministic'
Assert ($mal.Truncated -eq $false) 'extra single root not truncated'
Assert ($mal.LineHint -eq '') 'extra LineHint empty'

# ---------- extra: DOM-built round-trip serialization is not byte-identical ----------
# XmlDocument.OuterXml normalizes '<x/>' to '<x />' so a DOM round-trip that only
# inserts then removes a node is NOT byte-identical when the source contains a
# self-closing tag. The frozen contract classifies this as formatting-only.
$rtDoc = New-Object System.Xml.XmlDocument
$rtDoc.XmlResolver = $null
$rtSrc = '<EsetExport><HipsRules><Flag/></HipsRules></EsetExport>'
[void]$rtDoc.LoadXml($rtSrc)
$rtTemp = $rtDoc.CreateElement('TEMP')
[void]$rtDoc.DocumentElement.FirstChild.AppendChild($rtTemp)
[void]$rtDoc.DocumentElement.FirstChild.RemoveChild($rtTemp)
$rtAfter = $rtDoc.OuterXml
Assert ($rtAfter -cne $rtSrc) 'extra DOM round-trip bytes differ after insert-then-remove'
$d = Compare-SafeXml -Before $rtSrc -After $rtAfter
Assert ($d.Kind -eq 'ORDER_OR_FORMATTING_ONLY_UNVERIFIED') 'extra DOM round-trip formatting-only'

# ---------- extra: exactly-10 added roots must NOT truncate ----------
$sbX = New-Object System.Text.StringBuilder
[void]$sbX.Append('<R><Rules>')
for ($i = 0; $i -lt 10; $i++) { [void]$sbX.Append('<Rule n="a' + $i + '"/>') }
[void]$sbX.Append('</Rules></R>')
$tenBefore = $sbX.ToString()
$sbY = New-Object System.Text.StringBuilder
[void]$sbY.Append('<R><Rules>')
for ($i = 0; $i -lt 20; $i++) { [void]$sbY.Append('<Rule n="a' + ($i % 10) + '"/>') }
[void]$sbY.Append('</Rules></R>')
$tenAfter = $sbY.ToString()
$d = Compare-SafeXml -Before $tenBefore -After $tenAfter
Assert ($d.Kind -eq 'MULTIPLE_SUBTREE_INSERTIONS') 'extra exactly-10 roots classified'
Assert ($d.AddedRootCount -eq 10) 'extra exactly-10 roots counted'
Assert ($d.Truncated -eq $false) 'extra exactly-10 roots not truncated'
Assert (@($d.AddedRoots).Count -eq 10) 'extra exactly-10 roots all listed'

# ---------- extra: attribute ORDER change only is formatting-level ----------
$attrOrderBefore = '<Root><Rule a="1" b="2"/></Root>'
$attrOrderAfter = '<Root><Rule b="2" a="1"/></Root>'
$d = Compare-SafeXml -Before $attrOrderBefore -After $attrOrderAfter
Assert ($d.Kind -eq 'ORDER_OR_FORMATTING_ONLY_UNVERIFIED') 'extra attribute-order-only formatting-level'
Assert ($d.AddedElements -eq 0 -and $d.RemovedElements -eq 0) 'extra attribute-order zero element delta'

# ---------- extra: added subtree nested under an existing subtree ----------
$nestBefore = '<Root><Group id="g"><Existing/></Group></Root>'
$nestAfter = '<Root><Group id="g"><Existing/><NewChild/></Group></Root>'
$d = Compare-SafeXml -Before $nestBefore -After $nestAfter
Assert ($d.Kind -eq 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE') 'extra nested insertion classified'
Assert ($d.AddedRootCount -eq 1) 'extra nested insertion one root'
Assert ($d.AddedRoots[0].Path -eq '/Root/Group/NewChild') 'extra nested insertion root path'
Assert ($d.AddedElements -eq 1) 'extra nested insertion one element instance'

# ---------- extra: mixed added+removed with unequal counts stays UNEXPLAINED ----------
$mixBefore = '<Root><Rules><Rule n="1"/></Rules></Root>'
$mixAfter = '<Root><Rules><Rule n="X"/><Rule n="2"/><Rule n="3"/></Rules></Root>'
$d = Compare-SafeXml -Before $mixBefore -After $mixAfter
Assert ($d.Kind -eq 'UNEXPLAINED_DIFFERENCE') 'extra 2-added-1-removed UNEXPLAINED'
Assert ($d.AddedElements -eq 3 -and $d.RemovedElements -eq 1) 'extra 2-added-1-removed counts'
Assert ($d.AddedRootCount -eq 3) 'extra 2-added-1-removed root count'

# ---------- extra: changed element counts as added+removed+changed ----------
$firstTextBefore = '<Root><Node/></Root>'
$firstTextAfter = '<Root><Node>hello</Node></Root>'
$d = Compare-SafeXml -Before $firstTextBefore -After $firstTextAfter
Assert ($d.Kind -eq 'UNEXPLAINED_DIFFERENCE') 'extra first-text-child UNEXPLAINED'
Assert ($d.ChangedElements -eq 1 -and $d.AddedElements -eq 1 -and $d.RemovedElements -eq 1) 'extra first-text-child counts'

# ---------- extra: comment content change is UNEXPLAINED; trailing root comment is formatting-level ----------
$d = Compare-SafeXml -Before '<Root><!-- abc --><A/></Root>' -After '<Root><!-- xyz --><A/></Root>'
Assert ($d.Kind -eq 'UNEXPLAINED_DIFFERENCE') 'extra comment-content-change UNEXPLAINED'
$d = Compare-SafeXml -Before '<Root><A/></Root>' -After '<Root><A/></Root><!-- after -->'
Assert ($d.Kind -eq 'ORDER_OR_FORMATTING_ONLY_UNVERIFIED') 'extra trailing-root-comment formatting-level'

# ---------- extra: attribute VALUES must never leak into any result field ----------
$leakProbe = Compare-SafeXml -Before $largeBefore -After $largeWithInsert
$serialized = ConvertTo-Json -InputObject $leakProbe -Depth 8 -Compress
Assert (-not $serialized.Contains('any')) 'extra no source attribute value in result'
Assert (-not $serialized.Contains('C:')) 'extra no target path value in result'

Write-Output ('All ' + $script:Checks + ' tests passed (synthetic helpers; no live ESET).')
if ($script:Failures -gt 0) { exit 1 }
exit 0
