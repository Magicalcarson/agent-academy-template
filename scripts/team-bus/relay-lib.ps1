[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Function names are the adopted public relay API and must remain compatible.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Claim and Quarantine name the adopted message lifecycle transitions.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Relay mutations are explicit lifecycle operations invoked by an authorized orchestrator.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingEmptyCatchBlock', '', Justification = 'Export-ModuleMember intentionally fails when this library is dot-sourced rather than imported as a module.')]
param()

# relay-lib.ps1 - Permanent Core Relay Mechanics
# Handles message lifecycle (Publish, Claim, Complete, Quarantine) for team coordination.

function Get-ResolvedDirs {
    param([string]$InboxDir)
    
    $resolvedBase = $InboxDir
    if (-not $resolvedBase) {
        $resolvedBase = $PSScriptRoot
        if (-not $resolvedBase) {
            $resolvedBase = Get-Location
        }
    }
    
    return @{
        Base = $resolvedBase
        Tmp = Join-Path $resolvedBase ".tmp"
        Pending = Join-Path $resolvedBase "pending"
        Inflight = Join-Path $resolvedBase "inflight"
        Archive = Join-Path $resolvedBase "archive"
        Quarantine = Join-Path $resolvedBase "quarantine"
    }
}

function Initialize-Relay {
    param([string]$InboxDir = $null)
    $resolved = Get-ResolvedDirs -InboxDir $InboxDir
    $dirs = @($resolved.Tmp, $resolved.Pending, $resolved.Inflight, $resolved.Archive, $resolved.Quarantine)
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }
}

function New-Ulid {
    $alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    
    # 48-bit timestamp (milliseconds since Unix epoch)
    $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $timeChars = New-Object char[] 10
    $temp = $epoch
    for ($i = 9; $i -ge 0; $i--) {
        $timeChars[$i] = $alphabet[[int]($temp % 32)]
        $temp = [Math]::Floor($temp / 32)
    }
    
    # 80-bit randomness (16 base32 characters, 32^16 = 2^80)
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $randomBytes = New-Object byte[] 16
    $rng.GetBytes($randomBytes)
    
    $randChars = New-Object char[] 16
    for ($i = 0; $i -lt 16; $i++) {
        $randChars[$i] = $alphabet[[int]($randomBytes[$i] % 32)]
    }
    
    return (New-Object string (,$timeChars)) + (New-Object string (,$randChars))
}

function Test-MessageSchema {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [string]$ExpectedFrom = $null
    )
    $result = @{
        valid = $false
        forgedFrom = $false
        reason = ''
        message = $null
        identityTrust = 'refused' # from=coordination-only flag; never trust from as identity
        fromCoordinationOnly = $true
    }
    
    try {
        if (-not (Test-Path $Path)) {
            $result.reason = "File not found: $Path"
            return $result
        }
        $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        $m = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $result.reason = "malformed JSON: $($_.Exception.Message)"
        return $result
    }
    
    # Required schema fields for Phase 1
    $requiredFields = @('schemaVersion', 'id', 'thread', 'from', 'to', 'type', 'task', 'body', 'ts')
    foreach ($field in $requiredFields) {
        if ($null -eq $m.$field -or ($m.$field -is [string] -and [string]::IsNullOrWhiteSpace($m.$field))) {
            $result.reason = "missing or empty required field: $field"
            return $result
        }
    }
    
    # ULID format check (26 characters, base32 alphabet excluding I, L, O, U)
    if ($m.id -notmatch '^[0-9A-HJKMNP-TV-Zabcdefghjkmnp-tv-z]{26}$') {
        $result.reason = "invalid ULID format: $($m.id)"
        return $result
    }
    
    # Timestamp parsing verification
    try {
        [void][DateTimeOffset]::Parse($m.ts)
    } catch {
        $result.reason = "invalid timestamp format: $($m.ts)"
        return $result
    }
    
    # Flag forged sender mismatch (from is coordination-only, never trusted as identity)
    if ($ExpectedFrom -and $m.from -ne $ExpectedFrom) {
        $result.forgedFrom = $true
    }
    
    $result.valid = $true
    $result.message = $m
    return $result
}

function Publish-Message {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$Content,
        [string]$InboxDir = $null
    )
    Initialize-Relay -InboxDir $InboxDir
    $resolvedDirs = Get-ResolvedDirs -InboxDir $InboxDir
    
    $ulid = New-Ulid
    $tmpPath = Join-Path $resolvedDirs.Tmp "$ulid.json"
    $pendingPath = Join-Path $resolvedDirs.Pending "$ulid.json"
    
    $jsonContent = $Content
    if ($Content -isnot [string]) {
        $jsonContent = $Content | ConvertTo-Json -Depth 10 -Compress
    }
    
    # Write to staging area first to prevent partial reads
    [System.IO.File]::WriteAllText($tmpPath, $jsonContent, [System.Text.Encoding]::UTF8)
    
    # Atomic same-volume rename into pending/
    [System.IO.File]::Move($tmpPath, $pendingPath)
    
    return $ulid
}

function Claim-Message {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Ulid,
        [string]$InboxDir = $null,
        [string]$ExpectedFrom = $null,
        [switch]$SkipValidation
    )
    Initialize-Relay -InboxDir $InboxDir
    $resolvedDirs = Get-ResolvedDirs -InboxDir $InboxDir
    $pendingPath = Join-Path $resolvedDirs.Pending "$Ulid.json"
    $inflightPath = Join-Path $resolvedDirs.Inflight "$Ulid.json"
    
    if (-not (Test-Path $pendingPath)) {
        throw "Pending message not found: $pendingPath"
    }
    
    if (-not $SkipValidation) {
        $validation = Test-MessageSchema -Path $pendingPath -ExpectedFrom $ExpectedFrom
        if (-not $validation.valid) {
            # Quarantine malformed message immediately
            $quarantinePath = Join-Path $resolvedDirs.Quarantine "$Ulid.json"
            [System.IO.File]::Move($pendingPath, $quarantinePath)
            
            $reasonPath = Join-Path $resolvedDirs.Quarantine "$Ulid.reason"
            [System.IO.File]::WriteAllText($reasonPath, $validation.reason, [System.Text.Encoding]::UTF8)
            
            throw "Schema validation failed for pending message ${Ulid}: $($validation.reason)"
        }
    }
    
    # Atomic claim: rename pending/ -> inflight/
    [System.IO.File]::Move($pendingPath, $inflightPath)
}

function Complete-Message {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Ulid,
        [string]$InboxDir = $null
    )
    Initialize-Relay -InboxDir $InboxDir
    $resolvedDirs = Get-ResolvedDirs -InboxDir $InboxDir
    $inflightPath = Join-Path $resolvedDirs.Inflight "$Ulid.json"
    $archivePath = Join-Path $resolvedDirs.Archive "$Ulid.json"
    
    if (-not (Test-Path $inflightPath)) {
        throw "Inflight message not found: $inflightPath"
    }
    
    [System.IO.File]::Move($inflightPath, $archivePath)
}

function Quarantine-Message {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Ulid,
        [string]$InboxDir = $null,
        [string]$Reason = 'validation-failed'
    )
    Initialize-Relay -InboxDir $InboxDir
    $resolvedDirs = Get-ResolvedDirs -InboxDir $InboxDir
    $pendingPath = Join-Path $resolvedDirs.Pending "$Ulid.json"
    $inflightPath = Join-Path $resolvedDirs.Inflight "$Ulid.json"
    $quarantinePath = Join-Path $resolvedDirs.Quarantine "$Ulid.json"
    
    $src = $null
    if (Test-Path $inflightPath) {
        $src = $inflightPath
    } elseif (Test-Path $pendingPath) {
        $src = $pendingPath
    }
    
    if (-not $src) {
        throw "Message $Ulid not found in pending or inflight directories."
    }
    
    [System.IO.File]::Move($src, $quarantinePath)
    
    $reasonPath = Join-Path $resolvedDirs.Quarantine "$Ulid.reason"
    [System.IO.File]::WriteAllText($reasonPath, $Reason, [System.Text.Encoding]::UTF8)
}

function Get-InflightMessages {
    param([string]$InboxDir = $null)
    Initialize-Relay -InboxDir $InboxDir
    $resolvedDirs = Get-ResolvedDirs -InboxDir $InboxDir
    if (Test-Path $resolvedDirs.Inflight) {
        return (Get-ChildItem -Path $resolvedDirs.Inflight -Filter "*.json" | ForEach-Object {
            [PSCustomObject]@{
                Ulid = $_.BaseName
                Path = $_.FullName
                LastWriteTime = $_.LastWriteTime
            }
        })
    }
    return @()
}

# Export functions for module and script context
try {
    Export-ModuleMember -Function Initialize-Relay, New-Ulid, Publish-Message, Claim-Message, Complete-Message, Quarantine-Message, Get-InflightMessages, Test-MessageSchema, Get-ResolvedDirs
} catch {
    # Suppress error if dot-sourced as a standard script
}
