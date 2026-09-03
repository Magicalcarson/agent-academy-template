[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Register', 'List', 'Validate', 'Focus', 'Checkpoint', 'Pause', 'Wait', 'Complete', 'Archive')]
    [string]$Action,

    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$Id,

    [string]$Name,
    [string]$Location,
    [string]$Plan = 'PROJECT_PLAN.md',
    [string]$Worklog = 'WORKLOG.md',
    [string]$Checkpoint,
    [string]$NextAction,

    [ValidateSet('Trainer')]
    [string]$ApprovedBy,

    [string]$StatePath
)

$ErrorActionPreference = 'Stop'
$ValidStatuses = @('queued', 'focused', 'waiting', 'paused', 'completed', 'archived')

if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = [System.IO.Path]::Combine((Split-Path -Parent $PSScriptRoot), 'status', 'project-focus.json')
}

function Get-EmptyAcademyProjectState {
    [pscustomobject][ordered]@{
        schemaVersion = 1
        team = 'Agent Academy'
        operatingMode = 'project-coding'
        focusProjectId = $null
        projects = @()
    }
}

function Get-AcademyProjectState {
    param(
        [string]$Path,
        [switch]$AllowMissing
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($AllowMissing) {
            return Get-EmptyAcademyProjectState
        }
        throw "Project-focus state does not exist: $Path"
    }

    try {
        return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
    } catch {
        throw "Project-focus state is not valid JSON: $Path. $($_.Exception.Message)"
    }
}

function Get-ProjectCollection {
    param($State)
    @($State.projects)
}

function Get-ProjectById {
    param(
        $State,
        [string]$ProjectId
    )
    @(Get-ProjectCollection $State | Where-Object { $_.id -eq $ProjectId }) | Select-Object -First 1
}

function Assert-ProjectIdParameter {
    if ([string]::IsNullOrWhiteSpace($Id)) {
        throw "Action '$Action' requires -Id."
    }
}

function Assert-RequiredText {
    param(
        [string]$Value,
        [string]$ParameterName
    )
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Action '$Action' requires -$ParameterName."
    }
}

function Assert-AcademyProjectState {
    param($State)

    if ($State.schemaVersion -ne 1) {
        throw 'Project-focus state schemaVersion must be 1.'
    }
    if ($State.team -ne 'Agent Academy' -or $State.operatingMode -ne 'project-coding') {
        throw 'Project-focus state team/operatingMode does not match Agent Academy.'
    }

    $projects = @(Get-ProjectCollection $State)
    $ids = @($projects | ForEach-Object { [string]$_.id })
    if (@($ids | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
        throw 'Project-focus state contains duplicate project ids.'
    }

    foreach ($project in $projects) {
        if ([string]::IsNullOrWhiteSpace([string]$project.id) -or
            [string]::IsNullOrWhiteSpace([string]$project.name) -or
            [string]::IsNullOrWhiteSpace([string]$project.location)) {
            throw 'Every project requires id, name, and location.'
        }
        if ($project.status -notin $ValidStatuses) {
            throw "Project '$($project.id)' has invalid status '$($project.status)'."
        }
    }

    $focused = @($projects | Where-Object status -eq 'focused')
    if ($focused.Count -gt 1) {
        throw 'Only one Agent Academy project may be focused at a time.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$State.focusProjectId)) {
        if ($focused.Count -ne 0) {
            throw 'focusProjectId is empty but a project is marked focused.'
        }
    } else {
        if ($focused.Count -ne 1 -or $focused[0].id -ne $State.focusProjectId) {
            throw 'focusProjectId must identify the single project marked focused.'
        }
        if ($focused[0].focusApproval.approvedBy -ne 'Trainer') {
            throw 'The focused project must record Trainer approval.'
        }
    }
}

function Write-AcademyProjectState {
    param(
        $State,
        [string]$Path
    )

    Assert-AcademyProjectState $State
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $temporaryPath = Join-Path $directory ('.project-focus.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $json = $State | ConvertTo-Json -Depth 10
        [IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

$allowMissing = $Action -eq 'Register'
$state = Get-AcademyProjectState -Path $StatePath -AllowMissing:$allowMissing

switch ($Action) {
    'Register' {
        Assert-ProjectIdParameter
        Assert-RequiredText $Name 'Name'
        Assert-RequiredText $Location 'Location'
        if (Get-ProjectById $state $Id) {
            throw "Project '$Id' is already registered."
        }

        $project = [pscustomobject][ordered]@{
            id = $Id
            name = $Name
            location = $Location
            status = 'queued'
            plan = $Plan
            worklog = $Worklog
            checkpoint = $null
            nextAction = $null
            updatedAt = [DateTime]::UtcNow.ToString('o')
            focusApproval = $null
        }
        $state.projects = @(Get-ProjectCollection $state) + @($project)
        Write-AcademyProjectState $state $StatePath
    }
    'List' {
        Assert-AcademyProjectState $state
    }
    'Validate' {
        Assert-AcademyProjectState $state
    }
    'Focus' {
        Assert-ProjectIdParameter
        if ($ApprovedBy -ne 'Trainer') {
            throw "Action 'Focus' requires -ApprovedBy Trainer."
        }
        $target = Get-ProjectById $state $Id
        if (-not $target) {
            throw "Project '$Id' is not registered."
        }
        if ($target.status -in @('completed', 'archived')) {
            throw "Project '$Id' cannot be focused from status '$($target.status)'."
        }

        if ($state.focusProjectId -eq $Id) {
            Assert-AcademyProjectState $state
            break
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$state.focusProjectId)) {
            Assert-RequiredText $Checkpoint 'Checkpoint'
            Assert-RequiredText $NextAction 'NextAction'
            $current = Get-ProjectById $state $state.focusProjectId
            $current.status = 'paused'
            $current.checkpoint = $Checkpoint
            $current.nextAction = $NextAction
            $current.focusApproval = $null
            $current.updatedAt = [DateTime]::UtcNow.ToString('o')
        }

        $target.status = 'focused'
        $target.focusApproval = [pscustomobject][ordered]@{
            approvedBy = 'Trainer'
            approvedAt = [DateTime]::UtcNow.ToString('o')
        }
        $target.updatedAt = [DateTime]::UtcNow.ToString('o')
        $state.focusProjectId = $Id
        Write-AcademyProjectState $state $StatePath
    }
    'Checkpoint' {
        Assert-ProjectIdParameter
        Assert-RequiredText $Checkpoint 'Checkpoint'
        Assert-RequiredText $NextAction 'NextAction'
        if ($state.focusProjectId -ne $Id) {
            throw "Only the focused project may be checkpointed. Current focus: '$($state.focusProjectId)'."
        }
        $project = Get-ProjectById $state $Id
        $project.checkpoint = $Checkpoint
        $project.nextAction = $NextAction
        $project.updatedAt = [DateTime]::UtcNow.ToString('o')
        Write-AcademyProjectState $state $StatePath
    }
    { $_ -in @('Pause', 'Wait', 'Complete') } {
        Assert-ProjectIdParameter
        Assert-RequiredText $Checkpoint 'Checkpoint'
        if ($Action -ne 'Complete') {
            Assert-RequiredText $NextAction 'NextAction'
        }
        if ($state.focusProjectId -ne $Id) {
            throw "Only the focused project may transition via '$Action'. Current focus: '$($state.focusProjectId)'."
        }
        $project = Get-ProjectById $state $Id
        $project.status = switch ($Action) {
            'Pause' { 'paused' }
            'Wait' { 'waiting' }
            'Complete' { 'completed' }
        }
        $project.checkpoint = $Checkpoint
        $project.nextAction = if ($Action -eq 'Complete') { $null } else { $NextAction }
        $project.focusApproval = $null
        $project.updatedAt = [DateTime]::UtcNow.ToString('o')
        $state.focusProjectId = $null
        Write-AcademyProjectState $state $StatePath
    }
    'Archive' {
        Assert-ProjectIdParameter
        if ($ApprovedBy -ne 'Trainer') {
            throw "Action 'Archive' requires -ApprovedBy Trainer."
        }
        $project = Get-ProjectById $state $Id
        if (-not $project) {
            throw "Project '$Id' is not registered."
        }
        if ($project.status -ne 'completed') {
            throw 'Only a completed project may be archived.'
        }
        $project.status = 'archived'
        $project.updatedAt = [DateTime]::UtcNow.ToString('o')
        Write-AcademyProjectState $state $StatePath
    }
}

$result = Get-AcademyProjectState -Path $StatePath
Assert-AcademyProjectState $result
$result

