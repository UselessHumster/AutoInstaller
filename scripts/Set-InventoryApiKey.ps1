[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$directory = Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$key = Read-Host 'Inventory API key (saved on this portable drive)' -AsSecureString
if ($key.Length -eq 0) { throw 'No API key supplied.' }
$path = Join-Path $directory 'inventory-api-key.txt'
$plainKey = ([pscredential]::new('Inventory', $key)).GetNetworkCredential().Password
Set-Content -LiteralPath $path -Value $plainKey -Encoding UTF8
$plainKey = $null
Write-Output 'Inventory key saved in runtime for use on other computers.'
