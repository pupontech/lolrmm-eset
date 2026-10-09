# Dependency-free behavioral tests for the Quick Rules POC.
$ErrorActionPreference = 'Stop'
$scriptPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../Eset-QuickRules.ps1'))
$script:Passed = 0
$script:Failed = 0
$script:Assertions = 0
$script:FailureMessages = New-Object System.Collections.Generic.List[string]

function Assert-True([bool] $Condition, [string] $Message) {
    $script:Assertions++
    if (-not $Condition) { throw $Message }
}
function Assert-Equal($Expected, $Actual, [string] $Message) {
    $script:Assertions++
    if ($Expected -cne $Actual) { throw ("{0}: expected [{1}], got [{2}]" -f $Message, $Expected, $Actual) }
}
function Assert-Throws([scriptblock] $Action, [string] $Message) {
    $script:Assertions++
    $thrown = $false
    try { & $Action } catch { $thrown = $true }
    if (-not $thrown) { throw $Message }
}
function Invoke-Test([string] $Name, [scriptblock] $Action) {
    try { & $Action; $script:Passed++ }
    catch { $script:Failed++; $script:FailureMessages.Add(($Name + ': ' + $_.Exception.Message)) }
}
function New-SyntheticConfig {
    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $true
    $doc.LoadXml('<ESET><PRODUCT NAME="home" VERSION="19.99.synthetic" VENDOR-TOKEN="keep"><ITEM NAME="plugins"><ITEM NAME="01000001"><ITEM NAME="settings"><NODE NAME="UnrelatedSetting" TYPE="string" VALUE="preserve"/><ITEM NAME="rules"><ITEM NAME="00FF"><NODE NAME="name" TYPE="string" VALUE="Administrator rule"/><NODE NAME="priority" TYPE="number" VALUE="44"/><ITEM NAME="opaque"><NODE NAME="future" TYPE="string" VALUE="keep-me"/></ITEM></ITEM></ITEM></ITEM></ITEM></ITEM></PRODUCT><ITEM NAME="OtherSection"><NODE NAME="value" TYPE="string" VALUE="ordered"/></ITEM></ESET>')
    return ,$doc
}
function New-TestDesired([string] $Name, [string] $Path) {
    return ,([pscustomobject]@{ Name = $Name; Path = $Path })
}
function New-FakeProviders([string] $BaseXml) {
    $script:FakeState = [pscustomobject]@{ Xml = $BaseXml; ExportCount = 0; ImportCount = 0; SignCount = 0; Failure = ''; DriftOnSecondExport = $false; CorruptReadback = $false }
    $export = {
        param($path)
        $script:FakeState.ExportCount++
        if ($script:FakeState.Failure -eq 'export-first' -and $script:FakeState.ExportCount -eq 1) { throw 'fake export failure' }
        if ($script:FakeState.Failure -eq 'export-second' -and $script:FakeState.ExportCount -eq 2) { throw 'fake concurrent export failure' }
        if ($script:FakeState.Failure -eq 'export-third' -and $script:FakeState.ExportCount -eq 3) { throw 'fake post-import export failure' }
        if ($script:FakeState.DriftOnSecondExport -and $script:FakeState.ExportCount -eq 2) {
            $script:FakeState.Xml = $script:FakeState.Xml.Replace('VALUE="preserve"', 'VALUE="changed"')
        }
        if ($script:FakeState.CorruptReadback -and $script:FakeState.ExportCount -ge 3) {
            $script:FakeState.Xml = $script:FakeState.Xml.Replace('VALUE="C:\Tools\One.exe"', 'VALUE="C:\Tools\Other.exe"')
        }
        [IO.File]::WriteAllText($path, $script:FakeState.Xml, (New-Object Text.UTF8Encoding($false)))
        return [pscustomobject]@{ ExitCode = 0; StdOut = 'exported'; StdErr = '' }
    }
    $sign = {
        param($path)
        $script:FakeState.SignCount++
        if ($script:FakeState.Failure -eq 'sign') { throw 'fake signing failure' }
        # Synthetic observed-format marker only; NEVER native cryptographic proof.
        [IO.File]::AppendAllText($path, ('<!-- Signature: '+[Convert]::ToBase64String((New-Object byte[] 64))+' -->'))
        return [pscustomobject]@{ ExitCode = 0; StdOut = ''; StdErr = '' }
    }
    $import = {
        param($path)
        $script:FakeState.ImportCount++
        if ($script:FakeState.Failure -eq 'import') { throw 'fake import failure' }
        $base = New-Object System.Xml.XmlDocument
        $base.PreserveWhitespace = $true
        $base.LoadXml($script:FakeState.Xml)
        $payload = New-Object System.Xml.XmlDocument
        $payload.PreserveWhitespace = $true
        $payload.Load([string]$path)
        $baseRules = $base.SelectSingleNode("/ESET/PRODUCT[@NAME='home']/ITEM[@NAME='plugins']/ITEM[@NAME='01000001']/ITEM[@NAME='settings']/ITEM[@NAME='rules']")
        $payloadRules = $payload.SelectSingleNode("/ESET/PRODUCT[@NAME='home']/ITEM[@NAME='plugins']/ITEM[@NAME='01000001']/ITEM[@NAME='settings']/ITEM[@NAME='rules']")
        foreach ($rule in @($payloadRules.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })) {
            [void]$baseRules.AppendChild($base.ImportNode($rule, $true))
        }
        $script:FakeState.Xml = $base.OuterXml
        return [pscustomobject]@{ ExitCode = 0; StdOut = 'imported'; StdErr = '' }
    }
    return @{ Export = $export; Sign = $sign; Import = $import }
}
function Invoke-FakeTransaction([hashtable] $Providers, [object[]] $Desired, [string] $Tag) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('quick-rules-test-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($root)
    try { return Invoke-QuickApplyTransaction -Desired $Desired -Providers $Providers -RunRoot $root -TestOnlyProvider }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

. $scriptPath -FunctionsOnly

Invoke-Test 'CSV exact headers, paths and case-insensitive dedupe' {
    $file = Join-Path ([IO.Path]::GetTempPath()) ('quick-rules-' + [Guid]::NewGuid().ToString('N') + '.csv')
    try {
        [IO.File]::WriteAllText($file, "Name,Path`nTool,C:\Tools\One.exe`ntool,c:\tools\one.EXE`n", (New-Object Text.UTF8Encoding($false)))
        $items = @(Import-QuickRulesCsv -Path $file -ScriptDirectory 'C:\Quick')
        Assert-Equal 1 $items.Count 'deduplicated count'
        Assert-Equal 'Tool' $items[0].Name 'preserved first name'
        Assert-Equal 'C:\Tools\One.exe' $items[0].Path 'absolute path'
    } finally { Remove-Item $file -Force -ErrorAction SilentlyContinue }
}
Invoke-Test 'CSV rejects empty, missing, extra, malformed and unsafe values' {
    $cases = @(
        "Name,Path`n",
        "Name`nTool`n",
        "Name,Path,Extra`nTool,C:\Tools\One.exe,x`n",
        "Name,Path`nTool,C:\Tools\One.exe,extra`n",
        "Name,Path`n, C:\Tools\One.exe`n",
        "Name,Path`nTool,C:\Windows\System32\cmd.exe`n",
        "Name,Path`nTool,\\server\share\tool.exe`n",
        "Name,Path`nTool,C:\Tools\..\One.exe`n",
        "Name,Path`nTool,C:\Tools\*.exe`n",
        "Name,Path`nTool,C:\Tools\%TEMP%\one.exe`n",
        "Name,Path`nTool,C:\Tools\One.exe:stream`n",
        "Name,Path`nTool,C:\Tools\One.exe. `n",
        "Name,Path`nTool,C:\Tools\folder\CON.exe`n",
        "Name,Path`nTool,C:\Tools\folder\one.txt`n",
        "Name,Path`nTool,C:\Tools\One.exe`nBroken,`"unterminated`n"
    )
    foreach ($text in $cases) {
        $file = Join-Path ([IO.Path]::GetTempPath()) ('quick-rules-' + [Guid]::NewGuid().ToString('N') + '.csv')
        try {
            [IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding($false)))
            Assert-Throws { Import-QuickRulesCsv -Path $file -ScriptDirectory 'C:\Quick' } 'unsafe CSV accepted'
        } finally { Remove-Item $file -Force -ErrorAction SilentlyContinue }
    }
    $sameName = Join-Path ([IO.Path]::GetTempPath()) ('quick-rules-' + [Guid]::NewGuid().ToString('N') + '.csv')
    try {
        [IO.File]::WriteAllText($sameName, "Name,Path`nTool,C:\Tools\One.exe`nTool,C:\Tools\Two.exe`n", (New-Object Text.UTF8Encoding($false)))
        Assert-Throws { Import-QuickRulesCsv -Path $sameName -ScriptDirectory 'C:\Quick' } 'same name with conflicting paths accepted'
    } finally { Remove-Item $sameName -Force -ErrorAction SilentlyContinue }
}
Invoke-Test 'Only exact harmless sibling relative path is accepted' {
    $file = Join-Path ([IO.Path]::GetTempPath()) ('quick-rules-' + [Guid]::NewGuid().ToString('N') + '.csv')
    try {
        [IO.File]::WriteAllText($file, "Name,Path`nLolrmmEsetTest,.\LolrmmEsetTest.exe`n", (New-Object Text.UTF8Encoding($false)))
        $items = @(Import-QuickRulesCsv -Path $file -ScriptDirectory 'D:\Kit')
        Assert-Equal 'D:\Kit\LolrmmEsetTest.exe' $items[0].Path 'resolved sibling path'
        [IO.File]::WriteAllText($file, "Name,Path`nOther,.\other.exe`n", (New-Object Text.UTF8Encoding($false)))
        Assert-Throws { Import-QuickRulesCsv -Path $file -ScriptDirectory 'D:\Kit' } 'other relative path accepted'
    } finally { Remove-Item $file -Force -ErrorAction SilentlyContinue }
}
Invoke-Test 'Windows paths containing spaces remain exact' {
    $file = Join-Path ([IO.Path]::GetTempPath()) ('quick-rules-' + [Guid]::NewGuid().ToString('N') + '.csv')
    try {
        [IO.File]::WriteAllText($file, "Name,Path`nTool,C:\Program Files\Vendor\tool.exe`n", (New-Object Text.UTF8Encoding($false)))
        $items = @(Import-QuickRulesCsv -Path $file -ScriptDirectory 'C:\Quick')
        Assert-Equal 'C:\Program Files\Vendor\tool.exe' $items[0].Path 'path containing spaces'
    } finally { Remove-Item $file -Force -ErrorAction SilentlyContinue }
}
Invoke-Test 'Rule name XML escaping, stable name and new id' {
    $desired = @(New-TestDesired 'A & <B>' 'C:\Tools\One.exe')
    $doc = New-SyntheticConfig
    $plan = Get-QuickRulesPlan -Desired $desired -Configuration $doc
    $payload = New-QuickAppendPayload -Configuration $doc -Additions @($plan.Additions)
    $rule = $payload.SelectSingleNode("/ESET/PRODUCT[@NAME='home']/ITEM[@NAME='plugins']/ITEM[@NAME='01000001']/ITEM[@NAME='settings']/ITEM[@NAME='rules']/ITEM")
    Assert-Equal $plan.Desired[0].RuleName $rule.SelectSingleNode("NODE[@NAME='name']").GetAttribute('VALUE') 'XML escaped name round-trip'
    Assert-Equal '100' $rule.GetAttribute('NAME') 'fresh hex id after maximum'
    Assert-True ($rule.SelectSingleNode("NODE[@NAME='name']").GetAttribute('VALUE').Contains('&')) 'ampersand lost'
}
Invoke-Test 'Payload is minimal append-only native HIPS structure' {
    $desired = @(New-TestDesired 'Tool' 'C:\Tools\One.exe')
    $doc = New-SyntheticConfig
    $plan = Get-QuickRulesPlan -Desired $desired -Configuration $doc
    $payload = New-QuickAppendPayload -Configuration $doc -Additions @($plan.Additions)
    Assert-Equal 1 @($payload.DocumentElement.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element }).Count 'payload product count'
    Assert-Equal 1 @($payload.SelectNodes('//ITEM[@NAME="rules"]/*[self::ITEM]')).Count 'payload rule count'
    $rules = $payload.SelectSingleNode("/ESET/PRODUCT[@NAME='home']/ITEM[@NAME='plugins']/ITEM[@NAME='01000001']/ITEM[@NAME='settings']/ITEM[@NAME='rules']")
    Assert-Equal '1' $rules.GetAttribute('APPEND') 'append attribute'
    Assert-True (-not $rules.HasAttribute('DELETE')) 'rules collection delete attribute present'
    Assert-Equal 1 $rules.ChildNodes.Count 'minimal payload child count'
    $r = $rules.SelectSingleNode('ITEM')
    Assert-Equal '1' $r.SelectSingleNode("NODE[@NAME='enabled']").GetAttribute('VALUE') 'enabled'
    Assert-Equal '80' $r.SelectSingleNode("NODE[@NAME='priority']").GetAttribute('VALUE') 'priority'
    Assert-Equal '2' $r.SelectSingleNode("NODE[@NAME='action']").GetAttribute('VALUE') 'deny action'
    Assert-Equal '3' $r.SelectSingleNode("NODE[@NAME='severity']").GetAttribute('VALUE') 'severity'
    Assert-Equal '1' $r.SelectSingleNode("NODE[@NAME='allAppSources']").GetAttribute('VALUE') 'all sources'
    Assert-Equal 0 $r.SelectSingleNode("ITEM[@NAME='appSources']").ChildNodes.Count 'empty source targets'
    Assert-Equal '1' $r.SelectSingleNode("NODE[@NAME='hasPeTargets']").GetAttribute('VALUE') 'PE target enabled'
    Assert-Equal '0' $r.SelectSingleNode("NODE[@NAME='allPeTargets']").GetAttribute('VALUE') 'not all PE targets'
    Assert-Equal 'C:\Tools\One.exe' $r.SelectSingleNode("ITEM[@NAME='peTargets']/NODE").GetAttribute('VALUE') 'exact target'
    Assert-Equal '0' $r.SelectSingleNode("ITEM[@NAME='peOperations']/NODE[@NAME='Process_AllOperations']").GetAttribute('VALUE') 'all process operations off'
    Assert-Equal '1' $r.SelectSingleNode("ITEM[@NAME='peOperations']/NODE[@NAME='Application_Create']").GetAttribute('VALUE') 'application create only'
    foreach ($field in @('Application_Debug','Application_Hook','Application_Stop','Application_Modify')) {
        Assert-Equal '0' $r.SelectSingleNode("ITEM[@NAME='peOperations']/NODE[@NAME='$field']").GetAttribute('VALUE') ($field + ' disabled')
    }
    Assert-Equal 4 @($payload.SelectNodes('//*[@DELETE="1"]')).Count 'only per-rule deletion markers'
    Assert-Equal '19.99.synthetic' $payload.SelectSingleNode('/ESET/PRODUCT').GetAttribute('VERSION') 'product header preserved'
}
Invoke-Test 'Plan preserves unrelated config and same rules are no-op' {
    $desired = @(New-TestDesired 'Tool' 'C:\Tools\One.exe')
    $before = New-SyntheticConfig
    $beforeXml = $before.OuterXml
    $plan = Get-QuickRulesPlan -Desired $desired -Configuration $before
    Assert-Equal 1 $plan.Additions.Count 'initial addition'
    Assert-Equal 0 $plan.Unchanged.Count 'initial unchanged'
    $payload = New-QuickAppendPayload -Configuration $before -Additions @($plan.Additions)
    $after = New-Object System.Xml.XmlDocument
    $after.PreserveWhitespace = $true
    $after.LoadXml($beforeXml)
    $target = $after.SelectSingleNode("/ESET/PRODUCT[@NAME='home']/ITEM[@NAME='plugins']/ITEM[@NAME='01000001']/ITEM[@NAME='settings']/ITEM[@NAME='rules']")
    $source = $payload.SelectSingleNode("/ESET/PRODUCT[@NAME='home']/ITEM[@NAME='plugins']/ITEM[@NAME='01000001']/ITEM[@NAME='settings']/ITEM[@NAME='rules']/ITEM")
    [void]$target.AppendChild($after.ImportNode($source, $true))
    $round = Get-QuickRulesPlan -Desired $desired -Configuration $after
    Assert-Equal 0 $round.Additions.Count 'rerun additions'
    Assert-Equal 1 $round.Unchanged.Count 'rerun unchanged'
    Assert-Equal 'Administrator rule' $after.SelectSingleNode("//ITEM[@NAME='00FF']/NODE[@NAME='name']").GetAttribute('VALUE') 'unrelated rule preserved'
    Assert-Equal 'ordered' $after.SelectSingleNode("/ESET/ITEM[@NAME='OtherSection']/NODE").GetAttribute('VALUE') 'unrelated ordered section preserved'
    Assert-Equal $beforeXml $before.OuterXml 'planner mutated source document'
}
Invoke-Test 'Empty, scalar and multiple rule inventories allocate safely' {
    $desired = @(New-TestDesired 'Tool' 'C:\Tools\One.exe')
    $empty = New-SyntheticConfig
    $emptyRules = $empty.SelectSingleNode("//ITEM[@NAME='rules']")
    while ($emptyRules.HasChildNodes) { [void]$emptyRules.RemoveChild($emptyRules.FirstChild) }
    $emptyPlan = Get-QuickRulesPlan -Desired $desired -Configuration $empty
    Assert-Equal 1 $emptyPlan.Additions.Count 'empty inventory addition'
    $multiple = New-SyntheticConfig
    $rules = $multiple.SelectSingleNode("//ITEM[@NAME='rules']")
    $extra = $multiple.CreateElement('ITEM'); $extra.SetAttribute('NAME', '0100')
    $node = $multiple.CreateElement('NODE'); $node.SetAttribute('NAME', 'name'); $node.SetAttribute('TYPE', 'string'); $node.SetAttribute('VALUE', 'Second administrator rule')
    [void]$extra.AppendChild($node); [void]$rules.AppendChild($extra)
    $multiPlan = Get-QuickRulesPlan -Desired $desired -Configuration $multiple
    Assert-Equal 1 $multiPlan.Additions.Count 'multiple inventory addition'
    $payload = New-QuickAppendPayload -Configuration $multiple -Additions @($multiPlan.Additions)
    Assert-Equal '101' $payload.SelectSingleNode("//ITEM[@NAME='rules']/ITEM").GetAttribute('NAME') 'multiple inventory next id'
}
Invoke-Test 'Owned collision, duplicate ids/names/collections and unknown schema fail closed' {
    $desired = @(New-TestDesired 'Tool' 'C:\Tools\One.exe')
    $base = New-SyntheticConfig
    $plan = Get-QuickRulesPlan -Desired $desired -Configuration $base
    $payload = New-QuickAppendPayload -Configuration $base -Additions @($plan.Additions)
    $rule = $payload.SelectSingleNode("//ITEM[@NAME='rules']/ITEM")
    $different = New-Object System.Xml.XmlDocument
    $different.LoadXml($base.OuterXml)
    $differentRule = $different.ImportNode($rule, $true)
    [void]$different.SelectSingleNode("//ITEM[@NAME='rules']").AppendChild($differentRule)
    $differentRule.SelectSingleNode("NODE[@NAME='priority']").SetAttribute('VALUE', '20')
    Assert-Throws { Get-QuickRulesPlan -Desired $desired -Configuration $different } 'different semantics owned collision accepted'
    $dup = New-Object System.Xml.XmlDocument; $dup.LoadXml($base.OuterXml)
    $rules = $dup.SelectSingleNode("//ITEM[@NAME='rules']")
    [void]$rules.AppendChild($dup.ImportNode($rules.SelectSingleNode('ITEM'), $true))
    Assert-Throws { Get-QuickRulesPlan -Desired $desired -Configuration $dup } 'duplicate rule ids accepted'
    $dupName = New-Object System.Xml.XmlDocument; $dupName.LoadXml($base.OuterXml)
    $rules = $dupName.SelectSingleNode("//ITEM[@NAME='rules']")
    $extra = $dupName.CreateElement('ITEM'); $extra.SetAttribute('NAME', '0100')
    $n = $dupName.CreateElement('NODE'); $n.SetAttribute('NAME','name'); $n.SetAttribute('TYPE','string'); $n.SetAttribute('VALUE','Administrator rule')
    [void]$extra.AppendChild($n); [void]$rules.AppendChild($extra)
    Assert-Throws { Get-QuickRulesPlan -Desired $desired -Configuration $dupName } 'duplicate existing rule names accepted'
    $multiple = New-Object System.Xml.XmlDocument; $multiple.LoadXml($base.OuterXml)
    $s = $multiple.SelectSingleNode("//ITEM[@NAME='settings']")
    [void]$s.AppendChild($multiple.ImportNode($s.SelectSingleNode("ITEM[@NAME='rules']"), $true))
    Assert-Throws { Get-QuickRulesPlan -Desired $desired -Configuration $multiple } 'ambiguous rules collection accepted'
    $unknown = New-SyntheticConfig; $unknown.SelectSingleNode('/ESET/PRODUCT').SetAttribute('VERSION','20.0.1')
    Assert-Throws { Get-QuickRulesPlan -Desired $desired -Configuration $unknown } 'unknown major version accepted'
}
Invoke-Test 'Secure XML parser rejects malformed XML and DTD entities' {
    Assert-Throws { ConvertFrom-QuickXmlText -Text '<ESET><x></ESET>' } 'malformed XML accepted'
    Assert-Throws { ConvertFrom-QuickXmlText -Text '<!DOCTYPE ESET [<!ENTITY x "bad">]><ESET>&x;</ESET>' } 'DTD accepted'
    $wrong = New-Object System.Xml.XmlDocument; $wrong.LoadXml('<NOT-ESET/>')
    Assert-Throws { Get-QuickRulesPlan -Desired @(New-TestDesired 'Tool' 'C:\Tools\One.exe') -Configuration $wrong } 'unknown root accepted'
}
Invoke-Test 'Injected real transaction caller signs/imports/verifies and no-ops without sign' {
    $desired = @(New-TestDesired 'Tool' 'C:\Tools\One.exe')
    $providers = New-FakeProviders (New-SyntheticConfig).OuterXml
    $result = Invoke-FakeTransaction $providers $desired 'apply'
    Assert-True $result.Success 'fake transaction did not succeed'
    Assert-Equal 1 $script:FakeState.SignCount 'sign count'
    Assert-Equal 1 $script:FakeState.ImportCount 'import count'
    Assert-True $result.OwnerPending 'native enforcement must remain owner pending'
    Assert-True $result.Experimental 'append must remain experimental'
    $providers2 = New-FakeProviders $script:FakeState.Xml
    $again = Invoke-FakeTransaction $providers2 $desired 'noop'
    Assert-True $again.Success 'no-op transaction failed'
    Assert-Equal 0 $script:FakeState.SignCount 'no-op signed'
    Assert-Equal 0 $script:FakeState.ImportCount 'no-op imported'
    Assert-Equal 1 $again.UnchangedCount 'no-op unchanged count'
}
Invoke-Test 'Injected transaction aborts on signing, concurrency, import and readback failures' {
    $desired = @(New-TestDesired 'Tool' 'C:\Tools\One.exe')
    foreach ($failure in @('sign','import','export-first','export-second','export-third','concurrency','readback')) {
        $providers = New-FakeProviders (New-SyntheticConfig).OuterXml
        if ($failure -eq 'concurrency') { $script:FakeState.DriftOnSecondExport = $true }
        if ($failure -eq 'readback') { $script:FakeState.CorruptReadback = $true }
        if ($failure -in @('sign','import','export-first','export-second','export-third')) { $script:FakeState.Failure = $failure }
        Assert-Throws { Invoke-FakeTransaction $providers $desired $failure } ($failure + ' did not fail transaction')
        if ($failure -eq 'sign') { Assert-Equal 0 $script:FakeState.ImportCount 'import after sign failure' }
        if ($failure -in @('concurrency','export-second')) { Assert-Equal 0 $script:FakeState.ImportCount 'import after pre-import failure' }
    }
}
Invoke-Test 'Offline top-level Preview and Apply gates have no run-directory side effects' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('quick-rules-top-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($root)
    $local = Join-Path $root 'local'; [void][IO.Directory]::CreateDirectory($local)
    $rules = Join-Path $root 'rules.csv'
    $config = Join-Path $root 'synthetic.xml'
    try {
        [IO.File]::WriteAllText($rules, "Name,Path`nTool,C:\Tools\One.exe`n", (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($config, (New-SyntheticConfig).OuterXml, (New-Object Text.UTF8Encoding($false)))
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $psi.Arguments = '-NoProfile -File ' + (Quote-QuickWindowsArgument $scriptPath) + ' -RulesFile ' + (Quote-QuickWindowsArgument $rules) + ' -ConfigurationFile ' + (Quote-QuickWindowsArgument $config)
        $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.EnvironmentVariables['LOCALAPPDATA'] = $local
        $proc = [Diagnostics.Process]::Start($psi)
        $out = $proc.StandardOutput.ReadToEnd(); $err = $proc.StandardError.ReadToEnd(); $proc.WaitForExit()
        Assert-Equal 0 $proc.ExitCode ('offline preview exit: ' + $err)
        Assert-True ($out.Contains('ADD') -and $out.Contains('LOLRMM Block - Tool') -and $out.Contains('C:\Tools\One.exe')) 'preview omitted exact planned rule/target'
        Assert-Equal 0 @(Get-ChildItem -LiteralPath $local -Force).Count 'offline preview created private files'
        foreach ($extra in @('-Apply', '-Apply -IAmOnATestMachine')) {
            $psi.Arguments = '-NoProfile -File ' + (Quote-QuickWindowsArgument $scriptPath) + ' -RulesFile ' + (Quote-QuickWindowsArgument $rules) + ' ' + $extra
            $proc = [Diagnostics.Process]::Start($psi)
            $null = $proc.StandardOutput.ReadToEnd(); $null = $proc.StandardError.ReadToEnd(); $proc.WaitForExit()
            Assert-True ($proc.ExitCode -ne 0) ('unsafe apply gate passed: ' + $extra)
            Assert-Equal 0 @(Get-ChildItem -LiteralPath $local -Force).Count 'failed apply created private files'
        }
    } finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:Failed -gt 0) {
    [Console]::Error.WriteLine(('FAILED: {0}; PASSED: {1}' -f $script:Failed, $script:Passed))
    foreach ($message in $script:FailureMessages) { [Console]::Error.WriteLine(('  ' + $message)) }
    exit 1
}
[Console]::WriteLine(('PASSED: {0}; FAILED: 0; ASSERTIONS: {1}' -f $script:Passed, $script:Assertions))
exit 0
