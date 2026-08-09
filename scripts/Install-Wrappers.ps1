[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$ProvidersPath,
    [string]$OutputDirectory,
    [switch]$DryRun,
    [switch]$Apply
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ($DryRun -and $Apply) { throw 'Choose either -DryRun or -Apply, not both.' }
if ([string]::IsNullOrWhiteSpace($ProvidersPath)) { $ProvidersPath = Join-Path $Root 'providers.json' }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $Root 'wrappers' }

$rosterPath = Join-Path $Root 'governance\roster.json'
if (-not (Test-Path -LiteralPath $rosterPath -PathType Leaf)) { throw "Roster is missing: $rosterPath" }
if (-not (Test-Path -LiteralPath $ProvidersPath -PathType Leaf)) { throw "Provider configuration is missing: $ProvidersPath" }
try {
    $roster = Get-Content -LiteralPath $rosterPath -Raw | ConvertFrom-Json
    $config = Get-Content -LiteralPath $ProvidersPath -Raw | ConvertFrom-Json
} catch {
    throw "Roster or provider configuration is not valid JSON. $($_.Exception.Message)"
}
if ($config.schemaVersion -ne 1 -or $null -eq $config.providers) { throw 'Provider configuration schemaVersion must be 1 and publish providers.' }

function ConvertTo-SingleQuotedLiteral {
    param([AllowEmptyString()][string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function ConvertTo-WrapperContent {
    param([Parameter(Mandatory = $true)]$Member, [Parameter(Mandatory = $true)]$Provider)
    $executable = [string]$Provider.executable
    if ([string]::IsNullOrWhiteSpace($executable)) { throw "Provider '$($Member.transport)' has no executable." }
    $argumentLiterals = @($Provider.arguments | ForEach-Object { ConvertTo-SingleQuotedLiteral -Value ([string]$_) })
    $argumentsExpression = if ($argumentLiterals.Count) { '@(' + ($argumentLiterals -join ', ') + ')' } else { '@()' }
    $closeStdin = if ([bool]$Provider.closeStdin) { '$true' } else { '$false' }
    $executableLiteral = ConvertTo-SingleQuotedLiteral -Value $executable

    return @"
[CmdletBinding()]
param(
    [Parameter(Mandatory = `$true)][ValidateNotNullOrEmpty()][string]`$Task,
    [Parameter(Mandatory = `$true)][ValidateNotNullOrEmpty()][string]`$WorkDir
)

`$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath `$WorkDir -PathType Container)) { throw "WorkDir does not exist: `$WorkDir" }
`$executable = $executableLiteral
`$providerArguments = $argumentsExpression
`$closeStdin = $closeStdin
Push-Location -LiteralPath `$WorkDir
try {
    if (`$closeStdin) {
        `$null | & `$executable @providerArguments `$Task
    } else {
        & `$executable @providerArguments `$Task
    }
    if (`$null -ne `$LASTEXITCODE -and `$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
} finally {
    Pop-Location
}
"@
}

$actions = @()
foreach ($member in @($roster.members)) {
    $providerProperty = $config.providers.PSObject.Properties[[string]$member.transport]
    if ($null -eq $providerProperty) { throw "No provider configuration exists for transport '$($member.transport)' used by '$($member.id)'." }
    $content = ConvertTo-WrapperContent -Member $member -Provider $providerProperty.Value
    $path = Join-Path $OutputDirectory ("{0}.ps1" -f $member.id)
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $existing = Get-Content -LiteralPath $path -Raw
        if ($existing.TrimEnd() -ne $content.TrimEnd()) { throw "Wrapper already exists with different content; refusing to overwrite: $path" }
        $actions += [pscustomobject]@{ Action = 'Preserve'; Path = $path; Member = $member.id; Transport = $member.transport }
        continue
    }
    $actions += [pscustomobject]@{ Action = if ($Apply) { 'Create' } else { 'WouldCreate' }; Path = $path; Member = $member.id; Transport = $member.transport }
    if ($Apply) {
        if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }
        [IO.File]::WriteAllText($path, $content.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    }
}
$actions
