[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$ClaudeHome,
    [switch]$DryRun,
    [switch]$Apply
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ($DryRun -and $Apply) { throw 'Choose either -DryRun or -Apply, not both.' }
if ([string]::IsNullOrWhiteSpace($ClaudeHome)) {
    $ClaudeHome = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude'
}
$sourceHook = Join-Path $PSScriptRoot 'worklog-guard.ps1'
$targetHook = Join-Path $ClaudeHome 'hooks\agent-academy-worklog-guard.ps1'
$settingsPath = Join-Path $ClaudeHome 'settings.json'
if (-not (Test-Path -LiteralPath $sourceHook -PathType Leaf)) { throw "Hook source is missing: $sourceHook" }

function ConvertTo-CommandQuotedValue {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + ($Value -replace '"','\"') + '"'
}

$command = 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ' +
    (ConvertTo-CommandQuotedValue -Value $targetHook) + ' -RepositoryRoot ' +
    (ConvertTo-CommandQuotedValue -Value $Root)
$actions = @()

$hookNeedsCreate = -not (Test-Path -LiteralPath $targetHook -PathType Leaf)
if (-not $hookNeedsCreate) {
    $sourceText = Get-Content -LiteralPath $sourceHook -Raw
    $targetText = Get-Content -LiteralPath $targetHook -Raw
    if ($sourceText.TrimEnd() -ne $targetText.TrimEnd()) { throw "Managed hook exists with different content; refusing to overwrite: $targetHook" }
}
$actions += [pscustomobject]@{ Action = if ($hookNeedsCreate) { if ($Apply) { 'Create' } else { 'WouldCreate' } } else { 'Preserve' }; Path = $targetHook }

$settings = if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    try { Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json }
    catch { throw "Claude settings are not valid JSON; refusing to write: $settingsPath. $($_.Exception.Message)" }
} else {
    [pscustomobject]@{}
}
$hooksProperty = $settings.PSObject.Properties['hooks']
if ($null -eq $hooksProperty -or $null -eq $hooksProperty.Value) {
    if ($null -eq $hooksProperty) { $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }
    else { $settings.hooks = [pscustomobject]@{} }
}
$sessionStartProperty = $settings.hooks.PSObject.Properties['SessionStart']
if ($null -eq $sessionStartProperty -or $null -eq $sessionStartProperty.Value) {
    if ($null -eq $sessionStartProperty) { $settings.hooks | Add-Member -NotePropertyName SessionStart -NotePropertyValue @() }
    else { $settings.hooks.SessionStart = @() }
}
$existingCommands = @($settings.hooks.SessionStart | ForEach-Object { @($_.hooks) } | ForEach-Object { [string]$_.command })
$settingsNeedsUpdate = $command -notin $existingCommands
if ($settingsNeedsUpdate) {
    $entry = [pscustomobject][ordered]@{
        matcher = ''
        hooks = @([pscustomobject][ordered]@{ type = 'command'; command = $command })
    }
    $settings.hooks.SessionStart = @($settings.hooks.SessionStart) + @($entry)
}
$actions += [pscustomobject]@{ Action = if ($settingsNeedsUpdate) { if ($Apply) { 'Update' } else { 'WouldUpdate' } } else { 'Preserve' }; Path = $settingsPath }

if ($Apply) {
    $hookDirectory = Split-Path -Parent $targetHook
    if (-not (Test-Path -LiteralPath $hookDirectory)) { New-Item -ItemType Directory -Path $hookDirectory -Force | Out-Null }
    if ($hookNeedsCreate) {
        [IO.File]::WriteAllText($targetHook, (Get-Content -LiteralPath $sourceHook -Raw).TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    }
    if ($settingsNeedsUpdate) {
        if (-not (Test-Path -LiteralPath $ClaudeHome)) { New-Item -ItemType Directory -Path $ClaudeHome -Force | Out-Null }
        if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
            $backupPath = "$settingsPath.agent-academy.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -LiteralPath $settingsPath -Destination $backupPath
            $actions += [pscustomobject]@{ Action = 'Backup'; Path = $backupPath }
        }
        $temporaryPath = "$settingsPath.agent-academy.$([guid]::NewGuid().ToString('N')).tmp"
        [IO.File]::WriteAllText($temporaryPath, ($settings | ConvertTo-Json -Depth 20) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $settingsPath -Force
    }
}
$actions
