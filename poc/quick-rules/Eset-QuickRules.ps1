[CmdletBinding()]
param(
    [string] $RulesFile = '',
    [string] $ConfigurationFile = '',
    [switch] $Apply,
    [switch] $IAmOnATestMachine,
    [string] $SignToolPath = '',
    [switch] $FunctionsOnly
)

$script:QuickRulesMaxXmlBytes = 16MB
$script:QuickRulesOwnedPrefix = 'LOLRMM Block - '
$script:QuickRulesSignerUrl = 'https://download.eset.com/com/eset/tools/installers/xmlsigntool/latest/xmlsigntool.exe'
$script:QuickRulesGenericBinaries = @(
    'explorer.exe','svchost.exe','services.exe','lsass.exe','winlogon.exe','csrss.exe',
    'wininit.exe','smss.exe','cmd.exe','powershell.exe','pwsh.exe','rundll32.exe',
    'msiexec.exe','wscript.exe','cscript.exe'
)

function Get-QuickDirectElements {
    param([System.Xml.XmlNode] $Parent, [string] $ElementName, [string] $NameAttribute)
    $found = New-Object System.Collections.Generic.List[System.Xml.XmlElement]
    foreach ($child in $Parent.ChildNodes) {
        if ($child -is [System.Xml.XmlElement] -and [string]::IsNullOrEmpty($child.NamespaceURI) -and
            [string]::IsNullOrEmpty($child.Prefix) -and $child.LocalName -ceq $ElementName -and
            $child.HasAttribute('NAME') -and $child.GetAttribute('NAME') -ceq $NameAttribute) {
            $found.Add([System.Xml.XmlElement]$child)
        }
    }
    return ,$found.ToArray()
}

function ConvertFrom-QuickXmlText {
    param([Parameter(Mandatory=$true)][string] $Text)
    if ($Text.Length -gt $script:QuickRulesMaxXmlBytes) { throw 'Configuration exceeds the 16 MiB safety limit.' }
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = $script:QuickRulesMaxXmlBytes
    $settings.MaxCharactersFromEntities = 0
    $reader = $null
    $stringReader = $null
    try {
        $stringReader = [System.IO.StringReader]::new($Text)
        $reader = [System.Xml.XmlReader]::Create($stringReader, $settings)
        $document = New-Object System.Xml.XmlDocument
        $document.PreserveWhitespace = $true
        $document.XmlResolver = $null
        $document.Load($reader)
        # Normalize indentation in element-only containers, never leaf values
        # or xml:space significant whitespace. Do this before rule removal.
        foreach ($element in $document.SelectNodes('//*')) {
            $hasElement = $false; $hasText = $false
            foreach ($child in $element.ChildNodes) {
                if ($child.NodeType -eq [Xml.XmlNodeType]::Element) { $hasElement = $true }
                if ($child.NodeType -in @([Xml.XmlNodeType]::Text,[Xml.XmlNodeType]::CDATA,[Xml.XmlNodeType]::SignificantWhitespace)) { $hasText = $true }
            }
            if ($hasElement -and -not $hasText) {
                foreach ($child in @($element.ChildNodes)) {
                    if ($child.NodeType -eq [Xml.XmlNodeType]::Whitespace) { [void]$element.RemoveChild($child) }
                }
            }
        }
        return ,$document
    } catch {
        throw 'Configuration XML is malformed or uses a prohibited DTD/entity.'
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $stringReader) { $stringReader.Dispose() }
    }
}

function Read-QuickXmlFile {
    param([Parameter(Mandatory=$true)][string] $Path)
    $info = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($info.Length -gt $script:QuickRulesMaxXmlBytes) { throw 'Configuration exceeds the 16 MiB safety limit.' }
    $text = [System.IO.File]::ReadAllText($info.FullName)
    $document = ConvertFrom-QuickXmlText -Text $text
    return ,$document
}

function ConvertTo-QuickCsvFields {
    param([Parameter(Mandatory=$true)][string] $Line)
    $fields = New-Object System.Collections.Generic.List[string]
    $field = New-Object System.Text.StringBuilder
    $quoted = $false
    $closedQuote = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $ch = $Line[$i]
        if ($quoted) {
            if ($ch -eq '"') {
                if (($i + 1) -lt $Line.Length -and $Line[$i + 1] -eq '"') {
                    [void]$field.Append('"'); $i++
                } else { $quoted = $false; $closedQuote = $true }
            } else { [void]$field.Append($ch) }
        } elseif ($closedQuote) {
            if ($ch -eq ',') {
                $fields.Add($field.ToString()); [void]$field.Clear(); $closedQuote = $false
            } else { throw 'CSV contains malformed quoting.' }
        } elseif ($ch -eq ',') {
            $fields.Add($field.ToString()); [void]$field.Clear()
        } elseif ($ch -eq '"') {
            if ($field.Length -ne 0) { throw 'CSV contains malformed quoting.' }
            $quoted = $true
        } else { [void]$field.Append($ch) }
    }
    if ($quoted) { throw 'CSV contains malformed quoting.' }
    $fields.Add($field.ToString())
    return ,$fields.ToArray()
}

function Assert-QuickRuleName {
    param([Parameter(Mandatory=$true)][string] $Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 120 -or $Name -cne $Name.Trim() -or
        $Name -match '[\x00-\x1F\x7F]') { throw 'CSV contains an empty or unsafe product name.' }
    try { [void][System.Xml.XmlConvert]::VerifyXmlChars($Name) }
    catch { throw 'Product name contains characters that cannot be represented safely in XML.' }
}

function Normalize-QuickRulePath {
    param([Parameter(Mandatory=$true)][string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -cne $Path.Trim() -or $Path.Length -gt 240) {
        throw 'CSV contains an empty or unsafe executable path.'
    }
    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path.StartsWith('\\') -or $Path -match '[\x00-\x1F<>"/|?*%]' -or
        $Path.Substring(2).Contains(':')) { throw 'Executable paths must be exact absolute Windows drive paths.' }
    $parts = $Path.Substring(3).Split([char]'\')
    if ($parts.Count -lt 1) { throw 'Executable path is incomplete.' }
    foreach ($part in $parts) {
        if ([string]::IsNullOrEmpty($part) -or $part -ceq '.' -or $part -ceq '..' -or
            $part.EndsWith('.') -or $part.EndsWith(' ') -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$') {
            throw 'Executable path contains an unsafe Windows path segment.'
        }
    }
    if ($Path -notmatch '(?i)\.exe$') { throw 'Only exact executable file paths ending in .exe are allowed.' }
    try { [void][System.Xml.XmlConvert]::VerifyXmlChars($Path) }
    catch { throw 'Executable path contains characters that cannot be represented safely in XML.' }
    $base = $Path.Substring($Path.LastIndexOf('\') + 1)
    if ($script:QuickRulesGenericBinaries -contains $base.ToLowerInvariant()) {
        throw 'Generic Windows process binaries are not eligible for blocking.'
    }
    return $Path
}

function New-QuickRuleSpec {
    param([Parameter(Mandatory=$true)][string] $Name, [Parameter(Mandatory=$true)][string] $Path)
    Assert-QuickRuleName -Name $Name
    $safePath = Normalize-QuickRulePath -Path $Path
    $normalized = $safePath.ToUpperInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
        $digest = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').Substring(0, 12)
    } finally { $sha.Dispose() }
    return [pscustomobject]@{
        Name = $Name
        Path = $safePath
        NormalizedPath = $normalized
        RuleName = ($script:QuickRulesOwnedPrefix + $Name + ' - ' + $digest)
    }
}

function Import-QuickRulesCsv {
    param([Parameter(Mandatory=$true)][string] $Path, [Parameter(Mandatory=$true)][string] $ScriptDirectory)
    $info = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($info.Length -gt 1MB) { throw 'Rules CSV exceeds the 1 MiB safety limit.' }
    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    try { $text = [System.IO.File]::ReadAllText($info.FullName, $encoding) }
    catch { throw 'Rules CSV must be valid UTF-8.' }
    $lines = $text -split "`r?`n"
    if ($lines.Count -lt 2 -or [string]::IsNullOrWhiteSpace($lines[0])) { throw 'Rules CSV must contain the exact Name,Path header and at least one row.' }
    $header = ConvertTo-QuickCsvFields -Line $lines[0].TrimEnd([char]"`r")
    if ($header.Count -ne 2 -or $header[0] -cne 'Name' -or $header[1] -cne 'Path') {
        throw 'Rules CSV columns must be exactly Name,Path.'
    }
    $expectedRows = 0
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].TrimEnd([char]"`r")
        if ($i -eq ($lines.Count - 1) -and $line.Length -eq 0) { continue }
        if ($line.Length -eq 0) { throw 'Rules CSV contains an empty row.' }
        $fields = ConvertTo-QuickCsvFields -Line $line
        if ($fields.Count -ne 2) { throw 'Rules CSV rows must contain exactly two columns.' }
        $expectedRows++
    }
    if ($expectedRows -eq 0) { throw 'Rules CSV must contain at least one rule.' }
    try { $rows = @(Import-Csv -LiteralPath $info.FullName -ErrorAction Stop) }
    catch { throw 'Rules CSV could not be parsed.' }
    if ($rows.Count -ne $expectedRows) { throw 'Rules CSV contains an inconsistent number of records.' }
    $seenNames = @{}
    $seenPaths = @{}
    $desired = New-Object System.Collections.Generic.List[object]
    foreach ($row in $rows) {
        $properties = @($row.PSObject.Properties | ForEach-Object { $_.Name })
        if ($properties.Count -ne 2 -or $properties[0] -cne 'Name' -or $properties[1] -cne 'Path') {
            throw 'Rules CSV columns must be exactly Name,Path.'
        }
        $name = [string]$row.Name
        $rawPath = [string]$row.Path
        Assert-QuickRuleName -Name $name
        if ($rawPath -ceq '.\LolrmmEsetTest.exe') {
            if ($name -cne 'LolrmmEsetTest' -or $ScriptDirectory -notmatch '^[A-Za-z]:\\') {
                throw 'Only the harmless sibling LolrmmEsetTest.exe may use a relative path.'
            }
            $rawPath = $ScriptDirectory.TrimEnd('\') + '\LolrmmEsetTest.exe'
        } elseif ($rawPath -match '^[.]{1,2}[\\/]') {
            throw 'Only the harmless sibling LolrmmEsetTest.exe may use a relative path.'
        }
        $spec = New-QuickRuleSpec -Name $name -Path $rawPath
        $nameKey = $name.ToUpperInvariant()
        $pathKey = $spec.NormalizedPath
        if ($seenNames.ContainsKey($nameKey) -and $seenNames[$nameKey] -cne $pathKey) {
            throw 'The same product name has conflicting executable paths.'
        }
        $seenNames[$nameKey] = $pathKey
        if (-not $seenPaths.ContainsKey($pathKey)) {
            $seenPaths[$pathKey] = $true
            $desired.Add($spec)
        }
    }
    if ($desired.Count -eq 0) { throw 'Rules CSV contains no unique executable paths.' }
    return ,$desired.ToArray()
}

function Get-QuickHipsContext {
    param([Parameter(Mandatory=$true)][System.Xml.XmlDocument] $Configuration)
    if ($Configuration.DocumentElement -eq $null -or $Configuration.DocumentElement.LocalName -cne 'ESET' -or
        -not [string]::IsNullOrEmpty($Configuration.DocumentElement.NamespaceURI) -or -not [string]::IsNullOrEmpty($Configuration.DocumentElement.Prefix)) {
        throw 'Unknown configuration root.'
    }
    $products = Get-QuickDirectElements -Parent $Configuration.DocumentElement -ElementName 'PRODUCT' -NameAttribute 'home'
    if ($products.Count -ne 1) { throw 'Expected exactly one unambiguous home product wrapper.' }
    $product = $products[0]
    if (-not $product.HasAttribute('VERSION') -or $product.GetAttribute('VERSION') -notmatch '^19(?:\.|$)') {
        throw 'Only ESET consumer home export major 19 is supported by this experimental POC.'
    }
    $current = $product
    foreach ($name in @('plugins','01000001','settings','rules')) {
        $items = Get-QuickDirectElements -Parent $current -ElementName 'ITEM' -NameAttribute $name
        if ($items.Count -ne 1) { throw 'Expected exactly one known HIPS rules collection; configuration is ambiguous or unknown.' }
        $current = $items[0]
    }
    $rules = New-Object System.Collections.Generic.List[System.Xml.XmlElement]
    $ids = @{}
    $ruleNames = @{}
    [UInt64]$maximum = 0
    foreach ($child in $current.ChildNodes) {
        if ($child -isnot [System.Xml.XmlElement]) { continue }
        if ($child.LocalName -cne 'ITEM' -or -not [string]::IsNullOrEmpty($child.NamespaceURI) -or
            -not [string]::IsNullOrEmpty($child.Prefix) -or -not $child.HasAttribute('NAME')) {
            throw 'HIPS rules collection contains an unknown element.'
        }
        $idText = $child.GetAttribute('NAME')
        [UInt64]$idValue = 0
        if ($idText -notmatch '^[0-9A-Fa-f]+$' -or -not [UInt64]::TryParse($idText, [Globalization.NumberStyles]::AllowHexSpecifier, [Globalization.CultureInfo]::InvariantCulture, [ref]$idValue)) {
            throw 'HIPS rule identifiers are not unambiguous hexadecimal values.'
        }
        $idKey = $idText.ToUpperInvariant()
        if ($ids.ContainsKey($idKey) -or $ids.ContainsKey($idValue.ToString('X'))) { throw 'Duplicate HIPS rule identifiers are ambiguous.' }
        $ids[$idKey] = $true
        $ids[$idValue.ToString('X')] = $true
        if ($idValue -gt $maximum) { $maximum = $idValue }
        $nameNode = Get-QuickDirectElements -Parent $child -ElementName 'NODE' -NameAttribute 'name'
        if ($nameNode.Count -ne 1 -or $nameNode[0].GetAttribute('TYPE') -cne 'string' -or -not $nameNode[0].HasAttribute('VALUE')) {
            throw 'A HIPS rule has an unknown or ambiguous name field.'
        }
        $ruleName = $nameNode[0].GetAttribute('VALUE')
        if ([string]::IsNullOrEmpty($ruleName)) { throw 'A HIPS rule has an empty name.' }
        $nameKey = $ruleName.ToUpperInvariant()
        if ($ruleNames.ContainsKey($nameKey)) { throw 'Duplicate HIPS rule names are ambiguous.' }
        $ruleNames[$nameKey] = $true
        $rules.Add($child)
    }
    return [pscustomobject]@{ Product = $product; Collection = $current; Rules = $rules.ToArray(); MaximumId = $maximum }
}

function Get-QuickNodeValue {
    param([System.Xml.XmlNode] $Parent, [string] $Name)
    $nodes = Get-QuickDirectElements -Parent $Parent -ElementName 'NODE' -NameAttribute $Name
    if ($nodes.Count -ne 1 -or $nodes[0].GetAttribute('TYPE') -cne 'string' -or -not $nodes[0].HasAttribute('VALUE')) {
        throw 'An existing managed rule has an unknown or ambiguous field.'
    }
    return $nodes[0].GetAttribute('VALUE')
}

function Add-QuickNode {
    param([System.Xml.XmlDocument] $Document, [System.Xml.XmlElement] $Parent, [string] $Name, [string] $Type, [string] $Value)
    $node = $Document.CreateElement('NODE')
    $node.SetAttribute('NAME', $Name)
    $node.SetAttribute('TYPE', $Type)
    $node.SetAttribute('VALUE', $Value)
    [void]$Parent.AppendChild($node)
    return ,$node
}

function Add-QuickItem {
    param([System.Xml.XmlDocument] $Document, [System.Xml.XmlElement] $Parent, [string] $Name, [bool] $Delete)
    $item = $Document.CreateElement('ITEM')
    $item.SetAttribute('NAME', $Name)
    if ($Delete) { $item.SetAttribute('DELETE', '1') }
    [void]$Parent.AppendChild($item)
    return ,$item
}

function New-QuickExpectedRule {
    param([System.Xml.XmlDocument] $Document, [string] $Id, [string] $RuleName, [string] $Path)
    $rule = $Document.CreateElement('ITEM')
    $rule.SetAttribute('NAME', $Id)
    [void](Add-QuickNode $Document $rule 'enabled' 'number' '1')
    [void](Add-QuickNode $Document $rule 'name' 'string' $RuleName)
    [void](Add-QuickNode $Document $rule 'priority' 'number' '80')
    [void](Add-QuickNode $Document $rule 'action' 'number' '2')
    [void](Add-QuickNode $Document $rule 'notify' 'number' '1')
    [void](Add-QuickNode $Document $rule 'allAppSources' 'number' '1')
    [void](Add-QuickItem $Document $rule 'appSources' $true)
    [void](Add-QuickNode $Document $rule 'hasFileTargets' 'number' '0')
    [void](Add-QuickNode $Document $rule 'hasRegTargets' 'number' '0')
    [void](Add-QuickNode $Document $rule 'hasPeTargets' 'number' '1')
    $fileOps = Add-QuickItem $Document $rule 'fileOperations' $false
    foreach ($field in @('File_AllOperations','File_Delete','File_Modify','File_DirectDiskAccess','Image_GlobalHook','Image_LoadDriver')) {
        [void](Add-QuickNode $Document $fileOps $field 'number' '0')
    }
    $regOps = Add-QuickItem $Document $rule 'regOperations' $false
    foreach ($field in @('Registry_AllOperations','Registry_ModifyStartup','Registry_Delete','Registry_Rename','Registry_Modify')) {
        [void](Add-QuickNode $Document $regOps $field 'number' '0')
    }
    $peOps = Add-QuickItem $Document $rule 'peOperations' $false
    foreach ($field in @('Process_AllOperations','Application_Debug','Application_Hook','Application_Stop','Application_Create','Application_Modify')) {
        $value = if ($field -ceq 'Application_Create') { '1' } else { '0' }
        [void](Add-QuickNode $Document $peOps $field 'number' $value)
    }
    [void](Add-QuickNode $Document $rule 'allFileTargets' 'number' '0')
    [void](Add-QuickItem $Document $rule 'fileTargets' $true)
    [void](Add-QuickNode $Document $rule 'allRegTargets' 'number' '0')
    [void](Add-QuickItem $Document $rule 'regTargets' $true)
    [void](Add-QuickNode $Document $rule 'allPeTargets' 'number' '0')
    $peTargets = Add-QuickItem $Document $rule 'peTargets' $true
    [void](Add-QuickNode $Document $peTargets '1' 'string' $Path)
    [void](Add-QuickNode $Document $rule 'severity' 'number' '3')
    return ,$rule
}

function ConvertTo-QuickCanonicalNode {
    param([System.Xml.XmlNode] $Node, [System.Text.StringBuilder] $Builder, [bool] $IgnoreRootId = $false, [bool] $IsRoot = $true)
    if ($Node.NodeType -eq [System.Xml.XmlNodeType]::Document) {
        foreach ($child in $Node.ChildNodes) {
            if ($child.NodeType -ne [Xml.XmlNodeType]::Whitespace) { ConvertTo-QuickCanonicalNode $child $Builder $IgnoreRootId $false }
        }
        return
    }
    if ($Node.NodeType -eq [System.Xml.XmlNodeType]::Element) {
        [void]$Builder.Append('<').Append($Node.LocalName).Append('@').Append($Node.NamespaceURI.Length).Append(':').Append($Node.NamespaceURI)
        $attrs = @($Node.Attributes | Sort-Object Name -CaseSensitive)
        foreach ($attr in $attrs) {
            if ($IgnoreRootId -and $IsRoot -and $attr.Name -ceq 'NAME') { continue }
            [void]$Builder.Append(' ').Append($attr.Name).Append('=')
            [void]$Builder.Append(([string]$attr.Value).Length).Append(':').Append([string]$attr.Value)
        }
        [void]$Builder.Append('>')
        foreach ($child in $Node.ChildNodes) {
            ConvertTo-QuickCanonicalNode $child $Builder $IgnoreRootId $false
        }
        [void]$Builder.Append('</').Append($Node.LocalName).Append('>')
    } elseif ($Node.NodeType -eq [System.Xml.XmlNodeType]::Text -or $Node.NodeType -eq [System.Xml.XmlNodeType]::CDATA -or
        $Node.NodeType -eq [System.Xml.XmlNodeType]::Comment -or $Node.NodeType -eq [System.Xml.XmlNodeType]::ProcessingInstruction -or
        $Node.NodeType -eq [System.Xml.XmlNodeType]::XmlDeclaration -or
        $Node.NodeType -eq [System.Xml.XmlNodeType]::Whitespace -or
        $Node.NodeType -eq [System.Xml.XmlNodeType]::SignificantWhitespace) {
        $value = [string]$Node.Value
        [void]$Builder.Append('!').Append([int]$Node.NodeType).Append(':').Append($value.Length).Append(':').Append($value)
    }
}

function Get-QuickCanonicalXml {
    param([System.Xml.XmlNode] $Node, [switch] $IgnoreRootId)
    $builder = New-Object System.Text.StringBuilder
    ConvertTo-QuickCanonicalNode $Node $builder ([bool]$IgnoreRootId) $true
    return $builder.ToString()
}

function Get-QuickRulesPlan {
    param([Parameter(Mandatory=$true)][object[]] $Desired, [Parameter(Mandatory=$true)][System.Xml.XmlDocument] $Configuration)
    if ($Desired.Count -eq 0) { throw 'At least one exact executable rule is required.' }
    $context = Get-QuickHipsContext -Configuration $Configuration
    $normalizedDesired = New-Object System.Collections.Generic.List[object]
    $inputNames = @{}
    $inputPaths = @{}
    foreach ($entry in $Desired) {
        $spec = New-QuickRuleSpec -Name ([string]$entry.Name) -Path ([string]$entry.Path)
        $nameKey = $spec.Name.ToUpperInvariant()
        if ($inputNames.ContainsKey($nameKey) -and $inputNames[$nameKey] -cne $spec.NormalizedPath) { throw 'The same product name has conflicting executable paths.' }
        $inputNames[$nameKey] = $spec.NormalizedPath
        if (-not $inputPaths.ContainsKey($spec.NormalizedPath)) {
            $inputPaths[$spec.NormalizedPath] = $true
            $normalizedDesired.Add($spec)
        }
    }
    $existingByName = @{}
    foreach ($rule in $context.Rules) {
        $ruleName = Get-QuickNodeValue -Parent $rule -Name 'name'
        $existingByName[$ruleName.ToUpperInvariant()] = $rule
    }
    $additions = New-Object System.Collections.Generic.List[object]
    $unchanged = New-Object System.Collections.Generic.List[object]
    foreach ($spec in $normalizedDesired) {
        $key = $spec.RuleName.ToUpperInvariant()
        if ($existingByName.ContainsKey($key)) {
            $existing = $existingByName[$key]
            $expected = New-QuickExpectedRule -Document $Configuration -Id $existing.GetAttribute('NAME') -RuleName $spec.RuleName -Path $spec.Path
            $comparable = [System.Xml.XmlElement]$existing.CloneNode($true)
            $targetLists = Get-QuickDirectElements $comparable 'ITEM' 'peTargets'
            if ($targetLists.Count -eq 1) {
                $targets = Get-QuickDirectElements $targetLists[0] 'NODE' '1'
                if ($targets.Count -eq 1 -and $targets[0].GetAttribute('TYPE') -ceq 'string' -and
                    $targets[0].GetAttribute('VALUE').Equals($spec.Path,[StringComparison]::OrdinalIgnoreCase)) {
                    $targets[0].SetAttribute('VALUE',$spec.Path)
                }
            }
            if ((Get-QuickCanonicalXml $comparable -IgnoreRootId) -cne (Get-QuickCanonicalXml $expected -IgnoreRootId)) {
                throw 'An owned rule name already exists with different semantics; no update or removal is allowed.'
            }
            $unchanged.Add($spec)
        } else { $additions.Add($spec) }
    }
    if ([UInt64]$context.MaximumId -eq [UInt64]::MaxValue -and $additions.Count -gt 0) { throw 'No collision-free hexadecimal rule identifiers remain.' }
    return [pscustomobject]@{ Context = $context; Desired = $normalizedDesired.ToArray(); Additions = $additions.ToArray(); Unchanged = $unchanged.ToArray() }
}

function New-QuickAppendPayload {
    param([Parameter(Mandatory=$true)][System.Xml.XmlDocument] $Configuration, [Parameter(Mandatory=$true)][object[]] $Additions)
    if ($Additions.Count -eq 0) { throw 'An empty APPEND payload is prohibited.' }
    $context = Get-QuickHipsContext -Configuration $Configuration
    $payload = New-Object System.Xml.XmlDocument
    $payload.PreserveWhitespace = $true
    $payload.XmlResolver = $null
    $declaration = $payload.CreateXmlDeclaration('1.0', 'utf-8', $null)
    [void]$payload.AppendChild($declaration)
    $root = $payload.CreateElement('ESET'); [void]$payload.AppendChild($root)
    $product = [System.Xml.XmlElement]$payload.ImportNode($context.Product.CloneNode($false), $true)
    [void]$root.AppendChild($product)
    $plugins = Add-QuickItem $payload $product 'plugins' $false
    $plugin = Add-QuickItem $payload $plugins '01000001' $false
    $settings = Add-QuickItem $payload $plugin 'settings' $false
    $rules = Add-QuickItem $payload $settings 'rules' $false
    $rules.SetAttribute('APPEND', '1')
    [UInt64]$next = $context.MaximumId
    foreach ($spec in $Additions) {
        if ($next -eq [UInt64]::MaxValue) { throw 'No collision-free hexadecimal rule identifiers remain.' }
        $next++
        $rule = New-QuickExpectedRule -Document $payload -Id $next.ToString('X') -RuleName $spec.RuleName -Path $spec.Path
        [void]$rules.AppendChild($rule)
    }
    return ,$payload
}

function Assert-QuickSignedPayload {
    param([Xml.XmlDocument] $Before, [Xml.XmlDocument] $Signed)
    # Observed from the official XmlSignTool /version 2 on both Windows CI legs.
    # This validates representation and unchanged content, NOT cryptographic validity.
    $copy = [Xml.XmlDocument]$Signed.CloneNode($true)
    $markers = @($copy.SelectNodes('//comment()') | Where-Object { $_.Value -cmatch '\A Signature: [A-Za-z0-9+/]{86}== \z' })
    if ($markers.Count -ne 1 -or $markers[0].ParentNode -ne $copy) { throw 'Expected exactly one trailing native signature comment.' }
    $last = @($copy.ChildNodes | Where-Object { $_.NodeType -ne [Xml.XmlNodeType]::Whitespace })[-1]
    if ($last -ne $markers[0]) { throw 'Native signature comment is not the final document node.' }
    $encoded = $markers[0].Value.Substring(12,88)
    if ([Convert]::FromBase64String($encoded).Length -ne 64) { throw 'Unexpected native signature length.' }
    [void]$copy.RemoveChild($markers[0])
    if ((Get-QuickCanonicalXml $Before) -cne (Get-QuickCanonicalXml $copy)) { throw 'Signer changed payload XML beyond the exact observed signature comment.' }
}

function Show-QuickRulesPlan {
    param([object] $Plan)
    [Console]::WriteLine('EXPERIMENTAL ESET 19 append schema: NOT CERTIFIED; preview is not evidence of blocking.')
    foreach ($entry in $Plan.Additions) { [Console]::WriteLine(('ADD       {0}  ->  {1}' -f $entry.RuleName, $entry.Path)) }
    foreach ($entry in $Plan.Unchanged) { [Console]::WriteLine(('UNCHANGED {0}  ->  {1}' -f $entry.RuleName, $entry.Path)) }
    [Console]::WriteLine(('Counts: ADD={0}; UNCHANGED={1}' -f $Plan.Additions.Count, $Plan.Unchanged.Count))
}

function Quote-QuickWindowsArgument {
    param([Parameter(Mandatory=$true)][string] $Argument)
    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') { return $Argument }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append([char]34)
    $slashes = 0
    foreach ($ch in $Argument.ToCharArray()) {
        if ($ch -eq [char]92) { $slashes++; continue }
        if ($ch -eq [char]34) {
            if ($slashes -gt 0) { [void]$builder.Append([char]92, (2 * $slashes)) }
            [void]$builder.Append([char]92).Append([char]34); $slashes = 0; continue
        }
        if ($slashes -gt 0) { [void]$builder.Append([char]92, $slashes); $slashes = 0 }
        [void]$builder.Append($ch)
    }
    if ($slashes -gt 0) { [void]$builder.Append([char]92, (2 * $slashes)) }
    [void]$builder.Append([char]34)
    return $builder.ToString()
}

function Invoke-QuickProcess {
    param([string] $FilePath, [string[]] $Arguments, [int] $TimeoutSeconds = 180, [switch] $Interactive)
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $FilePath
    $start.Arguments = (($Arguments | ForEach-Object { Quote-QuickWindowsArgument ([string]$_) }) -join ' ')
    $start.UseShellExecute = [bool]$Interactive
    if (-not $Interactive) { $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true; $start.CreateNoWindow = $true }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    $stdoutTask = $null; $stderrTask = $null
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw 'Process did not start.' }
        if (-not $Interactive) {
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
        }
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch {}
            [void]$process.WaitForExit(5000)
            throw 'Process timed out. Termination of all native work is unproven; outcome unknown. Inspect ESET before any retry.'
        }
        if ($Interactive) { return [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = ''; StdErr = '' } }
        $process.WaitForExit()
        $remaining = [Math]::Max(0,($TimeoutSeconds * 1000 - [int]$clock.ElapsedMilliseconds))
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask),[int]$remaining)) {
            throw 'Output collection timed out; a descendant may still be active. Outcome unknown; inspect ESET before any retry.'
        }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdoutTask.Result; StdErr = $stderrTask.Result }
    } finally { $process.Dispose() }
}

function Get-QuickFileHash {
    param([string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Assert-QuickEsetSignature {
    param([Parameter(Mandatory=$true)][string] $Path)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'ESET Authenticode verification is available only on Windows.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
        $null -eq $signature.SignerCertificate -or
        [string]$signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O="?ESET, spol\. s r\.o\."?(?:,|$)') {
        throw 'ESET executable Authenticode signature is not valid for an ESET signer.'
    }
    return Get-QuickFileHash -Path $Path
}

function Get-QuickEsetInstall {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Live ESET Preview and Apply require Windows.' }
    $views = @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)
    $installedProducts = New-Object System.Collections.Generic.List[object]
    foreach ($view in $views) {
        $base = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            $uninstall = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
            if ($null -eq $uninstall) { continue }
            foreach ($subName in $uninstall.GetSubKeyNames()) {
                $key = $uninstall.OpenSubKey($subName)
                if ($null -eq $key) { continue }
                try {
                    $display = [string]$key.GetValue('DisplayName', '')
                    $version = [string]$key.GetValue('DisplayVersion', '')
                    if ($display -match '(?i)^ESET (?:HOME )?Security(?:\s|$)' -and
                        $display -notmatch '(?i)Endpoint|PROTECT|Inspect|Server' -and $version -match '^19(?:\.|$)') {
                        $install = [string]$key.GetValue('InstallLocation', '')
                        if ([string]::IsNullOrWhiteSpace($install)) {
                            $icon = [string]$key.GetValue('DisplayIcon', '')
                            if ($icon -match '^(?:"([^"]+\.exe)"|([^"]+\.exe))(?:,\d+)?$') {
                                $iconPath = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
                                $install = Split-Path -Parent $iconPath
                            }
                        }
                        $installedProducts.Add([pscustomobject]@{ Name = $display; Version = $version; InstallLocation = $install })
                    }
                } finally { $key.Dispose() }
            }
            $uninstall.Dispose()
        } finally { if ($null -ne $base) { $base.Dispose() } }
    }
    $unique = @($installedProducts | Sort-Object Name, Version, InstallLocation -Unique)
    if ($unique.Count -ne 1) { throw 'Could not identify exactly one installed ESET consumer product major 19.' }
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($unique[0].InstallLocation)) { $candidates.Add((Join-Path $unique[0].InstallLocation 'ecmd.exe')) }
    foreach ($programRoot in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not [string]::IsNullOrWhiteSpace($programRoot)) {
            foreach ($folder in @('ESET\ESET Security','ESET\ESET HOME Security')) { $candidates.Add((Join-Path (Join-Path $programRoot $folder) 'ecmd.exe')) }
        }
    }
    $ecmd = @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -Unique)
    if ($ecmd.Count -ne 1) { throw 'Could not identify exactly one ESET ecmd.exe for the installed consumer product.' }
    return [pscustomobject]@{ Product = $unique[0]; EcmdPath = $ecmd[0] }
}

function Test-QuickAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-QuickPrivateAcl {
    param([Parameter(Mandatory=$true)][string] $Path)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Private Windows ACL setup is unavailable.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $sid = $identity.User
    if ($null -eq $sid) { throw 'Could not identify the current Windows user SID.' }
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $rule = [Security.AccessControl.FileSystemAccessRule]::new($sid, [Security.AccessControl.FileSystemRights]::FullControl, [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit', [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
    [void]$acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
    $check = Get-Acl -LiteralPath $Path -ErrorAction Stop
    if (-not $check.AreAccessRulesProtected) { throw 'Private run-directory DACL inheritance could not be disabled.' }
    foreach ($access in $check.Access) {
        if ($access.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -ne $sid.Value -or
            $access.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
            ($access.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq 0) {
            throw 'Private run-directory DACL contains an unexpected access rule.'
        }
    }
}

function Test-QuickNoReparsePath {
    param([string] $Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $cursor = $full
    while (-not [string]::IsNullOrEmpty($cursor)) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Private run path contains a reparse point.' }
        $parent = Split-Path -Parent $cursor
        if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $cursor) { break }
        $cursor = $parent
    }
}

function New-QuickRunRoot {
    $local = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($local) -or -not (Test-Path -LiteralPath $local -PathType Container)) { throw 'Local application data folder is unavailable.' }
    if ($local -match '(?i)(^|[\\/])(OneDrive(?: [^\\/]+)?|Dropbox|Google Drive|iCloudDrive)([\\/]|$)') { throw 'Local application data resolves inside a known cloud-sync folder.' }
    $volume = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($local))
    $drive = [System.IO.DriveInfo]::new($volume)
    if ($volume -notmatch '^[A-Za-z]:\\$' -or $drive.DriveType -ne [System.IO.DriveType]::Fixed) {
        throw 'Private evidence requires a local fixed Windows drive.'
    }
    $base = Join-Path $local 'LOLRMM-QuickRules'
    if (-not (Test-Path -LiteralPath $base)) { [void][System.IO.Directory]::CreateDirectory($base) }
    Test-QuickNoReparsePath -Path $base
    Set-QuickPrivateAcl -Path $base
    $runs = Join-Path $base 'runs'
    if (-not (Test-Path -LiteralPath $runs)) { [void][System.IO.Directory]::CreateDirectory($runs) }
    Test-QuickNoReparsePath -Path $runs
    Set-QuickPrivateAcl -Path $runs
    $run = Join-Path $runs ([Guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($run)
    Test-QuickNoReparsePath -Path $run
    Set-QuickPrivateAcl -Path $run
    return $run
}

function Get-QuickSignerPath {
    param([string] $SuppliedPath, [string] $RunRoot)
    if (-not [string]::IsNullOrWhiteSpace($SuppliedPath)) {
        if (-not (Test-Path -LiteralPath $SuppliedPath -PathType Leaf)) { throw 'The supplied signer path does not exist.' }
        return [pscustomobject]@{ Path = (Get-Item -LiteralPath $SuppliedPath).FullName; Hash = (Assert-QuickEsetSignature -Path $SuppliedPath) }
    }
    $download = Join-Path $RunRoot 'xmlsigntool.exe.download'
    $final = Join-Path $RunRoot 'xmlsigntool.exe'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $script:QuickRulesSignerUrl -OutFile $download -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        $hash = Assert-QuickEsetSignature -Path $download
        [System.IO.File]::Move($download, $final)
        return [pscustomobject]@{ Path = $final; Hash = $hash }
    } catch {
        Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
        throw 'Official XmlSignTool download or ESET Authenticode verification failed.'
    }
}

function Write-QuickDiagnostic {
    param([string] $Path, [string] $Message)
    $safe = [DateTime]::UtcNow.ToString('o') + ' ' + $Message + [Environment]::NewLine
    [System.IO.File]::AppendAllText($Path, $safe, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-QuickResults {
    param([string] $RunRoot, [string] $Status, [int] $Added, [int] $Unchanged)
    $lines = @(
        'LOLRMM Quick Rules Phase 1 append experiment',
        ('Status: ' + $Status),
        'Append schema: EXPERIMENTAL - NOT CERTIFIED',
        'Native block/log/unblock: OWNER_PENDING - NOT VERIFIED',
        ('Added: ' + $Added),
        ('Unchanged: ' + $Unchanged),
        'No automatic rollback or restore was attempted.'
    )
    [System.IO.File]::WriteAllLines((Join-Path $RunRoot 'RESULTS.txt'), $lines, (New-Object System.Text.UTF8Encoding($false)))
}

function Assert-QuickProviderResult {
    param([object] $Result, [string] $Operation)
    if ($null -eq $Result -or -not $Result.PSObject.Properties['ExitCode'] -or [int]$Result.ExitCode -ne 0) {
        $details = ''
        $exitCode = 'unknown'
        if ($null -ne $Result) {
            if ($Result.PSObject.Properties['ExitCode']) { $exitCode = [string]$Result.ExitCode }
            if ($Result.PSObject.Properties['StdOut']) { $details += [string]$Result.StdOut }
            if ($Result.PSObject.Properties['StdErr']) { $details += [string]$Result.StdErr }
        }
        if ($details.Length -gt 65536) { $details = $details.Substring(0, 65536) }
        throw ($Operation + ' failed or timed out. ExitCode=' + $exitCode + '; Output=' + $details)
    }
}

function Get-QuickProviderConfiguration {
    param([hashtable] $Providers, [string] $Path, [string] $Operation)
    $result = & $Providers.Export $Path
    Assert-QuickProviderResult -Result $result -Operation $Operation
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ($Operation + ' did not create an export file.') }
    $document = Read-QuickXmlFile -Path $Path
    if ($Providers.ContainsKey('ExpectedVersion')) {
        $expectedVersion = [string]$Providers.ExpectedVersion
        $context = Get-QuickHipsContext -Configuration $document
        if ($expectedVersion -cnotmatch '^19\.\d+\.\d+(?:\.\d+)?$' -or
            $context.Product.GetAttribute('VERSION') -cne $expectedVersion) {
            throw 'Export does not exactly match the independently identified installed consumer version.'
        }
    }
    return ,$document
}

function Save-QuickPayload {
    param([System.Xml.XmlDocument] $Payload, [string] $Path)
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.Indent = $true
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::None
    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try { $Payload.Save($writer) } finally { $writer.Dispose() }
}

function Confirm-QuickApply {
    param([object] $Plan)
    Show-QuickRulesPlan -Plan $Plan
    [Console]::WriteLine('This is an experimental, uncertified ESET 19 append test. It does not prove blocking.')
    [Console]::WriteLine('Owner acknowledgment: confirm HIPS is enabled on this isolated test machine by typing HIPS-ENABLED.')
    $hips = [Console]::ReadLine()
    if ($hips -cne 'HIPS-ENABLED') { return $false }
    [Console]::WriteLine('After reviewing the exact names and paths above, type APPLY to continue.')
    return ([Console]::ReadLine() -ceq 'APPLY')
}

function Invoke-QuickApplyTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object[]] $Desired,
        [Parameter(Mandatory=$true)][hashtable] $Providers,
        [Parameter(Mandatory=$true)][string] $RunRoot,
        [switch] $TestOnlyProvider
    )
    if (-not (Test-Path -LiteralPath $RunRoot -PathType Container)) { throw 'Private run directory is unavailable.' }
    foreach ($required in @('Export','Sign','Import')) {
        if (-not $Providers.ContainsKey($required) -or $Providers[$required] -isnot [scriptblock]) { throw 'A required transaction provider is unavailable.' }
    }
    if (-not $TestOnlyProvider -and $Providers['ProductionVerified'] -ne $true) { throw 'Unverified transaction providers are prohibited.' }
    $diagPath = Join-Path $RunRoot 'DIAGNOSTICS.log'
    $baselinePath = Join-Path $RunRoot 'before.xml'
    $payloadPath = Join-Path $RunRoot 'append-payload.xml'
    $concurrentPath = Join-Path $RunRoot 'before-import.xml'
    $afterPath = Join-Path $RunRoot 'after.xml'
    $added = 0; $unchanged = 0; $importStarted = $false; $stage = 'baseline export'
    try {
        $baseline = Get-QuickProviderConfiguration -Providers $Providers -Path $baselinePath -Operation 'Initial safe export'
        Copy-Item -LiteralPath $baselinePath -Destination (Join-Path $RunRoot 'before-untouched.xml') -Force -ErrorAction Stop
        $plan = Get-QuickRulesPlan -Desired $Desired -Configuration $baseline
        $added = $plan.Additions.Count; $unchanged = $plan.Unchanged.Count
        if (-not $TestOnlyProvider) {
            if (-not $Providers.ContainsKey('Confirm') -or $Providers['Confirm'] -isnot [scriptblock]) { throw 'Visible owner confirmation is unavailable.' }
            $confirmed = & $Providers.Confirm $plan
            if (-not $confirmed) {
                Write-QuickResults -RunRoot $RunRoot -Status 'CANCELLED_BEFORE_IMPORT' -Added $added -Unchanged $unchanged
                return [pscustomobject]@{ Success = $false; Cancelled = $true; AddedCount = $added; UnchangedCount = $unchanged; OwnerPending = $true; Experimental = $true; DiagnosticsPath = $diagPath; Names = @($plan.Desired | ForEach-Object { $_.RuleName }) }
            }
        }
        if ($added -eq 0) {
            Write-QuickResults -RunRoot $RunRoot -Status 'NO_CHANGES_VERIFIED' -Added 0 -Unchanged $unchanged
            return [pscustomobject]@{ Success = $true; AddedCount = 0; UnchangedCount = $unchanged; OwnerPending = $true; Experimental = $true; DiagnosticsPath = $diagPath; Names = @($plan.Desired | ForEach-Object { $_.RuleName }) }
        }
        $stage = 'payload generation'
        $payload = New-QuickAppendPayload -Configuration $baseline -Additions @($plan.Additions)
        Save-QuickPayload -Payload $payload -Path $payloadPath
        $payloadCanonical = Get-QuickCanonicalXml (Read-QuickXmlFile -Path $payloadPath)
        $stage = 'official interactive signing'
        $signResult = & $Providers.Sign $payloadPath
        Assert-QuickProviderResult -Result $signResult -Operation 'Official interactive signing'
        $stage = 'signed payload integrity'
        $payloadLock = [IO.File]::Open($payloadPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try {
            $signed = Read-QuickXmlFile -Path $payloadPath
            Assert-QuickSignedPayload -Before $payload -Signed $signed
            $signedHash = Get-QuickFileHash -Path $payloadPath
            $stage = 'pre-import concurrency export'
            $concurrent = Get-QuickProviderConfiguration -Providers $Providers -Path $concurrentPath -Operation 'Pre-import safe export'
            if ((Get-QuickCanonicalXml $baseline) -cne (Get-QuickCanonicalXml $concurrent)) { throw 'Configuration changed after preview; import was stopped.' }
            $stage = 'signed payload integrity'
            $hash = [Security.Cryptography.SHA256]::Create()
            try { $lockedHash = [BitConverter]::ToString($hash.ComputeHash($payloadLock)).Replace('-','') } finally { $hash.Dispose() }
            if ($lockedHash -cne $signedHash) { throw 'Signed payload changed after validation; import stopped.' }
            $stage = 'ecmd import'
            $importStarted = $true
            $importResult = & $Providers.Import $payloadPath
            Assert-QuickProviderResult -Result $importResult -Operation 'ESET ecmd import'
        } finally { $payloadLock.Dispose() }
        $stage = 'post-import readback export'
        $after = Get-QuickProviderConfiguration -Providers $Providers -Path $afterPath -Operation 'Post-import safe export'
        $afterPlan = Get-QuickRulesPlan -Desired $plan.Desired -Configuration $after
        if ($afterPlan.Additions.Count -ne 0 -or $afterPlan.Unchanged.Count -ne $plan.Desired.Count) { throw 'Post-import readback did not contain every exact expected rule.' }
        $afterContext = Get-QuickHipsContext -Configuration $after
        $removeNames = @{}; foreach ($entry in $plan.Additions) { $removeNames[$entry.RuleName.ToUpperInvariant()] = $true }
        foreach ($rule in @($afterContext.Rules)) {
            $ruleName = Get-QuickNodeValue -Parent $rule -Name 'name'
            if ($removeNames.ContainsKey($ruleName.ToUpperInvariant())) { [void]$afterContext.Collection.RemoveChild($rule) }
        }
        if ((Get-QuickCanonicalXml $baseline) -cne (Get-QuickCanonicalXml $after)) {
            throw 'Post-import configuration changed unrelated or pre-existing settings/rules.'
        }
        Write-QuickResults -RunRoot $RunRoot -Status 'READBACK_VERIFIED_NOT_ENFORCEMENT' -Added $added -Unchanged $unchanged
        return [pscustomobject]@{ Success = $true; AddedCount = $added; UnchangedCount = $unchanged; OwnerPending = $true; Experimental = $true; DiagnosticsPath = $diagPath; Names = @($plan.Desired | ForEach-Object { $_.RuleName }) }
    } catch {
        $raw = $_.Exception.ToString()
        try { Write-QuickDiagnostic -Path $diagPath -Message ('Stage=' + $stage + '; ' + $raw) } catch {}
        $status = if ($importStarted) { 'IMPORT_OR_READBACK_UNVERIFIED' } else { 'FAILED_BEFORE_IMPORT' }
        try { Write-QuickResults -RunRoot $RunRoot -Status $status -Added $added -Unchanged $unchanged } catch {}
        throw ('Apply transaction failed at ' + $stage + '. Import/native-work outcome may be unknown; inspect ESET before retrying. No automatic rollback was attempted; private diagnostics: ' + $diagPath + '.')
    }
}

function New-QuickProductionProviders {
    param([object] $Install, [object] $Signer)
    $ecmdPath = $Install.EcmdPath
    $ecmdHash = Assert-QuickEsetSignature -Path $ecmdPath
    $signerPath = $Signer.Path
    $signerHash = $Signer.Hash
    $export = {
        param($path)
        if ((Assert-QuickEsetSignature -Path $ecmdPath) -cne $ecmdHash) { throw 'ESET ecmd binary changed after verification.' }
        return Invoke-QuickProcess -FilePath $ecmdPath -Arguments @('/getcfg', $path) -TimeoutSeconds 180
    }.GetNewClosure()
    $sign = {
        param($path)
        if ((Assert-QuickEsetSignature -Path $signerPath) -cne $signerHash) { throw 'XmlSignTool binary changed after verification.' }
        return Invoke-QuickProcess -FilePath $signerPath -Arguments @('/version', '2', $path) -TimeoutSeconds 300 -Interactive
    }.GetNewClosure()
    $import = {
        param($path)
        if ((Assert-QuickEsetSignature -Path $ecmdPath) -cne $ecmdHash) { throw 'ESET ecmd binary changed after verification.' }
        return Invoke-QuickProcess -FilePath $ecmdPath -Arguments @('/setcfg', $path) -TimeoutSeconds 180
    }.GetNewClosure()
    return @{ Export = $export; Sign = $sign; Import = $import; Confirm = { param($plan) return Confirm-QuickApply -Plan $plan }; ProductionVerified = $true; ExpectedVersion = [string]$Install.Product.Version }
}

function Invoke-QuickRulesMain {
    param([string] $RulesFilePath, [string] $ConfigurationPath, [switch] $DoApply, [switch] $TestMachine, [string] $SignerPath)
    if ([string]::IsNullOrWhiteSpace($RulesFilePath)) { $RulesFilePath = Join-Path $PSScriptRoot 'rules.csv' }
    $desired = Import-QuickRulesCsv -Path $RulesFilePath -ScriptDirectory $PSScriptRoot
    if (-not $DoApply -and -not [string]::IsNullOrWhiteSpace($ConfigurationPath)) {
        $configuration = Read-QuickXmlFile -Path $ConfigurationPath
        $plan = Get-QuickRulesPlan -Desired $desired -Configuration $configuration
        Show-QuickRulesPlan -Plan $plan
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($ConfigurationPath)) { throw 'Apply does not accept an offline ConfigurationFile.' }
    if ($DoApply -and -not $TestMachine) { throw 'Apply requires -IAmOnATestMachine.' }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Live Preview and Apply require Windows.' }
    if (-not (Test-QuickAdministrator)) { throw 'Live Preview and Apply require an elevated PowerShell; relaunch using Run as administrator.' }
    $installation = Get-QuickEsetInstall
    $ecmdHash = Assert-QuickEsetSignature -Path $installation.EcmdPath
    $runRoot = New-QuickRunRoot
    if (-not $DoApply) {
        $provider = New-QuickProductionProviders -Install $installation -Signer ([pscustomobject]@{ Path = ''; Hash = '' })
        $previewPath = Join-Path $runRoot 'preview.xml'
        $configuration = Get-QuickProviderConfiguration -Providers $provider -Path $previewPath -Operation 'Live preview export'
        $plan = Get-QuickRulesPlan -Desired $desired -Configuration $configuration
        Show-QuickRulesPlan -Plan $plan
        [Console]::WriteLine(('Private export: ' + $previewPath))
        return
    }
    $signer = Get-QuickSignerPath -SuppliedPath $SignerPath -RunRoot $runRoot
    $providers = New-QuickProductionProviders -Install $installation -Signer $signer
    if ((Assert-QuickEsetSignature -Path $installation.EcmdPath) -cne $ecmdHash) { throw 'ESET ecmd binary changed after verification.' }
    $result = Invoke-QuickApplyTransaction -Desired $desired -Providers $providers -RunRoot $runRoot
    if ($result.Success) {
        [Console]::WriteLine(('Transaction status: ' + $(if ($result.AddedCount -eq 0) { 'no changes; no sign/import performed' } else { 'readback verified; this is NOT proof of blocking' })))
    } else { [Console]::WriteLine('Apply cancelled before import.') }
    [Console]::WriteLine('Append schema remains EXPERIMENTAL and NOT CERTIFIED.')
    [Console]::WriteLine('Native ESET block/log/unblock evidence remains OWNER_PENDING.')
    [Console]::WriteLine(('Private results and diagnostics: ' + $runRoot))
    if ($result.Names.Count -gt 0) {
        [Console]::WriteLine('CLEANUP WARNING: if imported, manually remove only these exact generated rule names in ESET:')
        foreach ($name in $result.Names) { [Console]::WriteLine(('  ' + $name)) }
    }
}

if ($FunctionsOnly) { return }
try {
    Invoke-QuickRulesMain -RulesFilePath $RulesFile -ConfigurationPath $ConfigurationFile -DoApply:$Apply -TestMachine:$IAmOnATestMachine -SignerPath $SignToolPath
    exit 0
} catch {
    [Console]::Error.WriteLine(('ERROR: ' + $_.Exception.Message))
    exit 1
}
