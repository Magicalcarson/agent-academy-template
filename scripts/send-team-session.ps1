[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('academy-lead', 'academy-deputy')]
    [string]$Dispatcher,

    [Parameter(Mandatory = $true)]
    [ValidateSet('academy-lead', 'academy-deputy', 'academy-analyst', 'academy-challenger', 'academy-steward')]
    [string]$Member,

    [string]$PacketPath,

    [ValidateSet('ApproveOnce', 'Deny')]
    [string]$PermissionDecision,

    [string]$Message,

    [string]$Root
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$resolvedRoot = [System.IO.Path]::GetFullPath($Root)

$allowed = if ($Dispatcher -eq 'academy-lead') {
    @('academy-deputy', 'academy-analyst', 'academy-challenger', 'academy-steward')
} else {
    @('academy-lead', 'academy-analyst', 'academy-challenger', 'academy-steward')
}
if ($Member -notin $allowed) {
    throw "Dispatcher '$Dispatcher' is not authorized to send to '$Member'."
}

$definitions = @{
    'academy-lead' = @{ sessionName = 'agent-academy-academy-lead'; windowTitle = 'Agent Academy - Academy Lead' }
    'academy-deputy' = @{ sessionName = 'agent-academy-academy-deputy'; windowTitle = 'Agent Academy - Academy Deputy' }
    'academy-analyst' = @{ sessionName = 'agent-academy-academy-analyst'; windowTitle = 'Agent Academy - Academy Analyst' }
    'academy-challenger' = @{ sessionName = 'agent-academy-academy-challenger'; windowTitle = 'Agent Academy - Academy Challenger' }
    'academy-steward' = @{ sessionName = 'agent-academy-academy-steward'; windowTitle = 'Agent Academy - Academy Steward' }
}
$definition = $definitions[$Member]

$specifiedCount = 0
if (-not [string]::IsNullOrWhiteSpace($PacketPath)) { $specifiedCount++ }
if (-not [string]::IsNullOrWhiteSpace($PermissionDecision)) { $specifiedCount++ }
if (-not [string]::IsNullOrWhiteSpace($Message)) { $specifiedCount++ }

if ($specifiedCount -ne 1) {
    throw 'Specify exactly one of -PacketPath, -PermissionDecision, or -Message.'
}

$relativePacket = $null
$messageText = $null
$action = $null
$actionType = $null

if (-not [string]::IsNullOrWhiteSpace($PacketPath)) {
    $resolvedPacket = [System.IO.Path]::GetFullPath($PacketPath)
    $memberInbox = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot "inbox\$Member"))
    $inboxPrefix = $memberInbox.TrimEnd('\') + '\'
    if (-not $resolvedPacket.StartsWith($inboxPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Packet must be inside the target member inbox: $memberInbox"
    }
    if (-not (Test-Path -LiteralPath $resolvedPacket -PathType Leaf)) {
        throw "Task packet not found: $resolvedPacket"
    }
    $memberOutbox = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot "outbox\$Member"))
    $matchingReply = Join-Path $memberOutbox ([System.IO.Path]::GetFileName($resolvedPacket))
    if (Test-Path -LiteralPath $matchingReply -PathType Leaf) {
        throw "Task packet already has a durable outbox reply and must not be re-delivered: $matchingReply"
    }
    $relativePacket = $resolvedPacket.Substring($resolvedRoot.TrimEnd('\').Length + 1).Replace('\', '/')
    $messageText = "Read the durable task packet at $relativePacket and execute only that packet. Keep your response and all tool activity visible in this existing interactive session."
    $action = "Deliver packet $relativePacket to the existing interactive session"
    $actionType = 'DeliverPacket'
} elseif (-not [string]::IsNullOrWhiteSpace($Message)) {
    if ([string]::IsNullOrWhiteSpace($Message)) {
        throw 'Message cannot be empty or whitespace.'
    }
    if ($Message.Length -gt 280) {
        throw 'Direct messages must not exceed 280 characters. Use -PacketPath for real work.'
    }
    if ($Message -match "[\r\n]") {
        throw 'Direct messages must not contain newlines.'
    }
    $messageText = $Message
    $action = "Send direct message to the existing interactive session"
    $actionType = 'SendMessage'
} else {
    $action = "$PermissionDecision on the currently displayed permission prompt"
    $actionType = $PermissionDecision
}

$result = [ordered]@{
    member = $Member
    status = 'planned'
    sessionName = $definition.sessionName
    windowTitle = $definition.windowTitle
    packetPath = $relativePacket
    action = $actionType
    processId = $null
    windowHandle = $null
}

if ($PSCmdlet.ShouldProcess($definition.windowTitle, $action)) {
    $statePath = Join-Path $resolvedRoot "status\warmup-sessions.local\$Member.json"
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "No warm session state for '$Member'. Run warmup first."
    }
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    if (
        $state.member -ne $Member -or
        $state.sessionName -ne $definition.sessionName -or
        $state.windowTitle -ne $definition.windowTitle
    ) {
        throw "Warm session identity mismatch for '$Member'."
    }

    if (-not ('AcademyWindowIdentity' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class AcademyWindowIdentity {
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint sourceThread, uint targetThread, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
}
'@
    }
    $windowHandle = [IntPtr]([long]$state.windowHandle)
    if (-not [AcademyWindowIdentity]::IsWindow($windowHandle)) {
        throw "The recorded visible session for '$Member' is not live. Run warmup again."
    }
    if (-not [AcademyWindowIdentity]::IsWindowVisible($windowHandle)) {
        throw "The recorded session window for '$Member' is not visible. Run warmup again."
    }
    [uint32]$ownerPid = 0
    [void][AcademyWindowIdentity]::GetWindowThreadProcessId($windowHandle, [ref]$ownerPid)
    if ([int]$ownerPid -ne [int]$state.processId) {
        throw "The recorded visible session owner for '$Member' no longer matches. Run warmup again."
    }
    $process = Get-Process -Id ([int]$ownerPid) -ErrorAction Stop
    if ($process.ProcessName -ne 'WindowsTerminal') { throw "The recorded window for '$Member' is not Windows Terminal." }
    if ($process.StartTime.ToUniversalTime().ToString('o') -ne [string]$state.processStartTime) {
        throw "The recorded process identity for '$Member' is stale. Run warmup again."
    }

    $previousForegroundHandle = [AcademyWindowIdentity]::GetForegroundWindow()

    [uint32]$unusedPid = 0
    $foregroundThread = if ($previousForegroundHandle -ne [IntPtr]::Zero) {
        [AcademyWindowIdentity]::GetWindowThreadProcessId($previousForegroundHandle, [ref]$unusedPid)
    } else { 0 }
    $targetThread = [AcademyWindowIdentity]::GetWindowThreadProcessId($windowHandle, [ref]$unusedPid)
    $currentThread = [AcademyWindowIdentity]::GetCurrentThreadId()

    if ($foregroundThread -ne 0) {
        [void][AcademyWindowIdentity]::AttachThreadInput($currentThread, $foregroundThread, $true)
    }
    [void][AcademyWindowIdentity]::AttachThreadInput($currentThread, $targetThread, $true)
    try {
        if ([AcademyWindowIdentity]::IsIconic($windowHandle)) {
            [void][AcademyWindowIdentity]::ShowWindowAsync($windowHandle, 9)
        }
        [void][AcademyWindowIdentity]::BringWindowToTop($windowHandle)
        [void][AcademyWindowIdentity]::SetForegroundWindow($windowHandle)
        Start-Sleep -Milliseconds 150
    } finally {
        [void][AcademyWindowIdentity]::AttachThreadInput($currentThread, $targetThread, $false)
        if ($foregroundThread -ne 0) {
            [void][AcademyWindowIdentity]::AttachThreadInput($currentThread, $foregroundThread, $false)
        }
    }
    if ([AcademyWindowIdentity]::GetForegroundWindow() -ne $windowHandle) {
        throw "Could not activate the exact visible session for '$Member'."
    }

    if (-not ('AcademyUnicodeInput' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class AcademyUnicodeInput {
    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT { public uint type; public InputUnion U; }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_UNICODE = 0x0004;

    private static void SendKey(ushort vk, ushort scan, uint flags) {
        var inputs = new INPUT[2];
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].U.ki.wVk = vk;
        inputs[0].U.ki.wScan = scan;
        inputs[0].U.ki.dwFlags = flags;
        inputs[1] = inputs[0];
        inputs[1].U.ki.dwFlags = flags | KEYEVENTF_KEYUP;
        int inputSize = Marshal.SizeOf(typeof(INPUT));
        if (SendInput(2, inputs, inputSize) != 2) {
            throw new InvalidOperationException("Windows SendInput did not deliver the requested key pair. Win32 error=" + Marshal.GetLastWin32Error() + ", INPUT size=" + inputSize + ".");
        }
    }

    public static int NativeInputSize() { return Marshal.SizeOf(typeof(INPUT)); }

    public static void SendText(string text) {
        foreach (char value in text) SendKey(0, value, KEYEVENTF_UNICODE);
    }

    public static void SendVirtualKey(ushort virtualKey) { SendKey(virtualKey, 0, 0); }
}
'@
    }
    $expectedInputSize = if ([IntPtr]::Size -eq 8) { 40 } else { 28 }
    if ([AcademyUnicodeInput]::NativeInputSize() -ne $expectedInputSize) {
        throw "Win32 INPUT layout mismatch; refusing to inject terminal input."
    }
    if ($PermissionDecision -eq 'ApproveOnce') {
        [AcademyUnicodeInput]::SendVirtualKey(0x0D)
        $result.status = 'approved-once'
    } elseif ($PermissionDecision -eq 'Deny') {
        [AcademyUnicodeInput]::SendVirtualKey(0x1B)
        $result.status = 'denied'
    } else {
        [AcademyUnicodeInput]::SendText($messageText)
        # Submit separately from the keystroke burst. A TUI that treats a fast burst
        # as a paste can absorb a trailing Enter into it, which leaves the text
        # sitting unsent in the composer. Observed with Codex on
        # 2026-08-11: the full text arrived but was never submitted.
        Start-Sleep -Milliseconds 400
        [AcademyUnicodeInput]::SendVirtualKey(0x0D)
        # SendInput success proves only that Windows accepted the synthetic
        # keystrokes. Receipt, rendering, and submission remain unconfirmed
        # until visible session output or a durable outbox artifact appears.
        $result.status = 'input-sent'
    }
    $result.processId = $process.Id
    $result.windowHandle = $windowHandle.ToInt64()

    if ($previousForegroundHandle -ne [IntPtr]::Zero -and $previousForegroundHandle -ne $windowHandle -and [AcademyWindowIdentity]::IsWindow($previousForegroundHandle)) {
        try {
            [uint32]$prevPid = 0
            $prevThread = [AcademyWindowIdentity]::GetWindowThreadProcessId($previousForegroundHandle, [ref]$prevPid)
            if ($prevThread -ne 0) {
                [void][AcademyWindowIdentity]::AttachThreadInput($currentThread, $prevThread, $true)
            }
            [void][AcademyWindowIdentity]::BringWindowToTop($previousForegroundHandle)
            [void][AcademyWindowIdentity]::SetForegroundWindow($previousForegroundHandle)
            if ($prevThread -ne 0) {
                [void][AcademyWindowIdentity]::AttachThreadInput($currentThread, $prevThread, $false)
            }
        } catch {
            # Non-fatal: the input was already queued before foreground restoration.
            $null = $_
        }
    }
}

[pscustomobject]$result
