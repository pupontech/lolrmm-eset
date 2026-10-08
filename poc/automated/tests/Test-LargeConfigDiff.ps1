#requires -Version 5.1
# =============================================================================
# Test-LargeConfigDiff.ps1
#
# INDEPENDENT ADVERSARIAL TEST of the frozen Compare-SafeXml contract, written
# from the contract SPEC, not from the implementation. Asserts EXACT Kind
# strings and element counts on a large, realistic, SYNTHETIC ESET-like
# configuration corpus. Nothing here touches live ESET, the network, or the
# controller; this file only exercises the comparator helper.
#
# IMPORTANT: all fixtures produced by New-SyntheticEsetConfig below are
# SYNTHETIC machine-generated XML. They are NOT real ESET exports and make no
# claim about real ESET semantics; they are shaped like a settings tree plus a
# HIPS-like rule container purely to give the comparator realistic load.
#
# Contract under test (frozen):
#   Kind: 'NO_CHANGE' | 'ORDER_OR_FORMATTING_ONLY_UNVERIFIED' |
#         'STRUCTURAL_SINGLE_INSERTION_CANDIDATE' | 'MULTIPLE_SUBTREE_INSERTIONS' |
#         'UNEXPLAINED_DIFFERENCE'
#   AddedElements, RemovedElements, ChangedElements, AddedRootCount: [int]
#   AddedRoots: max 10 objects (Path, LocalName, AttributeNames, ChildElementNames, LineHint)
#   Truncated [bool]; ElementsBefore, ElementsAfter [int]
#
# Exit code: 0 only if every assertion passes; nonzero on any failure.
# PowerShell 5.1 compatible, pure ASCII, self-contained, no Pester.
# =============================================================================

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# --- Kit.Helpers.ps1 (the comparator lives there; do not modify) -------------
$kitHelpersPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Kit.Helpers.ps1'
if (-not (Test-Path -LiteralPath $kitHelpersPath)) { throw ('Missing helper: ' + $kitHelpersPath) }
. $kitHelpersPath

# --- Sentinel vocabulary ------------------------------------------------------
$script:Sentinels = @(
    ('SENTINEL-VALUE-' + [guid]::NewGuid().ToString('N')),
    ('SENTINEL-VALUE-' + [guid]::NewGuid().ToString('N')),
    ('SENTINEL-VALUE-' + [guid]::NewGuid().ToString('N')),
    'SENTINEL-VALUE-DEFAULTRULE',
    'SENTINEL-VALUE-BLOCKRULE',
    'SENTINEL-VALUE-FLIPPED-RULE',
    'SENTINEL-VALUE-ATTR-CHANGED',
    'SENTINEL-VALUE-CLONED',
    'SENTINEL-VALUE-DEEP-CHAIN',
    'SENTINEL-VALUE-DEEP-LEAF',
    'SENTINEL-VALUE-DUPLICATE',
    'SENTINEL-VALUE-DUPLICATE-OFF',
    'SENTINEL-VALUE-REMOVE-AND-RESTORE',
    'SENTINEL-VALUE-TWO-RULES-A',
    'SENTINEL-VALUE-TWO-RULES-B',
    'SENTINEL-VALUE-TWO-RULES-ATTR',
    'SENTINEL-VALUE-CDATA-12-RULES',
    'SENTINEL-VALUE-CDATA-TRUNC',
    'SENTINEL-VALUE-CDATA-TRUNC-2',
    'SENTINEL-VALUE-CDATA-DEEP'
)
$script:AllSentinels = @($Sentinels)

# --- Pure-XML diff helpers (test-side; no Kit internals reused) ---------------
function Get-ElementCountFromText([string]$xmlText) {
    if ([string]::IsNullOrWhiteSpace($xmlText)) { return 0 }
    return [regex]::Matches($xmlText, '<([A-Za-z][A-Za-z0-9_.:-]*)\b[^>]*>').Count
}

function Get-XmlFromText([string]$xmlText) {
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create((New-Object System.IO.StringReader($xmlText)), $settings)
    $doc = New-Object System.Xml.XmlDocument
    $doc.XmlResolver = $null
    try { $doc.Load($reader) } finally { $reader.Dispose() }
    return $doc
}

function New-XmlFromString([string]$xmlText) {
    return Get-XmlFromText $xmlText
}

# --- Synthetic ESET-like configuration generator -------------------------------
# Machine-generated SYNTHETIC configuration with a deep settings tree and a
# HIPS-like rules container. Not real ESET output; explicitly labeled.
function New-SyntheticEsetConfig {
    param(
        [int]$SizeHint = 1,
        [int]$RuleCount = 400,
        [switch]$Indent
    )
    if ($SizeHint -lt 1) { $SizeHint = 1 }
    if ($RuleCount -lt 1) { $RuleCount = 1 }
    $script:SyntheticMarker = 'SYNTHETIC-FIXTURE-v1 (not real ESET output)'
    $sb = New-Object System.Text.StringBuilder
    $nl = ''
    $pad1 = ''
    $pad2 = ''
    $pad3 = ''
    if ($Indent) { $nl = "`n"; $pad1 = ' '; $pad2 = '  '; $pad3 = '   ' }
    [void]$sb.Append('<?xml version="1.0" encoding="utf-8"?>').Append($nl)
    [void]$sb.Append('<CONFIG>').Append($nl)
    [void]$sb.Append($pad1).Append('<SETTINGS>').Append($nl)
    $leafIndex = 0
    for ($branch = 0; $branch -lt 24; $branch++) {
        [void]$sb.Append($pad2).Append('<BRANCH Id="').Append($branch).Append('">').Append($nl)
        for ($leaf = 0; $leaf -lt ($SizeHint * 1000); $leaf++) {
            [void]$sb.Append($pad3)
            [void]$sb.Append(('<PROPERTY Key="b{0}-p{1}" Value="v{1}"/>' -f $branch, $leaf))
            [void]$sb.Append($nl)
            $leafIndex++
        }
        [void]$sb.Append($pad2).Append('</BRANCH>').Append($nl)
    }
    [void]$sb.Append($pad1).Append('</SETTINGS>').Append($nl)
    [void]$sb.Append($pad1).Append('<HIPS_RULES Count="').Append($RuleCount).Append('">').Append($nl)
    for ($i = 0; $i -lt $RuleCount; $i++) {
        [void]$sb.Append($pad2)
        [void]$sb.Append('<RULE Name="rule-{0}" Id="id-{0}">' -f $i).Append($nl)
        [void]$sb.Append($pad3).Append('<Enabled>1</Enabled>').Append($nl)
        [void]$sb.Append($pad3).Append('<Action>Block</Action>').Append($nl)
        [void]$sb.Append($pad3).Append('<Operations>Execute</Operations>').Append($nl)
        [void]$sb.Append($pad3).Append('<Target Path="C:\Synthetic\bin.exe"/>').Append($nl)
        [void]$sb.Append($pad3).Append('<Description>Synthetic rule {0}</Description>' -f $i).Append($nl)
        [void]$sb.Append($pad2).Append('</RULE>').Append($nl)
    }
    [void]$sb.Append($pad1).Append('</HIPS_RULES>').Append($nl)
    [void]$sb.Append('</CONFIG>').Append($nl)
    return $sb.ToString()
}

# --- Assertion helpers ---------------------------------------------------------
$script:PassCount = 0
function Assert-True([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw ('FAIL: ' + $Name) }
    $script:PassCount++
    Write-Output ('PASS: ' + $Name)
}

function Assert-KindIs([object]$Result, [string]$ExpectedKind, [string]$Name) {
    $actual = ''
    if ($null -ne $Result -and $null -ne $Result.Kind) { $actual = [string]$Result.Kind }
    if ([string]::Compare($actual, $ExpectedKind, [System.StringComparison]::Ordinal) -ne 0) {
        throw ('FAIL: ' + $Name + ': expected Kind=' + $ExpectedKind + ' but got ' + $actual)
    }
    $script:PassCount++
    Write-Output ('PASS: ' + $Name)
}

function Assert-IntIs([object]$Result, [string]$Property, [int]$Expected, [string]$Name) {
    $actual = 0
    if ($null -ne $Result -and $null -ne $Result.$Property) { $actual = [int]$Result.$Property }
    if ($actual -ne $Expected) {
        throw ('FAIL: ' + $Name + ': expected ' + $Property + '=' + $Expected + ' but got ' + $actual)
    }
    $script:PassCount++
    Write-Output ('PASS: ' + $Name)
}

function Assert-RootsCount([object]$Result, [int]$Expected, [string]$Name) {
    $roots = @()
    if ($null -ne $Result -and $null -ne $Result.AddedRoots) { $roots = @($Result.AddedRoots) }
    if ($roots.Count -ne $Expected) {
        throw ('FAIL: ' + $Name + ': expected AddedRoots.Count=' + $Expected + ' but got ' + $roots.Count)
    }
    $script:PassCount++
    Write-Output ('PASS: ' + $Name)
}

# Assert none of the sentinel strings appear anywhere in the JSON-serialized
# result (i.e. attribute VALUES must not leak through AddedRoots or anywhere).
function Assert-NoSentinelLeak([object]$Result, [string]$Name) {
    $json = ConvertTo-Json -InputObject $Result -Depth 8 -Compress
    foreach ($s in $script:AllSentinels) {
        if ($json.Contains($s)) {
            throw ('FAIL: ' + $Name + ': sentinel value leaked into output: ' + $s)
        }
    }
    $script:PassCount++
    Write-Output ('PASS: ' + $Name)
}

function Assert-SentinelInText([string]$Text, [string]$Name) {
    foreach ($s in $script:AllSentinels) {
        if ($Text.Contains($s)) {
            $script:PassCount++
            Write-Output ('PASS: ' + $Name)
            return
        }
    }
    throw ('FAIL: ' + $Name + ': expected a sentinel in the fixture')
}

# --- Test corpus ---------------------------------------------------------------
Write-Output '--- Test-LargeConfigDiff: adversarial Compare-SafeXml contract test ---'
Write-Output 'NOTE: fixtures are SYNTHETIC machine-generated XML, not real ESET output.'

$compact = New-SyntheticEsetConfig -SizeHint 3 -RuleCount 400
$indented = New-SyntheticEsetConfig -SizeHint 3 -RuleCount 400 -Indent
$compactCount = Get-ElementCountFromText $compact
$indentedCount = Get-ElementCountFromText $indented
Write-Output ('fixture: compact elements~' + $compactCount + '  indented elements~' + $indentedCount)

# Sentinel seeding: the compact fixture should include sentinel values in some
# rule attributes and text so that case 13 can detect any leakage.
$compact = $compact -replace 'Description>Synthetic rule 0<', ('Description>' + $script:Sentinels[0] + '<')
$compact = $compact -replace 'Id="id-0"', ('Id="' + $script:Sentinels[1] + '"')
$compact = $compact -replace 'Path="C:\\Synthetic\\bin.exe"', ('Path="' + $script:Sentinels[2] + '"')
$indented = $indented -replace 'Description>Synthetic rule 0<', ('Description>' + $script:Sentinels[0] + '<')
$indented = $indented -replace 'Id="id-0"', ('Id="' + $script:Sentinels[1] + '"')
$indented = $indented -replace 'Path="C:\\Synthetic\\bin.exe"', ('Path="' + $script:Sentinels[2] + '"')

# Sanity: the compact corpus must really be huge (60,000+ elements).
Assert-True ($compactCount -ge 60000) 'compact fixture has 60k+ elements'
Assert-SentinelInText $compact 'compact fixture carries sentinel values'

# --- Case 1: config vs itself -> NO_CHANGE --------------------------------------
$r = Compare-SafeXml -Before $compact -After $compact
Assert-KindIs $r 'NO_CHANGE' 'case 1: compact self-compare -> NO_CHANGE'
Assert-NoSentinelLeak $r 'case 1: no sentinel leak in self-compare result'

# --- Case 2: indented vs compact -> NO_CHANGE (whitespace is discarded) --------
$r = Compare-SafeXml -Before $indented -After $compact
Assert-KindIs $r 'NO_CHANGE' 'case 2: indented vs compact -> NO_CHANGE'

# --- Case 3: sibling rule subtree reorder -> ORDER_OR_FORMATTING_ONLY_UNVERIFIED
$doc = Get-XmlFromText $compact
$rules = $doc.SelectNodes('//HIPS_RULES/RULE')
if ($rules.Count -lt 3) { throw 'FAIL: fixture must have multiple rules to reorder' }
$r0 = $rules[0]; $r1 = $rules[1]
$parent = $r0.ParentNode
[void]$parent.RemoveChild($r1)
[void]$parent.InsertBefore($r1, $r0)
$reordered = $doc.OuterXml
$r = Compare-SafeXml -Before $compact -After $reordered
Assert-KindIs $r 'ORDER_OR_FORMATTING_ONLY_UNVERIFIED' 'case 3: sibling rule reorder -> ORDER_OR_FORMATTING_ONLY_UNVERIFIED'
Assert-IntIs $r 'AddedRootCount' 0 'case 3: reorder -> AddedRootCount 0'
Assert-IntIs $r 'RemovedElements' 0 'case 3: reorder -> RemovedElements 0'

# --- Case 4: one new rule inserted -> STRUCTURAL_SINGLE_INSERTION_CANDIDATE ----
$doc = Get-XmlFromText $compact
$rulesContainer = $doc.SelectSingleNode('//HIPS_RULES')
$newRuleXml = '<RULE Name="NEW-Inserted" Id="NEW-1"><Enabled>1</Enabled><Action>Allow</Action><Operations>Read</Operations><Target Path="C:\New\target.exe"/><Description>Synthetic NEW rule</Description></RULE>'
$newFrag = Get-XmlFromText $newRuleXml
$imported = $doc.ImportNode($newFrag.DocumentElement, $true)
[void]$rulesContainer.AppendChild($imported)
$afterInsert1 = $doc.OuterXml
$r = Compare-SafeXml -Before $compact -After $afterInsert1
Assert-KindIs $r 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE' 'case 4: one new rule -> STRUCTURAL_SINGLE_INSERTION_CANDIDATE'
Assert-IntIs $r 'AddedRootCount' 1 'case 4: AddedRootCount 1'
Assert-IntIs $r 'RemovedElements' 0 'case 4: RemovedElements 0'
Assert-IntIs $r 'ChangedElements' 0 'case 4: ChangedElements 0'
Assert-True ($r.ElementsAfter -gt 2000) 'case 4: ElementsAfter > 2000'
Assert-NoSentinelLeak $r 'case 4: no sentinel leak'

# --- Case 5: duplicate of an existing sibling -> still AddedRootCount 1 --------
$doc = Get-XmlFromText $compact
$rulesContainer = $doc.SelectSingleNode('//HIPS_RULES')
$existingRule = $doc.SelectSingleNode('//HIPS_RULES/RULE[1]')
$clone = $existingRule.CloneNode($true)
[void]$rulesContainer.AppendChild($clone)
$afterClone = $doc.OuterXml
$r = Compare-SafeXml -Before $compact -After $afterClone
Assert-KindIs $r 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE' 'case 5: duplicate of existing rule -> STRUCTURAL_SINGLE_INSERTION_CANDIDATE'
Assert-IntIs $r 'AddedRootCount' 1 'case 5: duplicate -> AddedRootCount 1'

# --- Case 6: one existing rule text flipped -> UNEXPLAINED_DIFFERENCE ----------
$doc = Get-XmlFromText $compact
$enabled = $doc.SelectSingleNode('//HIPS_RULES/RULE[2]/Enabled')
if ($null -eq $enabled) { throw 'FAIL: expected Enabled element in fixture' }
$enabled.InnerText = '0'
$afterFlip = $doc.OuterXml
$r = Compare-SafeXml -Before $compact -After $afterFlip
Assert-KindIs $r 'UNEXPLAINED_DIFFERENCE' 'case 6: Enabled text flipped -> UNEXPLAINED_DIFFERENCE'
Assert-True ($r.ChangedElements -ge 1 -or $r.AddedElements -ge 1) 'case 6: flipped text counted as a change'

# --- Case 7: one existing rule attribute value changed -> UNEXPLAINED_DIFFERENCE
$doc = Get-XmlFromText $compact
$target = $doc.SelectSingleNode('//HIPS_RULES/RULE[2]/Target')
if ($null -eq $target) { throw 'FAIL: expected Target element in fixture' }
$target.SetAttribute('Path', 'C:\Synthetic\bin-CHANGED.exe')
$afterAttr = $doc.OuterXml
$r = Compare-SafeXml -Before $compact -After $afterAttr
Assert-KindIs $r 'UNEXPLAINED_DIFFERENCE' 'case 7: attribute value changed -> UNEXPLAINED_DIFFERENCE'

# --- Case 8: one whole existing rule deleted -> UNEXPLAINED_DIFFERENCE --------
$doc = Get-XmlFromText $compact
$victim = $doc.SelectSingleNode('//HIPS_RULES/RULE[3]')
[void]$victim.ParentNode.RemoveChild($victim)
$afterDelete = $doc.OuterXml
$r = Compare-SafeXml -Before $compact -After $afterDelete
Assert-KindIs $r 'UNEXPLAINED_DIFFERENCE' 'case 8: rule deleted -> UNEXPLAINED_DIFFERENCE'
Assert-True ($r.RemovedElements -gt 0) 'case 8: RemovedElements > 0'
Assert-IntIs $r 'AddedRootCount' 0 'case 8: AddedRootCount 0'

# --- Case 9: two different new rules -> MULTIPLE_SUBTREE_INSERTIONS ------------
$doc = Get-XmlFromText $compact
$rulesContainer = $doc.SelectSingleNode('//HIPS_RULES')
$fragA = Get-XmlFromText '<RULE Name="NEW-A" Id="NEW-A"><Enabled>1</Enabled><Action>Block</Action><Target Path="C:\A\a.exe"/></RULE>'
$fragB = Get-XmlFromText '<RULE Name="NEW-B" Id="NEW-B"><Enabled>0</Enabled><Action>Allow</Action><Target Path="C:\B\b.exe"/></RULE>'
[void]$rulesContainer.AppendChild($doc.ImportNode($fragA.DocumentElement, $true))
[void]$rulesContainer.AppendChild($doc.ImportNode($fragB.DocumentElement, $true))
$afterTwo = $doc.OuterXml
$r = Compare-SafeXml -Before $compact -After $afterTwo
Assert-KindIs $r 'MULTIPLE_SUBTREE_INSERTIONS' 'case 9: two new rules -> MULTIPLE_SUBTREE_INSERTIONS'
Assert-IntIs $r 'AddedRootCount' 2 'case 9: AddedRootCount 2'

# --- Case 10: DOM-built insert then remove -> NO_CHANGE ------------------------
# XmlDocument.OuterXml rewrites '<RULE/>' style tags to '<RULE></RULE>' and may
# alter attribute/element serialization, so the strings are not byte-identical.
# The volatile-noise strip re-parses both sides with whitespace discarded, so a
# shape-preserving DOM round-trip classifies as NO_CHANGE.
$doc = Get-XmlFromText $compact
$rulesContainer = $doc.SelectSingleNode('//HIPS_RULES')
$frag = Get-XmlFromText '<RULE Name="NEW-TEMP" Id="NEW-TEMP"><Enabled>1</Enabled></RULE>'
$tmp = $doc.ImportNode($frag.DocumentElement, $true)
[void]$rulesContainer.AppendChild($tmp)
[void]$rulesContainer.RemoveChild($tmp)
$afterInsertRemove = $doc.OuterXml
if ($afterInsertRemove -ceq $compact) { throw 'FAIL: DOM round-trip unexpectedly byte-identical' }
$r = Compare-SafeXml -Before $compact -After $afterInsertRemove
Assert-KindIs $r 'NO_CHANGE' 'case 10: DOM insert-then-remove -> NO_CHANGE'

# --- Case 11: 12 new rules -> AddedRoots capped at 10, Truncated true ----------
$doc = Get-XmlFromText $compact
$rulesContainer = $doc.SelectSingleNode('//HIPS_RULES')
for ($i = 0; $i -lt 12; $i++) {
    $frag = Get-XmlFromText ('<RULE Name="NEW-CAP-{0}" Id="NEW-CAP-{0}"><Enabled>1</Enabled></RULE>' -f $i)
    [void]$rulesContainer.AppendChild($doc.ImportNode($frag.DocumentElement, $true))
}
$after12 = $doc.OuterXml
$r = Compare-SafeXml -Before $compact -After $after12
Assert-KindIs $r 'MULTIPLE_SUBTREE_INSERTIONS' 'case 11: 12 new rules -> MULTIPLE_SUBTREE_INSERTIONS'
Assert-RootsCount $r 10 'case 11: AddedRoots capped at 10'
Assert-True ($r.Truncated) 'case 11: Truncated true'
Assert-IntIs $r 'AddedRootCount' 12 'case 11: AddedRootCount 12'

# --- Case 12: deep 300-level nesting insertion -> single insertion candidate ---
$deep = New-Object System.Text.StringBuilder
[void]$deep.Append('<DEEPCHAIN Note="' + $script:Sentinels[8] + '">')
for ($i = 0; $i -lt 300; $i++) { [void]$deep.Append('<L>') }
[void]$deep.Append('<LEAF>' + $script:Sentinels[9] + '</LEAF>')
for ($i = 0; $i -lt 300; $i++) { [void]$deep.Append('</L>') }
[void]$deep.Append('</DEEPCHAIN>')
$doc = Get-XmlFromText $compact
$root = $doc.DocumentElement
$imported = $doc.ImportNode((Get-XmlFromText $deep.ToString()).DocumentElement, $true)
[void]$root.AppendChild($imported)
$afterDeep = $doc.OuterXml
$r = Compare-SafeXml -Before $compact -After $afterDeep
Assert-KindIs $r 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE' 'case 12: 300-deep nesting -> STRUCTURAL_SINGLE_INSERTION_CANDIDATE'
Assert-IntIs $r 'AddedRootCount' 1 'case 12: deep -> AddedRootCount 1'
Assert-NoSentinelLeak $r 'case 12: no sentinel leak in deep-chain result'

# --- Case 13: no leaked attribute values in AddedRoots --------------------------
$doc = Get-XmlFromText $compact
$rulesContainer = $doc.SelectSingleNode('//HIPS_RULES')
$leakFrag = Get-XmlFromText ('<RULE Name="' + $script:Sentinels[10] + '" Id="' + $script:Sentinels[11] + '"><Enabled>1</Enabled><Description>' + $script:Sentinels[12] + '</Description></RULE>')
[void]$rulesContainer.AppendChild($doc.ImportNode($leakFrag.DocumentElement, $true))
$afterLeak = $doc.OuterXml
$r = Compare-SafeXml -Before $compact -After $afterLeak
Assert-KindIs $r 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE' 'case 13: sentinel-rule insertion -> STRUCTURAL_SINGLE_INSERTION_CANDIDATE'
Assert-NoSentinelLeak $r 'case 13: no sentinel value leaks into result'

# --- Extra: CDATA / namespace sensitivity ---------------------------------------
$r = Compare-SafeXml -Before '<x><![CDATA[a]]></x>' -After '<x><![CDATA[b]]></x>'
Assert-KindIs $r 'UNEXPLAINED_DIFFERENCE' 'extra: CDATA content change -> UNEXPLAINED_DIFFERENCE'
$r = Compare-SafeXml -Before '<x xmlns="urn:a"/>' -After '<x xmlns="urn:b"/>'
Assert-KindIs $r 'UNEXPLAINED_DIFFERENCE' 'extra: namespace change -> UNEXPLAINED_DIFFERENCE'

# --- Summary ---------------------------------------------------------------------
Write-Output ('All ' + $script:PassCount + ' assertions passed (SYNTHETIC fixtures; no live ESET).')
exit 0
