# Exercise real installed-product discovery with fixture registry bases only.
# No registry writes, ESET installs or live configuration access.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$source=Join-Path $PSScriptRoot '../poc/quick-rules/Eset-QuickRules.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile((Resolve-Path $source),[ref]$null,[ref]$null)
$function=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-QuickEsetInstall'},$true)
if($null -eq $function) { throw 'Production discovery function missing.' }
$text=$function.Extent.Text
$native='[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)'
if(-not $text.Contains($native)) { throw 'Registry fixture seam needs deliberate review.' }
$text=$text.Replace($native,'(Open-FixtureRegistryBase $view)')
$text=$text.Replace('[Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT','$false')
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public class QuickRegistryFixtureNode {
    public Dictionary<string,QuickRegistryFixtureNode> Children = new Dictionary<string,QuickRegistryFixtureNode>();
    public Dictionary<string,string> Values = new Dictionary<string,string>();
    public object GetValue(string name, object fallback) { string value; return Values.TryGetValue(name,out value) ? value : fallback; }
    public string[] GetSubKeyNames() { string[] keys = new string[Children.Count]; Children.Keys.CopyTo(keys,0); return keys; }
    public QuickRegistryFixtureNode OpenSubKey(string name) { QuickRegistryFixtureNode node; return Children.TryGetValue(name,out node) ? node : null; }
    public void Dispose() { }
}
'@
. ([scriptblock]::Create($text))
$root=Join-Path ([IO.Path]::GetTempPath()) ('quick-discovery-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$oldProgramFiles=$env:ProgramFiles; $oldProgramFiles32=${env:ProgramFiles(x86)}
function Open-FixtureRegistryBase($View) { return $script:FixtureRegistry }
try {
    $env:ProgramFiles=$root; ${env:ProgramFiles(x86)}=$root
    $install=Join-Path $root 'ESET Security'
    [void][IO.Directory]::CreateDirectory($install)
    [IO.File]::WriteAllText((Join-Path $install 'ecmd.exe'),'fixture only; never executed')
    $script:FixtureRegistry=New-Object QuickRegistryFixtureNode
    $uninstall=New-Object QuickRegistryFixtureNode
    $script:FixtureRegistry.Children.Add('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',$uninstall)
    $product=New-Object QuickRegistryFixtureNode
    $product.Values.Add('DisplayName','ESET Security')
    $product.Values.Add('DisplayVersion','19.2.10.0')
    $product.Values.Add('InstallLocation',$install)
    $uninstall.Children.Add('fixture-product',$product)
    $result=Get-QuickEsetInstall
    if($result.Product.Name -cne 'ESET Security' -or $result.Product.Version -cne '19.2.10.0' -or $result.EcmdPath -cne (Join-Path $install 'ecmd.exe')) { throw 'Wrong discovered product/path.' }
    Write-Output 'PASS: real discovery handles supported product without automatic Matches collision.'
    # Exercise regex capture fallback, multiple entries, and duplicate registry views.
    $product.Values['InstallLocation']=''
    $product.Values.Add('DisplayIcon',('"'+(Join-Path $install 'egui.exe')+'",0'))
    $unrelated=New-Object QuickRegistryFixtureNode
    $unrelated.Values.Add('DisplayName','Unrelated application')
    $unrelated.Values.Add('DisplayVersion','1.0')
    $uninstall.Children.Add('unrelated',$unrelated)
    $result=Get-QuickEsetInstall
    if($result.Product.InstallLocation -cne $install) { throw 'DisplayIcon capture fallback failed.' }
    Write-Output 'PASS: icon fallback preserves actual Matches capture; duplicate views deduplicated.'
    $product.Values['DisplayIcon']=(Join-Path $install 'egui.exe')+',0'
    $result=Get-QuickEsetInstall
    if($result.Product.InstallLocation -cne $install) { throw 'Unquoted DisplayIcon fallback failed.' }
    Write-Output 'PASS: unquoted icon path with index supported.'
    $product.Values['DisplayVersion']='18.2.10.0'
    $rejected=$false
    try { $null=Get-QuickEsetInstall } catch { $rejected=$true }
    if(-not $rejected) { throw 'Unsupported product version accepted.' }
    Write-Output 'PASS: unsupported discovered version still refused.'
} finally {
    $env:ProgramFiles=$oldProgramFiles; ${env:ProgramFiles(x86)}=$oldProgramFiles32
    Remove-Item -LiteralPath $root -Recurse -Force
}
