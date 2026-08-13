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
}
