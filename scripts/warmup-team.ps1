[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('academy-lead', 'academy-deputy')]
    [string]$Dispatcher,

    [string]$WorkDir
)

$ErrorActionPreference = 'Stop'
$academyRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = $academyRoot
}

if (-not ('AcademyWindowLookup' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class AcademyWindowLookup {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr extraData);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
'@
}

function Format-PowerShellLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
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
        default { throw "Unsupported warm session member: $Member" }
    }
}

function Get-ExactWindow([string]$WindowTitle) {
    $script:matchingWindow = $null
    [AcademyWindowLookup]::EnumWindows({
        param([IntPtr]$handle, [IntPtr]$unused)
        $null = $unused
        if (-not [AcademyWindowLookup]::IsWindowVisible($handle)) { return $true }
        $buffer = [Text.StringBuilder]::new(1024)
        [void][AcademyWindowLookup]::GetWindowText($handle, $buffer, $buffer.Capacity)
        if ($buffer.ToString() -eq $WindowTitle) {
            [uint32]$ownerPid = 0
            [void][AcademyWindowLookup]::GetWindowThreadProcessId($handle, [ref]$ownerPid)
            $script:matchingWindow = [pscustomobject]@{ Handle = $handle; ProcessId = [int]$ownerPid }
            return $false
        }
        return $true
    }, [IntPtr]::Zero) | Out-Null
    return $script:matchingWindow
}

function Get-LiveSessionWindow(
    [string]$Member,
    [string]$SessionName,
    [string]$WindowTitle,
    [string]$StateDirectory
) {
    $statePath = Join-Path $StateDirectory "$Member.json"
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }

    try {
        $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        if ($state.member -ne $Member) { return $null }
        if ($state.sessionName -ne $SessionName) { return $null }
        if ($state.windowTitle -ne $WindowTitle) { return $null }
        $handle = [IntPtr]([long]$state.windowHandle)
        if (-not [AcademyWindowLookup]::IsWindow($handle)) { return $null }
        if (-not [AcademyWindowLookup]::IsWindowVisible($handle)) { return $null }
        [uint32]$ownerPid = 0
        [void][AcademyWindowLookup]::GetWindowThreadProcessId($handle, [ref]$ownerPid)
        if ([int]$ownerPid -ne [int]$state.processId) { return $null }
        $process = Get-Process -Id ([int]$ownerPid) -ErrorAction Stop
        if ($process.ProcessName -ne 'WindowsTerminal') { return $null }
        if ($process.StartTime.ToUniversalTime().ToString('o') -ne [string]$state.processStartTime) { return $null }
        return [pscustomobject]@{ Handle = $handle; Process = $process }
    } catch {
        return $null
    }
}

function Find-Window([string]$WindowTitle) {
    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        $match = Get-ExactWindow -WindowTitle $WindowTitle
        if ($match) {
            $process = Get-Process -Id $match.ProcessId -ErrorAction Stop
            if ($process.ProcessName -eq 'WindowsTerminal') {
                return [pscustomobject]@{ Handle = $match.Handle; Process = $process }
            }
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Windows Terminal session did not become observable: $WindowTitle"
}

function Write-SessionState([string]$Member, [hashtable]$Definition, [psobject]$Window, [string]$StateDirectory) {
    if (-not (Test-Path -LiteralPath $StateDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $StateDirectory -Force | Out-Null
    }

    $statePath = Join-Path $StateDirectory "$Member.json"
    $temporaryPath = Join-Path $StateDirectory (".{0}.{1}.tmp" -f $Member, [Guid]::NewGuid().ToString('N'))
    $state = [ordered]@{
        schemaVersion = 1
        member = $Member
        sessionName = $Definition.sessionName
        windowTitle = $Definition.windowTitle
        processId = $Window.Process.Id
        processStartTime = $Window.Process.StartTime.ToUniversalTime().ToString('o')
        windowHandle = $Window.Handle.ToInt64()
        recordedAt = [DateTime]::UtcNow.ToString('o')
    }
    [System.IO.File]::WriteAllText($temporaryPath, ($state | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $statePath -Force
}

$resolvedWorkDir = [System.IO.Path]::GetFullPath($WorkDir)
if (-not (Test-Path -LiteralPath $resolvedWorkDir -PathType Container)) {
    throw "Work directory not found: $resolvedWorkDir"
}
if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
    throw 'Windows Terminal (wt.exe) is required for persistent visible sessions.'
}

$sessionHost = Join-Path $academyRoot 'scripts\start-team-session.ps1'
if (-not (Test-Path -LiteralPath $sessionHost -PathType Leaf)) {
    throw "Session host not found: $sessionHost"
}
$stateDirectory = Join-Path $academyRoot 'status\warmup-sessions.local'

$members = if ($Dispatcher -eq 'academy-lead') {
    @('academy-deputy', 'academy-analyst', 'academy-challenger', 'academy-steward')
} else {
    @('academy-lead', 'academy-analyst', 'academy-challenger', 'academy-steward')
}
$rosterPath = Join-Path $academyRoot 'governance\roster.json'
$roster = Get-Content -Raw -LiteralPath $rosterPath | ConvertFrom-Json
$dispatchableIds = @($roster.members | Where-Object {
        $_.status -eq 'active' -and [bool]$_.dispatchable
    } | ForEach-Object { [string]$_.id })
$members = @($members | Where-Object { $dispatchableIds -contains $_ })

foreach ($member in $members) {
    $definition = Get-SessionDefinition -Member $member
    $quotedTitle = Format-PowerShellLiteral $definition.windowTitle
    $quotedWorkDir = Format-PowerShellLiteral $resolvedWorkDir
    $quotedHost = Format-PowerShellLiteral $sessionHost
    $command = "wt.exe -w $($definition.sessionName) new-tab --title $quotedTitle --suppressApplicationTitle --startingDirectory $quotedWorkDir powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File $quotedHost -Member $member -WorkDir $quotedWorkDir"

    $result = [ordered]@{
        member = $member
        status = 'planned'
        windowStyle = 'Normal'
        sessionName = $definition.sessionName
        windowTitle = $definition.windowTitle
        command = $command
        processId = $null
        windowHandle = $null
    }

    if ($PSCmdlet.ShouldProcess($member, 'Open or reuse visible native interactive Academy session')) {
        $liveWindow = Get-LiveSessionWindow -Member $member -SessionName $definition.sessionName -WindowTitle $definition.windowTitle -StateDirectory $stateDirectory
        if (-not $liveWindow) {
            $discovered = Get-ExactWindow -WindowTitle $definition.windowTitle
            if ($discovered) {
                $discoveredProcess = Get-Process -Id $discovered.ProcessId -ErrorAction Stop
                if ($discoveredProcess.ProcessName -eq 'WindowsTerminal') {
                    $liveWindow = [pscustomobject]@{ Handle = $discovered.Handle; Process = $discoveredProcess }
                    Write-SessionState -Member $member -Definition $definition -Window $liveWindow -StateDirectory $stateDirectory
                }
            }
        }
        if ($liveWindow) {
            $result.status = 'reused'
            $result.processId = $liveWindow.Process.Id
            $result.windowHandle = $liveWindow.Handle.ToInt64()
        } else {
            $nativeArgs = @(
                '-w', $definition.sessionName,
                'new-tab',
                '--title', ('"{0}"' -f $definition.windowTitle),
                '--suppressApplicationTitle',
                '--startingDirectory', ('"{0}"' -f $resolvedWorkDir),
                'powershell.exe', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit',
                '-File', ('"{0}"' -f $sessionHost), '-Member', $member, '-WorkDir', ('"{0}"' -f $resolvedWorkDir)
            )
            Start-Process -FilePath 'wt.exe' -ArgumentList $nativeArgs -WindowStyle Normal | Out-Null
            $liveWindow = Find-Window -WindowTitle $definition.windowTitle
            Write-SessionState -Member $member -Definition $definition -Window $liveWindow -StateDirectory $stateDirectory
            $result.status = 'launched'
            $result.processId = $liveWindow.Process.Id
            $result.windowHandle = $liveWindow.Handle.ToInt64()
        }
    }

    [pscustomobject]$result
}
