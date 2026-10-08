#requires -Version 5.1
# CI-only restricted-token proof; never shipped in the owner kit.
param([string]$HelperPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Kit.Helpers.ps1'))
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Restricted-token ACL proof requires Windows.' }
. $HelperPath
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class AclRestrictedTokenProof {
    [StructLayout(LayoutKind.Sequential)] public struct SidAndAttributes { public IntPtr Sid; public UInt32 Attributes; }
    [StructLayout(LayoutKind.Sequential)] public struct Luid { public UInt32 Low; public Int32 High; }
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentThread();
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr h);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr p, UInt32 access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenThreadToken(IntPtr t, UInt32 access, bool self, out IntPtr token);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool ConvertStringSidToSid(string text, out IntPtr sid);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool CreateRestrictedToken(IntPtr token, UInt32 flags, UInt32 count, ref SidAndAttributes sid, UInt32 deleteCount, IntPtr deletes, UInt32 restrictCount, IntPtr restricts, out IntPtr restricted);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool ImpersonateLoggedOnUser(IntPtr token);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool RevertToSelf();
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool GetTokenInformation(IntPtr token, int info, IntPtr buffer, int length, out int needed);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool LookupPrivilegeValue(string system, string name, out Luid luid);
    static void Check(bool ok) { if(!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    public static IntPtr Begin() {
        IntPtr original=IntPtr.Zero, admin=IntPtr.Zero, restricted=IntPtr.Zero;
        try {
            Check(OpenProcessToken(GetCurrentProcess(), 0x000F01FF, out original));
            Check(ConvertStringSidToSid("S-1-5-32-544", out admin));
            SidAndAttributes disabled=new SidAndAttributes(); disabled.Sid=admin;
            // DISABLE_MAX_PRIVILEGE; deny-only Administrators. No bypass flags.
            Check(CreateRestrictedToken(original, 1, 1, ref disabled, 0, IntPtr.Zero, 0, IntPtr.Zero, out restricted));
            Check(ImpersonateLoggedOnUser(restricted));
            return restricted;
        } catch { if(restricted!=IntPtr.Zero) CloseHandle(restricted); throw; }
        finally { if(original!=IntPtr.Zero) CloseHandle(original); if(admin!=IntPtr.Zero) LocalFree(admin); }
    }
    public static bool HasSecurityPrivilege() {
        IntPtr token=IntPtr.Zero, buffer=IntPtr.Zero;
        try {
            Check(OpenThreadToken(GetCurrentThread(), 8, true, out token));
            int size=0; GetTokenInformation(token, 3, IntPtr.Zero, 0, out size);
            buffer=Marshal.AllocHGlobal(size); Check(GetTokenInformation(token,3,buffer,size,out size));
            Luid wanted; Check(LookupPrivilegeValue(null,"SeSecurityPrivilege",out wanted));
            int count=Marshal.ReadInt32(buffer);
            for(int i=0;i<count;i++) {
                int at=4+i*12;
                if(unchecked((UInt32)Marshal.ReadInt32(buffer,at))==wanted.Low && Marshal.ReadInt32(buffer,at+4)==wanted.High) return true;
            }
            return false;
        } finally { if(buffer!=IntPtr.Zero) Marshal.FreeHGlobal(buffer); if(token!=IntPtr.Zero) CloseHandle(token); }
    }
    public static void End(IntPtr token) { Check(RevertToSelf()); if(token!=IntPtr.Zero) CloseHandle(token); }
}
'@
$root = Join-Path $env:RUNNER_TEMP ('acl-limited-proof-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
# Parent grants fixture access to the same user before removing privileged groups.
$baseAcl = New-Object Security.AccessControl.DirectorySecurity
$baseAcl.SetAccessRuleProtection($true,$false)
$identity = New-Object Security.Principal.SecurityIdentifier($sid)
$baseAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
[IO.Directory]::SetAccessControl($root,$baseAcl)
$token = [IntPtr]::Zero
try {
    $token = [AclRestrictedTokenProof]::Begin()
    $limitedIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($limitedIdentity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Proof token still has enabled administrator membership.' }
    if ([AclRestrictedTokenProof]::HasSecurityPrivilege()) { throw 'Proof token still possesses SeSecurityPrivilege.' }
    Write-Output 'TOKEN_PROOF: administrator membership disabled; SeSecurityPrivilege absent.'
    $dir = Join-Path $root 'private evidence'
    [void][IO.Directory]::CreateDirectory($dir)
    $file = Join-Path $dir 'baseline.xml'
    $sections = [Security.AccessControl.AccessControlSections]'Owner,Group'
    $ownerBefore = [IO.Directory]::GetAccessControl($dir,$sections).GetSecurityDescriptorSddlForm($sections)
    Set-PrivateAcl $dir $sid
    [IO.File]::WriteAllText($file,'<SyntheticFixture/>')
    $fileOwnerBefore = [IO.File]::GetAccessControl($file,$sections).GetSecurityDescriptorSddlForm($sections)
    Set-PrivateAcl $file $sid
    for ($i=0; $i -lt 20; $i++) { Set-PrivateAcl $dir $sid; Set-PrivateAcl $file $sid }
    if ([IO.Directory]::GetAccessControl($dir,$sections).GetSecurityDescriptorSddlForm($sections) -cne $ownerBefore -or [IO.File]::GetAccessControl($file,$sections).GetSecurityDescriptorSddlForm($sections) -cne $fileOwnerBefore) { throw 'DACL update changed owner or group.' }
    if ([IO.File]::ReadAllText($file) -cne '<SyntheticFixture/>') { throw 'ACL update altered file content.' }
    $script:Checks = New-Object 'System.Collections.Generic.List[object]'
    $controller = Get-ChildItem -LiteralPath (Split-Path $HelperPath -Parent) -Filter 'Invoke-EsetHipsPoc.v*.ps1' | Select-Object -First 1
    $tokens=$null; $errors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile($controller.FullName,[ref]$tokens,[ref]$errors)
    $fn=$ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Export-Configuration'},$true)[0]
    Invoke-Expression $fn.Extent.Text
    $script:Evidence=$dir; $script:Sid=$sid; $script:RunId=('0' * 32)
    # Reproduce the pre-UAC export preparation while refusing any actual UAC/export.
    # The mock must emit no pipeline value: a real missing Get-Process result is
    # empty, and the preflight's @(Get-Process).Count must stay 0. A function that
    # "returns" $null emits one null element and would fail the preflight instead.
    function Get-Process { <# missing process: no pipeline output #> }
    function Start-Process { throw 'UAC_BOUNDARY_REACHED_NO_VENDOR_EXECUTED' }
    $boundary = $false; $boundaryError = $null; $boundaryErrorType = $null
    try { Export-Configuration 'baseline' | Out-Null }
    catch {
        $boundaryError = [string]$_.Exception.Message
        $boundaryErrorType = $_.Exception.GetType().FullName
        if ($boundaryError.Contains('UAC_BOUNDARY_REACHED_NO_VENDOR_EXECUTED')) { $boundary = $true }
    }
    if (-not $boundary) {
        $actualError = $boundaryError
        if (-not $actualError) { $actualError = 'no exception was raised before the UAC boundary' }
        throw ('Production export preflight did not reach the UAC boundary under restricted token. Actual error: ' + $boundaryErrorType + ' - ' + $actualError)
    }
    Write-Output 'ACL_RESTRICTED_PASS: first and 20 repeated folder/file updates; production export pre-UAC path reached.'
} finally {
    if ($token -ne [IntPtr]::Zero) { [AclRestrictedTokenProof]::End($token) }
    Remove-Item -LiteralPath $root -Recurse -Force
}
