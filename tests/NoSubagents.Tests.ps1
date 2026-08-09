$repositoryRoot = Split-Path -Parent $PSScriptRoot

Describe 'Portable no-subagent invariant' {
    BeforeAll {
        $script:roster = Get-Content -LiteralPath (Join-Path $repositoryRoot 'governance\roster.json') -Raw | ConvertFrom-Json
        $script:templateManifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'manifests\template-manifest.json') -Raw | ConvertFrom-Json
        $script:requiredFiles = @(
            'AGENTS.md'
            'CLAUDE.md'
            'GEMINI.md'
            'governance\no-subagents.md'
            'governance\team.md'
            'governance\workflow.md'
            'governance\transport.md'
        )
    }

    It 'disables platform subagents in both machine-readable manifests' {
        $script:roster.subagentsAllowed | Should Be $false
        $script:templateManifest.subagentsAllowed | Should Be $false
    }

    It 'publishes the prohibition to every canonical harness and governance surface' {
        foreach ($relativePath in $script:requiredFiles) {
            $path = Join-Path $repositoryRoot $relativePath
            (Test-Path -LiteralPath $path -PathType Leaf) | Should Be $true
            (Get-Content -LiteralPath $path -Raw) | Should Match '(?i)subagent'
        }
    }

    It 'overrides conflicting instructions in bundled project skills' {
        $paths = @(
            'team-skills\graphify\SKILL.md'
            'team-skills\graphify\.variants\codex\SKILL.md'
            'team-skills\project-development\SKILL.md'
        )
        foreach ($relativePath in $paths) {
            $content = Get-Content -LiteralPath (Join-Path $repositoryRoot $relativePath) -Raw
            $content | Should Match 'Academy execution (override|constraint)'
            if ($relativePath -match 'graphify') {
                $content | Should Match 'ACADEMY STOP.+ENTIRE UPSTREAM PART B IS NON-OPERATIVE'
            }
        }
    }

    It 'places the prohibition in onboarding and task-packet surfaces' {
        $paths = @(
            'prompts\00-bootstrap.md'
            'scripts\new-task-packet.ps1'
            'templates\task-packet.md'
        )
        foreach ($relativePath in $paths) {
            (Get-Content -LiteralPath (Join-Path $repositoryRoot $relativePath) -Raw) |
                Should Match '(?i)platform (child/forked agent|subagent)'
        }
    }
}
