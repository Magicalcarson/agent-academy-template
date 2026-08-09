[CmdletBinding()]
param(
    [string]$Agent = 'All',
    [string]$Root,
    [string]$ProvidersPath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($ProvidersPath)) { $ProvidersPath = Join-Path $Root 'providers.json' }
$rosterPath = Join-Path $Root 'governance\roster.json'
if (-not (Test-Path -LiteralPath $rosterPath -PathType Leaf)) { throw "Roster is missing: $rosterPath" }
$members = @((Get-Content -LiteralPath $rosterPath -Raw | ConvertFrom-Json).members)
if ($Agent -ne 'All' -and $Agent -notin @($members.id)) { throw "Unknown roster id '$Agent'." }

$providers = $null
if (Test-Path -LiteralPath $ProvidersPath -PathType Leaf) {
    try { $providers = (Get-Content -LiteralPath $ProvidersPath -Raw | ConvertFrom-Json).providers }
    catch { throw "Provider configuration is not valid JSON: $ProvidersPath. $($_.Exception.Message)" }
}

$selected = if ($Agent -eq 'All') { $members } else { @($members | Where-Object id -eq $Agent) }
$rows = @($selected | ForEach-Object {
    $provider = if ($null -ne $providers) { $providers.PSObject.Properties[[string]$_.transport] } else { $null }
    $executable = if ($null -ne $provider) { [string]$provider.Value.executable } else { '' }
    [pscustomobject]@{
        id = $_.id
        displayName = $_.displayName
        transport = $_.transport
        rosterStatus = $_.status
        dispatchable = [bool]$_.dispatchable
        providerConfigured = $null -ne $provider
        executableAvailable = if ([string]::IsNullOrWhiteSpace($executable)) { $false } else { $null -ne (Get-Command $executable -ErrorAction SilentlyContinue) }
        quota = 'provider-managed'
    }
})

if ($Json) { [pscustomobject]@{ generatedAt = [DateTime]::UtcNow.ToString('o'); agents = $rows } | ConvertTo-Json -Depth 6; exit 0 }
$rows | Format-Table id, displayName, transport, rosterStatus, dispatchable, providerConfigured, executableAvailable -AutoSize
Write-Output 'Quota values remain provider-managed; use each provider CLI for exact limits.'
