$repositoryRoot = Split-Path -Parent $PSScriptRoot
$providerExamplePath = Join-Path $repositoryRoot 'templates\providers.example.json'
$credentialKeyPattern = '(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|authorization|credential|secret)'

function Get-JsonPropertyName {
    param([Parameter(Mandatory = $true)]$Value)

    if ($null -eq $Value) {
        return
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        foreach ($item in $Value) {
            Get-JsonPropertyName -Value $item
        }
        return
    }

    if ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            $property.Name
            Get-JsonPropertyName -Value $property.Value
        }
    }
}

Describe 'Provider transport example' {
    It 'exists and parses as JSON' {
        (Test-Path -LiteralPath $providerExamplePath -PathType Leaf) | Should Be $true
        { Get-Content -LiteralPath $providerExamplePath -Raw | ConvertFrom-Json | Out-Null } |
            Should Not Throw
    }

    It 'contains no credential-shaped property names' {
        (Test-Path -LiteralPath $providerExamplePath -PathType Leaf) | Should Be $true
        if (-not (Test-Path -LiteralPath $providerExamplePath -PathType Leaf)) {
            return
        }

        $providerExample = Get-Content -LiteralPath $providerExamplePath -Raw | ConvertFrom-Json
        $credentialShapedNames = @(
            Get-JsonPropertyName -Value $providerExample |
                Where-Object { $_ -match $credentialKeyPattern }
        )
        $credentialShapedNames.Count | Should Be 0
    }
}
