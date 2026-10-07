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
function Compare-SafeXml {
    param([string]$Before, [string]$After)
    $x = Get-SafeXmlTree $Before; $y = Get-SafeXmlTree $After
    if ($Before -ceq $After) { return [pscustomobject]@{ Kind = 'NO_CHANGE' } }
    $reference = Get-XmlFingerprint $x
    if ($reference -ceq (Get-XmlFingerprint $y)) { return [pscustomobject]@{ Kind = 'FORMATTING_ONLY_UNVERIFIED' } }
    # Removing one added complete subtree must restore the entire parsed document.
    # This proves a structural candidate only, NOT HIPS rule semantics or ownership.
    $nodes = @($y.SelectNodes('//*'))
    if ($nodes.Count -gt 2000) { return [pscustomobject]@{ Kind = 'UNEXPLAINED_DIFFERENCE' } }
    for ($i = 1; $i -lt $nodes.Count; $i++) {
        $clone = $y.CloneNode($true)
        $candidate = $clone.SelectNodes('//*').Item($i)
        [void]$candidate.ParentNode.RemoveChild($candidate)
        if ((Get-XmlFingerprint $clone) -ceq $reference) { return [pscustomobject]@{ Kind = 'STRUCTURAL_SINGLE_INSERTION_CANDIDATE' } }
    }
    return [pscustomobject]@{ Kind = 'UNEXPLAINED_DIFFERENCE' }
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
function Assert-SafeLocalPath {
    param([string]$Path)
    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path -match '[*?]' -or $Path -match 'OneDrive|Dropbox|Google Drive|iCloud') { throw 'Unsafe local path.' }
    $full = [IO.Path]::GetFullPath($Path)
    $part = $full
    while ($part) {
        if (Test-Path -LiteralPath $part) {
            $item = Get-Item -LiteralPath $part -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse path component rejected.' }
        }
        $parent = [IO.Path]::GetDirectoryName($part)
        if ($parent -eq $part) { break }; $part = $parent
    }
    foreach ($sync in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
        if ($sync -and $full.StartsWith(($sync.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Synced location rejected.' }
    }
    return $full
}
function Set-PrivateAcl {
    param([string]$Path, [string]$UserSid)
    if ($env:OS -ne 'Windows_NT') { throw 'Windows required for ACLs.' }
    $item = Get-Item -LiteralPath $Path -Force
    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRuleSpecific($rule) }
    $inherit = [Security.AccessControl.InheritanceFlags]::None
    if ($item.PSIsContainer) { $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit' }
    foreach ($sid in @($UserSid, 'S-1-5-32-544')) {
        $identity = New-Object Security.Principal.SecurityIdentifier($sid)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, [Security.AccessControl.FileSystemRights]::FullControl, $inherit, [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
        [void]$acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
    $check = Get-Acl -LiteralPath $Path
    if (-not $check.AreAccessRulesProtected -or @($check.Access).Count -ne 2) { throw 'Private ACL verification failed.' }
    foreach ($rule in $check.Access) {
        $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        if ($sid -notin @($UserSid, 'S-1-5-32-544') -or $rule.AccessControlType -ne 'Allow' -or $rule.FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl -or $rule.InheritanceFlags -ne $inherit -or $rule.PropagationFlags -ne [Security.AccessControl.PropagationFlags]::None -or $rule.IsInherited) { throw 'Unexpected private ACL entry.' }
    }
}
