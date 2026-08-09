[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateRange(8,100)][int]$MaxLines = 25
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$worklogDir = Join-Path $RepositoryRoot 'vault\02-worklog'
$latest = Get-ChildItem -LiteralPath $worklogDir -Filter '????-??-??.md' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1

$output = [Collections.Generic.List[string]]::new()
if ($latest) {
    $output.Add("=== Latest worklog: $($latest.Name) (tail) ===")
    $content = @(Get-Content -LiteralPath $latest.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)
    $tailCount = [Math]::Max(1, $MaxLines - 4)
    if ($content.Count -gt $tailCount) { $content = @($content[($content.Count - $tailCount)..($content.Count - 1)]) }
    foreach ($line in $content) { $output.Add([string]$line) }
} else {
    $output.Add('=== No dated worklog files found in the repository vault ===')
}
$today = (Get-Date).ToString('yyyy-MM-dd')
$output.Add('=== ACTION REQUIRED ===')
$output.Add("Log every meaningful step to vault\02-worklog\$today.md as it happens: findings, decisions, file changes, dispatch, and verification.")
$output | Select-Object -First $MaxLines
exit 0
