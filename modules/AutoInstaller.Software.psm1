Set-StrictMode -Version Latest

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

    Invoke-AICommand -Context $Context -Description "Install $($Software.name)" -ScriptBlock {
        if ($kind -eq 'msi') {
            $msiArgs = "/i `"$installerPath`" $arguments"
            $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
        }
        else {
            $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -PassThru
        }

        if ($process.ExitCode -notin @(0, 3010, 1641)) {
            throw "Installer failed with exit code $($process.ExitCode): $($Software.name)"
        }

        if ($process.ExitCode -in @(3010, 1641)) {
            return "Installed, reboot required: $($Software.name)"
        }

        return "Installed: $($Software.name)"
    }
}

Export-ModuleMember -Function Test-AISoftwareInstalled, Install-AISoftware
