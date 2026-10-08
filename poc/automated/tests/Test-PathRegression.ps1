$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Kit.Helpers.ps1')
# A valid forward-slash drive path is supported by Windows Path.GetFullPath.
try { Assert-SafeLocalPath 'C:/ESET-Test' | Out-Null } catch { Write-Output ('OLD-GUARD-REPRO: ' + $_.Exception.Message) }
# A product-like folder name is not itself a cloud-storage root.
try { Assert-SafeLocalPath 'C:\Users\Admin\Downloads\NotOneDrive\Kit' | Out-Null } catch { Write-Output ('OLD-FALSE-POSITIVE-REPRO: ' + $_.Exception.Message) }
if ((Get-LocalPathGuardReason 'C:/ESET-Test') -ne '') { throw 'Valid drive path was rejected.' }
if ((Get-LocalPathGuardReason 'C:\Users\Admin\Downloads\NotOneDrive\Kit') -ne '') { throw 'Ordinary folder with cloud-like substring rejected.' }
foreach ($bad in @('', 'relative\kit', '\\server\share\kit', 'C:\kit\*.exe', 'C:\kit\x.exe:stream', 'C:\OneDrive\kit')) {
    if (-not (Get-LocalPathGuardReason $bad)) { throw 'Unsafe path accepted.' }
}
if ($env:OS -eq 'Windows_NT') {
    if ((Assert-SafeLocalPath 'C:/ESET-Test') -cne 'C:\ESET-Test') { throw 'Windows path normalization failed.' }
    [void](Assert-SafeLocalPath 'C:\Users\Admin\Downloads\NotOneDrive\Kit')
    $oldSync = $env:OneDrive
    try {
        $env:OneDrive = 'C:\SyntheticSyncRoot'
        foreach ($path in @('C:\SyntheticSyncRoot','C:\SyntheticSyncRoot\Kit')) {
            $rejected = $false
            try { Assert-SafeLocalPath $path 'Sync fixture' | Out-Null } catch { $rejected = $_.Exception.Message.Contains('configured-sync-root') }
            if (-not $rejected) { throw 'Configured sync root boundary was not rejected.' }
        }
        [void](Assert-SafeLocalPath 'C:\SyntheticSyncRootSibling\Kit')
    } finally { $env:OneDrive = $oldSync }
}
Write-Output 'Path regression assertions passed.'
