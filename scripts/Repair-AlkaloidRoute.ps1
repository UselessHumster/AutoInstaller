[CmdletBinding()]
param([switch]$DryRun)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/AutoInstaller.Config.psm1') -Force
Import-Module (Join-Path $root 'modules/AutoInstaller.Context.psm1') -Force
Import-Module (Join-Path $root 'modules/AutoInstaller.SystemTasks.psm1') -Force
$context = [pscustomobject]@{
    Profile = Import-AIProfile (Join-Path $root 'profiles/alkaloid.yaml')
    DryRun = [bool]$DryRun
    IsWindows = Test-AIWindows
    IsAdministrator = Test-AIAdministrator
}
$log = Join-Path $root 'logs/route-repair.log'
try {
    Set-AIStaticRoutes -Context $context | Tee-Object -FilePath $log
    Set-AIStaticRoutes -Context $context | Tee-Object -FilePath $log -Append
    if (-not $DryRun) {
        $result = & nltest.exe /dsgetdc:alkaloidad.local /force 2>&1
        $code = $LASTEXITCODE
        $result | Tee-Object -FilePath $log -Append
        if ($code -ne 0) { throw "Domain controller discovery failed: $code" }
    }
}
catch {
    $_.Exception.Message | Add-Content -LiteralPath $log
    throw
}
