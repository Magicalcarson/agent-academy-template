[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root,

    [Parameter()]
    [string[]]$AdditionalForbiddenMarker = @()
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$violations = New-Object System.Collections.Generic.List[string]
$approvedExtensions = @('.md', '.ps1', '.json', '.txt')
$approvedRootExtensionlessPaths = @('LICENSE')
$workspaceDirectories = @('projects', 'inbox', 'outbox', 'meetings', 'vault')
$forwardSlash = [char]47
$backslash = [char]92

$allItems = Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Force |
    Where-Object {
        $_.FullName -notlike (Join-Path $resolvedRoot '.git\*') -and
        $_.FullName -ne (Join-Path $resolvedRoot '.git') -and
        $_.FullName -notlike (Join-Path $resolvedRoot '.agent-academy-backups\*') -and
        $_.FullName -ne (Join-Path $resolvedRoot '.agent-academy-backups') -and
        $_.FullName -notin @(
            (Join-Path $resolvedRoot 'governance\trainer.local.md')
            (Join-Path $resolvedRoot 'governance\assignments.local.md')
        )
    }

foreach ($item in $allItems) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $relativePath = $item.FullName.Substring($resolvedRoot.Length).TrimStart('\', '/')
        $violations.Add("reparse-point:$relativePath")
    }
}

$files = @($allItems | Where-Object { -not $_.PSIsContainer })
$allowlistPath = Join-Path $resolvedRoot 'manifests\release-allowlist.txt'
if (Test-Path -LiteralPath $allowlistPath) {
    $expectedPaths = @(
        Get-Content -LiteralPath $allowlistPath |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $actualPaths = @(
        $files |
            ForEach-Object {
                $_.FullName.Substring($resolvedRoot.Length).TrimStart('\', '/') -replace '\\', '/'
            }
    )

    foreach ($unexpectedPath in @($actualPaths | Where-Object { $expectedPaths -notcontains $_ })) {
        $violations.Add("not-allowlisted:$unexpectedPath")
    }

    foreach ($missingPath in @($expectedPaths | Where-Object { $actualPaths -notcontains $_ })) {
        $violations.Add("allowlisted-file-missing:$missingPath")
    }
}

foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($resolvedRoot.Length).TrimStart('\', '/')
    $normalizedRelativePath = $relativePath -replace '\\', '/'
    $extension = [IO.Path]::GetExtension($file.Name).ToLowerInvariant()

    if (
        $file.Name -notin @('.gitignore', '.gitattributes', '.graphify_version') -and
        $approvedRootExtensionlessPaths -notcontains $normalizedRelativePath -and
        $approvedExtensions -notcontains $extension
    ) {
        $violations.Add("unapproved-file-type:$normalizedRelativePath")
        continue
    }

    foreach ($workspaceDirectory in $workspaceDirectories) {
        if (
            $normalizedRelativePath.StartsWith("$workspaceDirectory/", [StringComparison]::OrdinalIgnoreCase) -and
            $normalizedRelativePath -ne "$workspaceDirectory/README.md"
        ) {
            $violations.Add("nonblank-workspace:$normalizedRelativePath")
        }
    }

    try {
        $content = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    }
    catch {
        $violations.Add("unreadable-text:$normalizedRelativePath")
        continue
    }

    $builtInPatterns = @(
        '(?i)[A-Z]:\x5cUsers\x5c[^\x5c\r\n]+'
        '(?i)(?:/Users|/home)/[^/\r\n]+'
        ('(?i)file:' + $forwardSlash + $forwardSlash)
        (
            '(?i)' +
            [regex]::Escape("$backslash$backslash") +
            '[A-Za-z0-9._-]+' +
            [regex]::Escape("$backslash")
        )
        '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
        '(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|authorization)\s*[:=]\s*[''"]?[^\s''"]+'
        '\bsk-[A-Za-z0-9_-]{16,}\b'
        '\bgh[pousr]_[A-Za-z0-9]{20,}\b'
        '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
    )

    foreach ($pattern in $builtInPatterns) {
        if ([regex]::IsMatch($content, $pattern)) {
            $violations.Add("content-pattern:$normalizedRelativePath")
            break
        }
    }

    foreach ($marker in $AdditionalForbiddenMarker) {
        if (
            -not [string]::IsNullOrWhiteSpace($marker) -and
            $content.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0
        ) {
            $violations.Add("forbidden-marker:$normalizedRelativePath")
            break
        }
    }
}

if ($violations.Count -gt 0) {
    $summary = ($violations | Sort-Object -Unique) -join [Environment]::NewLine
    throw "Privacy gate failed with $($violations.Count) finding(s):$([Environment]::NewLine)$summary"
}

[pscustomobject]@{
    Status = 'PASS'
    Root = $resolvedRoot
    FilesScanned = $files.Count
}
