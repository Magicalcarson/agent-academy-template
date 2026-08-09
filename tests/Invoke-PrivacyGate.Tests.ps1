$repositoryRoot = Split-Path -Parent $PSScriptRoot
$privacyGateScript = Join-Path $repositoryRoot 'scripts\Invoke-PrivacyGate.ps1'
$releaseAllowlistPath = Join-Path $repositoryRoot 'manifests\release-allowlist.txt'

Describe 'Invoke-PrivacyGate' {
    It 'publishes both English and Thai root README files' {
        $releasePaths = @(Get-Content -LiteralPath $releaseAllowlistPath)

        @($releasePaths | Where-Object { $_ -in @('README.md', 'README-TH.md') }).Count | Should Be 2
    }

    It 'passes a clean template tree' {
        (Test-Path -LiteralPath $privacyGateScript) | Should Be $true

        $root = Join-Path $TestDrive 'clean-template'
        $governanceRoot = Join-Path $root 'governance'
        New-Item -ItemType Directory -Path $governanceRoot -Force | Out-Null
        Set-Content `
            -LiteralPath (Join-Path $governanceRoot 'team.md') `
            -Value '# Team personas only' `
            -Encoding UTF8

        { & $privacyGateScript -Root $root | Out-Null } | Should Not Throw
    }

    It 'rejects content containing the source machine path' {
        (Test-Path -LiteralPath $privacyGateScript) | Should Be $true

        $root = Join-Path $TestDrive 'leaking-template'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $syntheticSourcePath = 'C:\Use' + 'rs\source-owner\private-workspace.'
        Set-Content `
            -LiteralPath (Join-Path $root 'leak.txt') `
            -Value "Copied from $syntheticSourcePath" `
            -Encoding UTF8

        { & $privacyGateScript -Root $root | Out-Null } | Should Throw
    }

    It 'rejects a caller-supplied forbidden marker' {
        (Test-Path -LiteralPath $privacyGateScript) | Should Be $true

        $root = Join-Path $TestDrive 'custom-marker-template'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Set-Content `
            -LiteralPath (Join-Path $root 'notes.md') `
            -Value 'PRIVATE-SOURCE-PROJECT appears here.' `
            -Encoding UTF8

        {
            & $privacyGateScript `
                -Root $root `
                -AdditionalForbiddenMarker 'PRIVATE-SOURCE-PROJECT' | Out-Null
        } | Should Throw
    }

    It 'accepts the Graphify version stamp by exact file name' {
        (Test-Path -LiteralPath $privacyGateScript) | Should Be $true

        $root = Join-Path $TestDrive 'graphify-version-template'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Set-Content `
            -LiteralPath (Join-Path $root '.graphify_version') `
            -Value '1' `
            -Encoding UTF8

        { & $privacyGateScript -Root $root | Out-Null } | Should Not Throw
    }

    It 'does not extend the Graphify exemption to similarly named files' {
        (Test-Path -LiteralPath $privacyGateScript) | Should Be $true

        $root = Join-Path $TestDrive 'graphify-version-lookalike-template'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Set-Content `
            -LiteralPath (Join-Path $root '.graphify_version.backup') `
            -Value '1' `
            -Encoding UTF8

        { & $privacyGateScript -Root $root | Out-Null } | Should Throw
    }

    It 'accepts the standard root LICENSE file by exact path' {
        (Test-Path -LiteralPath $privacyGateScript) | Should Be $true

        $root = Join-Path $TestDrive 'licensed-template'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Set-Content `
            -LiteralPath (Join-Path $root 'LICENSE') `
            -Value 'MIT License fixture' `
            -Encoding UTF8

        { & $privacyGateScript -Root $root | Out-Null } | Should Not Throw
    }

    It 'does not extend the LICENSE exemption to nested extensionless files' {
        (Test-Path -LiteralPath $privacyGateScript) | Should Be $true

        $root = Join-Path $TestDrive 'nested-license-template'
        $nestedRoot = Join-Path $root 'docs'
        New-Item -ItemType Directory -Path $nestedRoot -Force | Out-Null
        Set-Content `
            -LiteralPath (Join-Path $nestedRoot 'LICENSE') `
            -Value 'Unexpected nested extensionless file' `
            -Encoding UTF8

        { & $privacyGateScript -Root $root | Out-Null } | Should Throw
    }
}
