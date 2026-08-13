[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('academy-lead', 'academy-deputy')]
    [string]$Dispatcher,

    [ValidateRange(1, 30)]
    [int]$CloseTimeoutSeconds = 8
)

$ErrorActionPreference = 'Stop'
$academyRoot = Split-Path -Parent $PSScriptRoot
$stateDirectory = Join-Path $academyRoot 'status\warmup-sessions.local'

if (-not ('AcademyCooldownWindow' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class AcademyCooldownWindow {
    public const uint WM_CLOSE = 0x0010;
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool PostMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
}
'@
}

function Get-SessionDefinition([string]$Member) {
    switch ($Member) {
        'academy-lead' {
            return [ordered]@{ sessionName = 'agent-academy-academy-lead'; windowTitle = 'Agent Academy - Academy Lead' }
        }
        'academy-deputy' {
            return [ordered]@{ sessionName = 'agent-academy-academy-deputy'; windowTitle = 'Agent Academy - Academy Deputy' }
        }
        'academy-analyst' {
            return [ordered]@{ sessionName = 'agent-academy-academy-analyst'; windowTitle = 'Agent Academy - Academy Analyst' }
        }
        'academy-challenger' {
            return [ordered]@{ sessionName = 'agent-academy-academy-challenger'; windowTitle = 'Agent Academy - Academy Challenger' }
        }
        'academy-steward' {
            return [ordered]@{ sessionName = 'agent-academy-academy-steward'; windowTitle = 'Agent Academy - Academy Steward' }
        }
        default { throw "Unsupported cooldown member: $Member" }
    }
}

function Get-IdentityResult([bool]$IsValid, [string]$Reason) {
    return [pscustomobject]@{ isValid = $IsValid; reason = $Reason }
}

function Test-RecordedSessionIdentity {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Member,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Definition,
        [Parameter(Mandatory = $true)][bool]$WindowExists,
        [Parameter(Mandatory = $true)][bool]$WindowVisible,
        [Parameter(Mandatory = $true)][int]$OwnerProcessId,
        [AllowEmptyString()][string]$ProcessName,
        [AllowEmptyString()][string]$ProcessStartTime
    )

    if ([string]$State.member -ne $Member) {
        return Get-IdentityResult -IsValid $false -Reason 'memberMismatch'
    }
    if ([string]$State.sessionName -ne [string]$Definition.sessionName) {
        return Get-IdentityResult -IsValid $false -Reason 'sessionNameMismatch'
    }
    if ([string]$State.windowTitle -ne [string]$Definition.windowTitle) {
        return Get-IdentityResult -IsValid $false -Reason 'canonicalTitleMismatch'
    }
    if (-not $WindowExists) {
        return Get-IdentityResult -IsValid $false -Reason 'windowNotLive'
    }
    if (-not $WindowVisible) {
        return Get-IdentityResult -IsValid $false -Reason 'windowNotVisible'
    }
    if ($OwnerProcessId -ne [int]$State.processId) {
        return Get-IdentityResult -IsValid $false -Reason 'ownerProcessMismatch'
    }
    if ($ProcessName -ne 'WindowsTerminal') {
        return Get-IdentityResult -IsValid $false -Reason 'processNameMismatch'
    }
    if ($ProcessStartTime -ne [string]$State.processStartTime) {
        return Get-IdentityResult -IsValid $false -Reason 'processStartMismatch'
    }

    return Get-IdentityResult -IsValid $true -Reason $null
}

$members = if ($Dispatcher -eq 'academy-lead') {
    @('academy-deputy', 'academy-analyst', 'academy-challenger', 'academy-steward', 'academy-lead')
} else {
    @('academy-lead', 'academy-analyst', 'academy-challenger', 'academy-steward', 'academy-deputy')
}

foreach ($member in $members) {
    $definition = Get-SessionDefinition -Member $member
    $statePath = Join-Path $stateDirectory "$member.json"
    $result = [ordered]@{
        member = $member
        status = 'planned'
        action = 'closeExactWindow'
        sessionName = $definition.sessionName
        windowTitle = $definition.windowTitle
        processId = $null
        windowHandle = $null
        reason = $null
    }

    if ($PSCmdlet.ShouldProcess($member, 'Close the exact recorded Academy session window')) {
        if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
            $result.status = 'notFound'
            $result.reason = 'stateMissing'
            [pscustomobject]$result
            continue
        }

        try {
            $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
            $windowHandle = [IntPtr]([long]$state.windowHandle)
            $windowExists = [AcademyCooldownWindow]::IsWindow($windowHandle)
            $windowVisible = $windowExists -and [AcademyCooldownWindow]::IsWindowVisible($windowHandle)
            [uint32]$ownerPid = 0
            if ($windowExists) {
                [void][AcademyCooldownWindow]::GetWindowThreadProcessId($windowHandle, [ref]$ownerPid)
            }

            $process = if ($ownerPid -gt 0) {
                Get-Process -Id ([int]$ownerPid) -ErrorAction SilentlyContinue
            } else { $null }
            $processName = if ($process) { $process.ProcessName } else { '' }
            $processStartTime = if ($process) {
                $process.StartTime.ToUniversalTime().ToString('o')
            } else { '' }

            $result.processId = if ($ownerPid -gt 0) { [int]$ownerPid } else { $null }
            $result.windowHandle = $windowHandle.ToInt64()

            $identity = Test-RecordedSessionIdentity `
                -State $state `
                -Member $member `
                -Definition $definition `
                -WindowExists $windowExists `
                -WindowVisible $windowVisible `
                -OwnerProcessId ([int]$ownerPid) `
                -ProcessName $processName `
                -ProcessStartTime $processStartTime
            if (-not $identity.isValid) {
                $result.status = 'identityRejected'
                $result.reason = $identity.reason
                [pscustomobject]$result
                continue
            }

            $closeRequested = [AcademyCooldownWindow]::PostMessage(
                $windowHandle,
                [AcademyCooldownWindow]::WM_CLOSE,
                [IntPtr]::Zero,
                [IntPtr]::Zero
            )
            if (-not $closeRequested) {
                $result.status = 'closeRequestFailed'
                $result.reason = 'postMessageFailed'
                [pscustomobject]$result
                continue
            }

            $deadline = [DateTime]::UtcNow.AddSeconds($CloseTimeoutSeconds)
            while ([AcademyCooldownWindow]::IsWindow($windowHandle) -and [DateTime]::UtcNow -lt $deadline) {
                Start-Sleep -Milliseconds 100
            }
            if ([AcademyCooldownWindow]::IsWindow($windowHandle)) {
                $result.status = 'closeTimedOut'
                $result.reason = 'windowStillLive'
                [pscustomobject]$result
                continue
            }

            Remove-Item -LiteralPath $statePath -Force
            $result.status = 'closed'
        } catch {
            $result.status = 'error'
            $result.reason = $_.Exception.Message
        }
    }

    [pscustomobject]$result
}
