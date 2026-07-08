[CmdletBinding()]
param(
    [string]$ProfilePath = '',
    [string]$DepartmentId = '',
    [string]$ComputerName = '',
    [switch]$NoUi,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $ProfilePath = Join-Path $PSScriptRoot 'profiles/sample-company.yaml'
}

$moduleRoot = Join-Path $PSScriptRoot 'modules'
Import-Module (Join-Path $moduleRoot 'AutoInstaller.Config.psm1') -Force
Import-Module (Join-Path $moduleRoot 'AutoInstaller.Logging.psm1') -Force
Import-Module (Join-Path $moduleRoot 'AutoInstaller.Context.psm1') -Force
Import-Module (Join-Path $moduleRoot 'AutoInstaller.SystemTasks.psm1') -Force
Import-Module (Join-Path $moduleRoot 'AutoInstaller.Software.psm1') -Force
Import-Module (Join-Path $moduleRoot 'AutoInstaller.TaskRunner.psm1') -Force
Import-Module (Join-Path $moduleRoot 'AutoInstaller.Ui.psm1') -Force

$logRoot = Join-Path $PSScriptRoot 'logs'
$logger = New-AILogger -LogRoot $logRoot

try {
    if ((Test-AIWindows) -and -not (Test-AIAdministrator) -and -not $DryRun) {
        Start-AIElevatedSelf -ScriptPath $PSCommandPath -ProfilePath $ProfilePath -DepartmentId $DepartmentId -ComputerName $ComputerName -NoUi:$NoUi
        return
    }

    $profile = Import-AIProfile -Path $ProfilePath

    if (-not $NoUi -and (Test-AIWindowsGuiAvailable)) {
        Start-AIWinFormsUi -Profile $profile -ProfilePath $ProfilePath -Logger $logger -DryRun:$DryRun
        return
    }

    $context = New-AIRunContext -Profile $profile -ProfilePath $ProfilePath -DepartmentId $DepartmentId -ComputerName $ComputerName -DryRun:$DryRun
    $tasks = New-AITaskPlan -Context $context
    Invoke-AITaskPlan -Context $context -Tasks $tasks -Logger $logger
    Export-AIRunReport -Context $context -Tasks $tasks -Logger $logger
}
catch {
    Write-AILog -Logger $logger -Level 'ERROR' -Message $_.Exception.Message
    throw
}
