$repositoryRoot = Split-Path -Parent $PSScriptRoot
$initializeScript = Join-Path $repositoryRoot 'scripts\Initialize-AgentAcademy.ps1'

Describe 'Initialize-AgentAcademy' {
    It 'makes no filesystem changes when DryRun is used' {
        $installRoot = Join-Path $TestDrive 'dry-run-academy'

        & $initializeScript `
            -InstallRoot $installRoot `
            -TrainerName 'New Trainer' `
            -PreferredLanguage 'English' `
            -TimeZone 'Asia/Bangkok' `
            -DryRun | Out-Null

        (Test-Path -LiteralPath $installRoot) | Should Be $false
    }

    It 'creates trainer and assignment files from noninteractive parameters' {
        $installRoot = Join-Path $TestDrive 'initialized-academy'
        $assignmentsJson = @'
[
  {
    "name": "Academy Lead",
    "role": "Coordinator",
    "provider": "Example Provider",
    "model": "example-model"
  }
]
'@

        & $initializeScript `
            -InstallRoot $installRoot `
            -TrainerName 'New Trainer' `
            -PreferredLanguage 'English' `
            -TimeZone 'Asia/Bangkok' `
            -AssignmentsJson $assignmentsJson | Out-Null

        $trainerPath = Join-Path $installRoot 'governance\trainer.local.md'
        $assignmentsPath = Join-Path $installRoot 'governance\assignments.local.md'

        (Test-Path -LiteralPath $trainerPath) | Should Be $true
        (Test-Path -LiteralPath $assignmentsPath) | Should Be $true

        $trainerContent = Get-Content -LiteralPath $trainerPath -Raw
        $trainerContent | Should Match 'New Trainer'
        $trainerContent | Should Match 'English'
        $trainerContent | Should Match 'Asia/Bangkok'

        $assignmentsContent = Get-Content -LiteralPath $assignmentsPath -Raw
        $assignmentsContent | Should Match 'Academy Lead'
        $assignmentsContent | Should Match 'Coordinator'
        $assignmentsContent | Should Match 'Example Provider'
        $assignmentsContent | Should Match 'example-model'
    }

    It 'preserves user-modified governance files when rerun' {
        $installRoot = Join-Path $TestDrive 'rerun-academy'
        $commonParameters = @{
            InstallRoot = $installRoot
            TrainerName = 'First Trainer'
            PreferredLanguage = 'English'
            TimeZone = 'UTC'
        }

        & $initializeScript @commonParameters | Out-Null

        $trainerPath = Join-Path $installRoot 'governance\trainer.local.md'
        $assignmentsPath = Join-Path $installRoot 'governance\assignments.local.md'
        (Test-Path -LiteralPath $trainerPath) | Should Be $true
        (Test-Path -LiteralPath $assignmentsPath) | Should Be $true

        $customTrainerContent = "# Trainer`r`n`r`nUser-maintained trainer details."
        $customAssignmentsContent = "# Assignments`r`n`r`nUser-maintained assignments."
        Set-Content -LiteralPath $trainerPath -Value $customTrainerContent -Encoding UTF8
        Set-Content -LiteralPath $assignmentsPath -Value $customAssignmentsContent -Encoding UTF8

        & $initializeScript `
            -InstallRoot $installRoot `
            -TrainerName 'Replacement Trainer' `
            -PreferredLanguage 'Thai' `
            -TimeZone 'Asia/Bangkok' | Out-Null

        (Get-Content -LiteralPath $trainerPath -Raw).Trim() |
            Should Be $customTrainerContent
        (Get-Content -LiteralPath $assignmentsPath -Raw).Trim() |
            Should Be $customAssignmentsContent
    }

    It 'uses the requested install root without embedding the source machine path' {
        $installRoot = Join-Path $TestDrive 'custom-location\nested-academy'

        & $initializeScript `
            -InstallRoot $installRoot `
            -TrainerName 'Portable Trainer' `
            -PreferredLanguage 'English' `
            -TimeZone 'UTC' | Out-Null

        $trainerPath = Join-Path $installRoot 'governance\trainer.local.md'
        $assignmentsPath = Join-Path $installRoot 'governance\assignments.local.md'

        (Test-Path -LiteralPath $trainerPath) | Should Be $true
        (Test-Path -LiteralPath $assignmentsPath) | Should Be $true

        $generatedContent = @(
            Get-Content -LiteralPath $trainerPath -Raw
            Get-Content -LiteralPath $assignmentsPath -Raw
        ) -join "`n"

        $syntheticSourcePathPattern = 'C:\\Use' + 'rs\\source-owner'
        $generatedContent | Should Not Match $syntheticSourcePathPattern
    }
}
