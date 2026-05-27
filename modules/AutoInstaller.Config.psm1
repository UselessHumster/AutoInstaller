Set-StrictMode -Version Latest

function Import-AIProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Profile file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Profile file is empty: $Path"
    }

    $yamlCommand = Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue
    if ($yamlCommand) {
        return $raw | ConvertFrom-Yaml
    }

    try {
        return $raw | ConvertFrom-Json
    }
    catch {
        throw "Profile must be valid YAML via ConvertFrom-Yaml, or JSON-compatible YAML when ConvertFrom-Yaml is unavailable. File: $Path"
    }
}

function Resolve-AIPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    $baseDirectory = Split-Path -Parent $BasePath
    return [System.IO.Path]::GetFullPath((Join-Path $baseDirectory $Path))
}

function Get-AIDepartment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Profile,
        [string]$DepartmentId
    )

    $departments = @($Profile.departments)
    if ($departments.Count -eq 0) {
        throw 'Profile does not define any departments.'
    }

    if ([string]::IsNullOrWhiteSpace($DepartmentId)) {
        return $departments[0]
    }

    $department = $departments | Where-Object { $_.id -eq $DepartmentId } | Select-Object -First 1
    if (-not $department) {
        throw "Department '$DepartmentId' was not found in profile '$($Profile.company)'."
    }

    return $department
}

function Get-AISoftwareById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Profile,
        [Parameter(Mandatory)]
        [string]$Id
    )

    $software = @($Profile.software) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $software) {
        throw "Software '$Id' was referenced but not defined in profile '$($Profile.company)'."
    }

    return $software
}

Export-ModuleMember -Function Import-AIProfile, Resolve-AIPath, Get-AIDepartment, Get-AISoftwareById
