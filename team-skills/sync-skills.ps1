[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Justification = 'This interactive installer intentionally uses host-coloured progress; its machine-readable plan remains available as returned objects.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseSingularNouns',
    '',
    Justification = 'Preserve the adopted installer internal function name to avoid changing its established implementation surface.'
)]
param(
    [switch]$DryRun,
    [switch]$Apply,
    [string]$Skill,
    [string]$Surface
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($DryRun.IsPresent -and $Apply.IsPresent) {
    [Console]::Error.WriteLine('ERROR: -DryRun and -Apply are mutually exclusive.')
    exit 1
}

# Dry run is the effective default. Only an explicit -Apply permits mutations.
$IsDryRun = -not $Apply.IsPresent
$StoreRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$ManifestPath = Join-Path $StoreRoot 'skills-manifest.json'
$KnownSurfaceNames = @('claude', 'codex', 'kimi', 'antigravity')
$Results = @()
$Errors = @()
$SurfaceStates = @{}
$SurfaceDirectoriesPlanned = 0
$SurfaceDirectoriesCreated = 0
$script:VisualBasicLoaded = $false

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-RequiredPropertyValue {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        throw "$Context is missing required property '$Name'."
    }

    return $property.Value
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Length -gt $pathRoot.Length) {
        $fullPath = $fullPath.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
    }

    return $fullPath
}

function Test-PathIsUnder {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $normalizedPath = Get-NormalizedFullPath -Path $Path
    $normalizedRoot = Get-NormalizedFullPath -Path $Root
    $prefix = $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar
    return $normalizedPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-PathIsUnderAnyRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Roots
    )

    foreach ($root in $Roots) {
        if (Test-PathIsUnder -Path $Path -Root $root) {
            return $true
        }
    }

    return $false
}

function Test-SafeLeafName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    if (($Name -eq '.') -or ($Name -eq '..')) {
        return $false
    }
    # Windows aliases trailing dots/spaces to the unsuffixed directory name.
    if ($Name.EndsWith('.', [System.StringComparison]::Ordinal) -or
        $Name.EndsWith(' ', [System.StringComparison]::Ordinal)) {
        return $false
    }
    if ([System.IO.Path]::IsPathRooted($Name)) {
        return $false
    }
    if ($Name.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        return $false
    }
    if (($Name.IndexOf([System.IO.Path]::DirectorySeparatorChar) -ge 0) -or
        ($Name.IndexOf([System.IO.Path]::AltDirectorySeparatorChar) -ge 0)) {
        return $false
    }

    return $true
}

function Get-ExistingItem {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        return Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
    catch {
        if ($_.CategoryInfo.Category -eq [System.Management.Automation.ErrorCategory]::ObjectNotFound) {
            return $null
        }
        throw
    }
}

function Test-IsReparsePoint {
    param([Parameter(Mandatory = $true)]$Item)

    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-ReparsePointInPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $normalizedPath = Get-NormalizedFullPath -Path $Path
    $normalizedRoot = Get-NormalizedFullPath -Path $Root
    if (-not (Test-PathIsUnder -Path $normalizedPath -Root $normalizedRoot)) {
        throw "Path '$normalizedPath' is outside ancestry root '$normalizedRoot'."
    }

    $rootItem = Get-ExistingItem -Path $normalizedRoot
    if (($null -ne $rootItem) -and (Test-IsReparsePoint -Item $rootItem)) {
        return $normalizedRoot
    }

    $relativePath = $normalizedPath.Substring($normalizedRoot.Length + 1)
    $components = @($relativePath.Split(@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ), [System.StringSplitOptions]::RemoveEmptyEntries))
    $currentPath = $normalizedRoot
    foreach ($component in $components) {
        $currentPath = Join-Path $currentPath $component
        $item = Get-ExistingItem -Path $currentPath
        if ($null -eq $item) {
            # Descendants cannot exist below the first missing component.
            break
        }
        if (Test-IsReparsePoint -Item $item) {
            return (Get-NormalizedFullPath -Path $currentPath)
        }
    }

    return $null
}

function Get-RelativeChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $normalizedPath = Get-NormalizedFullPath -Path $Path
    $normalizedRoot = Get-NormalizedFullPath -Path $Root
    if (-not (Test-PathIsUnder -Path $normalizedPath -Root $normalizedRoot)) {
        throw "Path '$normalizedPath' is outside root '$normalizedRoot'."
    }

    return $normalizedPath.Substring($normalizedRoot.Length + 1)
}

function Get-FileMap {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$ExcludeVariants
    )

    $map = @{}
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction Stop)
    foreach ($file in $files) {
        $relativePath = Get-RelativeChildPath -Path $file.FullName -Root $Root
        $variantPrefix = '.variants' + [System.IO.Path]::DirectorySeparatorChar
        if ($ExcludeVariants.IsPresent -and
            (($relativePath -ieq '.variants') -or
             $relativePath.StartsWith($variantPrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
            continue
        }

        $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
        $map[$relativePath] = [pscustomobject]@{
            Hash = $hash.Hash
            Bytes = [long]$file.Length
            Source = $file.FullName
        }
    }

    return $map
}

function Get-ExpectedMirrorMap {
    param(
        [Parameter(Mandatory = $true)][string]$Canonical,
        [string]$VariantPath
    )

    $map = Get-FileMap -Root $Canonical -ExcludeVariants
    if (-not [string]::IsNullOrWhiteSpace($VariantPath)) {
        $overlayMap = Get-FileMap -Root $VariantPath
        foreach ($relativePath in $overlayMap.Keys) {
            $map[$relativePath] = $overlayMap[$relativePath]
        }
    }

    return $map
}

function Test-FileMapsEqual {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Expected,
        [Parameter(Mandatory = $true)][hashtable]$Actual
    )

    if ($Expected.Count -ne $Actual.Count) {
        return $false
    }

    foreach ($relativePath in $Expected.Keys) {
        if (-not $Actual.ContainsKey($relativePath)) {
            return $false
        }
        if ($Expected[$relativePath].Hash -ne $Actual[$relativePath].Hash) {
            return $false
        }
    }

    return $true
}

function Resolve-JunctionTargetPath {
    param([Parameter(Mandatory = $true)]$Item)

    $targetProperty = $Item.PSObject.Properties['Target']
    if ($null -eq $targetProperty) {
        return $null
    }

    $targetValues = @($targetProperty.Value | Where-Object { $null -ne $_ })
    if ($targetValues.Count -ne 1) {
        return $null
    }

    $targetPath = [string]$targetValues[0]
    if ($targetPath.StartsWith('\??\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) {
        $targetPath = '\\' + $targetPath.Substring(8)
    }
    elseif ($targetPath.StartsWith('\??\', [System.StringComparison]::OrdinalIgnoreCase)) {
        $targetPath = $targetPath.Substring(4)
    }
    elseif ($targetPath.StartsWith('\\?\', [System.StringComparison]::OrdinalIgnoreCase)) {
        $targetPath = $targetPath.Substring(4)
    }

    if (-not [System.IO.Path]::IsPathRooted($targetPath)) {
        $targetPath = Join-Path $Item.Parent.FullName $targetPath
    }

    return Get-NormalizedFullPath -Path $targetPath
}

function Test-JunctionDesired {
    param(
        $Item,
        [Parameter(Mandatory = $true)][string]$Canonical
    )

    if ($null -eq $Item) {
        return $false
    }
    if (-not $Item.PSIsContainer) {
        return $false
    }
    if (-not (Test-IsReparsePoint -Item $Item)) {
        return $false
    }

    $linkTypeProperty = $Item.PSObject.Properties['LinkType']
    if (($null -eq $linkTypeProperty) -or ([string]$linkTypeProperty.Value -ine 'Junction')) {
        return $false
    }

    $resolvedTarget = Resolve-JunctionTargetPath -Item $Item
    if ($null -eq $resolvedTarget) {
        return $false
    }

    return $resolvedTarget.Equals(
        (Get-NormalizedFullPath -Path $Canonical),
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Test-MirrorDesired {
    param(
        $Item,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][hashtable]$ExpectedMap
    )

    if ($null -eq $Item) {
        return $false
    }
    if (-not $Item.PSIsContainer) {
        return $false
    }
    if (Test-IsReparsePoint -Item $Item) {
        return $false
    }

    $actualMap = Get-FileMap -Root $Target
    return Test-FileMapsEqual -Expected $ExpectedMap -Actual $actualMap
}

function Get-TreeFileSummary {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$ExcludeVariants
    )

    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction Stop)
    if ($ExcludeVariants.IsPresent) {
        $filtered = @()
        foreach ($file in $files) {
            $relativePath = Get-RelativeChildPath -Path $file.FullName -Root $Root
            $variantPrefix = '.variants' + [System.IO.Path]::DirectorySeparatorChar
            if (($relativePath -ieq '.variants') -or
                $relativePath.StartsWith($variantPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            $filtered += $file
        }
        $files = $filtered
    }

    $totalBytes = [long]0
    foreach ($file in $files) {
        $totalBytes += [long]$file.Length
    }

    return [pscustomobject]@{
        FileCount = $files.Count
        TotalBytes = $totalBytes
    }
}

function Get-BackupSummary {
    param([Parameter(Mandatory = $true)][string]$Target)

    $targetItem = Get-ExistingItem -Path $Target
    if ($null -eq $targetItem) {
        throw "Backup target disappeared before it could be summarized: $Target"
    }
    if (Test-IsReparsePoint -Item $targetItem) {
        # SAFETY: summarize the junction/link itself; never traverse an unexpected external target.
        return [pscustomobject]@{
            ItemCount = 1
            TotalBytes = [long]0
        }
    }

    $items = @(Get-ChildItem -LiteralPath $Target -Recurse -Force -ErrorAction Stop)
    $totalBytes = [long]0
    foreach ($item in $items) {
        if (-not $item.PSIsContainer) {
            $totalBytes += [long]$item.Length
        }
    }

    return [pscustomobject]@{
        ItemCount = $items.Count
        TotalBytes = $totalBytes
    }
}

function Send-DirectoryToRecycleBin {
    param([Parameter(Mandatory = $true)][string]$Target)

    if (-not $script:VisualBasicLoaded) {
        Add-Type -AssemblyName Microsoft.VisualBasic
        $script:VisualBasicLoaded = $true
    }

    # SAFETY: replacement is recoverable; this deliberately uses the Recycle Bin.
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
        $Target,
        'OnlyErrorDialogs',
        'SendToRecycleBin'
    )
}

function Copy-MirrorContent {
    param(
        [Parameter(Mandatory = $true)][string]$Canonical,
        [Parameter(Mandatory = $true)][string]$Target,
        [string]$VariantPath
    )

    New-Item -ItemType Directory -Path $Target -Force | Out-Null

    # SAFETY: .variants is metadata, never part of a base mirror.
    $baseItems = @(Get-ChildItem -LiteralPath $Canonical -Force -ErrorAction Stop |
        Where-Object { $_.Name -ine '.variants' })
    foreach ($item in $baseItems) {
        Copy-Item -LiteralPath $item.FullName -Destination $Target -Recurse -Force
    }

    if (-not [string]::IsNullOrWhiteSpace($VariantPath)) {
        $variantMap = Get-FileMap -Root $VariantPath
        foreach ($relativePath in $variantMap.Keys) {
            $destinationPath = Join-Path $Target $relativePath
            $destinationParent = Split-Path -Parent $destinationPath
            if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
                New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
            }
            # Variant files intentionally replace the exact same-relative-path base files.
            Copy-Item -LiteralPath $variantMap[$relativePath].Source -Destination $destinationPath -Force
        }
    }
}

function Add-Result {
    param(
        [Parameter(Mandatory = $true)][string]$SkillName,
        [Parameter(Mandatory = $true)][string]$SurfaceName,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$Action
    )

    $script:Results += [pscustomobject]@{
        skill = $SkillName
        surface = $SurfaceName
        mode = $Mode
        action = $Action
    }
}

function Add-OperationError {
    param(
        [Parameter(Mandatory = $true)][string]$SkillName,
        [Parameter(Mandatory = $true)][string]$SurfaceName,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $script:Errors += "[$SkillName/$SurfaceName] $Message"
    [Console]::Error.WriteLine("ERROR [$SkillName/$SurfaceName]: $Message")
}

function Get-LeaveUntouchedNames {
    param(
        $LeaveUntouched,
        [Parameter(Mandatory = $true)][string]$SurfaceName
    )

    if ($null -eq $LeaveUntouched) {
        return @()
    }

    $property = $LeaveUntouched.PSObject.Properties[$SurfaceName]
    if ($null -eq $property) {
        return @()
    }

    return @($property.Value)
}

function Get-VariantRelativePath {
    param(
        $Variants,
        [Parameter(Mandatory = $true)][string]$SurfaceName
    )

    if ($null -eq $Variants) {
        return $null
    }

    $property = $Variants.PSObject.Properties[$SurfaceName]
    if ($null -eq $property) {
        return $null
    }

    return [string]$property.Value
}

function Get-ManifestSkillEntryByName {
    param(
        [Parameter(Mandatory = $true)][object[]]$Skills,
        [Parameter(Mandatory = $true)][string]$Name
    )

    foreach ($skillEntry in $Skills) {
        $entryName = [string](Get-RequiredPropertyValue -InputObject $skillEntry -Name 'name' -Context 'Skill entry')
        if ($entryName.Equals($Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $skillEntry
        }
    }

    return $null
}

if ($IsDryRun) {
    Write-Host '=== DRY RUN: PLAN ONLY - NO FILESYSTEM CHANGES WILL BE MADE ===' -ForegroundColor Yellow
}
else {
    Write-Host '=== APPLY MODE: FILESYSTEM CHANGES ENABLED ===' -ForegroundColor Cyan
}

try {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest not found: $ManifestPath"
    }
    if ([string]::IsNullOrWhiteSpace([string]$HOME)) {
        throw '$HOME is empty; surface directories cannot be resolved.'
    }

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $homeRelativeSurfaces = Get-RequiredPropertyValue -InputObject $manifest -Name 'homeRelativeSurfaces' -Context 'Manifest'
    if ($homeRelativeSurfaces -ne $true) {
        throw 'Manifest homeRelativeSurfaces must be true.'
    }

    $manifestSurfaces = Get-RequiredPropertyValue -InputObject $manifest -Name 'surfaces' -Context 'Manifest'
    $manifestSurfaceProperties = @($manifestSurfaces.PSObject.Properties)
    if ($manifestSurfaceProperties.Count -ne $KnownSurfaceNames.Count) {
        throw 'Manifest must define exactly the four known surfaces: claude, codex, kimi, antigravity.'
    }
    foreach ($knownSurfaceName in $KnownSurfaceNames) {
        if ($null -eq $manifestSurfaces.PSObject.Properties[$knownSurfaceName]) {
            throw "Manifest is missing known surface '$knownSurfaceName'."
        }
    }
    foreach ($surfaceProperty in $manifestSurfaceProperties) {
        if ($KnownSurfaceNames -notcontains $surfaceProperty.Name) {
            throw "Manifest contains unknown surface '$($surfaceProperty.Name)'."
        }
    }

    $normalizedHome = Get-NormalizedFullPath -Path ([string]$HOME)
    $surfaceRoots = @{}
    foreach ($knownSurfaceName in $KnownSurfaceNames) {
        $relativeSurfacePath = [string]$manifestSurfaces.PSObject.Properties[$knownSurfaceName].Value
        if ([string]::IsNullOrWhiteSpace($relativeSurfacePath) -or
            [System.IO.Path]::IsPathRooted($relativeSurfacePath)) {
            throw "Surface '$knownSurfaceName' must have a non-empty home-relative path."
        }

        $surfaceRoot = Get-NormalizedFullPath -Path (Join-Path $normalizedHome $relativeSurfacePath)
        if (-not (Test-PathIsUnder -Path $surfaceRoot -Root $normalizedHome)) {
            throw "Surface '$knownSurfaceName' resolves outside `$HOME: $surfaceRoot"
        }
        $surfaceRoots[$knownSurfaceName] = $surfaceRoot
    }
    if ((@($surfaceRoots.Values | Sort-Object -Unique)).Count -ne $KnownSurfaceNames.Count) {
        throw 'Known surface directories must resolve to four distinct paths.'
    }

    if (-not [string]::IsNullOrWhiteSpace($Surface)) {
        if ($KnownSurfaceNames -notcontains $Surface) {
            throw "Unknown -Surface '$Surface'. Expected one of: $($KnownSurfaceNames -join ', ')."
        }
    }

    $skills = @(Get-RequiredPropertyValue -InputObject $manifest -Name 'skills' -Context 'Manifest')
    if ($skills.Count -eq 0) {
        throw 'Manifest skills list is empty.'
    }

    $skillNames = @()
    foreach ($skillEntry in $skills) {
        $skillNames += [string](Get-RequiredPropertyValue -InputObject $skillEntry -Name 'name' -Context 'Skill entry')
    }
    if ((@($skillNames | Sort-Object -Unique)).Count -ne $skillNames.Count) {
        throw 'Manifest contains duplicate skill names.'
    }
    if (-not [string]::IsNullOrWhiteSpace($Skill)) {
        if ($skillNames -notcontains $Skill) {
            throw "Unknown -Skill '$Skill'."
        }
    }

    $leaveUntouched = Get-ObjectPropertyValue -InputObject $manifest -Name 'leaveUntouched'
    $perSurfaceMode = Get-ObjectPropertyValue -InputObject $manifest -Name 'perSurfaceMode'
    if ($null -ne $perSurfaceMode) {
        foreach ($modeOverrideProperty in @($perSurfaceMode.PSObject.Properties)) {
            if ($KnownSurfaceNames -notcontains $modeOverrideProperty.Name) {
                throw "Manifest perSurfaceMode contains unknown surface '$($modeOverrideProperty.Name)'."
            }

            $modeOverride = [string]$modeOverrideProperty.Value
            if (($modeOverride -ine 'junction') -and ($modeOverride -ine 'mirror')) {
                throw "Manifest perSurfaceMode for surface '$($modeOverrideProperty.Name)' must be 'junction' or 'mirror', not '$modeOverride'."
            }
        }
    }

    foreach ($skillEntry in $skills) {
        $skillName = [string](Get-RequiredPropertyValue -InputObject $skillEntry -Name 'name' -Context 'Skill entry')
        if ((-not [string]::IsNullOrWhiteSpace($Skill)) -and ($skillName -ine $Skill)) {
            continue
        }

        $mode = [string](Get-RequiredPropertyValue -InputObject $skillEntry -Name 'mode' -Context "Skill '$skillName'")
        $skillSurfaces = @(Get-RequiredPropertyValue -InputObject $skillEntry -Name 'surfaces' -Context "Skill '$skillName'")
        $variants = Get-ObjectPropertyValue -InputObject $skillEntry -Name 'variants'

        foreach ($surfaceNameValue in $skillSurfaces) {
            $surfaceName = [string]$surfaceNameValue
            if ((-not [string]::IsNullOrWhiteSpace($Surface)) -and ($surfaceName -ine $Surface)) {
                continue
            }

            $effectiveMode = $mode
            if ($null -ne $perSurfaceMode) {
                $modeOverrideProperty = $perSurfaceMode.PSObject.Properties[$surfaceName]
                if ($null -ne $modeOverrideProperty) {
                    $effectiveMode = [string]$modeOverrideProperty.Value
                }
            }

            $backedUp = $false
            $relinked = $false
            try {
                if (-not (Test-SafeLeafName -Name $skillName)) {
                    throw "Refused unsafe skill directory name '$skillName'."
                }
                if ($KnownSurfaceNames -notcontains $surfaceName) {
                    Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action 'skipped(unknown-surface)'
                    throw "Refused unknown surface '$surfaceName'."
                }
                if (($mode -ine 'junction') -and ($mode -ine 'mirror')) {
                    Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $mode -Action 'skipped(unsupported-mode)'
                    throw "Refused unsupported mode '$mode'."
                }

                $untouchedNames = @(Get-LeaveUntouchedNames -LeaveUntouched $leaveUntouched -SurfaceName $surfaceName)
                if ($untouchedNames -contains $skillName) {
                    Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action 'skipped(leaveUntouched)'
                    throw "Refused leaveUntouched name '$skillName' on surface '$surfaceName'."
                }

                $surfaceRoot = [string]$surfaceRoots[$surfaceName]
                $canonical = Get-NormalizedFullPath -Path (Join-Path $StoreRoot $skillName)
                $target = Get-NormalizedFullPath -Path (Join-Path $surfaceRoot $skillName)

                foreach ($untouchedNameValue in $untouchedNames) {
                    $untouchedName = [string]$untouchedNameValue
                    if (-not (Test-SafeLeafName -Name $untouchedName)) {
                        throw "Manifest leaveUntouched contains unsafe name '$untouchedName' for surface '$surfaceName'."
                    }
                    $protectedTarget = Get-NormalizedFullPath -Path (Join-Path $surfaceRoot $untouchedName)
                    if ($target.Equals($protectedTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
                        Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action 'skipped(leaveUntouched)'
                        throw "Refused normalized leaveUntouched target '$protectedTarget'."
                    }
                }

                # SAFETY: both source and destination must remain inside their declared roots.
                if (-not (Test-PathIsUnder -Path $canonical -Root $StoreRoot)) {
                    Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action 'skipped(unsafe-canonical)'
                    throw "Refused canonical path outside store root: $canonical"
                }
                if (-not (Test-PathIsUnderAnyRoot -Path $target -Roots @($surfaceRoots.Values))) {
                    Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action 'skipped(unsafe-target)'
                    throw "Refused target outside known surface directories: $target"
                }
                if (-not (Test-PathIsUnder -Path $target -Root $surfaceRoot)) {
                    Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action 'skipped(wrong-surface-root)'
                    throw "Refused target outside selected surface '$surfaceName': $target"
                }
                if (-not (Test-Path -LiteralPath $canonical -PathType Container)) {
                    Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action 'skipped(canonical-missing)'
                    throw "Refused missing canonical directory: $canonical"
                }

                $variantRelativePath = Get-VariantRelativePath -Variants $variants -SurfaceName $surfaceName
                $variantPath = $null
                if (-not [string]::IsNullOrWhiteSpace($variantRelativePath)) {
                    if ([System.IO.Path]::IsPathRooted($variantRelativePath)) {
                        Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action 'skipped(unsafe-variant)'
                        throw "Refused rooted variant path '$variantRelativePath'."
                    }
                    $variantPath = Get-NormalizedFullPath -Path (Join-Path $canonical $variantRelativePath)
                    if (-not (Test-PathIsUnder -Path $variantPath -Root $canonical)) {
                        Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action 'skipped(unsafe-variant)'
                        throw "Refused variant outside canonical skill directory: $variantPath"
                    }
                    if (-not (Test-Path -LiteralPath $variantPath -PathType Container)) {
                        Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action 'skipped(variant-missing)'
                        throw "Refused missing variant directory: $variantPath"
                    }
                }

                $surfaceReparsePoint = Get-ReparsePointInPath -Path $surfaceRoot -Root $normalizedHome
                if ($null -ne $surfaceReparsePoint) {
                    Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action 'skipped(surface-reparse-point)'
                    throw "Refused surface directory with reparse-point ancestry: $surfaceReparsePoint"
                }

                if (-not $SurfaceStates.ContainsKey($surfaceName)) {
                    $surfaceItem = Get-ExistingItem -Path $surfaceRoot
                    if ($null -eq $surfaceItem) {
                        if ($IsDryRun) {
                            Write-Host "CREATE SURFACE DIR (would): '$surfaceRoot'"
                            $SurfaceDirectoriesPlanned++
                        }
                        else {
                            New-Item -ItemType Directory -Path $surfaceRoot -Force | Out-Null
                            Write-Host "CREATE SURFACE DIR: '$surfaceRoot'"
                            $SurfaceDirectoriesCreated++
                        }
                        $SurfaceStates[$surfaceName] = 'ready'
                    }
                    elseif (-not $surfaceItem.PSIsContainer) {
                        $SurfaceStates[$surfaceName] = 'not-directory'
                    }
                    else {
                        $SurfaceStates[$surfaceName] = 'ready'
                    }
                }
                if ($SurfaceStates[$surfaceName] -ne 'ready') {
                    Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action 'skipped(surface-not-directory)'
                    throw "Refused surface path that is not a directory: $surfaceRoot"
                }

                $targetItem = Get-ExistingItem -Path $target
                if (($null -ne $targetItem) -and (-not $targetItem.PSIsContainer)) {
                    Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action 'skipped(target-not-directory)'
                    throw "Refused target that is not a directory: $target"
                }

                $expectedMap = $null
                $isDesired = $false
                if ($effectiveMode -ieq 'junction') {
                    $isDesired = Test-JunctionDesired -Item $targetItem -Canonical $canonical
                }
                else {
                    $expectedMap = Get-ExpectedMirrorMap -Canonical $canonical -VariantPath $variantPath
                    $isDesired = Test-MirrorDesired -Item $targetItem -Target $target -ExpectedMap $expectedMap
                }

                if ($isDesired) {
                    Write-Host "IN SYNC: skill='$skillName' surface='$surfaceName' target='$target'"
                    Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action 'in-sync'
                    continue
                }

                $baseAction = 'created-junction'
                if ($effectiveMode -ieq 'mirror') {
                    if ($null -ne $variantPath) {
                        $baseAction = 'mirrored+variant'
                    }
                    else {
                        $baseAction = 'mirrored'
                    }
                }

                if ($null -ne $targetItem) {
                    if (Test-IsReparsePoint -Item $targetItem) {
                        if ($IsDryRun) {
                            Write-Host "REMOVE JUNCTION/LINK ONLY (would): '$target' [non-recursive; no Recycle Bin]"
                        }
                        else {
                            Write-Host "REMOVE JUNCTION/LINK ONLY: '$target' [non-recursive; no Recycle Bin]"
                            # SAFETY: never give a reparse point to a recursive Recycle-Bin API.
                            [System.IO.Directory]::Delete($target, $false)
                            if ($null -ne (Get-ExistingItem -Path $target)) {
                                throw "Link-only removal did not remove the original target: $target"
                            }
                            if (-not (Test-Path -LiteralPath $canonical -PathType Container)) {
                                throw "Canonical directory disappeared after link-only removal: $canonical"
                            }
                        }
                        $relinked = $true
                    }
                    else {
                        $backupSummary = Get-BackupSummary -Target $target
                        if ($IsDryRun) {
                            Write-Host ("BACKUP TO RECYCLE BIN (would): '{0}' [items={1}; bytes={2}]" -f
                                $target, $backupSummary.ItemCount, $backupSummary.TotalBytes)
                        }
                        else {
                            Write-Host ("BACKUP TO RECYCLE BIN: '{0}' [items={1}; bytes={2}]" -f
                                $target, $backupSummary.ItemCount, $backupSummary.TotalBytes)
                            # SAFETY: backup completes before any junction/copy realization starts.
                            Send-DirectoryToRecycleBin -Target $target
                            if ($null -ne (Get-ExistingItem -Path $target)) {
                                throw "Recycle Bin backup did not remove the original target: $target"
                            }
                        }
                        $backedUp = $true
                    }
                }

                if ($effectiveMode -ieq 'junction') {
                    if ($IsDryRun) {
                        Write-Host "CREATE JUNCTION (would): '$target' -> '$canonical'"
                    }
                    else {
                        New-Item -ItemType Junction -Path $target -Target $canonical | Out-Null
                        Write-Host "CREATE JUNCTION: '$target' -> '$canonical'"
                        $createdItem = Get-ExistingItem -Path $target
                        if (-not (Test-JunctionDesired -Item $createdItem -Canonical $canonical)) {
                            throw "Junction verification failed: $target"
                        }
                    }
                }
                else {
                    $baseSummary = Get-TreeFileSummary -Root $canonical -ExcludeVariants
                    if ($IsDryRun) {
                        Write-Host ("COPY BASE (would): '{0}' -> '{1}' [recursive; force; excludes '{2}'; files={3}; bytes={4}]" -f
                            $canonical, $target, (Join-Path $canonical '.variants'),
                            $baseSummary.FileCount, $baseSummary.TotalBytes)
                    }
                    else {
                        Write-Host ("COPY BASE: '{0}' -> '{1}' [recursive; force; excludes '{2}'; files={3}; bytes={4}]" -f
                            $canonical, $target, (Join-Path $canonical '.variants'),
                            $baseSummary.FileCount, $baseSummary.TotalBytes)
                    }

                    if ($null -ne $variantPath) {
                        $variantSummary = Get-TreeFileSummary -Root $variantPath
                        if ($IsDryRun) {
                            Write-Host ("COPY VARIANT OVERLAY (would): '{0}' -> '{1}' [recursive; force; replace; files={2}; bytes={3}]" -f
                                $variantPath, $target, $variantSummary.FileCount, $variantSummary.TotalBytes)
                        }
                        else {
                            Write-Host ("COPY VARIANT OVERLAY: '{0}' -> '{1}' [recursive; force; replace; files={2}; bytes={3}]" -f
                                $variantPath, $target, $variantSummary.FileCount, $variantSummary.TotalBytes)
                        }
                    }

                    if (-not $IsDryRun) {
                        Copy-MirrorContent -Canonical $canonical -Target $target -VariantPath $variantPath
                        $mirroredItem = Get-ExistingItem -Path $target
                        if (-not (Test-MirrorDesired -Item $mirroredItem -Target $target -ExpectedMap $expectedMap)) {
                            throw "Mirror verification failed: $target"
                        }
                    }
                }

                $action = $baseAction
                if ($backedUp) {
                    $action = 'backed-up-then-' + $baseAction
                }
                elseif ($relinked) {
                    $action = 'relinked-' + $baseAction
                }
                Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action $action
            }
            catch {
                $alreadyRecorded = @($Results | Where-Object {
                    ($_.skill -ieq $skillName) -and
                    ($_.surface -ieq $surfaceName) -and
                    $_.action.StartsWith('skipped(', [System.StringComparison]::OrdinalIgnoreCase)
                }).Count -gt 0

                if (-not $alreadyRecorded) {
                    $failureAction = 'skipped(error)'
                    if ($backedUp -and (-not $IsDryRun)) {
                        $failureAction = 'backed-up-then-skipped(error)'
                    }
                    elseif ($relinked -and (-not $IsDryRun)) {
                        $failureAction = 'relinked-skipped(error)'
                    }
                    Add-Result -SkillName $skillName -SurfaceName $surfaceName -Mode $effectiveMode -Action $failureAction
                }
                Add-OperationError -SkillName $skillName -SurfaceName $surfaceName -Message $_.Exception.Message
            }
        }
    }

    # Reconcile managed surface entries after provisioning. A managed entry is
    # removable only when its name is in the manifest but this surface is not.
    foreach ($gcSurfaceName in $KnownSurfaceNames) {
        if ((-not [string]::IsNullOrWhiteSpace($Surface)) -and ($gcSurfaceName -ine $Surface)) {
            continue
        }

        $gcSurfaceRoot = [string]$surfaceRoots[$gcSurfaceName]
        try {
            if (-not (Test-PathIsUnder -Path $gcSurfaceRoot -Root $normalizedHome)) {
                throw "Refused GC surface outside `$HOME: $gcSurfaceRoot"
            }

            $gcSurfaceItem = Get-ExistingItem -Path $gcSurfaceRoot
            if ($null -eq $gcSurfaceItem) {
                continue
            }
            if (-not $gcSurfaceItem.PSIsContainer) {
                throw "Refused GC surface path that is not a directory: $gcSurfaceRoot"
            }

            $gcSurfaceReparsePoint = Get-ReparsePointInPath -Path $gcSurfaceRoot -Root $normalizedHome
            if ($null -ne $gcSurfaceReparsePoint) {
                throw "Refused GC surface directory with reparse-point ancestry: $gcSurfaceReparsePoint"
            }

            $gcUntouchedNames = @(Get-LeaveUntouchedNames -LeaveUntouched $leaveUntouched -SurfaceName $gcSurfaceName)
            foreach ($gcUntouchedNameValue in $gcUntouchedNames) {
                $gcUntouchedName = [string]$gcUntouchedNameValue
                if (-not (Test-SafeLeafName -Name $gcUntouchedName)) {
                    throw "Manifest leaveUntouched contains unsafe name '$gcUntouchedName' for surface '$gcSurfaceName'."
                }
            }

            $gcChildren = @(Get-ChildItem -LiteralPath $gcSurfaceRoot -Directory -Force -ErrorAction Stop)
            foreach ($gcChild in $gcChildren) {
                # SAFETY: protected and unknown/user-authored directories are never GC candidates.
                if ($gcUntouchedNames -contains $gcChild.Name) {
                    continue
                }

                $gcSkillEntry = Get-ManifestSkillEntryByName -Skills $skills -Name $gcChild.Name
                if ($null -eq $gcSkillEntry) {
                    continue
                }

                $gcSkillName = [string](Get-RequiredPropertyValue -InputObject $gcSkillEntry -Name 'name' -Context 'Skill entry')
                if ((-not [string]::IsNullOrWhiteSpace($Skill)) -and ($gcSkillName -ine $Skill)) {
                    continue
                }

                $gcDesiredSurfaces = @(Get-RequiredPropertyValue -InputObject $gcSkillEntry -Name 'surfaces' -Context "Skill '$gcSkillName'")
                if ($gcDesiredSurfaces -contains $gcSurfaceName) {
                    continue
                }

                $gcMode = [string](Get-RequiredPropertyValue -InputObject $gcSkillEntry -Name 'mode' -Context "Skill '$gcSkillName'")
                if ($null -ne $perSurfaceMode) {
                    $gcModeOverrideProperty = $perSurfaceMode.PSObject.Properties[$gcSurfaceName]
                    if ($null -ne $gcModeOverrideProperty) {
                        $gcMode = [string]$gcModeOverrideProperty.Value
                    }
                }

                $gcMutated = $false
                try {
                    if (-not (Test-SafeLeafName -Name $gcChild.Name)) {
                        throw "Refused unsafe GC child directory name '$($gcChild.Name)'."
                    }
                    if (-not (Test-SafeLeafName -Name $gcSkillName)) {
                        throw "Refused unsafe manifest skill directory name '$gcSkillName'."
                    }

                    $gcTarget = Get-NormalizedFullPath -Path $gcChild.FullName
                    if (-not (Test-PathIsUnder -Path $gcTarget -Root $gcSurfaceRoot)) {
                        throw "Refused GC target outside selected surface '$gcSurfaceName': $gcTarget"
                    }

                    $gcRelativePath = Get-RelativeChildPath -Path $gcTarget -Root $gcSurfaceRoot
                    if ((-not (Test-SafeLeafName -Name $gcRelativePath)) -or
                        (-not $gcRelativePath.Equals($gcChild.Name, [System.StringComparison]::OrdinalIgnoreCase))) {
                        throw "Refused GC target that is not an immediate child of the surface root: $gcTarget"
                    }

                    $gcParentPath = Get-NormalizedFullPath -Path $gcChild.Parent.FullName
                    if (-not $gcParentPath.Equals($gcSurfaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                        throw "Refused GC target with unexpected parent '$gcParentPath': $gcTarget"
                    }

                    $gcCanonical = Get-NormalizedFullPath -Path (Join-Path $StoreRoot $gcSkillName)
                    if (-not (Test-PathIsUnder -Path $gcCanonical -Root $StoreRoot)) {
                        throw "Refused GC canonical path outside store root: $gcCanonical"
                    }
                    if (-not (Test-Path -LiteralPath $gcCanonical -PathType Container)) {
                        throw "Refused GC because canonical directory is missing: $gcCanonical"
                    }

                    $gcTargetItem = Get-ExistingItem -Path $gcTarget
                    if ($null -eq $gcTargetItem) {
                        continue
                    }
                    if (-not $gcTargetItem.PSIsContainer) {
                        throw "Refused GC target that is not a directory: $gcTarget"
                    }

                    if (Test-IsReparsePoint -Item $gcTargetItem) {
                        if ($IsDryRun) {
                            Write-Output "GC REMOVE LINK ONLY (would): skill='$gcSkillName' surface='$gcSurfaceName' target='$gcTarget' [non-recursive; no Recycle Bin]"
                            $gcAction = 'gc-would-remove-link'
                        }
                        else {
                            Write-Output "GC REMOVE LINK ONLY: skill='$gcSkillName' surface='$gcSurfaceName' target='$gcTarget' [non-recursive; no Recycle Bin]"
                            # SAFETY: delete only the reparse-point entry; never traverse its target.
                            [System.IO.Directory]::Delete($gcTarget, $false)
                            $gcMutated = $true
                            if ($null -ne (Get-ExistingItem -Path $gcTarget)) {
                                throw "GC link-only removal did not remove the original target: $gcTarget"
                            }
                            if (-not (Test-Path -LiteralPath $gcCanonical -PathType Container)) {
                                throw "Canonical directory disappeared after GC link-only removal: $gcCanonical"
                            }
                            $gcAction = 'gc-removed-link'
                        }
                    }
                    else {
                        if ($IsDryRun) {
                            Write-Output "GC RECYCLE DIRECTORY (would): skill='$gcSkillName' surface='$gcSurfaceName' target='$gcTarget' [Recycle Bin; never permanent]"
                            $gcAction = 'gc-would-recycle'
                        }
                        else {
                            Write-Output "GC RECYCLE DIRECTORY: skill='$gcSkillName' surface='$gcSurfaceName' target='$gcTarget' [Recycle Bin; never permanent]"
                            Send-DirectoryToRecycleBin -Target $gcTarget
                            $gcMutated = $true
                            if ($null -ne (Get-ExistingItem -Path $gcTarget)) {
                                throw "GC Recycle Bin removal did not remove the original target: $gcTarget"
                            }
                            if (-not (Test-Path -LiteralPath $gcCanonical -PathType Container)) {
                                throw "Canonical directory disappeared after GC Recycle Bin removal: $gcCanonical"
                            }
                            $gcAction = 'gc-recycled'
                        }
                    }

                    Add-Result -SkillName $gcSkillName -SurfaceName $gcSurfaceName -Mode $gcMode -Action $gcAction
                }
                catch {
                    $gcFailureAction = 'skipped(gc-error)'
                    if ($gcMutated) {
                        $gcFailureAction = 'gc-mutated-then-skipped(error)'
                    }
                    Add-Result -SkillName $gcSkillName -SurfaceName $gcSurfaceName -Mode $gcMode -Action $gcFailureAction
                    Add-OperationError -SkillName $gcSkillName -SurfaceName $gcSurfaceName -Message $_.Exception.Message
                }
            }
        }
        catch {
            Add-OperationError -SkillName 'gc' -SurfaceName $gcSurfaceName -Message $_.Exception.Message
        }
    }
}
catch {
    $Errors += "[fatal] $($_.Exception.Message)"
    [Console]::Error.WriteLine("FATAL: $($_.Exception.Message)")
}

Write-Host ''
if ($IsDryRun) {
    Write-Host '=== DRY RUN SUMMARY (PLAN ONLY) ===' -ForegroundColor Yellow
}
else {
    Write-Host '=== APPLY SUMMARY ===' -ForegroundColor Cyan
}

if ($Results.Count -gt 0) {
    $Results |
        Sort-Object skill, surface |
        Format-Table skill, surface, mode, action -AutoSize |
        Out-Host
}
else {
    Write-Host '(no skill/surface rows matched the filters)'
}

$inSyncCount = @($Results | Where-Object { $_.action -eq 'in-sync' }).Count
$skippedCount = @($Results | Where-Object {
    $_.action.IndexOf('skipped(', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}).Count
$backupCount = @($Results | Where-Object {
    $_.action.StartsWith('backed-up-then-', [System.StringComparison]::OrdinalIgnoreCase)
}).Count
$changeCount = @($Results | Where-Object {
    ($_.action -ne 'in-sync') -and
    (-not $_.action.StartsWith('skipped(', [System.StringComparison]::OrdinalIgnoreCase))
}).Count
$gcWouldRemoveLinkCount = @($Results | Where-Object { $_.action -eq 'gc-would-remove-link' }).Count
$gcWouldRecycleCount = @($Results | Where-Object { $_.action -eq 'gc-would-recycle' }).Count
$gcRemovedLinkCount = @($Results | Where-Object { $_.action -eq 'gc-removed-link' }).Count
$gcRecycledCount = @($Results | Where-Object { $_.action -eq 'gc-recycled' }).Count
$gcActionCount = $gcWouldRemoveLinkCount + $gcWouldRecycleCount + $gcRemovedLinkCount + $gcRecycledCount

Write-Host ("Counts: rows={0}; changes={1}; backups={2}; in-sync={3}; skipped={4}; errors={5}; surface-dirs-planned={6}; surface-dirs-created={7}; gc-actions={8}; gc-would-remove-links={9}; gc-would-recycle={10}; gc-removed-links={11}; gc-recycled={12}" -f
    $Results.Count, $changeCount, $backupCount, $inSyncCount, $skippedCount, $Errors.Count,
    $SurfaceDirectoriesPlanned, $SurfaceDirectoriesCreated, $gcActionCount, $gcWouldRemoveLinkCount,
    $gcWouldRecycleCount, $gcRemovedLinkCount, $gcRecycledCount)

if ($Errors.Count -gt 0) {
    exit 1
}

exit 0
