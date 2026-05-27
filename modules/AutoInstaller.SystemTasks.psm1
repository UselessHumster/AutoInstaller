Set-StrictMode -Version Latest

function Set-AIPowerPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Context)

    $minutes = [int]$Context.Profile.windows.power.acSleepTimeoutMinutes
    Invoke-AICommand -Context $Context -Description "Set AC sleep timeout to $minutes minutes" -ScriptBlock {
        powercfg /change standby-timeout-ac $minutes | Out-Null
        powercfg /change hibernate-timeout-ac 0 | Out-Null
    }
}

function Enable-AIRemoteDesktop {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Context)

    Invoke-AICommand -Context $Context -Description 'Enable Remote Desktop' -ScriptBlock {
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
        Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' | Out-Null
    }
}

function Rename-AIComputer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Context)

    $targetName = $Context.ComputerName
    if ([string]::IsNullOrWhiteSpace($targetName)) {
        return 'Computer rename skipped: no computer name was provided.'
    }

    Invoke-AICommand -Context $Context -Description "Rename computer to $targetName" -ScriptBlock {
        if ($env:COMPUTERNAME -ne $targetName) {
            Rename-Computer -NewName $targetName -Force
        }
    }
}

function Join-AIDomain {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Context)

    $domain = $Context.Department.domain
    if (-not $domain -or -not $domain.name) {
        return 'Domain join skipped: department has no domain configured.'
    }

    $domainName = [string]$domain.name
    $ouPath = [string]$domain.ouPath
    $credential = $Context.DomainCredential

    Invoke-AICommand -Context $Context -Description "Join domain $domainName" -ScriptBlock {
        $params = @{
            DomainName = $domainName
            Credential = $credential
            Force      = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($ouPath)) {
            $params.OUPath = $ouPath
        }
        Add-Computer @params
    }
}

function Enable-AIBitLocker {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Context)

    if (-not $Context.Profile.windows.bitLocker.enable) {
        return 'BitLocker skipped: disabled in profile.'
    }

    Invoke-AICommand -Context $Context -Description 'Enable BitLocker on system drive' -ScriptBlock {
        Enable-BitLocker -MountPoint $env:SystemDrive -RecoveryPasswordProtector -UsedSpaceOnly -SkipHardwareTest
    }
}

Export-ModuleMember -Function Set-AIPowerPolicy, Enable-AIRemoteDesktop, Rename-AIComputer, Join-AIDomain, Enable-AIBitLocker
