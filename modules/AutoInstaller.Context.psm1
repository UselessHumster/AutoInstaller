Set-StrictMode -Version Latest

function Test-AIWindows {
    $isWindowsVariable = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
    if ($isWindowsVariable) {
        return [bool]$isWindowsVariable.Value
    }

    return $PSVersionTable.PSEdition -eq 'Desktop'
}

function Test-AIAdministrator {
    if (-not (Test-AIWindows)) {
        return $false
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-AIElevatedSelf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$ProfilePath,
        [string]$DepartmentId,
        [string]$ComputerName,
        [switch]$NoUi
    )

    $arguments = @(
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$ScriptPath`"",
        '-ProfilePath', "`"$ProfilePath`""
    )

    if (-not [string]::IsNullOrWhiteSpace($DepartmentId)) {
        $arguments += @('-DepartmentId', "`"$DepartmentId`"")
    }
    if (-not [string]::IsNullOrWhiteSpace($ComputerName)) {
        $arguments += @('-ComputerName', "`"$ComputerName`"")
    }
    if ($NoUi) {
        $arguments += '-NoUi'
    }

    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs | Out-Null
}

function New-AIRunContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Profile,
        [Parameter(Mandatory)]
        [string]$ProfilePath,
        [string]$DepartmentId,
        [string]$ComputerName,
        [switch]$DryRun
    )

    $department = Get-AIDepartment -Profile $Profile -DepartmentId $DepartmentId
    if ([string]::IsNullOrWhiteSpace($ComputerName)) {
        $ComputerName = Read-Host 'Computer name'
    }

    $domainCredential = $null
    if (-not $DryRun -and $department.domain -and $department.domain.name) {
        $domainCredential = Get-Credential -Message "Credentials for joining $($department.domain.name)"
    }

    $programData = if ($env:ProgramData) { $env:ProgramData } else { Join-Path (Get-Location) '.autoinstaller' }

    [pscustomobject]@{
        Profile          = $Profile
        ProfilePath      = $ProfilePath
        Department       = $department
        ComputerName     = $ComputerName
        DomainCredential = $domainCredential
        DryRun           = [bool]$DryRun
        IsWindows        = Test-AIWindows
        IsAdministrator  = Test-AIAdministrator
        ResumeStatePath  = Join-Path $programData 'AutoInstaller\resume.json'
    }
}

function Invoke-AICommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,
        [Parameter(Mandatory)]
        [string]$Description,
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    if ($Context.DryRun) {
        return "DRY RUN: $Description"
    }

    if (-not $Context.IsWindows) {
        throw "Windows-only action cannot run on this OS: $Description"
    }

    if (-not $Context.IsAdministrator) {
        throw "Administrator rights are required: $Description"
    }

    & $ScriptBlock
}

Export-ModuleMember -Function Test-AIWindows, Test-AIAdministrator, Start-AIElevatedSelf, New-AIRunContext, Invoke-AICommand
