Set-StrictMode -Version Latest

function New-AITask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Group,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    [pscustomobject]@{
        Id      = $Id
        Name    = $Name
        Group   = $Group
        Status  = 'Pending'
        Message = ''
        Action  = $Action
    }
}

function New-AITaskPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Context)

    $tasks = [System.Collections.Generic.List[object]]::new()

    if ($Context.Profile.windows.power) {
        $tasks.Add((New-AITask -Id 'windows.power' -Name 'Power policy' -Group 'Windows' -Action { Set-AIPowerPolicy -Context $Context }))
    }
    if ($Context.Profile.windows.enableRdp) {
        $tasks.Add((New-AITask -Id 'windows.rdp' -Name 'Enable Remote Desktop' -Group 'Windows' -Action { Enable-AIRemoteDesktop -Context $Context }))
    }
    $tasks.Add((New-AITask -Id 'windows.rename' -Name 'Rename computer' -Group 'Windows' -Action { Rename-AIComputer -Context $Context }))

    if ($Context.Department.domain -and $Context.Department.domain.name) {
        $tasks.Add((New-AITask -Id 'domain.join' -Name 'Join domain' -Group 'Domain' -Action { Join-AIDomain -Context $Context }))
    }

    foreach ($softwareId in @($Context.Department.software)) {
        $software = Get-AISoftwareById -Profile $Context.Profile -Id $softwareId
        $action = {
            Install-AISoftware -Context $Context -Software $software
        }.GetNewClosure()
        $tasks.Add((New-AITask -Id "software.$softwareId" -Name "Install $($software.name)" -Group 'Software' -Action $action))
    }

    if ($Context.Profile.windows.bitLocker.enable) {
        $tasks.Add((New-AITask -Id 'security.bitlocker' -Name 'Enable BitLocker' -Group 'Security' -Action { Enable-AIBitLocker -Context $Context }))
    }

    return $tasks.ToArray()
}

function Invoke-AITaskPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][array]$Tasks,
        [Parameter(Mandatory)][object]$Logger
    )

    Write-AILog -Logger $Logger -Level 'INFO' -Message "Starting AutoInstaller for $($Context.Profile.company), department $($Context.Department.id)"

    foreach ($task in $Tasks) {
        $task.Status = 'Running'
        Write-AILog -Logger $Logger -Level 'INFO' -Message "Running task: $($task.Id)"

        try {
            $result = & $task.Action
            $task.Status = 'Success'
            $task.Message = [string]$result
            Write-AILog -Logger $Logger -Level 'INFO' -Message "$($task.Id): $($task.Message)"
        }
        catch {
            $task.Status = 'Failed'
            $task.Message = $_.Exception.Message
            Write-AILog -Logger $Logger -Level 'ERROR' -Message "$($task.Id): $($task.Message)"
        }

        Save-AIResumeState -Context $Context -Tasks $Tasks
    }
}

function Save-AIResumeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][array]$Tasks
    )

    $directory = Split-Path -Parent $Context.ResumeStatePath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $state = [pscustomobject]@{
        profilePath  = $Context.ProfilePath
        departmentId = $Context.Department.id
        computerName = $Context.ComputerName
        savedAt      = (Get-Date).ToString('s')
        tasks        = $Tasks | Select-Object Id, Status, Message
    }
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Context.ResumeStatePath -Encoding UTF8
}

Export-ModuleMember -Function New-AITaskPlan, Invoke-AITaskPlan, Save-AIResumeState
