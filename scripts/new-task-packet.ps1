[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$Agent,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [ValidateSet('low','normal','high')]
    [string]$Priority = 'normal',

    [ValidateSet('read-only','edit','review','research')]
    [string]$Mode = 'read-only',

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$Dispatcher,

    [Parameter(Mandatory = $true)]
    [ValidateSet('lead','delegated','failover')]
    [string]$Authority,

    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$Reviewer,

    [Parameter(Mandatory = $true)]
    [ValidateSet('code','review','research','ops','docs','portfolio-admin')]
    [string]$WorkType,

    [string]$ProjectId,
    [int]$CoordinatorEpoch,
    [string]$Root
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$coordinatorState = [System.IO.Path]::Combine($Root, 'status', 'coordinator-lease.local.json')
if (Test-Path -LiteralPath $coordinatorState) {
    $coordinatorScript = [System.IO.Path]::Combine($Root, 'scripts', 'team-coordinator.ps1')
    if (Test-Path -LiteralPath $coordinatorScript) {
        $fence = & $coordinatorScript -Action Assert -Coordinator $Dispatcher -Epoch $CoordinatorEpoch -StatePath $coordinatorState
        if (-not $fence.allowed) { throw "Coordinator fence rejected packet creation: active=$($fence.activeCoordinator) epoch=$($fence.epoch) state=$($fence.state)" }
    }
}

# Stable governance decides who may receive and dispatch work. Runtime telemetry
# may report availability, quota, or liveness, but it never grants authority.
$rosterPath = [System.IO.Path]::Combine($Root, 'governance', 'roster.json')
if (-not (Test-Path -LiteralPath $rosterPath -PathType Leaf)) {
    throw "Canonical roster is missing: $rosterPath. Dispatch is blocked."
}
try {
    $roster = Get-Content -LiteralPath $rosterPath -Raw | ConvertFrom-Json
} catch {
    throw "Roster is not valid JSON: $rosterPath. $($_.Exception.Message)"
}

$members = @($roster.members)
if ($members.Count -eq 0) {
    throw "Roster publishes no members: $rosterPath. Dispatch is blocked."
}

$membersById = @{}
foreach ($member in $members) {
    $id = [string]$member.id
    if ([string]::IsNullOrWhiteSpace($id) -or $membersById.ContainsKey($id)) {
        throw "Roster member ids must be non-empty and unique: $rosterPath"
    }
    $membersById[$id] = $member
}

function Get-ActiveMember {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Role
    )

    if (-not $membersById.ContainsKey($Id)) {
        throw "'$Id' is not published in the canonical roster and may not be assigned as $Role."
    }
    $member = $membersById[$Id]
    if ($member.status -eq 'on-leave') {
        $since = if ($null -ne $member.PSObject.Properties['onLeaveSince']) { $member.onLeaveSince } else { 'an unrecorded date' }
        $reason = if ($null -ne $member.PSObject.Properties['onLeaveReason']) { $member.onLeaveReason } else { 'reason not published' }
        throw "$($member.displayName) is on leave since $since ($reason) and may not be assigned as $Role. Reactivation requires a Trainer order."
    }
    if ($member.status -ne 'active' -or -not [bool]$member.dispatchable) {
        throw "$($member.displayName) is not active and dispatchable and may not be assigned as $Role."
    }
    return $member
}

$null = Get-ActiveMember -Id $Agent -Role 'maker'
$dispatcherMember = Get-ActiveMember -Id $Dispatcher -Role 'dispatcher'
if ($dispatcherMember.authority -eq 'lead' -and $Authority -ne 'lead') {
    throw 'A lead dispatcher must use -Authority lead.'
}
if ($dispatcherMember.authority -eq 'deputy' -and $Authority -notin @('delegated','failover')) {
    throw 'A deputy dispatcher must use -Authority delegated or failover.'
}
if ($dispatcherMember.authority -notin @('lead','deputy')) {
    throw "$($dispatcherMember.displayName) is not authorized to dispatch."
}

$requiresIndependentReviewer = $WorkType -eq 'code' -or ($WorkType -eq 'portfolio-admin' -and $Mode -eq 'edit')
if ($WorkType -eq 'code' -and $Mode -ne 'edit') {
    throw 'Code task packets require -Mode edit.'
}
if ($requiresIndependentReviewer) {
    if ([string]::IsNullOrWhiteSpace($Reviewer)) {
        throw 'Code-changing task packets require an independent -Reviewer.'
    }
    if ($Reviewer -eq $Agent) {
        throw 'The code reviewer must be different from the assigned maker.'
    }
    $null = Get-ActiveMember -Id $Reviewer -Role 'reviewer'
} elseif (-not [string]::IsNullOrWhiteSpace($Reviewer)) {
    $null = Get-ActiveMember -Id $Reviewer -Role 'reviewer'
}

if ($WorkType -ne 'portfolio-admin') {
    if ([string]::IsNullOrWhiteSpace($ProjectId)) {
        throw 'Project work requires -ProjectId.'
    }
    $statePath = [System.IO.Path]::Combine($Root, 'status', 'project-focus.json')
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "Project-focus state does not exist: $statePath"
    }
    try {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "Project-focus state is not valid JSON: $statePath. $($_.Exception.Message)"
    }
    $focused = @($state.projects | Where-Object { $_.id -eq $ProjectId -and $_.status -eq 'focused' })
    if ($state.focusProjectId -ne $ProjectId -or $focused.Count -ne 1) {
        throw "Project '$ProjectId' is not the single current execution focus."
    }
} elseif (-not [string]::IsNullOrWhiteSpace($ProjectId)) {
    throw 'Portfolio administration must not claim a project execution focus.'
}

$slug = ($Title.ToLowerInvariant() -replace '[^a-z0-9]+','-' -replace '^-|-$','')
if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'task' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$agentInbox = [System.IO.Path]::Combine($Root, 'inbox', $Agent)
if (-not (Test-Path -LiteralPath $agentInbox)) {
    New-Item -ItemType Directory -Path $agentInbox -Force | Out-Null
}
$path = Join-Path $agentInbox "$stamp-$slug.md"
$reviewerValue = if ([string]::IsNullOrWhiteSpace($Reviewer)) { 'N/A' } else { $Reviewer }
$projectValue = if ([string]::IsNullOrWhiteSpace($ProjectId)) { 'N/A (portfolio administration)' } else { $ProjectId }
$template = @"
# Task: $Title

Owner: $Agent
Reviewer: $reviewerValue
Dispatcher: $Dispatcher
Authority: $Authority
Project: $projectValue
Work type: $WorkType
Priority: $Priority
Mode: $Mode
Deadline: normal

## Goal
Write the exact outcome needed here.

## Context
Include the minimum offline-complete context required for the maker.

## Constraints
- Keep the answer evidence-backed.
- State assumptions separately from facts.
- Do not mutate production data unless explicitly authorized.
- Work only inside the named project or portfolio-admin boundary.
- A maker must not approve her own code.
- Never create or use a platform subagent. Delegate only to a real active roster member through the configured direct provider wrapper and durable packet.

## Allowed mutations
- Replace this placeholder with exact authorized files or boundaries.

## Acceptance criteria
- Replace this placeholder with observable pass/fail conditions.

## Required output
- Summary
- Evidence
- Verification
- Risks / unknowns
- Recommended next step
"@
[IO.File]::WriteAllText($path, $template + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Output $path
