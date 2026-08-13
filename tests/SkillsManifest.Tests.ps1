$repositoryRoot = Split-Path -Parent $PSScriptRoot
$skillStoreRoot = Join-Path $repositoryRoot 'team-skills'
$manifestPath = Join-Path $skillStoreRoot 'skills-manifest.json'
$expectedSurfaces = @('antigravity', 'claude', 'codex', 'kimi')
$excludedBusinessSkills = @(
    'financial-reporting-reconciliation'
    'lease-contract-review'
    'product-requirements-writing'
    'staff-workflow-research'
    'tenant-data-privacy-review'
    'thai-localization-review'
)

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

    It 'contains exactly 28 generic skills with unique names' {
        $script:skills.Count | Should Be 28
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

    It 'excludes project-specific business skills' {
        $manifestNames = @($script:skills | ForEach-Object { $_.name })
        foreach ($excludedSkill in $excludedBusinessSkills) {
            ($manifestNames -contains $excludedSkill) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $skillStoreRoot $excludedSkill)) | Should Be $false
        }
    }
}
