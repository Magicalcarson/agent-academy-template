$repositoryRoot = Split-Path -Parent $PSScriptRoot
$rosterPath = Join-Path $repositoryRoot 'governance\roster.json'

Describe 'Portable roster contract' {
    BeforeAll {
        (Test-Path -LiteralPath $rosterPath) | Should Be $true
        $script:roster = Get-Content -LiteralPath $rosterPath -Raw | ConvertFrom-Json
        $script:members = @($script:roster.members)
    }

    It 'has the supported schema and a non-empty member list' {
        $script:roster.schemaVersion | Should Be 1
        $script:members.Count | Should BeGreaterThan 0
    }

    It 'defines every required member field and supported value' {
        foreach ($member in $script:members) {
            $member.id | Should Match '^[a-z0-9]+(?:-[a-z0-9]+)*$'
            [string]::IsNullOrWhiteSpace([string]$member.displayName) | Should Be $false
            @('lead', 'deputy', 'member') -contains $member.authority | Should Be $true
            @('active', 'on-leave') -contains $member.status | Should Be $true
            $member.dispatchable -is [bool] | Should Be $true
            [string]::IsNullOrWhiteSpace([string]$member.transport) | Should Be $false
            [string]::IsNullOrWhiteSpace([string]$member.voice.selfReference) | Should Be $false
            [string]::IsNullOrWhiteSpace([string]$member.voice.anchor) | Should Be $false
        }
    }

    It 'uses unique permanent ids' {
        $ids = @($script:members | ForEach-Object { $_.id })
        @($ids | Select-Object -Unique).Count | Should Be $ids.Count
    }

    It 'defines exactly one lead and at most one deputy' {
        @($script:members | Where-Object { $_.authority -eq 'lead' }).Count | Should Be 1
        @($script:members | Where-Object { $_.authority -eq 'deputy' }).Count | Should BeLessThan 2
    }

    It 'has one matching agent persona for every member id' {
        foreach ($member in $script:members) {
            $agentPath = Join-Path $repositoryRoot ("agents\{0}.md" -f $member.id)
            (Test-Path -LiteralPath $agentPath -PathType Leaf) | Should Be $true
        }
    }
}
