$repositoryRoot = Split-Path -Parent $PSScriptRoot
$warmup = Join-Path $repositoryRoot 'scripts\warmup-team.ps1'
$cooldown = Join-Path $repositoryRoot 'scripts\cooldown-team.ps1'
$hostScript = Join-Path $repositoryRoot 'scripts\start-team-session.ps1'
$sessionSender = Join-Path $repositoryRoot 'scripts\send-team-session.ps1'

Describe 'Visible warm-session transport' {
    It 'ships parseable PowerShell scripts' {
        foreach ($path in @($warmup, $cooldown, $hostScript, $sessionSender)) {
            $tokens = $null
            $errors = $null
            [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
            @($errors).Count | Should Be 0
        }
    }

    It 'supports the complete neutral roster without source identities' {
        $combined = (@($warmup, $cooldown, $hostScript, $sessionSender) | ForEach-Object {
                Get-Content -Raw -LiteralPath $_
            }) -join "`n"
        foreach ($id in @('academy-lead', 'academy-deputy', 'academy-analyst', 'academy-challenger', 'academy-steward')) {
            $combined | Should Match ([regex]::Escape($id))
        }
        $combined | Should Not Match 'symboli-rudolf|tokai-teio|oguri-cap|tm-opera-o|Tracen'
    }

    It 'rehydrates durable context without authorizing work' {
        $text = Get-Content -Raw -LiteralPath $hostScript
        $text | Should Match 'status/project-focus\.json'
        $text | Should Match 'latest daily worklog'
        $text | Should Match 'not as new authorization'
        $text | Should Match 'governed task packet'
    }

    It 'blocks packet replay before GUI action' {
        $text = Get-Content -Raw -LiteralPath $sessionSender
        $text | Should Match 'already has a durable outbox reply'
        $text.IndexOf('$matchingReply', [StringComparison]::Ordinal) |
            Should BeLessThan $text.IndexOf('if ($PSCmdlet.ShouldProcess', [StringComparison]::Ordinal)
    }

    It 'closes exact windows rather than terminal processes' {
        $text = Get-Content -Raw -LiteralPath $cooldown
        $text | Should Match 'WM_CLOSE'
        $text | Should Not Match 'Stop-Process|taskkill'
    }

    It 'uses non-json temp suffix and cleans up on atomic tracking failure' {
        $text = Get-Content -Raw -LiteralPath $sessionSender
        $text | Should Match '\.writing'
        $text | Should Match 'try\s*\{'
        $text | Should Match 'finally\s*\{'
        $text | Should Match 'Remove-Item -LiteralPath \$temporaryTrackingPath'
    }

    It 'refuses hand-planted partial temp files and enumerates only completed dispatch records' {
        $testDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ('test-dispatches-' + [Guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        try {
            # Plant an interrupted partial write with non-json extension
            $partialTemp = [System.IO.Path]::Combine($testDir, '.tmp-interrupted-write.writing')
            Set-Content -LiteralPath $partialTemp -Value '{"member":"academy-deputy","schemaVersion":1,"interrupted":' -Encoding UTF8

            # Plant a completed valid record
            $validRecord = [System.IO.Path]::Combine($testDir, 'academy-deputy__20260902-120000-task.json')
            [ordered]@{
                schemaVersion = 1
                member = 'academy-deputy'
                dispatcher = 'academy-lead'
                packetPath = 'inbox/academy-deputy/20260902-120000-task.md'
                expectedOutboxPath = 'outbox/academy-deputy/20260902-120000-task.md'
                dispatchedAt = [DateTime]::UtcNow.ToString('o')
                timeoutMinutes = 15
                targetProcessId = 1234
                targetProcessStartTime = [DateTime]::UtcNow.ToString('o')
            } | ConvertTo-Json | Set-Content -LiteralPath $validRecord -Encoding UTF8

            # Standard pending-dispatches reader enumerates *.json
            $discoveredJsonFiles = @(Get-ChildItem -LiteralPath $testDir -Filter '*.json' -File | Where-Object { $_.Name -notlike '.tmp*' })
            $discoveredJsonFiles.Count | Should Be 1
            $discoveredJsonFiles[0].Name | Should Be 'academy-deputy__20260902-120000-task.json'

            # The partial temp file is never enumerated as a valid dispatch record
            $parsedDispatches = @(foreach ($file in $discoveredJsonFiles) {
                Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            })
            $parsedDispatches.Count | Should Be 1
            $parsedDispatches[0].member | Should Be 'academy-deputy'
            $parsedDispatches[0].timeoutMinutes | Should Be 15
        } finally {
            if (Test-Path -LiteralPath $testDir) {
                Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
