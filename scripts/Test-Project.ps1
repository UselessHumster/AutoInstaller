[CmdletBinding()]
param(
    [string]$ProfilePath = (Join-Path $PSScriptRoot '../profiles/sample-company.yaml')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$required = @(
    'Start-AutoInstaller.ps1',
    'modules/AutoInstaller.Config.psm1',
    'modules/AutoInstaller.Context.psm1',
    'modules/AutoInstaller.Logging.psm1',
    'modules/AutoInstaller.Software.psm1',
    'modules/AutoInstaller.SystemTasks.psm1',
    'modules/AutoInstaller.TaskRunner.psm1',
    'modules/AutoInstaller.Ui.psm1',
    'profiles/sample-company.yaml'
)

foreach ($relative in $required) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required file: $relative"
    }
}

$moduleRoot = Join-Path $root 'modules'
Import-Module (Join-Path $moduleRoot 'AutoInstaller.Config.psm1') -Force
$profile = Import-AIProfile -Path $ProfilePath

if (-not $profile.company) {
    throw 'Profile is missing company.'
}
if (-not $profile.departments -or @($profile.departments).Count -eq 0) {
    throw 'Profile must define at least one department.'
}
if (-not $profile.software -or @($profile.software).Count -eq 0) {
    throw 'Profile must define at least one software package.'
}

foreach ($department in @($profile.departments)) {
    foreach ($softwareId in @($department.software)) {
        [void](Get-AISoftwareById -Profile $profile -Id $softwareId)
    }
}

Write-Host "Project validation passed for profile: $ProfilePath"
