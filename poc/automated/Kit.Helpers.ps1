#requires -Version 5.1
Set-StrictMode -Version 2.0
function ConvertFrom-SafeManifest {
    param([string]$Text, [string[]]$Members)
    $map = @{}
    foreach ($line in ($Text -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '^([0-9a-fA-F]{64}) [ *](.+)$') { throw 'Malformed SHA256 manifest line.' }
        $hash = $Matches[1].ToLowerInvariant(); $name = $Matches[2]
        if ($name -cnotmatch '^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$') { throw 'Unsafe manifest path.' }
        if ($map.ContainsKey($name)) { throw 'Duplicate manifest path.' }
        $map[$name] = $hash
    }
    $expected = @($Members | Sort-Object -CaseSensitive)
    $actual = @($map.Keys | Sort-Object -CaseSensitive)
    if (($expected -join "`n") -cne ($actual -join "`n")) { throw 'Manifest does not cover the exact expected member set.' }
    return $map
}
function Get-SafeXmlTree {
    param([string]$Text)
    if ($Text.Length -gt 16777216) { throw 'XML exceeds 16 MiB character limit.' }
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 16777216
    $reader = [System.Xml.XmlReader]::Create((New-Object System.IO.StringReader($Text)), $settings)
    $doc = New-Object System.Xml.XmlDocument
    $doc.XmlResolver = $null
    $doc.PreserveWhitespace = $false
    try { $doc.Load($reader) } finally { $reader.Dispose() }
    if ($null -eq $doc.DocumentElement) { throw 'XML has no document element.' }
    return ,$doc
}
function Get-XmlFingerprint {
    param([System.Xml.XmlNode]$Node, [int]$Depth = 0)
    if ($Depth -gt 64) { throw 'XML depth exceeds safety limit.' }
    $parts = @([string][int]$Node.NodeType, $Node.Name, $Node.NamespaceURI, $Node.Value)
    $builder = New-Object System.Text.StringBuilder
    foreach ($part in $parts) { $value = [string]$part; [void]$builder.Append($value.Length).Append(':').Append($value) }
    $attrs = @()
    if ($Node.Attributes) { $attrs = @($Node.Attributes | Sort-Object Name) }
    [void]$builder.Append('A').Append($attrs.Count).Append(':')
    foreach ($attr in $attrs) {
        $value = Get-XmlFingerprint $attr ($Depth + 1)
        [void]$builder.Append($value.Length).Append(':').Append($value)
    }
    [void]$builder.Append('C').Append($Node.ChildNodes.Count).Append(':')
    foreach ($child in $Node.ChildNodes) {
        $value = Get-XmlFingerprint $child ($Depth + 1)
        [void]$builder.Append($value.Length).Append(':').Append($value)
    }
    return $builder.ToString()
}
# ---------------------------------------------------------------------------
# O(n) Compare-SafeXml: multiset diff over top-down context hashes.
# Iterative traversal with an explicit stack (no recursion depth limit),
# no XPath, no element-count cap. Classifies a structural candidate only;
# it does NOT prove HIPS semantics or ownership.
# ---------------------------------------------------------------------------
function Get-SelfFingerprintString {
    # Node type + localName + namespaceURI + sorted attribute name/value pairs
    # + concatenated direct child text/CDATA/comment values, EXCLUDING child
    # elements. Whitespace-only text is treated as absent (indentation is not
    # semantic). Fields are length-prefixed so no value can impersonate a
    # delimiter. Kept deterministic and invariant for reproducible hashes.
    param([System.Xml.XmlNode]$Node)
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('T').Append([int]$Node.NodeType)
    $name = [string]$Node.LocalName
    [void]$builder.Append('|N').Append($name.Length).Append(':').Append($name)
    $uri = [string]$Node.NamespaceURI
    [void]$builder.Append('|U').Append($uri.Length).Append(':').Append($uri)
    $attrList = $Node.Attributes
    $attrCount = 0
    if ($null -ne $attrList) { $attrCount = $attrList.Count }
    [void]$builder.Append('|A').Append($attrCount)
    if ($attrCount -eq 1) {
        $attr = $attrList[0]
        [void]$builder.Append('|@').Append([string]$attr.Name).Append('=').Append([string]$attr.Value)
    } elseif ($attrCount -gt 1) {
        $attrNodes = New-Object 'System.Collections.Generic.List[object]'
        foreach ($attr in $attrList) { [void]$attrNodes.Add($attr) }
        # Insertion sort by attribute name (ordinal). Attribute order is not
        # semantic, so the fingerprint must not depend on it. Attribute counts
        # are tiny, so a small in-place sort avoids cmdlet overhead per element.
        for ($i = 1; $i -lt $attrCount; $i++) {
            $current = $attrNodes[$i]
            $currentName = [string]$current.Name
            $j = $i - 1
            while ($j -ge 0) {
                if ([string]::Compare([string]$attrNodes[$j].Name, $currentName, [StringComparison]::Ordinal) -gt 0) {
                    $attrNodes[$j + 1] = $attrNodes[$j]
                    $j--
                } else { break }
            }
            $attrNodes[$j + 1] = $current
        }
        foreach ($attr in $attrNodes) {
            [void]$builder.Append('|@').Append([string]$attr.Name).Append('=').Append([string]$attr.Value)
        }
    }
    # Direct text/CDATA/comment values only (types 3/4/8). Whitespace-only text
    # nodes are treated as absent. Child elements are excluded entirely.
    [void]$builder.Append('|X')
    foreach ($child in $Node.ChildNodes) {
        $type = [int]$child.NodeType
        if ($type -eq 3 -or $type -eq 4 -or $type -eq 8) {
            $value = [string]$child.Value
            if ($type -eq 3 -and [string]::IsNullOrWhiteSpace($value)) { continue }
            [void]$builder.Append('|').Append($type).Append(':').Append($value.Length).Append(':').Append($value)
        }
    }
    return $builder.ToString()
}
function Get-XmlContextHashes {
    # Iterative pre-order traversal with an explicit stack. Returns
    # @($elements, $contextHashes) in document order.
    # ContextHash(node) = SHA256 over an invariant UTF-8 string of
    # (localName, namespaceURI, SelfFingerprint, ContextHash(parent));
    # the root context is the empty string. The hash is top-down only, so
    # inserting or removing one child does NOT alter surviving siblings.
    param([System.Xml.XmlNode]$Root)
    $elements = New-Object 'System.Collections.Generic.List[System.Xml.XmlElement]'
    $hashes = New-Object 'System.Collections.Generic.List[string]'
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stack = New-Object 'System.Collections.Generic.List[object]'
        [void]$stack.Add(@($Root, ''))
        while ($stack.Count -gt 0) {
            $last = $stack.Count - 1
            $entry = $stack[$last]
            $stack.RemoveAt($last)
            $node = [System.Xml.XmlElement]$entry[0]
            $parentContext = [string]$entry[1]
            $combined = (Get-SelfFingerprintString $node) + '|P' + $parentContext
            $digest = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($combined))
            $hash = [System.BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
            [void]$elements.Add($node)
            [void]$hashes.Add($hash)
            # Buffer element children first (XmlNodeList indexing is O(n)),
            # then push in reverse so the walk preserves document order.
            $childBuffer = New-Object 'System.Collections.Generic.List[System.Xml.XmlElement]'
            foreach ($child in $node.ChildNodes) {
                if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) { [void]$childBuffer.Add($child) }
            }
            for ($i = $childBuffer.Count - 1; $i -ge 0; $i--) {
                [void]$stack.Add(@($childBuffer[$i], $hash))
            }
        }
    } finally { $sha.Dispose() }
    return @($elements, $hashes)
}
function Compare-SafeXml {
    param([string]$Before, [string]$After)
    if ($Before -ceq $After) {
        # Byte-identical: parse once so element totals stay honest.
        $sameDoc = Get-SafeXmlTree $Before
        $elementCount = 0
        $countStack = New-Object 'System.Collections.Generic.List[object]'
        [void]$countStack.Add($sameDoc.DocumentElement)
        while ($countStack.Count -gt 0) {
            $last = $countStack.Count - 1
            $current = [System.Xml.XmlElement]$countStack[$last]
            $countStack.RemoveAt($last)
            $elementCount++
            $childBuffer = New-Object 'System.Collections.Generic.List[System.Xml.XmlElement]'
            foreach ($child in $current.ChildNodes) {
                if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) { [void]$childBuffer.Add($child) }
            }
            for ($i = $childBuffer.Count - 1; $i -ge 0; $i--) { [void]$countStack.Add($childBuffer[$i]) }
        }
        return [pscustomobject]@{
            Kind = 'NO_CHANGE'
            AddedElements = 0; RemovedElements = 0; ChangedElements = 0
            AddedRootCount = 0; AddedRoots = @(); Truncated = $false
            ElementsBefore = $elementCount; ElementsAfter = $elementCount
        }
    }
    $x = Get-SafeXmlTree $Before
    $y = Get-SafeXmlTree $After
    $beforeData = Get-XmlContextHashes $x.DocumentElement
    $afterData = Get-XmlContextHashes $y.DocumentElement
    $beforeElements = $beforeData[0]; $beforeHashes = $beforeData[1]
    $afterElements = $afterData[0]; $afterHashes = $afterData[1]
    $elementsBefore = $beforeElements.Count
    $elementsAfter = $afterElements.Count
    # Multiset diff over context hashes: count Before occurrences, then walk
    # After in document order consuming matched counts. An After element whose
    # Before count is exhausted is added; leftover positive Before counts are
    # removed. O(n), index-free, no document-size cap.
    $beforeCounts = @{}
    foreach ($hash in $beforeHashes) {
        if ($beforeCounts.ContainsKey($hash)) { $beforeCounts[$hash] = $beforeCounts[$hash] + 1 }
        else { $beforeCounts[$hash] = 1 }
    }
    $addedNodeList = New-Object 'System.Collections.Generic.List[System.Xml.XmlElement]'
    for ($i = 0; $i -lt $elementsAfter; $i++) {
        $hash = $afterHashes[$i]
        if ($beforeCounts.ContainsKey($hash) -and $beforeCounts[$hash] -gt 0) {
            $beforeCounts[$hash] = $beforeCounts[$hash] - 1
        } else {
            [void]$addedNodeList.Add($afterElements[$i])
        }
    }
    $removedCount = 0
    foreach ($remaining in $beforeCounts.Values) {
        if ($remaining -gt 0) { $removedCount = $removedCount + $remaining }
    }
    $addedCount = $addedNodeList.Count
    # Modified detection: paired additions and removals are content or
    # attribute modifications, reported as unexplained per the frozen contract.
    $changedCount = 0
    if ($addedCount -gt 0 -and $removedCount -gt 0) {
        $changedCount = [Math]::Min($addedCount, $removedCount)
    }
    # Added root: added element whose parent element is not itself added.
    $addedSet = New-Object 'System.Collections.Generic.HashSet[object]'
    foreach ($node in $addedNodeList) { [void]$addedSet.Add($node) }
    $addedRootList = New-Object 'System.Collections.Generic.List[System.Xml.XmlElement]'
    foreach ($node in $addedNodeList) {
        $parent = $node.ParentNode
        if (($parent -is [System.Xml.XmlElement]) -and $addedSet.Contains($parent)) { continue }
        [void]$addedRootList.Add($node)
    }
    $addedRootCount = $addedRootList.Count
    # Bounded added-root details: never attribute VALUES, names only.
    $truncated = $false
    $addedRoots = New-Object 'System.Collections.Generic.List[object]'
    foreach ($node in $addedRootList) {
        if ($addedRoots.Count -ge 10) { $truncated = $true; break }
        $segments = New-Object 'System.Collections.Generic.List[string]'
        $walk = $node
        while (($null -ne $walk) -and ($walk -is [System.Xml.XmlElement])) {
            [void]$segments.Insert(0, $walk.LocalName)
            $walk = $walk.ParentNode
        }
        $attrNames = New-Object 'System.Collections.Generic.List[string]'
        if ($null -ne $node.Attributes) {
            foreach ($attr in $node.Attributes) { [void]$attrNames.Add([string]$attr.Name) }
        }
        $childNames = New-Object 'System.Collections.Generic.List[string]'
        foreach ($child in $node.ChildNodes) {
            if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) { [void]$childNames.Add([string]$child.LocalName) }
        }
        [void]$addedRoots.Add([pscustomobject]@{
            Path = '/' + ($segments -join '/')
            LocalName = [string]$node.LocalName
            AttributeNames = [string[]]@($attrNames | Sort-Object)
            ChildElementNames = [string[]]@($childNames | Sort-Object -Unique)
            LineHint = ''
        })
    }
    $kind = 'UNEXPLAINED_DIFFERENCE'
    if ($addedCount -eq 0 -and $removedCount -eq 0 -and $changedCount -eq 0) {
        $kind = 'ORDER_OR_FORMATTING_ONLY_UNVERIFIED'
    } elseif ($removedCount -eq 0 -and $changedCount -eq 0 -and $addedRootCount -eq 1) {
        $kind = 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE'
    } elseif ($removedCount -eq 0 -and $changedCount -eq 0 -and $addedRootCount -gt 1) {
        $kind = 'MULTIPLE_SUBTREE_INSERTIONS'
    }
    return [pscustomobject]@{
        Kind = $kind
        AddedElements = $addedCount
        RemovedElements = $removedCount
        ChangedElements = $changedCount
        AddedRootCount = $addedRootCount
        AddedRoots = $addedRoots.ToArray()
        Truncated = $truncated
        ElementsBefore = $elementsBefore
        ElementsAfter = $elementsAfter
        LineHint = ''
    }
}
function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    return ('"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"')
}
function Invoke-CapturedProcess {
    param([string]$FilePath, [string[]]$ArgumentList = @(), [int]$TimeoutSeconds = 30, [switch]$KillOnTimeout)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath; $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.Arguments = (@($ArgumentList | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    if (-not $p.Start()) { throw 'Process start failed.' }
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        if ($KillOnTimeout) { $p.Kill(); $p.WaitForExit() }
        throw ('Process timed out; PID=' + $p.Id + '; killed=' + [bool]$KillOnTimeout + '. State unresolved if not killed.')
    }
    $p.WaitForExit()
    $result = [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $out.GetAwaiter().GetResult(); Stderr = $err.GetAwaiter().GetResult(); ProcessId = $p.Id }
    $p.Dispose()
    return $result
}
function Get-OverallTruth {
    param([string[]]$Statuses)
    $value = 'UNVERIFIED'
    if ($Statuses -contains 'FAIL') { $value = 'FAIL' }
    return [pscustomobject]@{ Overall = $value }
}
function Get-LocalPathGuardReason {
    param([AllowEmptyString()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return 'empty-path' }
    if ($Path -notmatch '^[A-Za-z]:[\\/]') { return 'not-an-absolute-local-drive-path' }
    if ($Path -match '[*?]' -or $Path -match '[\x00-\x1f]' -or $Path.Substring(2).Contains(':')) { return 'wildcard-control-character-or-alternate-stream' }
    # A substring in an ordinary filename is not evidence of cloud storage.
    if ($Path -match '(^|[\\/])(OneDrive(?: - [^\\/]+)?|Dropbox|Google Drive|iCloud|iCloudDrive|iCloud Drive)([\\/]|$)') { return 'cloud-storage-path-component' }
    return ''
}
function Format-PathForDiagnostic {
    param([string]$Path)
    $shown = $Path
    foreach ($pair in @(@($env:USERPROFILE, '<USERPROFILE>'), @($env:USERNAME, '<USER>'), @($env:COMPUTERNAME, '<MACHINE>'))) {
        if ($pair[0]) { $shown = [regex]::Replace($shown, [regex]::Escape($pair[0]), $pair[1], [Text.RegularExpressions.RegexOptions]::IgnoreCase) }
    }
    return $shown
}
function Assert-SafeLocalPath {
    param([string]$Path, [string]$Label = 'local')
    $reason = Get-LocalPathGuardReason $Path
    if ($reason) { throw ($Label + ' path rejected [' + $reason + ']: ' + (Format-PathForDiagnostic $Path)) }
    # Windows accepts forward slashes; normalize before checking ancestors.
    $full = [IO.Path]::GetFullPath($Path.Replace('/', '\'))
    $reason = Get-LocalPathGuardReason $full
    if ($env:OS -eq 'Windows_NT' -and $reason) { throw ($Label + ' normalized path rejected [' + $reason + ']: ' + (Format-PathForDiagnostic $full)) }
    if ($env:OS -eq 'Windows_NT') {
        $drive = New-Object IO.DriveInfo($full.Substring(0, 3))
        if ($drive.DriveType -eq [IO.DriveType]::Network) { throw ($Label + ' path rejected [mapped-network-drive]: ' + (Format-PathForDiagnostic $full)) }
    }
    $part = $full
    while ($part) {
        if (Test-Path -LiteralPath $part) {
            $item = Get-Item -LiteralPath $part -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ($Label + ' path rejected [reparse-point-component]: ' + (Format-PathForDiagnostic $part)) }
        }
        $parent = [IO.Path]::GetDirectoryName($part)
        if ($parent -eq $part) { break }; $part = $parent
    }
    foreach ($sync in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
        if ($sync) {
            $syncRoot = $sync.Replace('/', '\').TrimEnd('\')
            if ($full.Equals($syncRoot, [StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith(($syncRoot + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw ($Label + ' path rejected [configured-sync-root]: ' + (Format-PathForDiagnostic $full)) }
        }
    }
    return $full
}
function Test-KitIntegrity {
    param([string]$KitDir, [string]$ControllerName)
    $kit = Assert-SafeLocalPath $KitDir 'Kit directory'
    if (-not (Test-Path -LiteralPath $kit -PathType Container)) { throw 'Kit directory does not exist; extract the complete ZIP first.' }
    if ($ControllerName -cnotmatch '^Invoke-EsetHipsPoc\.v\d{4}-\d{2}-\d{2}\.\d+\.ps1$') { throw 'Unexpected controller filename.' }
    $required = @('Run-EsetHipsPoc.bat','Launch-Kit.ps1',$ControllerName,'Kit.Helpers.ps1','README.md','OWNER-RUN.md','PROVENANCE.txt','LolrmmEsetTest.exe')
    $actual = @(Get-ChildItem -LiteralPath $kit -File -Force | Where-Object { $_.Name -ne 'SHA256SUMS.txt' } | ForEach-Object { $_.Name })
    if ((@($required | Sort-Object) -join '|') -cne (@($actual | Sort-Object) -join '|')) { throw 'Root member set unexpected; extract a fresh ZIP, do not overlay older kits.' }
    $manifest = ConvertFrom-SafeManifest ([IO.File]::ReadAllText((Join-Path $kit 'SHA256SUMS.txt'))) $required
    foreach ($name in $required) {
        $path = Assert-SafeLocalPath (Join-Path $kit $name) ('Package member ' + $name)
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $manifest[$name]) { throw ('Package hash mismatch: ' + $name) }
    }
    return [pscustomobject]@{ KitPath=$kit; Manifest=$manifest }
}
function Set-PrivateAcl {
    param([string]$Path, [string]$UserSid)
    if ($env:OS -ne 'Windows_NT') { throw 'Windows required for ACLs.' }
    $item = Get-Item -LiteralPath $Path -Force
    # Construct a fresh DACL-only descriptor. Do not round-trip Owner/Group/SACL
    # through Set-Acl: that can request SeSecurityPrivilege on a limited token.
    if ($item.PSIsContainer) { $acl = New-Object Security.AccessControl.DirectorySecurity }
    else { $acl = New-Object Security.AccessControl.FileSecurity }
    $acl.SetAccessRuleProtection($true, $false)
    $inherit = [Security.AccessControl.InheritanceFlags]::None
    if ($item.PSIsContainer) { $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit' }
    foreach ($sid in @($UserSid, 'S-1-5-32-544')) {
        $identity = New-Object Security.Principal.SecurityIdentifier($sid)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, [Security.AccessControl.FileSystemRights]::FullControl, $inherit, [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
        [void]$acl.AddAccessRule($rule)
    }
    if ($item.PSIsContainer) {
        [IO.Directory]::SetAccessControl($Path, $acl)
        $check = [IO.Directory]::GetAccessControl($Path, [Security.AccessControl.AccessControlSections]::Access)
    } else {
        [IO.File]::SetAccessControl($Path, $acl)
        $check = [IO.File]::GetAccessControl($Path, [Security.AccessControl.AccessControlSections]::Access)
    }
    $rules = @($check.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    if (-not $check.AreAccessRulesProtected -or $rules.Count -ne 2) { throw 'Private ACL verification failed.' }
    foreach ($rule in $rules) {
        $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        if ($sid -notin @($UserSid, 'S-1-5-32-544') -or $rule.AccessControlType -ne 'Allow' -or $rule.FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl -or $rule.InheritanceFlags -ne $inherit -or $rule.PropagationFlags -ne [Security.AccessControl.PropagationFlags]::None -or $rule.IsInherited) { throw 'Unexpected private ACL entry.' }
    }
}
