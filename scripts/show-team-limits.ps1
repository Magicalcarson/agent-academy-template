[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Parameter is consumed in script scope by UI helper functions.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Console status dashboard requires colored host output for interactive terminals.')]
[CmdletBinding()]
param(
    [string]$Agent = 'All',
    [string]$Root,
    [string]$ProvidersPath,
    [string]$StatusPath,
    [switch]$Json,
    [switch]$NoColor
)

$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Console]::OutputEncoding
} catch {
    $null = $_
}

if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$academyRoot = [System.IO.Path]::GetFullPath($Root)

if ([string]::IsNullOrWhiteSpace($ProvidersPath)) {
    $ProvidersPath = [System.IO.Path]::Combine($academyRoot, 'providers.json')
}
if ([string]::IsNullOrWhiteSpace($StatusPath)) {
    $localStatus = [System.IO.Path]::Combine($academyRoot, 'status', 'team-status.local.json')
    $sharedStatus = [System.IO.Path]::Combine($academyRoot, 'status', 'team-status.json')
    $StatusPath = if (Test-Path -LiteralPath $localStatus -PathType Leaf) {
        $localStatus
    } elseif (Test-Path -LiteralPath $sharedStatus -PathType Leaf) {
        $sharedStatus
    } else {
        $null
    }
}

$rosterPath = [System.IO.Path]::Combine($academyRoot, 'governance', 'roster.json')
if (-not (Test-Path -LiteralPath $rosterPath -PathType Leaf)) {
    throw "Canonical roster not found: $rosterPath"
}

try {
    $roster = Get-Content -LiteralPath $rosterPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    throw "Roster is not valid JSON: $rosterPath. $($_.Exception.Message)"
}

$members = @($roster.members)
if ($members.Count -eq 0) {
    throw "Roster publishes no members: $rosterPath"
}

$onLeaveIds = @($roster.onLeave | ForEach-Object { [string]$_.id })
$members | ForEach-Object {
    if ($_.status -eq 'on-leave' -and $onLeaveIds -notcontains $_.id) {
        $onLeaveIds += [string]$_.id
    }
}

$providers = $null
if (Test-Path -LiteralPath $ProvidersPath -PathType Leaf) {
    try {
        $providers = (Get-Content -LiteralPath $ProvidersPath -Raw -Encoding UTF8 | ConvertFrom-Json).providers
    } catch {
        throw "Provider configuration is not valid JSON: $ProvidersPath. $($_.Exception.Message)"
    }
}

$telemetry = $null
if ($StatusPath -and (Test-Path -LiteralPath $StatusPath -PathType Leaf)) {
    try {
        $telemetry = Get-Content -LiteralPath $StatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $telemetry = $null
    }
}

if ($Agent -ne 'All') {
    $matched = @($members | Where-Object { $_.id -eq $Agent -or $_.displayName -eq $Agent })
    if ($matched.Count -eq 0) {
        throw "Unknown roster member: '$Agent'."
    }
    $selectedMembers = $matched
} else {
    $selectedMembers = $members
}

$Ui = [pscustomobject]@{
    TopLeft = [char]0x256D
    TopRight = [char]0x256E
    MidLeft = [char]0x251C
    MidRight = [char]0x2524
    BottomLeft = [char]0x2570
    BottomRight = [char]0x256F
    Horizontal = [char]0x2500
    Vertical = [char]0x2502
    Dot = [char]0x00B7
    Ellipsis = [char]0x2026
    Full = [char]0x2588
    Empty = [char]0x2591
    OpenDot = [char]0x25CB
    HalfDot = [char]0x25D0
    SolidDot = [char]0x25CF
    Shield = [char]0x25C6
}

function Format-Percent {
    param($Value)
    if ($null -eq $Value) { return 'UNKNOWN' }
    return '{0:0.#}%' -f [double]$Value
}

function Format-TokenCount {
    param($Value)
    if ($null -eq $Value) { return 'UNKNOWN' }
    $number = [double]$Value
    if ($number -ge 1000000) { return ('{0:0.#}m' -f ($number / 1000000)) }
    if ($number -ge 1000) { return ('{0:0.#}k' -f ($number / 1000)) }
    return ('{0:0}' -f $number)
}

function Format-Bar {
    param($Value, [int]$Size = 12)
    if ($null -eq $Value) { return '[' + (([string]$Ui.Dot) * $Size) + ']  UNKNOWN' }
    $number = [Math]::Max(0, [Math]::Min(100, [double]$Value))
    $filled = [Math]::Round(($number / 100) * $Size)
    return '[' + (([string]$Ui.Full) * $filled) + (([string]$Ui.Empty) * ($Size - $filled)) + '] ' + ('{0,3:0}%' -f $number)
}

function Format-ResetShort {
    param($Value)
    if (-not $Value) { return 'UNKNOWN' }
    try {
        $date = [DateTimeOffset]::Parse([string]$Value).LocalDateTime
        if ($date.Date -eq (Get-Date).Date) { return $date.ToString('HH:mm') }
        return $date.ToString('ddd HH:mm')
    } catch {
        return 'UNKNOWN'
    }
}

function Get-GuardrailStatus {
    param($FiveHourPercent, $SevenDayPercent, $ContextPercent)
    $flags = [System.Collections.Generic.List[string]]::new()

    if ($null -ne $FiveHourPercent) {
        $5hUsed = 100 - [double]$FiveHourPercent
        if ($5hUsed -ge 85) { $flags.Add('CRITICAL: 5h usage >= 85% (handoff required)') }
        elseif ($5hUsed -ge 70) { $flags.Add('WARNING: 5h usage >= 70% (checkpoint only)') }
    }

    if ($null -ne $SevenDayPercent) {
        $7dUsed = 100 - [double]$SevenDayPercent
        if ($7dUsed -ge 85) { $flags.Add('CRITICAL: 7d usage >= 85% (acceptance only)') }
    }

    if ($null -ne $ContextPercent) {
        $ctxRemaining = [double]$ContextPercent
        if ($ctxRemaining -le 15) { $flags.Add('CRITICAL: Context remaining <= 15% (clear context)') }
        elseif ($ctxRemaining -le 30) { $flags.Add('WARNING: Context remaining <= 30% (compact context)') }
    }

    if ($flags.Count -eq 0) { return 'NOMINAL' }
    return ($flags -join '; ')
}

$agentRecords = @($selectedMembers | ForEach-Object {
    $memberId = [string]$_.id
    $provider = if ($null -ne $providers) { $providers.PSObject.Properties[[string]$_.transport] } else { $null }
    $executable = if ($null -ne $provider) { [string]$provider.Value.executable } else { '' }
    $isOnLeave = $onLeaveIds -contains $memberId

    $agentTelemetry = $null
    if ($null -ne $telemetry -and $null -ne $telemetry.agents) {
        $agentTelemetry = @($telemetry.agents | Where-Object { $_.id -eq $memberId -or $_.name -eq $memberId })[0]
    }

    $status = if ($isOnLeave) {
        'ON LEAVE'
    } elseif ($null -ne $agentTelemetry -and $agentTelemetry.stale) {
        'STALE'
    } elseif ($null -ne $agentTelemetry -and $agentTelemetry.available -eq $false) {
        'WAITING'
    } elseif ($null -ne $agentTelemetry -and $agentTelemetry.available) {
        'ONLINE'
    } elseif (-not [string]::IsNullOrWhiteSpace($executable) -and (Get-Command $executable -ErrorAction SilentlyContinue)) {
        'CONFIGURED'
    } else {
        'UNKNOWN'
    }

    $model = if ($agentTelemetry -and $agentTelemetry.model) { $agentTelemetry.model } else { 'UNKNOWN - inspect interactive session' }
    $reasoning = if ($agentTelemetry -and $agentTelemetry.reasoning) { ([string]$agentTelemetry.reasoning).ToUpperInvariant() } else { 'DEFAULT' }

    $fiveHourRemaining = if ($agentTelemetry) { $agentTelemetry.fiveHourRemainingPercent } else { $null }
    $fiveHourReset = if ($agentTelemetry) { $agentTelemetry.fiveHourResetsAt } else { $null }
    $sevenDayRemaining = if ($agentTelemetry) { $agentTelemetry.sevenDayRemainingPercent } else { $null }
    $sevenDayReset = if ($agentTelemetry) { $agentTelemetry.sevenDayResetsAt } else { $null }
    $contextRemaining = if ($agentTelemetry) { $agentTelemetry.contextRemainingPercent } else { $null }
    $contextUsed = if ($agentTelemetry) { $agentTelemetry.contextUsedTokens } else { $null }
    $contextMax = if ($agentTelemetry) { $agentTelemetry.contextMaxTokens } else { $null }
    $quotaPercent = if ($agentTelemetry) { $agentTelemetry.quotaRemainingPercent } else { $null }
    $credits = if ($agentTelemetry) { $agentTelemetry.creditsRemaining } else { $null }

    $guardrails = Get-GuardrailStatus $fiveHourRemaining $sevenDayRemaining $contextRemaining

    [pscustomobject]@{
        id = $memberId
        displayName = $_.displayName
        authority = $_.authority
        transport = $_.transport
        rosterStatus = $_.status
        dispatchable = [bool]$_.dispatchable
        providerConfigured = $null -ne $provider
        executableAvailable = if ([string]::IsNullOrWhiteSpace($executable)) { $false } else { $null -ne (Get-Command $executable -ErrorAction SilentlyContinue) }
        status = $status
        model = $model
        reasoning = $reasoning
        quotaRemainingPercent = $quotaPercent
        creditsRemaining = $credits
        fiveHourRemainingPercent = $fiveHourRemaining
        fiveHourResetsAt = $fiveHourReset
        sevenDayRemainingPercent = $sevenDayRemaining
        sevenDayResetsAt = $sevenDayReset
        contextRemainingPercent = $contextRemaining
        contextUsedTokens = $contextUsed
        contextMaxTokens = $contextMax
        guardrailStatus = $guardrails
    }
})

if ($Json) {
    [pscustomobject]@{
        schemaVersion = 1
        generatedAt = [DateTime]::UtcNow.ToString('o')
        team = 'Agent Academy'
        statusSource = if ($StatusPath) { $StatusPath } else { 'NONE (telemetry absent; honest UNKNOWN)' }
        agents = $agentRecords
    } | ConvertTo-Json -Depth 6
    exit 0
}

function Get-DashboardWidth {
    try { $w = $Host.UI.RawUI.WindowSize.Width } catch { $w = 120 }
    if ($w -lt 1) { $w = 120 }
    return [Math]::Min(104, [Math]::Max(96, $w - 2))
}

function Get-FittedText {
    param([string]$Text, [int]$Width)
    if ($null -eq $Text) { $Text = '' }
    if ($Width -le 0) { return '' }
    if ($Text.Length -gt $Width) {
        if ($Width -le 1) { return $Text.Substring(0, $Width) }
        return $Text.Substring(0, $Width - 1) + [string]$Ui.Ellipsis
    }
    return $Text.PadRight($Width)
}

function Write-BoxLine {
    param(
        [string]$Text,
        [int]$Width,
        [ConsoleColor]$Color = [ConsoleColor]::Gray,
        [ConsoleColor]$BorderColor = [ConsoleColor]::DarkCyan
    )
    $innerWidth = $Width - 4
    $content = Get-FittedText $Text $innerWidth
    if ($script:NoColor) {
        Write-Output ('| ' + $content + ' |')
    } else {
        Write-Host ([string]$Ui.Vertical + ' ') -NoNewline -ForegroundColor $BorderColor
        Write-Host $content -NoNewline -ForegroundColor $Color
        Write-Host (' ' + [string]$Ui.Vertical) -ForegroundColor $BorderColor
    }
}

function Write-SplitBoxLine {
    param(
        [string]$Left,
        [string]$Right,
        [int]$Width,
        [ConsoleColor]$LeftColor = [ConsoleColor]::Gray,
        [ConsoleColor]$RightColor = [ConsoleColor]::Gray,
        [ConsoleColor]$BorderColor = [ConsoleColor]::DarkCyan
    )
    $innerWidth = $Width - 4
    $maxLeftWidth = [Math]::Max(1, $innerWidth - $Right.Length - 1)
    if ($Left.Length -gt $maxLeftWidth) { $Left = $Left.Substring(0, $maxLeftWidth - 1) + [string]$Ui.Ellipsis }
    $gap = [Math]::Max(1, $innerWidth - $Left.Length - $Right.Length)
    if ($script:NoColor) {
        Write-Output ('| ' + $Left + (' ' * $gap) + $Right + ' |')
    } else {
        Write-Host ([string]$Ui.Vertical + ' ') -NoNewline -ForegroundColor $BorderColor
        Write-Host $Left -NoNewline -ForegroundColor $LeftColor
        Write-Host (' ' * $gap) -NoNewline
        Write-Host $Right -NoNewline -ForegroundColor $RightColor
        Write-Host (' ' + [string]$Ui.Vertical) -ForegroundColor $BorderColor
    }
}

function Write-Border {
    param(
        [ValidateSet('Top', 'Middle', 'Bottom')][string]$Kind,
        [int]$Width,
        [ConsoleColor]$Color = [ConsoleColor]::DarkCyan
    )
    if ($script:NoColor) {
        Write-Output ('+' + ('-' * ($Width - 2)) + '+')
        return
    }
    $left = switch ($Kind) {
        'Top' { $Ui.TopLeft }
        'Middle' { $Ui.MidLeft }
        'Bottom' { $Ui.BottomLeft }
    }
    $right = switch ($Kind) {
        'Top' { $Ui.TopRight }
        'Middle' { $Ui.MidRight }
        'Bottom' { $Ui.BottomRight }
    }
    Write-Host ([string]$left + (([string]$Ui.Horizontal) * ($Width - 2)) + [string]$right) -ForegroundColor $Color
}

$dashboardWidth = Get-DashboardWidth
$innerWidth = $dashboardWidth - 4

Write-Border Top $dashboardWidth DarkCyan
Write-SplitBoxLine "AGENT ACADEMY  $($Ui.Dot)  TEAM LIMITS & GUARDRAILS" ("GENERATED  $($Ui.Dot)  " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) $dashboardWidth Cyan Green
$scopeText = if ($Agent -eq 'All') { "$($selectedMembers.Count) ROSTER MEMBERS" } else { $Agent }
Write-BoxLine ("Scope: $scopeText  $($Ui.Dot)  Honest telemetry: UNKNOWN is rendered when data is absent") $dashboardWidth Gray
Write-Border Middle $dashboardWidth DarkCyan

for ($i = 0; $i -lt $agentRecords.Count; $i++) {
    $rec = $agentRecords[$i]
    $statusColor = switch ($rec.status) {
        'ONLINE' { [ConsoleColor]::Green }
        'CONFIGURED' { [ConsoleColor]::Cyan }
        'STALE' { [ConsoleColor]::Yellow }
        'ON LEAVE' { [ConsoleColor]::DarkGray }
        default { [ConsoleColor]::DarkYellow }
    }
    $statusMarker = switch ($rec.status) {
        'ONLINE' { [string]$Ui.SolidDot }
        'CONFIGURED' { [string]$Ui.HalfDot }
        'STALE' { [string]$Ui.HalfDot }
        'ON LEAVE' { [string]$Ui.OpenDot }
        default { [string]$Ui.OpenDot }
    }

    $cardTitle = "$($Ui.Shield)  $($rec.displayName.ToUpperInvariant()) ($($rec.id))  $($Ui.Dot)  $($rec.transport.ToUpperInvariant())  $($Ui.Dot)  $($rec.authority.ToUpperInvariant())"
    $cardStatus = "$statusMarker $($rec.status)"
    Write-SplitBoxLine $cardTitle $cardStatus $dashboardWidth White $statusColor
    Write-BoxLine ("Model      " + $rec.model) $dashboardWidth Gray
    Write-BoxLine ("Mind       " + $rec.reasoning) $dashboardWidth Gray

    $quotaStr = if ($null -ne $rec.quotaRemainingPercent) {
        Format-Bar $rec.quotaRemainingPercent
    } elseif ($null -ne $rec.creditsRemaining) {
        "Credits: $($rec.creditsRemaining)"
    } else {
        "UNKNOWN (telemetry absent - inspect provider session)"
    }
    Write-BoxLine ("AI Quota   " + $quotaStr) $dashboardWidth Gray

    $fiveHourStr = "5h Limit   " + (Format-Bar $rec.fiveHourRemainingPercent) + "  $($Ui.Dot)  Reset " + (Format-ResetShort $rec.fiveHourResetsAt)
    Write-BoxLine $fiveHourStr $dashboardWidth Gray

    $sevenDayStr = "7d Limit   " + (Format-Bar $rec.sevenDayRemainingPercent) + "  $($Ui.Dot)  Reset " + (Format-ResetShort $rec.sevenDayResetsAt)
    Write-BoxLine $sevenDayStr $dashboardWidth Gray

    $contextDetail = if ($null -ne $rec.contextUsedTokens -and $null -ne $rec.contextMaxTokens) {
        "  $($Ui.Dot)  Used " + (Format-TokenCount $rec.contextUsedTokens) + '/' + (Format-TokenCount $rec.contextMaxTokens)
    } else { '' }
    $contextStr = "Context    " + (Format-Bar $rec.contextRemainingPercent) + $contextDetail
    Write-BoxLine $contextStr $dashboardWidth Gray

    $guardColor = if ($rec.guardrailStatus -match 'CRITICAL') { [ConsoleColor]::Red } elseif ($rec.guardrailStatus -match 'WARNING') { [ConsoleColor]::Yellow } else { [ConsoleColor]::Green }
    Write-BoxLine ("Guardrails " + $rec.guardrailStatus) $dashboardWidth $guardColor

    if ($i -lt ($agentRecords.Count - 1)) {
        Write-Border Middle $dashboardWidth DarkGray
    }
}

Write-Border Middle $dashboardWidth DarkCyan
Write-BoxLine ("Guardrail Thresholds: 5h >= 70% checkpoint, >= 85% handoff | 7d >= 85% accept only | Context <= 30% compact, <= 15% clear") $dashboardWidth DarkGray
Write-Border Bottom $dashboardWidth DarkCyan
