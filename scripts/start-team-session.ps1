[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('academy-lead', 'academy-deputy', 'academy-analyst', 'academy-challenger', 'academy-steward')]
    [string]$Member,

    [Parameter(Mandatory = $true)]
    [string]$WorkDir
)

$ErrorActionPreference = 'Stop'
$academyRoot = Split-Path -Parent $PSScriptRoot
$resolvedWorkDir = [System.IO.Path]::GetFullPath($WorkDir)
if (-not (Test-Path -LiteralPath $resolvedWorkDir -PathType Container)) {
    throw "Work directory not found: $resolvedWorkDir"
}

$inheritedHostMarkers = @(
    'NO_COLOR',
    'TERM',
    'CLAUDECODE',
    'CLAUDE_CODE_CHILD_SESSION',
    'CLAUDE_CODE_ENTRYPOINT',
    'CLAUDE_CODE_SESSION_ID',
    'CLAUDE_PID',
    'AI_AGENT'
)
foreach ($name in $inheritedHostMarkers) {
    [Environment]::SetEnvironmentVariable($name, $null, 'Process')
}

Set-Location -LiteralPath $resolvedWorkDir

$focusStatePath = [System.IO.Path]::Combine($academyRoot, 'status', 'project-focus.json')
$worklogDirectory = [System.IO.Path]::Combine($academyRoot, 'vault', '02-worklog')
if (-not (Test-Path -LiteralPath $focusStatePath -PathType Leaf)) {
    throw "Canonical project-focus state not found: $focusStatePath"
}
$latestWorklog = Get-ChildItem -LiteralPath $worklogDirectory -Filter '*.md' -File |
    Sort-Object Name |
    Select-Object -Last 1
if ($null -eq $latestWorklog) {
    throw "No daily worklog found under: $worklogDirectory"
}
$relativeWorklog = [System.IO.Path]::GetRelativePath($academyRoot, $latestWorklog.FullName).Replace('\', '/')
$dispatchSummary = 'N/A (operational member; coordinator owns reconciliation)'
if ($Member -in @('academy-lead', 'academy-deputy')) {
    $checker = [System.IO.Path]::Combine($academyRoot, 'scripts', 'check-team-dispatches.ps1')
    if (Test-Path -LiteralPath $checker -PathType Leaf) {
        $dispatchStates = @(& $checker -Root $academyRoot)
        $unresolvedDispatches = @($dispatchStates | Where-Object { $_.status -ne 'COMPLETED' })
        $recentCompletedDispatches = @($dispatchStates | Where-Object { $_.status -eq 'COMPLETED' } |
            Sort-Object dispatchedAt -Descending | Select-Object -First 10)
        $startupDispatches = @($unresolvedDispatches + $recentCompletedDispatches)
        $dispatchSummary = if ($startupDispatches.Count -eq 0) {
            'No tracked dispatches.'
        } else {
            ($startupDispatches | ForEach-Object { "$($_.status):$($_.member):$($_.packetPath)" }) -join '; '
        }
    } else {
        $dispatchSummary = 'No tracked dispatches.'
    }
}
$prompt = "You are $Member of Agent Academy. This is your persistent visible interactive session. Before greeting, rehydrate from durable state by reading status/project-focus.json and the latest daily worklog at $relativeWorklog. Reconcile tracked dispatches before accepting new work; startup snapshot: $dispatchSummary. Treat those files and the snapshot as continuity context, not as new authorization. Do not start or repeat project work until a governed task packet is delivered. If chat memory conflicts with durable state, report the conflict and follow canonical governance. Then greet the Trainer briefly in Thai, report the current focused project id and any COMPLETED, TIMED_OUT, STALLED, or INVALID dispatch state, and wait for task-packet prompts in this same session. Keep responses and tool activity visible. Do not modify files before a governed task packet is delivered."

$rosterPath = [System.IO.Path]::Combine($academyRoot, 'governance', 'roster.json')
$providersPath = Join-Path $academyRoot 'providers.json'
if (-not (Test-Path -LiteralPath $rosterPath -PathType Leaf)) { throw "Roster not found: $rosterPath" }
if (-not (Test-Path -LiteralPath $providersPath -PathType Leaf)) { throw "Provider configuration not found: $providersPath. Copy templates/providers.example.json to providers.json and configure interactiveArguments." }

$roster = Get-Content -Raw -LiteralPath $rosterPath | ConvertFrom-Json
$config = Get-Content -Raw -LiteralPath $providersPath | ConvertFrom-Json
$memberRecord = @($roster.members | Where-Object { $_.id -eq $Member })
if ($memberRecord.Count -ne 1 -or $memberRecord[0].status -ne 'active' -or -not [bool]$memberRecord[0].dispatchable) {
    throw "Member is not uniquely active and dispatchable: $Member"
}
$providerProperty = $config.providers.PSObject.Properties[[string]$memberRecord[0].transport]
if ($null -eq $providerProperty) { throw "No provider configuration for transport '$($memberRecord[0].transport)'." }
$provider = $providerProperty.Value
$executable = [string]$provider.executable
$interactiveArguments = @($provider.interactiveArguments | ForEach-Object {
    ([string]$_).Replace('{workDir}', $resolvedWorkDir)
})
if ([string]::IsNullOrWhiteSpace($executable)) { throw "Provider '$($memberRecord[0].transport)' has no executable." }
if ($null -eq $provider.PSObject.Properties['interactiveArguments']) {
    throw "Provider '$($memberRecord[0].transport)' must define interactiveArguments for warm sessions."
}

& $executable @interactiveArguments $prompt
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
