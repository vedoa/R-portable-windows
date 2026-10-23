[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$localFolder = (Resolve-Path -LiteralPath $PSScriptRoot -ErrorAction Stop).Path
$templatePath = Join-Path $localFolder 'TestEnv.wsb'
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf -ErrorAction Stop)) {
    throw "Windows Sandbox template was not found: $templatePath."
}

[xml]$configuration = Get-Content -LiteralPath $templatePath -Raw -ErrorAction Stop
$configurationRoot = $configuration.DocumentElement
$networkingNode = $configuration.SelectSingleNode('/Configuration/Networking')
if ($null -eq $networkingNode) {
    $networkingNode = $configuration.CreateElement('Networking')
    $networkingNode.InnerText = 'Default'
    $configurationRoot.PrependChild($networkingNode) | Out-Null
}
else {
    $networkingNode.InnerText = 'Default'
    $configurationRoot.PrependChild($networkingNode) | Out-Null
}

$hostFolderNode = $configuration.SelectSingleNode('/Configuration/MappedFolders/MappedFolder/HostFolder')
if ($null -eq $hostFolderNode) {
    throw "The Sandbox configuration does not contain a mapped HostFolder: $templatePath."
}
$hostFolderNode.InnerText = $localFolder

$sandboxFolderNode = $configuration.SelectSingleNode('/Configuration/MappedFolders/MappedFolder/SandboxFolder')
$commandNode = $configuration.SelectSingleNode('/Configuration/LogonCommand/Command')
if ($null -eq $sandboxFolderNode -or $null -eq $commandNode) {
    throw "The Sandbox configuration is missing its mapped folder or logon command: $templatePath."
}
$sandboxFolder = $sandboxFolderNode.InnerText
$powerShellCommand = "Set-DnsClientServerAddress -InterfaceIndex (Get-NetAdapter).InterfaceIndex -ServerAddresses ('8.8.8.8','1.1.1.1'); Set-Location -LiteralPath '$sandboxFolder'; .\Test-PortableR.ps1"
$commandNode.InnerText = "cmd.exe /c start `"Portable R test`" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -Command `"$powerShellCommand`""

$temporaryConfigurationPath = Join-Path ([IO.Path]::GetTempPath()) "R-portable-sandbox-$([guid]::NewGuid().ToString('N')).wsb"
$configuration.Save($temporaryConfigurationPath)

$sandboxExecutable = Join-Path $env:WINDIR 'System32\WindowsSandbox.exe'
if (-not (Test-Path -LiteralPath $sandboxExecutable -PathType Leaf -ErrorAction Stop)) {
    throw "Windows Sandbox executable was not found: $sandboxExecutable."
}

Write-Host "Launching Windows Sandbox with local folder '$localFolder'." -ForegroundColor Cyan
Start-Process -FilePath $sandboxExecutable -ArgumentList @("`"$temporaryConfigurationPath`"") -ErrorAction Stop
