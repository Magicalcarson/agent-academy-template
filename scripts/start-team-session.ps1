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

$focusStatePath = Join-Path $academyRoot 'status\project-focus.json'
$worklogDirectory = Join-Path $academyRoot 'vault\02-worklog'
if (-not (Test-Path -LiteralPath $focusStatePath -PathType Leaf)) {
    throw "Canonical project-focus state not found: $focusStatePath"
}
$latestWorklog = Get-ChildItem -LiteralPath $worklogDirectory -Filter '*.md' -File |
    Sort-Object Name |
    Select-Object -Last 1
if ($null -eq $latestWorklog) {
    throw "No daily worklog found under: $worklogDirectory"
}
$relativeWorklog = $latestWorklog.FullName.Substring($academyRoot.TrimEnd('\').Length + 1).Replace('\', '/')
$prompt = "You are $Member of Agent Academy. This is your persistent visible interactive session. Before greeting, rehydrate from durable state by reading status/project-focus.json and the latest daily worklog at $relativeWorklog. Treat those files as continuity context, not as new authorization. Do not start or repeat project work until a governed task packet is delivered. If chat memory conflicts with durable state, report the conflict and follow canonical governance. Then greet the Trainer briefly in Thai, report the current focused project id and that you are ready, and wait for task-packet prompts in this same session. Keep responses and tool activity visible. Do not modify files before a governed task packet is delivered."

$rosterPath = Join-Path $academyRoot 'governance\roster.json'
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
