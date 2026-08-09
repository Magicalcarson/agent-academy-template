<#
.SYNOPSIS
Manual-orchestrator lock helper for Relay Inbox failover. Dot-source this file, then call
Acquire-Lock before a human-directed pump and Release-Lock when that manual session ends.

.DESCRIPTION
Governance constraints: check every output before using it; never steal an existing lock
unilaterally; release only after an acknowledged handback when handing over; and preserve lock
history by renaming rather than deleting it. The exclusively-held lock file is never read by
watchers: FileShare.None blocks readers. Watchers read orchestrator.status.json instead.

This is deliberately manual-orchestrator tooling. It has NO auto-pump, wrapper invocation,
queue, timer, or unattended loop.
#>

Set-StrictMode -Version Latest

$script:LockSession = $null
$script:HeartbeatIntervalSeconds = 30
$script:LockHandleInheritFlag = [UInt32]0x00000001
$script:MoveFileReplaceExisting = [UInt32]0x00000001
$script:MoveFileWriteThrough = [UInt32]0x00000008

if (-not ('OrchestratorLockNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class OrchestratorLockNative
{
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetHandleInformation(IntPtr hObject, uint dwMask, uint dwFlags);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, uint dwFlags);
}
'@
}

function Get-ProcessStartTimeUtc {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$ProcessId)

    (Get-Process -Id $ProcessId -ErrorAction Stop).StartTime.ToUniversalTime().ToString('o')
}

function Test-Fence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Int64]$CurrentEpoch,
        [Parameter(Mandatory)][Int64]$MutationEpoch
    )

    if ($MutationEpoch -ne $CurrentEpoch) {
        throw "Fence rejected mutation epoch $MutationEpoch; current epoch is $CurrentEpoch."
    }
    return $true
}

function Get-OwnerIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string]$ProcessStartTime
    )

    if ([string]::IsNullOrWhiteSpace($ProcessStartTime)) {
        throw 'PID-only owner checks are forbidden; processStartTime is required.'
    }

    try {
        $actual = Get-ProcessStartTimeUtc -ProcessId $ProcessId
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        return [pscustomobject]@{ Status = 'Missing'; Pid = $ProcessId; ExpectedStartTime = $ProcessStartTime; ActualStartTime = $null }
    }
    catch {
        if ($_.Exception.Message -match 'Cannot find a process') {
            return [pscustomobject]@{ Status = 'Missing'; Pid = $ProcessId; ExpectedStartTime = $ProcessStartTime; ActualStartTime = $null }
        }
        throw
    }

    $status = if ($actual -eq $ProcessStartTime) { 'Match' } else { 'Mismatch' }
    return [pscustomobject]@{ Status = $status; Pid = $ProcessId; ExpectedStartTime = $ProcessStartTime; ActualStartTime = $actual }
}

function Assert-LockSessionFence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Int64]$MutationEpoch)

    if (-not $script:LockSession) {
        throw 'No lock is held in this PowerShell session.'
    }

    # All post-acquisition state mutations must pass this gate.
    Test-Fence -CurrentEpoch $script:LockSession.Metadata.epoch -MutationEpoch $MutationEpoch | Out-Null
}

function ConvertTo-CompactUtf8Json {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Value)

    [System.Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Compress -Depth 8))
}

function Write-LockMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Int64]$MutationEpoch)

    Assert-LockSessionFence -MutationEpoch $MutationEpoch
    $bytes = ConvertTo-CompactUtf8Json -Value $script:LockSession.Metadata
    $stream = $script:LockSession.Stream
    $stream.SetLength(0)
    $stream.Position = 0
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush($true)
}

function Publish-OrchestratorStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Int64]$MutationEpoch,
        [Parameter(Mandatory)][string]$State
    )

    Assert-LockSessionFence -MutationEpoch $MutationEpoch
    $session = $script:LockSession
    $status = [ordered]@{
        agent = $session.Metadata.agent
        pid = $session.Metadata.pid
        processStartTime = $session.Metadata.processStartTime
        epoch = $session.Metadata.epoch
        nonce = $session.Metadata.nonce
        acquiredAt = $session.Metadata.acquiredAt
        heartbeatAt = $session.Metadata.heartbeatAt
        state = $State
        handback = $session.Metadata.handback
        updatedAt = [DateTime]::UtcNow.ToString('o')
    }

    $statusDirectory = Split-Path -Parent $session.StatusPath
    $temporaryPath = Join-Path $statusDirectory ('.orchestrator.status.{0}.{1}.tmp' -f $session.Metadata.nonce, [Guid]::NewGuid().ToString('N'))
    $bytes = ConvertTo-CompactUtf8Json -Value $status
    $stream = $null
    try {
        # The status artifact is read-shared; watchers should open it with FileShare.ReadWrite.
        $stream = [System.IO.FileStream]::new($temporaryPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally {
        if ($stream) { $stream.Dispose() }
    }

    $flags = $script:MoveFileReplaceExisting -bor $script:MoveFileWriteThrough
    if (-not [OrchestratorLockNative]::MoveFileEx($temporaryPath, $session.StatusPath, $flags)) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Unable to atomically publish orchestrator status (Win32 error $errorCode)."
    }
    return [pscustomobject]$status
}

function Acquire-Lock {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Acquire describes the intentional lock-lifecycle operation.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LockPath,
        [Parameter()][string]$StatusPath,
        [Parameter(Mandatory)][string]$Agent,
        [Parameter(Mandatory)][ValidateRange(1, [Int64]::MaxValue)][Int64]$Epoch,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Nonce
    )

    if ($script:LockSession) {
        throw 'A lock is already held in this PowerShell session.'
    }
    if (-not $StatusPath) {
        $StatusPath = Join-Path (Split-Path -Parent $LockPath) 'orchestrator.status.json'
    }

    $lockDirectory = Split-Path -Parent $LockPath
    $statusDirectory = Split-Path -Parent $StatusPath
    if (-not (Test-Path -LiteralPath $lockDirectory -PathType Container)) {
        throw "Lock directory does not exist: $lockDirectory"
    }
    if (-not (Test-Path -LiteralPath $statusDirectory -PathType Container)) {
        throw "Status directory does not exist: $statusDirectory"
    }
    # The first write also passes the public fence function: later mutations must match this epoch.
    Test-Fence -CurrentEpoch $Epoch -MutationEpoch $Epoch | Out-Null

    # CreateNew is fail-if-exists: exactly one contender can create the live lock file.
    $stream = [System.IO.FileStream]::new(
        $LockPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )

    try {
        $handle = $stream.SafeFileHandle.DangerousGetHandle()
        if (-not [OrchestratorLockNative]::SetHandleInformation($handle, $script:LockHandleInheritFlag, 0)) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Unable to disable lock-handle inheritance (Win32 error $errorCode)."
        }

        $now = [DateTime]::UtcNow.ToString('o')
        $metadata = [ordered]@{
            agent = $Agent
            pid = $PID
            processStartTime = Get-ProcessStartTimeUtc -ProcessId $PID
            epoch = $Epoch
            nonce = $Nonce
            acquiredAt = $now
            heartbeatAt = $now
            handback = $null
        }
        $script:LockSession = [pscustomobject]@{
            Stream = $stream
            LockPath = $LockPath
            StatusPath = $StatusPath
            Metadata = [pscustomobject]$metadata
            LastHeartbeatAt = [DateTime]::UtcNow
        }

        Write-LockMetadata -MutationEpoch $Epoch
        Publish-OrchestratorStatus -MutationEpoch $Epoch -State 'Held' | Out-Null
        return $script:LockSession.Metadata
    }
    catch {
        $acquireError = $_
        $stream.Dispose()
        $script:LockSession = $null
        if (Test-Path -LiteralPath $LockPath -PathType Leaf) {
            try {
                $failedPath = '{0}.acquire-failed.{1}.{2}.json' -f $LockPath, $Epoch, $Nonce
                [System.IO.File]::Move($LockPath, $failedPath)
            }
            catch {
                Write-Warning "Acquire failed and the lock could not be safely archived: $LockPath"
            }
        }
        throw $acquireError
    }
}

function Update-Heartbeat {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'A heartbeat is a required lease mutation; confirmation would make the manual pump unsafe.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][Int64]$Epoch)

    Assert-LockSessionFence -MutationEpoch $Epoch
    $script:LockSession.Metadata.heartbeatAt = [DateTime]::UtcNow.ToString('o')
    $script:LockSession.LastHeartbeatAt = [DateTime]::UtcNow
    Write-LockMetadata -MutationEpoch $Epoch
    return Publish-OrchestratorStatus -MutationEpoch $Epoch -State 'Held'
}

function Update-HeartbeatIfDue {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper conditionally performs the required lease heartbeat mutation.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][Int64]$Epoch)

    Assert-LockSessionFence -MutationEpoch $Epoch
    if ((([DateTime]::UtcNow - $script:LockSession.LastHeartbeatAt).TotalSeconds) -ge $script:HeartbeatIntervalSeconds) {
        return Update-Heartbeat -Epoch $Epoch
    }
    return $null
}

function Request-Handback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Int64]$Epoch,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$HandoffId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ToAgent,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$EvidenceOfLockOwnership
    )

    Assert-LockSessionFence -MutationEpoch $Epoch
    $script:LockSession.Metadata.handback = [ordered]@{
        handoffId = $HandoffId
        toAgent = $ToAgent
        evidenceOfLockOwnership = $EvidenceOfLockOwnership
        requestedAt = [DateTime]::UtcNow.ToString('o')
        acknowledgedAt = $null
        acknowledgedBy = $null
    }
    Write-LockMetadata -MutationEpoch $Epoch
    return Publish-OrchestratorStatus -MutationEpoch $Epoch -State 'HandbackRequested'
}

function Acknowledge-Handback {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Acknowledge names the explicit handback protocol transition.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Int64]$Epoch,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$HandoffId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$AcknowledgedBy
    )

    Assert-LockSessionFence -MutationEpoch $Epoch
    $handback = $script:LockSession.Metadata.handback
    if (-not $handback -or $handback.handoffId -ne $HandoffId) {
        throw 'Handback acknowledgement does not match an outstanding handback request.'
    }
    $handback.acknowledgedAt = [DateTime]::UtcNow.ToString('o')
    $handback.acknowledgedBy = $AcknowledgedBy
    Write-LockMetadata -MutationEpoch $Epoch
    return Publish-OrchestratorStatus -MutationEpoch $Epoch -State 'HandbackAcknowledged'
}

function Release-Lock {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Release describes the intentional lock-lifecycle operation.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Int64]$Epoch,
        [Parameter()][string]$AcknowledgedHandbackId,
        [Parameter()][ValidateSet('SessionComplete', 'AcknowledgedHandback')][string]$Reason = 'SessionComplete'
    )

    Assert-LockSessionFence -MutationEpoch $Epoch
    $session = $script:LockSession
    if ($Reason -eq 'AcknowledgedHandback') {
        $handback = $session.Metadata.handback
        if (-not $handback -or $handback.handoffId -ne $AcknowledgedHandbackId -or -not $handback.acknowledgedAt) {
            throw 'Acknowledged handback is required before releasing for handback.'
        }
    }

    try {
        Publish-OrchestratorStatus -MutationEpoch $Epoch -State 'Released' | Out-Null
        $session.Stream.Flush($true)
    }
    finally {
        $session.Stream.Dispose()
        $script:LockSession = $null
    }

    # Safe release: preserve history by rename; never delete or overwrite a lock file.
    Test-Fence -CurrentEpoch $session.Metadata.epoch -MutationEpoch $Epoch | Out-Null
    $releasedPath = '{0}.released.{1}.{2}.json' -f $session.LockPath, $session.Metadata.epoch, $session.Metadata.nonce
    [System.IO.File]::Move($session.LockPath, $releasedPath)
    return [pscustomobject]@{ ReleasedPath = $releasedPath; Epoch = $session.Metadata.epoch; Reason = $Reason }
}

