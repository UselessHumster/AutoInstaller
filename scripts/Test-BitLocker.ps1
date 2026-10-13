[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Import-Module (Join-Path $root 'modules/AutoInstaller.SystemTasks.psm1') -Force -PassThru
& $module {
    function script:Invoke-AICommand { param($Context, $Description, $ScriptBlock) & $ScriptBlock }
    function script:Get-AIComputerSerialNumber { 'TEST-SERIAL' }
    function script:Get-ItemProperty { param($LiteralPath, $Name, $ErrorAction) [pscustomobject]@{ComputerName='PCRUS123'} }
    function script:Get-Tpm { [pscustomobject]@{TpmPresent=$true;TpmReady=$true} }
    function script:Get-BitLockerVolume { param($MountPoint) $script:testVolume }
    function script:Add-BitLockerKeyProtector {
        param($MountPoint, [switch]$RecoveryPasswordProtector)
        $script:addCount++
        $script:testVolume.KeyProtector = @([pscustomobject]@{KeyProtectorType='RecoveryPassword';RecoveryPassword=('000000-' * 7 + '000000')})
    }
    function script:Enable-BitLocker { param($MountPoint,[switch]$TpmProtector,[switch]$UsedSpaceOnly,[switch]$SkipHardwareTest) $script:enableCount++ }
    function script:Resume-BitLocker { param($MountPoint) $script:resumeCount++ }
    function script:Save-AIBitLockerRecoveryFile { param($ComputerName,$SerialNumber,$RecoveryKey) 'TEST-RECOVERY-FILE' }
    function script:Get-AIInventoryApiKey { param($Config,$ProfilePath) 'test-api-key' }
    function script:Invoke-WebRequest {
        param($Uri,$Method,$Headers,$ContentType,$Body,[switch]$UseBasicParsing)
        if ($script:apiFails) { throw 'Simulated transport failure' }
        $script:sentBody = $Body | ConvertFrom-Json
        [pscustomobject]@{StatusCode=201}
    }
    $context = [pscustomobject]@{
        ComputerName='PCRUS123';ProfilePath='test-profile.yaml'
        Profile=[pscustomobject]@{windows=[pscustomobject]@{bitLocker=[pscustomobject]@{
            enable=$true;inventoryApi=[pscustomobject]@{enabled=$true;url='https://inventory.example/api/bitlocker-keys'}
        }}}
    }
    foreach ($scenario in @('new','repeat','suspended','api-failure','rename-failure')) {
        $script:addCount=0; $script:enableCount=0; $script:resumeCount=0; $script:sentBody=$null
        $script:apiFails = $scenario -eq 'api-failure'
        $context.ComputerName = if ($scenario -eq 'rename-failure') { 'UNAPPLIED' } else { 'PCRUS123' }
        $script:testVolume=[pscustomobject]@{
            VolumeStatus= if ($scenario -in @('new','api-failure','rename-failure')) { 'FullyDecrypted' } else { 'FullyEncrypted' }
            ProtectionStatus= if ($scenario -eq 'repeat') { 'On' } else { 'Off' }
            KeyProtector= if ($scenario -in @('repeat','suspended')) { @([pscustomobject]@{KeyProtectorType='RecoveryPassword';RecoveryPassword=('000000-' * 7 + '000000')}) } else { @() }
        }
        $failed=$false
        try { Enable-AIBitLocker -Context $context | Out-Null } catch { $failed=$true }
        if ($scenario -in @('api-failure','rename-failure')) {
            if (-not $failed -or $script:enableCount -ne 0 -or $script:resumeCount -ne 0) { throw "Unsafe failure behavior: $scenario" }
        }
        else {
            if ($failed -or $script:sentBody.device_name -ne 'PCRUS123' -or $script:sentBody.serial_number -ne 'TEST-SERIAL') { throw "Inventory payload failed: $scenario" }
            if ($scenario -eq 'new' -and ($script:enableCount -ne 1 -or $script:addCount -ne 1)) { throw 'New encryption failed' }
            if ($scenario -eq 'repeat' -and ($script:enableCount -ne 0 -or $script:addCount -ne 0)) { throw 'Repeat run added duplicate protectors' }
            if ($scenario -eq 'suspended' -and $script:resumeCount -ne 1) { throw 'Suspended protection not resumed' }
        }
        Write-Output "PASS: $scenario"
    }
}
