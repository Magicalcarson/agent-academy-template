[CmdletBinding()]
param(
    [ValidateSet('Main','Task','Limits')][string]$Screen = 'Main',
    [string]$Root,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$rosterPath = Join-Path $Root 'governance\roster.json'
if (-not (Test-Path -LiteralPath $rosterPath -PathType Leaf)) { throw "Roster is missing: $rosterPath" }
$members = @((Get-Content -LiteralPath $rosterPath -Raw | ConvertFrom-Json).members)

$items = switch ($Screen) {
    'Main' {
        @(
            [pscustomobject]@{ key = 1; action = 'portfolio'; description = 'Show or manage project focus' }
            [pscustomobject]@{ key = 2; action = 'task'; description = 'Create a governed task packet' }
            [pscustomobject]@{ key = 3; action = 'limits'; description = 'Show provider and roster status' }
            [pscustomobject]@{ key = 4; action = 'vault'; description = 'Open the second-brain hub' }
        )
    }
    'Task' {
        @($members | ForEach-Object {
            [pscustomobject]@{
                id = $_.id
                displayName = $_.displayName
                authority = $_.authority
                status = $_.status
                dispatchable = [bool]$_.dispatchable
            }
        })
    }
    'Limits' {
        @($members | ForEach-Object {
            [pscustomobject]@{ id = $_.id; displayName = $_.displayName; transport = $_.transport; status = $_.status }
        })
    }
}

if ($Json) { [pscustomobject]@{ screen = $Screen; items = @($items) } | ConvertTo-Json -Depth 6; exit 0 }
Write-Output "AGENT ACADEMY :: $($Screen.ToUpperInvariant())"
foreach ($item in @($items)) {
    if ($Screen -eq 'Main') { Write-Output ("[{0}] {1} - {2}" -f $item.key, $item.action, $item.description) }
    elseif ($Screen -eq 'Task') { Write-Output ("{0} :: {1} :: {2} :: dispatchable={3}" -f $item.id, $item.displayName, $item.status, $item.dispatchable) }
    else { Write-Output ("{0} :: {1} :: {2} :: {3}" -f $item.id, $item.displayName, $item.transport, $item.status) }
}
