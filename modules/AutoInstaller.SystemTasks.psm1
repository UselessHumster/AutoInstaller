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

function Test-AIBitLockerRecoveryPasswordFormat {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RecoveryKey)

    return $RecoveryKey -match '^\d{6}(-\d{6}){7}$'
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
    $fileName = "$safeComputerName $safeSerialNumber.txt"
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
        [Parameter(Mandatory)][string]$ApiKey,
        [Parameter(Mandatory)][string]$SerialNumber,
        [Parameter(Mandatory)][string]$RecoveryKey
    )

    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        throw 'BitLocker inventory API is enabled, but no API key is configured.'
    }

    if (-not (Test-AIBitLockerRecoveryPasswordFormat -RecoveryKey $RecoveryKey)) {
        throw 'BitLocker recovery key does not match the expected eight-group recovery password format.'
    }

    $body = @{
        serial_number = $SerialNumber
        bitlocker_key = $RecoveryKey
    } | ConvertTo-Json -Depth 4

    $headers = @{
        'X-API-Key' = $ApiKey
    }

    try {
        $response = Invoke-WebRequest -Uri $ApiUrl -Method Post -Headers $headers -ContentType 'application/json' -Body $body -UseBasicParsing
        if ($response.StatusCode -notin @(200, 201)) {
            throw "BitLocker inventory API returned unexpected HTTP status $($response.StatusCode)."
        }
    }
    catch {
        $response = $_.Exception.Response
        if (-not $response) {
            throw
        }

        $statusCode = [int]$response.StatusCode
        switch ($statusCode) {
            401 { throw 'BitLocker inventory API rejected the request with HTTP 401. Check the API key.' }
            409 { throw 'BitLocker inventory API returned HTTP 409. Equipment belongs to another company; do not move it automatically.' }
            422 { throw 'BitLocker inventory API returned HTTP 422. Check that the payload contains a valid BitLocker Recovery Password with eight six-digit groups.' }
            default { throw "BitLocker inventory API returned HTTP $statusCode." }
        }
    }
}

function Set-AIStaticRoutes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Context)

    $routes = @(Get-AIObjectProperty -InputObject $Context.Profile.windows -Name 'routes' -DefaultValue @())
    foreach ($route in $routes) {
        $prefix = [string]$route.destinationPrefix
        $gateway = [string]$route.nextHop
        Invoke-AICommand -Context $Context -Description "Ensure persistent route $prefix via $gateway" -ScriptBlock {
            $interfaces = @(Find-NetRoute -RemoteIPAddress $gateway -ErrorAction Stop | Where-Object { $_.PSObject.Properties['IPAddress'] })
            if ($interfaces.Count -ne 1) {
                throw "Cannot determine interface for route gateway $gateway."
            }
            $interfaceIndex = $interfaces[0].InterfaceIndex
            foreach ($store in @('PersistentStore', 'ActiveStore')) {
                $existing = @(Get-NetRoute -DestinationPrefix $prefix -PolicyStore $store -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -eq $gateway -and $_.InterfaceIndex -eq $interfaceIndex })
                if ($existing.Count -eq 0) {
                    if ($store -eq 'PersistentStore') {
                        # New-NetRoute rejects an explicit PersistentStore on some Windows versions.
                        # route.exe -p records the route persistently and activates it immediately.
                        $parts = $prefix.Split('/')
                        if ($parts.Count -ne 2 -or [int]$parts[1] -lt 0 -or [int]$parts[1] -gt 32) {
                            throw "Invalid IPv4 route prefix: $prefix"
                        }
                        $bits = [int]$parts[1]
                        $mask = (@(0..3 | ForEach-Object {
                            $count = [Math]::Min(8, [Math]::Max(0, $bits - 8 * $_))
                            [int](256 - [Math]::Pow(2, 8 - $count))
                        }) -join '.')
                        $output = & route.exe -p ADD $parts[0] MASK $mask $gateway IF $interfaceIndex 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            throw "Persistent route creation failed: $prefix via $gateway. $output"
                        }
                    }
                    else {
                        New-NetRoute -DestinationPrefix $prefix -NextHop $gateway -InterfaceIndex $interfaceIndex -PolicyStore ActiveStore -ErrorAction Stop | Out-Null
                    }
                }
            }
            foreach ($store in @('PersistentStore', 'ActiveStore')) {
                $verified = @(Get-NetRoute -DestinationPrefix $prefix -PolicyStore $store -ErrorAction Stop | Where-Object { $_.NextHop -eq $gateway })
                if ($verified.Count -eq 0) { throw "Route verification failed in ${store}: $prefix via $gateway" }
            }
            "Route ready: $prefix via $gateway"
        }
    }
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
        $system = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($system.PartOfDomain) {
            if ($system.Domain -ine $domainName) { throw "Computer already belongs to another domain: $($system.Domain)" }
            Rename-AIComputer -Context $Context
            return "Already joined to $domainName; restart if computer was renamed."
        }
        $routes = @(Get-AIObjectProperty -InputObject $Context.Profile.windows -Name 'routes' -DefaultValue @())
        foreach ($route in $routes) {
            $ready = @(Get-NetRoute -DestinationPrefix $route.destinationPrefix -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -eq $route.nextHop })
            if ($ready.Count -eq 0) { throw "Domain join blocked: required route $($route.destinationPrefix) via $($route.nextHop) is missing." }
        }
        $null = & nltest.exe "/dsgetdc:$domainName" /force 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Domain controller discovery failed for $domainName. Check routes, DNS and domain connectivity." }
        if (-not $credential) {
            $credential = Get-Credential -Message "Credentials for joining $domainName"
            if (-not $credential) { throw 'Domain credentials were not supplied.' }
        }
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
        Add-Computer @params -ErrorAction Stop
        return "Joined $domainName; restart required."
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

            Send-AIBitLockerInventoryRecord -ApiUrl $inventoryApiUrl -ApiKey $inventoryApiKey -SerialNumber $serialNumber -RecoveryKey $recoveryKey
            $inventoryStatus = 'inventory API submitted'
        }

        return "BitLocker enabled; recovery key saved to $recoveryFilePath; $inventoryStatus."
    }
}

function Set-AIInputLanguage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Context)
    $settings = $Context.Profile.windows.inputLanguage
    Invoke-AICommand -Context $Context -Description "Set $($settings.languageTag) first and default input method $($settings.inputMethodTip) for current user" -ScriptBlock {
        $languages = Get-WinUserLanguageList
        $preferred = New-WinUserLanguageList -Language $settings.languageTag
        $preferred[0].InputMethodTips.Clear()
        $preferred[0].InputMethodTips.Add([string]$settings.inputMethodTip)
        foreach ($language in $languages) {
            if ($language.LanguageTag -ine $settings.languageTag) { $preferred.Add($language) }
        }
        Set-WinUserLanguageList -LanguageList $preferred -Force
        Set-WinDefaultInputMethodOverride -InputTip $settings.inputMethodTip
        return 'Default input configured for current user; other languages preserved.'
    }
}

function Copy-AIProfileFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Context)
    $copies = @($Context.Profile.windows.fileCopies)
    foreach ($copy in $copies) {
        $source = Resolve-AIPath -BasePath $Context.ProfilePath -Path $copy.source
        if (-not $Context.DryRun -and -not (Test-Path -LiteralPath $source -PathType Container)) {
            throw "Copy source directory not found: $source"
        }
    }
    foreach ($copy in $copies) {
        $source = Resolve-AIPath -BasePath $Context.ProfilePath -Path $copy.source
        $destination = [Environment]::ExpandEnvironmentVariables([string]$copy.destination)
        Invoke-AICommand -Context $Context -Description "Copy $source to $destination" -ScriptBlock {
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
            foreach ($item in @(Get-ChildItem -LiteralPath $source -Force)) {
                Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force -ErrorAction Stop
            }
            return "Files copied to $destination."
        }
    }
}

Export-ModuleMember -Function Set-AIInputLanguage, Copy-AIProfileFiles, Set-AIStaticRoutes, Set-AIPowerPolicy, Enable-AIRemoteDesktop, Rename-AIComputer, Join-AIDomain, Enable-AIBitLocker
