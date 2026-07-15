Set-StrictMode -Version Latest

function Get-AIObjectProperty {
    param(
        [Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [object]$DefaultValue = $null
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $DefaultValue
}

function ConvertTo-AISafeFileName {
    param([Parameter(Mandatory)][string]$Value)

    $invalidCharacters = [System.Text.RegularExpressions.Regex]::Escape((-join [System.IO.Path]::GetInvalidFileNameChars()))
    $safeValue = $Value -replace "[$invalidCharacters]", '_'
    $safeValue = $safeValue -replace '\s+', '_'

    if ([string]::IsNullOrWhiteSpace($safeValue)) {
        return 'unknown'
    }

    return $safeValue
}

function Get-AIComputerSerialNumber {
    [CmdletBinding()]
    param()

    $bios = Get-CimInstance -ClassName Win32_BIOS
    $serialNumber = [string]$bios.SerialNumber
    if ([string]::IsNullOrWhiteSpace($serialNumber)) {
        return 'unknown-serial'
    }

    return $serialNumber.Trim()
}

function Get-AIBitLockerRecoveryPassword {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Volume)

    foreach ($keyProtector in @($Volume.KeyProtector)) {
        if ($keyProtector.KeyProtectorType -eq 'RecoveryPassword' -and -not [string]::IsNullOrWhiteSpace([string]$keyProtector.RecoveryPassword)) {
            return [string]$keyProtector.RecoveryPassword
        }
    }

    return $null
}

function Save-AIBitLockerRecoveryFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$SerialNumber,
        [Parameter(Mandatory)][string]$RecoveryKey
    )

    $desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    if ([string]::IsNullOrWhiteSpace($desktopPath)) {
        $desktopPath = Join-Path $env:USERPROFILE 'Desktop'
    }
    if (-not (Test-Path -LiteralPath $desktopPath)) {
        New-Item -ItemType Directory -Path $desktopPath -Force | Out-Null
    }

    $safeComputerName = ConvertTo-AISafeFileName -Value $ComputerName
    $safeSerialNumber = ConvertTo-AISafeFileName -Value $SerialNumber
    $fileName = "BitLocker-$safeComputerName-$safeSerialNumber.txt"
    $filePath = Join-Path $desktopPath $fileName

    $content = @(
        "ComputerName: $ComputerName",
        "SerialNumber: $SerialNumber",
        "RecoveryKey: $RecoveryKey",
        "SavedAt: $((Get-Date).ToString('s'))"
    )
    Set-Content -LiteralPath $filePath -Value $content -Encoding UTF8

    return $filePath
}

function Send-AIBitLockerInventoryRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ApiUrl,
        [string]$ApiKey,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$SerialNumber,
        [Parameter(Mandatory)][string]$RecoveryKey
    )

    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
        $headers['X-API-Key'] = $ApiKey
    }

    $body = @{
        computerName = $ComputerName
        serialNumber = $SerialNumber
        recoveryKey  = $RecoveryKey
    } | ConvertTo-Json -Depth 4

    Invoke-RestMethod -Uri $ApiUrl -Method Post -Headers $headers -ContentType 'application/json' -Body $body | Out-Null
}

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
        $firewallRules = @(Get-NetFirewallRule -Name 'RemoteDesktop*' -ErrorAction SilentlyContinue)
        if ($firewallRules.Count -eq 0) {
            throw 'Remote Desktop firewall rules were not found.'
        }

        $firewallRules | Enable-NetFirewallRule | Out-Null
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
    $targetName = $Context.ComputerName

    Invoke-AICommand -Context $Context -Description "Join domain $domainName" -ScriptBlock {
        $params = @{
            DomainName = $domainName
            Credential = $credential
            Force      = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($ouPath)) {
            $params.OUPath = $ouPath
        }
        if (-not [string]::IsNullOrWhiteSpace($targetName) -and $env:COMPUTERNAME -ne $targetName) {
            $params.NewName = $targetName
        }
        Add-Computer @params
    }
}

function Enable-AIBitLocker {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Context)

    $bitLockerConfig = $Context.Profile.windows.bitLocker
    if (-not $bitLockerConfig.enable) {
        return 'BitLocker skipped: disabled in profile.'
    }

    $inventoryApiConfig = Get-AIObjectProperty -InputObject $bitLockerConfig -Name 'inventoryApi' -DefaultValue ([pscustomobject]@{})
    $inventoryApiEnabled = [bool](Get-AIObjectProperty -InputObject $inventoryApiConfig -Name 'enabled' -DefaultValue $false)
    $inventoryApiUrl = [string](Get-AIObjectProperty -InputObject $inventoryApiConfig -Name 'url' -DefaultValue '')
    $inventoryApiKey = [string](Get-AIObjectProperty -InputObject $inventoryApiConfig -Name 'apiKey' -DefaultValue '')

    Invoke-AICommand -Context $Context -Description 'Enable BitLocker on system drive' -ScriptBlock {
        $mountPoint = $env:SystemDrive
        $serialNumber = Get-AIComputerSerialNumber
        $computerName = if ([string]::IsNullOrWhiteSpace($Context.ComputerName)) { $env:COMPUTERNAME } else { $Context.ComputerName }

        $volume = Get-BitLockerVolume -MountPoint $mountPoint
        $isProtectionOff = $volume.ProtectionStatus -eq 'Off'

        if ($isProtectionOff) {
            Enable-BitLocker -MountPoint $mountPoint -RecoveryPasswordProtector -UsedSpaceOnly -SkipHardwareTest | Out-Null
        }
        else {
            $recoveryKey = Get-AIBitLockerRecoveryPassword -Volume $volume
            if ([string]::IsNullOrWhiteSpace($recoveryKey)) {
                Add-BitLockerKeyProtector -MountPoint $mountPoint -RecoveryPasswordProtector | Out-Null
            }
        }

        $volume = Get-BitLockerVolume -MountPoint $mountPoint
        $recoveryKey = Get-AIBitLockerRecoveryPassword -Volume $volume

        if ([string]::IsNullOrWhiteSpace($recoveryKey)) {
            throw 'BitLocker recovery password protector was not found after creation.'
        }

        $recoveryFilePath = Save-AIBitLockerRecoveryFile -ComputerName $computerName -SerialNumber $serialNumber -RecoveryKey $recoveryKey
        $inventoryStatus = 'inventory API disabled'

        if ($inventoryApiEnabled) {
            if ([string]::IsNullOrWhiteSpace($inventoryApiUrl)) {
                throw 'BitLocker inventory API is enabled, but no URL is configured.'
            }

            Send-AIBitLockerInventoryRecord -ApiUrl $inventoryApiUrl -ApiKey $inventoryApiKey -ComputerName $computerName -SerialNumber $serialNumber -RecoveryKey $recoveryKey
            $inventoryStatus = 'inventory API submitted'
        }

        return "BitLocker enabled; recovery key saved to $recoveryFilePath; $inventoryStatus."
    }
}

Export-ModuleMember -Function Set-AIPowerPolicy, Enable-AIRemoteDesktop, Rename-AIComputer, Join-AIDomain, Enable-AIBitLocker
