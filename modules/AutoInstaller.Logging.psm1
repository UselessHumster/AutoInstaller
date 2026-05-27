Set-StrictMode -Version Latest

function New-AILogger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogRoot
    )

    if (-not (Test-Path -LiteralPath $LogRoot)) {
        New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $runDirectory = Join-Path $LogRoot $stamp
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

    [pscustomobject]@{
        RunDirectory = $runDirectory
        LogFile      = Join-Path $runDirectory 'run.log'
        ReportFile   = Join-Path $runDirectory 'report.csv'
    }
}

function Write-AILog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Logger,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory)]
        [string]$Message
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 's'), $Level, $Message
    Add-Content -LiteralPath $Logger.LogFile -Value $line
    Write-Host $line
}

function Export-AIRunReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,
        [Parameter(Mandatory)]
        [array]$Tasks,
        [Parameter(Mandatory)]
        [object]$Logger
    )

    $Tasks |
        Select-Object Id, Name, Group, Status, Message |
        Export-Csv -LiteralPath $Logger.ReportFile -NoTypeInformation -Encoding UTF8

    Write-AILog -Logger $Logger -Level 'INFO' -Message "Report written: $($Logger.ReportFile)"
}

Export-ModuleMember -Function New-AILogger, Write-AILog, Export-AIRunReport
