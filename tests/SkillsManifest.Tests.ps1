$repositoryRoot = Split-Path -Parent $PSScriptRoot
$skillStoreRoot = Join-Path $repositoryRoot 'team-skills'
$manifestPath = Join-Path $skillStoreRoot 'skills-manifest.json'
$expectedSurfaces = @('antigravity', 'claude', 'codex', 'kimi')
$ratifiedHorizontalSkills = @(
    'product-requirements-writing'
    'staff-workflow-research'
    'thai-localization-review'
)
$ratifiedVerticalExclusions = @(
    'financial-reporting-reconciliation'
    'lease-contract-review'
    'tenant-data-privacy-review'
)

# Ratified public-bundle scope decision: Option C, 2026-09-03.
# These exact-name and physical-directory checks are deterministic scope and anti-sync
# tripwires, not a semantic guard. A neutral-named vertical skill can evade name checks,
# while a legitimate future skill can share a word with an excluded domain. Semantic
# approval belongs in a governed decision artifact with independent review; this test
# enforces only the ratified sets, published counts, and machine-checkable invariants.

Describe 'Portable skills manifest contract' {
    BeforeAll {
        (Test-Path -LiteralPath $manifestPath) | Should Be $true
        $script:manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $script:skills = @($script:manifest.skills)
    }

    It 'declares exactly four supported surfaces' {
        $surfaceNames = @($script:manifest.surfaces.PSObject.Properties.Name | Sort-Object)
        ($surfaceNames -join ',') | Should Be ($expectedSurfaces -join ',')
    }

    It 'contains exactly 31 ratified portable skills with unique names' {
        $script:skills.Count | Should Be 31
        $names = @($script:skills | ForEach-Object { $_.name })
        @($names | Select-Object -Unique).Count | Should Be $names.Count
    }

    It 'declares all four surfaces for every skill' {
        foreach ($skill in $script:skills) {
            $surfaces = @($skill.surfaces | Sort-Object)
            ($surfaces -join ',') | Should Be ($expectedSurfaces -join ',')
        }
    }

    It 'has exact manifest-to-directory parity' {
        $manifestNames = @($script:skills | ForEach-Object { $_.name } | Sort-Object)
        $directoryNames = @(
            Get-ChildItem -LiteralPath $skillStoreRoot -Directory -Force |
                Where-Object { $_.Name -notlike '.*' } |
                ForEach-Object { $_.Name } |
                Sort-Object
        )

        ($directoryNames -join ',') | Should Be ($manifestNames -join ',')
        foreach ($skillName in $manifestNames) {
            (Test-Path -LiteralPath (Join-Path $skillStoreRoot "$skillName\SKILL.md") -PathType Leaf) |
                Should Be $true
        }
    }

    It 'records usable provenance and a bundled license for every third-party skill' {
        $thirdPartySkills = @($script:skills | Where-Object { $_.source -notmatch '^team-authored' })
        $thirdPartySkills.Count | Should Be 9

        foreach ($skill in $thirdPartySkills) {
            ([string]$skill.sourceUrl) | Should Match '^https://github\.com/'
            ([string]$skill.licenseFile) | Should Not BeNullOrEmpty

            $licensePath = Join-Path $repositoryRoot ([string]$skill.licenseFile)
            (Test-Path -LiteralPath $licensePath -PathType Leaf) | Should Be $true
        }
    }

    It 'includes the three ratified horizontal skills in the manifest and on disk' {
        $manifestNames = @($script:skills | ForEach-Object { $_.name })
        foreach ($admittedSkill in $ratifiedHorizontalSkills) {
            ($manifestNames -contains $admittedSkill) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $skillStoreRoot "$admittedSkill\SKILL.md") -PathType Leaf) |
                Should Be $true
        }
    }

    It 'preserves the anti-sync tripwire for three ratified vertical exclusions' {
        $manifestNames = @($script:skills | ForEach-Object { $_.name })
        foreach ($excludedSkill in $ratifiedVerticalExclusions) {
            ($manifestNames -contains $excludedSkill) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $skillStoreRoot $excludedSkill)) | Should Be $false
        }
    }

    It 'keeps published README skill counts and capability-family totals at 31' {
        $readme = Get-Content -LiteralPath (Join-Path $repositoryRoot 'README.md') -Raw
        $readmeThai = Get-Content -LiteralPath (Join-Path $repositoryRoot 'README-TH.md') -Raw

        $readme | Should Match 'portable%20skills-31'
        $readme | Should Match '\*\*31 curated skills\*\*'
        $readme | Should Match '\| \*\*Total\*\* \| \*\*31\*\* \|'
        $readmeThai | Should Match 'portable%20skills-31'
        $readmeThai | Should Match '\*\*31 Skills ที่คัดเลือกไว้\*\*'
        $readmeThai | Should Match '### Skills ทั้ง 31 รายการ'
        $readmeThai | Should Match '\| \*\*รวม\*\* \| \*\*31\*\* \|'

        $englishFamilyCounts = [regex]::Matches(
            $readme,
            '(?m)^\| \*\*(?!Total\*\*)[^|]+\*\* \| (\d+) \|'
        ) | ForEach-Object { [int]$_.Groups[1].Value }
        $thaiFamilyCounts = [regex]::Matches(
            $readmeThai,
            '(?m)^\| \*\*(?!รวม\*\*)[^|]+\*\* \| (\d+) \|'
        ) | ForEach-Object { [int]$_.Groups[1].Value }

        ($englishFamilyCounts | Measure-Object -Sum).Sum | Should Be 31
        ($thaiFamilyCounts | Measure-Object -Sum).Sum | Should Be 31
    }
}
