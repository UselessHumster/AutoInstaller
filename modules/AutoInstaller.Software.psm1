Set-StrictMode -Version Latest

function Get-AIPropertyValue {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$Name,
        [object]$DefaultValue = $null
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $DefaultValue
}

function Test-AISoftwareInstalled {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Software)

    if (-not $Software.detection) {
        return $false
    }

    switch ($Software.detection.type) {
        'file' {
            return Test-Path -LiteralPath ([string]$Software.detection.path)
        }
        'registry' {
            $isWindowsVariable = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
            $isWindows = if ($isWindowsVariable) { [bool]$isWindowsVariable.Value } else { $PSVersionTable.PSEdition -eq 'Desktop' }
            if (-not $isWindows) {
                return $false
            }
            return Test-Path -LiteralPath ([string]$Software.detection.path)
        }
        'command' {
            $command = Get-Command ([string]$Software.detection.command) -ErrorAction SilentlyContinue
            return [bool]$command
        }
        'service' {
            return [bool](Get-Service -Name ([string]$Software.detection.name) -ErrorAction SilentlyContinue)
        }
        default {
            return $false
        }
    }
}

function Install-AISoftware {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,
        [Parameter(Mandatory)]
        [object]$Software
    )

    if (-not $Context.DryRun -and (Test-AISoftwareInstalled -Software $Software)) {
        return "Already installed: $($Software.name)"
    }

    $installerPath = Resolve-AIPath -BasePath $Context.ProfilePath -Path ([string]$Software.installer.path)
    if (-not $Context.DryRun -and -not (Test-Path -LiteralPath $installerPath)) {
        throw "Installer not found for $($Software.name): $installerPath"
    }

    $kind = [string]$Software.installer.type
    $arguments = [string]$Software.installer.arguments
    $continueWhenDetected = [bool](Get-AIPropertyValue -InputObject $Software.installer -Name 'continueWhenDetected' -DefaultValue $false)
    $stopProcessesOnDetected = @(Get-AIPropertyValue -InputObject $Software.installer -Name 'stopProcessesOnDetected' -DefaultValue @())
    $timeoutSeconds = [int](Get-AIPropertyValue -InputObject $Software.installer -Name 'timeoutSeconds' -DefaultValue 0)
    $copyToTemp = [bool](Get-AIPropertyValue -InputObject $Software.installer -Name 'copyToTemp' -DefaultValue $false)
    $detectionTimeoutSeconds = [int](Get-AIPropertyValue -InputObject $Software.installer -Name 'detectionTimeoutSeconds' -DefaultValue 0)

    Invoke-AICommand -Context $Context -Description "Install $($Software.name)" -ScriptBlock {
        $startedAt = Get-Date
        $effectiveInstallerPath = $installerPath
        $tempInstallerPath = $null

        try {
            if ($copyToTemp) {
                $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'AutoInstaller\Installers'
                if (-not (Test-Path -LiteralPath $tempRoot)) {
                    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
                }

                $installerFileName = Split-Path -Leaf $installerPath
                $tempInstallerPath = Join-Path $tempRoot ("{0}-{1}" -f ([guid]::NewGuid().ToString('N')), $installerFileName)
                Copy-Item -LiteralPath $installerPath -Destination $tempInstallerPath -Force
                $effectiveInstallerPath = $tempInstallerPath
            }

            if ($kind -eq 'msi') {
                $msiArgs = "/i `"$effectiveInstallerPath`" $arguments"
                $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -PassThru
            }
            elseif ($kind -eq 'bat') {
                $process = Start-Process -FilePath $env:ComSpec -ArgumentList "/d /s /c `"`"$effectiveInstallerPath`" $arguments`"" -WorkingDirectory (Split-Path -Parent $effectiveInstallerPath) -PassThru
            }
            elseif ($kind -eq 'exe') {
                $startParameters = @{
                    FilePath = $effectiveInstallerPath
                    WorkingDirectory = Split-Path -Parent $effectiveInstallerPath
                    PassThru = $true
                }
                if (-not [string]::IsNullOrWhiteSpace($arguments)) {
                    $startParameters.ArgumentList = $arguments
                }
                $process = Start-Process @startParameters
            }
            else {
                throw "Unsupported installer type: $kind"
            }

            while (-not $process.HasExited) {
                Start-Sleep -Seconds 1

                if ($continueWhenDetected -and (Test-AISoftwareInstalled -Software $Software)) {
                    foreach ($processName in $stopProcessesOnDetected) {
                        Get-Process -Name ([string]$processName) -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                    }

                    if (-not $process.HasExited) {
                        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                    }

                    return "Installed: $($Software.name)"
                }

                if ($timeoutSeconds -gt 0 -and ((Get-Date) - $startedAt).TotalSeconds -ge $timeoutSeconds) {
                    if (Test-AISoftwareInstalled -Software $Software) {
                        foreach ($processName in $stopProcessesOnDetected) {
                            Get-Process -Name ([string]$processName) -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                        }

                        if (-not $process.HasExited) {
                            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                        }

                        return "Installed: $($Software.name)"
                    }

                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                    throw "Installer timed out after $timeoutSeconds seconds: $($Software.name)"
                }
            }

            $process.WaitForExit()
            if ($process.ExitCode -notin @(0, 3010, 1641)) {
                throw "Installer failed with exit code $($process.ExitCode): $($Software.name)"
            }

            if ($detectionTimeoutSeconds -gt 0) {
                $deadline = (Get-Date).AddSeconds($detectionTimeoutSeconds)
                while (-not (Test-AISoftwareInstalled -Software $Software)) {
                    if ((Get-Date) -ge $deadline) {
                        throw "Installer exited but installed-state detection failed: $($Software.name)"
                    }
                    Start-Sleep -Seconds 2
                }
            }

            if ($process.ExitCode -in @(3010, 1641)) {
                return "Installed, reboot required: $($Software.name)"
            }

            return "Installed: $($Software.name)"
        }
        finally {
            if ($tempInstallerPath -and (Test-Path -LiteralPath $tempInstallerPath)) {
                Remove-Item -LiteralPath $tempInstallerPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Export-ModuleMember -Function Test-AISoftwareInstalled, Install-AISoftware
