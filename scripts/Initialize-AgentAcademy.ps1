[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallRoot = (Split-Path -Parent $PSScriptRoot),

    [Parameter()]
    [string]$TrainerName,

    [Parameter()]
    [string]$PreferredLanguage,

    [Parameter()]
    [string]$TimeZone,

    [Parameter()]
    [string]$AssignmentsJson,

    [Parameter()]
    [string]$DisplayNamesJson,

    [Parameter()]
    [switch]$DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$templateRoot = Split-Path -Parent $PSScriptRoot
$sourceRosterPath = Join-Path $templateRoot 'governance\roster.json'
$installedRosterPath = Join-Path $InstallRoot 'governance\roster.json'
$rosterReadPath = if (Test-Path -LiteralPath $installedRosterPath -PathType Leaf) { $installedRosterPath } else { $sourceRosterPath }
if (-not (Test-Path -LiteralPath $rosterReadPath -PathType Leaf)) { throw "Roster is missing: $rosterReadPath" }
try { $roster = Get-Content -LiteralPath $rosterReadPath -Raw | ConvertFrom-Json }
catch { throw "Roster is not valid JSON: $rosterReadPath. $($_.Exception.Message)" }

$rosterWasChanged = $false
if (-not [string]::IsNullOrWhiteSpace($DisplayNamesJson)) {
    try { $displayNames = $DisplayNamesJson | ConvertFrom-Json }
    catch { throw "DisplayNamesJson is not valid JSON. $($_.Exception.Message)" }
    foreach ($property in $displayNames.PSObject.Properties) {
        $memberMatches = @($roster.members | Where-Object { $_.id -eq $property.Name })
        if ($memberMatches.Count -ne 1) { throw "DisplayNamesJson contains unknown roster id '$($property.Name)'." }
        $displayName = [string]$property.Value
        if ([string]::IsNullOrWhiteSpace($displayName) -or $displayName -match '[\r\n]') { throw "Display name for '$($property.Name)' must be non-empty and single-line." }
        if ([string]$memberMatches[0].displayName -ne $displayName) {
            $memberMatches[0].displayName = $displayName
            $rosterWasChanged = $true
        }
    }
}
$memberNames = @($roster.members | ForEach-Object { [string]$_.displayName })

function ConvertTo-SafeMarkdownValue {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value,

        [string]$Fallback = '_Not set_'
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Fallback
    }

    return (($Value -replace '[\r\n]+', ' ').Trim())
}

function Read-OptionalValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    return (Read-Host $Prompt)
}

function Read-InteractiveAssignment {
    $items = @()

    foreach ($memberName in $memberNames) {
        $items += [pscustomobject]@{
            name = $memberName
            role = Read-OptionalValue -Prompt "Position or role for $memberName (optional)"
            responsibilities = Read-OptionalValue -Prompt "Responsibilities for $memberName (optional)"
            provider = Read-OptionalValue -Prompt "Provider for $memberName (optional)"
            model = Read-OptionalValue -Prompt "Model for $memberName (optional)"
        }
    }

    return $items
}

function ConvertFrom-AssignmentsJson {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Json
    )

    if ([string]::IsNullOrWhiteSpace($Json)) {
        return @()
    }

    $parsed = $Json | ConvertFrom-Json
    return @($parsed)
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return ''
    }

    return [string]$property.Value
}

function ConvertTo-AssignmentsMarkdown {
    param(
        [object[]]$Assignments
    )

    $byName = @{}
    foreach ($assignment in $Assignments) {
        $name = Get-PropertyValue -InputObject $assignment -Name 'name'
        if (-not [string]::IsNullOrWhiteSpace($name) -and $memberNames -contains $name) {
            $byName[$name] = $assignment
        }
    }

    $lines = @(
        '<!-- agent-academy:local-only -->'
        '# Team assignments'
        ''
        'These choices belong to this installation and are not part of the reusable template.'
        ''
    )

    foreach ($memberName in $memberNames) {
        $assignment = $null
        if ($byName.ContainsKey($memberName)) {
            $assignment = $byName[$memberName]
        }

        $role = ''
        $responsibilities = ''
        $provider = ''
        $model = ''
        if ($null -ne $assignment) {
            $role = Get-PropertyValue -InputObject $assignment -Name 'role'
            $responsibilities = Get-PropertyValue -InputObject $assignment -Name 'responsibilities'
            $provider = Get-PropertyValue -InputObject $assignment -Name 'provider'
            $model = Get-PropertyValue -InputObject $assignment -Name 'model'
        }

        $lines += "## $memberName"
        $lines += ''
        $lines += "- Position or role: $(ConvertTo-SafeMarkdownValue -Value $role -Fallback '_Unassigned_')"
        $lines += "- Responsibilities: $(ConvertTo-SafeMarkdownValue -Value $responsibilities -Fallback '_Unassigned_')"
        $lines += "- Provider: $(ConvertTo-SafeMarkdownValue -Value $provider -Fallback '_Unassigned_')"
        $lines += "- Model: $(ConvertTo-SafeMarkdownValue -Value $model -Fallback '_Unassigned_')"
        $lines += ''
    }

    return ($lines -join [Environment]::NewLine)
}

$interactive = -not $PSBoundParameters.ContainsKey('TrainerName')
if ($interactive) {
    $TrainerName = Read-Host 'Trainer name or preferred form of address'
    $PreferredLanguage = Read-OptionalValue -Prompt 'Preferred language'
    $TimeZone = Read-OptionalValue -Prompt 'Time zone'
}

if ([string]::IsNullOrWhiteSpace($TrainerName)) {
    throw 'TrainerName is required. Supply -TrainerName or run the script interactively.'
}

$assignments = @()
if (-not [string]::IsNullOrWhiteSpace($AssignmentsJson)) {
    $assignments = ConvertFrom-AssignmentsJson -Json $AssignmentsJson
}
elseif ($interactive) {
    $assignments = Read-InteractiveAssignment
}

$trainerMarkdown = @(
    '<!-- agent-academy:local-only -->'
    '# Trainer'
    ''
    "- Name or form of address: $(ConvertTo-SafeMarkdownValue -Value $TrainerName)"
    "- Preferred language: $(ConvertTo-SafeMarkdownValue -Value $PreferredLanguage)"
    "- Time zone: $(ConvertTo-SafeMarkdownValue -Value $TimeZone)"
    ''
    'Add only information you intentionally want agents in this installation to use.'
) -join [Environment]::NewLine

$assignmentsMarkdown = ConvertTo-AssignmentsMarkdown -Assignments $assignments
$governanceRoot = Join-Path $InstallRoot 'governance'
$contentTargets = @(
    [pscustomobject]@{
        Path = Join-Path $governanceRoot 'trainer.local.md'
        Content = $trainerMarkdown
    }
    [pscustomobject]@{
        Path = Join-Path $governanceRoot 'assignments.local.md'
        Content = $assignmentsMarkdown
    }
)

$actions = @()
foreach ($target in $contentTargets) {
    if (Test-Path -LiteralPath $target.Path) {
        $actions += [pscustomobject]@{ Action = 'Preserve'; Path = $target.Path }
        continue
    }

    $actions += [pscustomobject]@{ Action = if ($DryRun) { 'WouldCreate' } else { 'Create' }; Path = $target.Path }

    if (-not $DryRun) {
        $parent = Split-Path -Parent $target.Path
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllText($target.Path, $target.Content.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    }
}

$rosterContent = ($roster | ConvertTo-Json -Depth 10) + [Environment]::NewLine
if (Test-Path -LiteralPath $installedRosterPath -PathType Leaf) {
    if ($rosterWasChanged) {
        $actions += [pscustomobject]@{ Action = if ($DryRun) { 'WouldUpdateDisplayNames' } else { 'UpdateDisplayNames' }; Path = $installedRosterPath }
        if (-not $DryRun) { [IO.File]::WriteAllText($installedRosterPath, $rosterContent, [Text.UTF8Encoding]::new($false)) }
    } else {
        $actions += [pscustomobject]@{ Action = 'Preserve'; Path = $installedRosterPath }
    }
} else {
    $actions += [pscustomobject]@{ Action = if ($DryRun) { 'WouldCreate' } else { 'Create' }; Path = $installedRosterPath }
    if (-not $DryRun) {
        $parent = Split-Path -Parent $installedRosterPath
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllText($installedRosterPath, $rosterContent, [Text.UTF8Encoding]::new($false))
    }
}

$seedFiles = @(
    [pscustomobject]@{ Source = Join-Path $templateRoot 'templates\providers.example.json'; Target = Join-Path $InstallRoot 'providers.json' }
    [pscustomobject]@{ Source = Join-Path $templateRoot 'status\project-focus.example.json'; Target = Join-Path $InstallRoot 'status\project-focus.json' }
)
$vaultTemplateRoot = Join-Path $templateRoot 'templates\vault'
if (Test-Path -LiteralPath $vaultTemplateRoot -PathType Container) {
    foreach ($sourceFile in Get-ChildItem -LiteralPath $vaultTemplateRoot -File -Recurse) {
        $relative = $sourceFile.FullName.Substring($vaultTemplateRoot.Length).TrimStart('\','/')
        if ($relative -like 'obsidian\*') { $relative = '.obsidian\' + $relative.Substring('obsidian\'.Length) }
        $seedFiles += [pscustomobject]@{ Source = $sourceFile.FullName; Target = Join-Path (Join-Path $InstallRoot 'vault') $relative }
    }
}

foreach ($seed in $seedFiles) {
    if (-not (Test-Path -LiteralPath $seed.Source -PathType Leaf)) { throw "Template seed is missing: $($seed.Source)" }
    if (Test-Path -LiteralPath $seed.Target) {
        $actions += [pscustomobject]@{ Action = 'Preserve'; Path = $seed.Target }
        continue
    }
    $actions += [pscustomobject]@{ Action = if ($DryRun) { 'WouldCreate' } else { 'Create' }; Path = $seed.Target }
    if (-not $DryRun) {
        $parent = Split-Path -Parent $seed.Target
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $seed.Source -Destination $seed.Target
    }
}

$actions
