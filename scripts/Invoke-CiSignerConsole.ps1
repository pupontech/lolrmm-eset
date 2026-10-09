#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ExePath,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$XmlPath
)

$ErrorActionPreference = 'Stop'
$syntheticInput = 'synthetic-fixture'
$failureMessage = $null
$cleanupErrors = @()
$process = $null
$processStarted = $false
$stdoutTask = $null
$stderrTask = $null
$ownsConsole = $false
$handlesSaved = $false
$consoleModeSaved = $false
$originalConsoleMode = [uint32]0
$originalStdIn = [IntPtr]::Zero
$originalStdOut = [IntPtr]::Zero
$originalStdErr = [IntPtr]::Zero

function ConvertTo-WindowsArgument {
    param([Parameter(Mandatory=$true)][string]$Value)

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append([char]34)
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) {
            $slashes++
        } elseif ($character -eq [char]34) {
            if ($slashes -gt 0) { [void]$builder.Append([char]92, (2 * $slashes)) }
            [void]$builder.Append([char]92)
            [void]$builder.Append([char]34)
            $slashes = 0
        } else {
            if ($slashes -gt 0) { [void]$builder.Append([char]92, $slashes) }
            [void]$builder.Append($character)
            $slashes = 0
        }
    }
    if ($slashes -gt 0) { [void]$builder.Append([char]92, (2 * $slashes)) }
    [void]$builder.Append([char]34)
    return $builder.ToString()
}

function Get-SafeDiagnostic {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return '' }
    $safe = $Text.Replace($syntheticInput, '<SYNTHETIC_INPUT>')
    if ($safe.Length -gt 4096) { $safe = $safe.Substring(0, 4096) + ' [truncated]' }
    return $safe.Trim()
}

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'This helper is restricted to Windows GitHub Actions runners.'
    }
    if ($env:GITHUB_ACTIONS -cne 'true') {
        throw 'This helper is restricted to GitHub Actions.'
    }

    # The caller must supply only the signed official tool and public vendor sample in CI scratch.
    $resolvedExePath = [IO.Path]::GetFullPath($ExePath)
    $resolvedXmlPath = [IO.Path]::GetFullPath($XmlPath)
    if (-not [IO.File]::Exists($resolvedExePath)) { throw 'Signer executable was not found.' }
    if (-not [IO.File]::Exists($resolvedXmlPath)) { throw 'Public XML fixture was not found.' }
    if ([string]::Equals($resolvedExePath, $resolvedXmlPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Signer executable and XML fixture paths must be different.'
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $resolvedExePath
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O="?ESET, spol\. s r\.o\."?(?:,|$)') {
        throw 'Signer executable is not a valid ESET-signed tool.'
    }

    $nativeSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class LolrmmEsetCiSignerConsoleNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct KEY_EVENT_RECORD
    {
        public int KeyDown;
        public ushort RepeatCount;
        public ushort VirtualKeyCode;
        public ushort VirtualScanCode;
        public ushort UnicodeChar;
        public uint ControlKeyState;
    }

    [StructLayout(LayoutKind.Explicit, Size = 20)]
    public struct INPUT_RECORD
    {
        [FieldOffset(0)] public ushort EventType;
        [FieldOffset(4)] public KEY_EVENT_RECORD KeyEvent;
    }

    private const ushort KEY_EVENT = 0x0001;
    private const ushort VK_RETURN = 0x000D;
    private const ushort VK_OEM_MINUS = 0x00BD;
    private const uint ENABLE_ECHO_INPUT = 0x0004;

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool AllocConsole();

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool FreeConsole();

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetStdHandle(int nStdHandle, IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetHandleInformation(IntPtr handle, uint mask, uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetConsoleMode(IntPtr consoleInput, out uint mode);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetConsoleMode(IntPtr consoleInput, uint mode);

    public static bool DisableInputEcho(IntPtr consoleInput, out uint originalMode)
    {
        if (!GetConsoleMode(consoleInput, out originalMode)) return false;
        return SetConsoleMode(consoleInput, originalMode & ~ENABLE_ECHO_INPUT);
    }

    [DllImport("kernel32.dll", EntryPoint = "WriteConsoleInputW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool WriteConsoleInput(IntPtr consoleInput, [In] INPUT_RECORD[] records,
        uint recordCount, out uint recordsWritten);

    private static ushort GetVirtualKey(char value)
    {
        if (value >= 'a' && value <= 'z') return (ushort)(value - 'a' + 'A');
        if (value >= 'A' && value <= 'Z') return value;
        if (value >= '0' && value <= '9') return value;
        if (value == '-') return VK_OEM_MINUS;
        if (value == ' ') return 0x0020;
        return 0;
    }

    private static INPUT_RECORD MakeKeyRecord(bool keyDown, ushort virtualKey, ushort unicodeChar)
    {
        INPUT_RECORD record = new INPUT_RECORD();
        record.EventType = KEY_EVENT;
        record.KeyEvent = new KEY_EVENT_RECORD();
        record.KeyEvent.KeyDown = keyDown ? 1 : 0;
        record.KeyEvent.RepeatCount = 1;
        record.KeyEvent.VirtualKeyCode = virtualKey;
        record.KeyEvent.VirtualScanCode = 0;
        record.KeyEvent.UnicodeChar = unicodeChar;
        record.KeyEvent.ControlKeyState = 0;
        return record;
    }

    public static void QueueLine(IntPtr consoleInput, string value)
    {
        if (Marshal.SizeOf(typeof(KEY_EVENT_RECORD)) != 16 || Marshal.SizeOf(typeof(INPUT_RECORD)) != 20)
            throw new InvalidOperationException("Unexpected native console input structure layout.");

        List<INPUT_RECORD> records = new List<INPUT_RECORD>();
        foreach (char character in value)
        {
            ushort key = GetVirtualKey(character);
            records.Add(MakeKeyRecord(true, key, character));
            records.Add(MakeKeyRecord(false, key, 0));
        }
        records.Add(MakeKeyRecord(true, VK_RETURN, 0x000D));
        records.Add(MakeKeyRecord(false, VK_RETURN, 0));

        INPUT_RECORD[] buffer = records.ToArray();
        uint written;
        if (!WriteConsoleInput(consoleInput, buffer, (uint)buffer.Length, out written) || written != buffer.Length)
            throw new InvalidOperationException("Could not queue synthetic fixture console input.");
    }
}
'@
    if ($null -eq ('LolrmmEsetCiSignerConsoleNative' -as [type])) {
        Add-Type -TypeDefinition $nativeSource -Language CSharp
    }

    $beforeBytes = [IO.File]::ReadAllBytes($resolvedXmlPath)
    $originalStdIn = [LolrmmEsetCiSignerConsoleNative]::GetStdHandle(-10)
    $originalStdOut = [LolrmmEsetCiSignerConsoleNative]::GetStdHandle(-11)
    $originalStdErr = [LolrmmEsetCiSignerConsoleNative]::GetStdHandle(-12)
    $handlesSaved = $true

    # Detach only this helper process from any inherited/shared console, then own a fresh one.
    [void][LolrmmEsetCiSignerConsoleNative]::FreeConsole()
    if (-not [LolrmmEsetCiSignerConsoleNative]::AllocConsole()) {
        throw 'Could not allocate a private console for the CI fixture signer.'
    }
    $ownsConsole = $true

    $consoleInput = [LolrmmEsetCiSignerConsoleNative]::GetStdHandle(-10)
    if ($consoleInput -eq [IntPtr]::Zero -or $consoleInput.ToInt64() -eq -1) {
        throw 'Private console input handle is unavailable.'
    }
    if (-not [LolrmmEsetCiSignerConsoleNative]::SetHandleInformation($consoleInput, 1, 1)) {
        throw 'Could not prepare the private console input for the signer child.'
    }
    if (-not [LolrmmEsetCiSignerConsoleNative]::SetStdHandle(-10, $consoleInput)) {
        throw 'Could not assign private console input to the helper process.'
    }
    if (-not [LolrmmEsetCiSignerConsoleNative]::DisableInputEcho($consoleInput, [ref]$originalConsoleMode)) {
        throw 'Could not suppress echo on the private console input.'
    }
    $consoleModeSaved = $true
    if (-not [LolrmmEsetCiSignerConsoleNative]::SetStdHandle(-11, $originalStdOut)) {
        throw 'Could not restore helper standard output after console allocation.'
    }
    if (-not [LolrmmEsetCiSignerConsoleNative]::SetStdHandle(-12, $originalStdErr)) {
        throw 'Could not restore helper standard error after console allocation.'
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $resolvedExePath
    $startInfo.Arguments = '/version 2 ' + (ConvertTo-WindowsArgument -Value $resolvedXmlPath)
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $watch = [Diagnostics.Stopwatch]::StartNew()
    if (-not $process.Start()) { throw 'Signer process did not start.' }
    $processStarted = $true
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    # This fixed value exists only to exercise the public CI fixture's two native console prompts.
    [LolrmmEsetCiSignerConsoleNative]::QueueLine($consoleInput, $syntheticInput)
    [LolrmmEsetCiSignerConsoleNative]::QueueLine($consoleInput, $syntheticInput)

    $remainingMilliseconds = [Math]::Max(0, 30000 - [int]$watch.ElapsedMilliseconds)
    if (-not $process.WaitForExit($remainingMilliseconds)) {
        throw 'Official signer did not finish the public fixture within 30 seconds.'
    }
    $remainingMilliseconds = [Math]::Max(0, 30000 - [int]$watch.ElapsedMilliseconds)
    if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask),[int]$remainingMilliseconds)) {
        throw 'Public fixture output collection exceeded the 30-second deadline.'
    }

    if ($process.ExitCode -ne 0) {
        $diagnostic = Get-SafeDiagnostic -Text ($stdoutTask.Result + [Environment]::NewLine + $stderrTask.Result)
        if ([string]::IsNullOrWhiteSpace($diagnostic)) {
            throw ('Official signer exited with code ' + $process.ExitCode + '.')
        }
        throw ('Official signer exited with code ' + $process.ExitCode + '. Public fixture diagnostic: ' + $diagnostic)
    }

    $afterBytes = [IO.File]::ReadAllBytes($resolvedXmlPath)
    $bytesChanged = $beforeBytes.Length -ne $afterBytes.Length
    if (-not $bytesChanged) {
        for ($index = 0; $index -lt $beforeBytes.Length; $index++) {
            if ($beforeBytes[$index] -ne $afterBytes[$index]) {
                $bytesChanged = $true
                break
            }
        }
    }
    if (-not $bytesChanged) {
        throw 'Official signer exited successfully but the public fixture bytes did not change.'
    }
} catch {
    $failureMessage = Get-SafeDiagnostic -Text $_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($failureMessage)) { $failureMessage = 'Unspecified CI signer fixture failure.' }
} finally {
    if ($processStarted -and $null -ne $process) {
        try {
            if (-not $process.HasExited) {
                try { $process.Kill() } catch { }
                if (-not $process.WaitForExit(5000)) {
                    $cleanupErrors += 'Direct signer process termination could not be confirmed; its state is unknown.'
                }
            }
        } catch {
            $cleanupErrors += 'Direct signer process termination could not be confirmed; its state is unknown.'
        }
    }

    if ($handlesSaved) {
        if (-not [LolrmmEsetCiSignerConsoleNative]::SetStdHandle(-10, $originalStdIn)) {
            $cleanupErrors += 'Could not restore the helper standard input handle.'
        }
        if (-not [LolrmmEsetCiSignerConsoleNative]::SetStdHandle(-11, $originalStdOut)) {
            $cleanupErrors += 'Could not restore the helper standard output handle.'
        }
        if (-not [LolrmmEsetCiSignerConsoleNative]::SetStdHandle(-12, $originalStdErr)) {
            $cleanupErrors += 'Could not restore the helper standard error handle.'
        }
    }
    if ($consoleModeSaved -and -not [LolrmmEsetCiSignerConsoleNative]::SetConsoleMode($consoleInput, $originalConsoleMode)) {
        $cleanupErrors += 'Could not restore the private console input mode.'
    }
    if ($ownsConsole -and -not [LolrmmEsetCiSignerConsoleNative]::FreeConsole()) {
        $cleanupErrors += 'Could not detach the private console owned by this helper.'
    }
    if ($null -ne $process) { $process.Dispose() }
}

if ($cleanupErrors.Count -gt 0) {
    $cleanupText = [string]::Join(' ', $cleanupErrors)
    if ([string]::IsNullOrWhiteSpace($failureMessage)) { $failureMessage = $cleanupText }
    else { $failureMessage = $failureMessage + ' ' + $cleanupText }
}
if (-not [string]::IsNullOrWhiteSpace($failureMessage)) {
    [Console]::Error.WriteLine('CI signer fixture failed: ' + (Get-SafeDiagnostic -Text $failureMessage))
    exit 1
}

Write-Output 'CI_SIGNER_FIXTURE_PASS: official signer exited 0 and changed the public XML fixture bytes.'
exit 0
