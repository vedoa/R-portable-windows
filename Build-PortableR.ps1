[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RVersion
)

$ErrorActionPreference = 'Stop'

$isGitHubActions = $env:GITHUB_ACTIONS -eq 'true'
$tempRoot = if ($isGitHubActions -and -not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    $env:RUNNER_TEMP
}
else {
    $env:TEMP
}
if ([string]::IsNullOrWhiteSpace($tempRoot)) {
    throw 'Neither RUNNER_TEMP nor TEMP is set; cannot choose an installer download directory.'
}

$workspaceRoot = (Resolve-Path -LiteralPath $PSScriptRoot -ErrorAction Stop).Path
$baseInstallerUrl = "https://cran.r-project.org/bin/windows/base/R-$RVersion-win.exe"
$oldInstallerUrl = "https://cran.r-project.org/bin/windows/base/old/$RVersion/R-$RVersion-win.exe"
$installerPath = Join-Path $tempRoot "R-$RVersion-win.exe"
$portableRoot = Join-Path $workspaceRoot "R-portable-$RVersion"

try {
    Write-Host "Downloading R installer from $baseInstallerUrl" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $baseInstallerUrl -OutFile $installerPath -ErrorAction Stop
}
catch {
    $statusCode = $null
    if ($null -ne $_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
        $statusCode = [int]$_.Exception.Response.StatusCode
    }
    if ($statusCode -ne 404) {
        throw
    }

    Write-Host "Downloading R installer from $oldInstallerUrl" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $oldInstallerUrl -OutFile $installerPath -ErrorAction Stop
}

$installerArguments = @(
    '/VERYSILENT'
    "/DIR=`"$portableRoot`""
    '/COMPONENTS=main,x64'
    '/NOREGISTRY'
    '/SUPPRESSMSGBOXES'
    '/NORESTART'
)
Write-Host "Starting headless binary extraction to '$portableRoot'." -ForegroundColor Cyan
$installer = Start-Process -FilePath $installerPath -ArgumentList $installerArguments -Wait -PassThru -ErrorAction Stop
if ($installer.ExitCode -ne 0) {
    throw "R $RVersion installer failed with exit code $($installer.ExitCode)."
}
if (-not (Test-Path -LiteralPath $portableRoot -PathType Container -ErrorAction Stop)) {
    throw "Installer did not create $portableRoot."
}

$profilePath = Join-Path $portableRoot 'etc\Rprofile.site'
@'
Sys.setenv(R_LIBS_USER = "")
.libPaths(.Library)
'@ | Set-Content -LiteralPath $profilePath -Encoding ascii -ErrorAction Stop

$assetPaths = @(
    'doc'
    'tests'
    'Tcl'
    'share\locale'
    'MD5'
    'unins000.dat'
    'unins000.exe'
)
foreach ($relativePath in $assetPaths) {
    $assetPath = Join-Path $portableRoot $relativePath
    Remove-Item -LiteralPath $assetPath -Recurse -Force -ErrorAction SilentlyContinue
}

$libraryRoot = Join-Path $portableRoot 'library'
$packageMetadataDirectories = @('demo', 'doc', 'help', 'html', 'po', 'tests')
foreach ($packageDirectory in (Get-ChildItem -LiteralPath $libraryRoot -Directory -ErrorAction SilentlyContinue)) {
    foreach ($metadataDirectory in $packageMetadataDirectories) {
        $metadataPath = Join-Path $packageDirectory.FullName $metadataDirectory
        Remove-Item -LiteralPath $metadataPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$currentSizeBytes = (Get-ChildItem -LiteralPath $portableRoot -File -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
Write-Host "Runtime size after cleanup: $([Math]::Round($currentSizeBytes / 1MB, 1)) MB. All bundled package directories are retained." -ForegroundColor Cyan

$env:R_HOME = $portableRoot
$env:R_USER = $portableRoot
$env:R_LIBS_USER = ''
$rscriptPath = Join-Path $portableRoot 'bin\x64\Rscript.exe'
if (-not (Test-Path -LiteralPath $rscriptPath -PathType Leaf -ErrorAction Stop)) {
    throw "Rscript.exe was not found at $rscriptPath."
}
Write-Host 'Running isolated environment sanity verification.' -ForegroundColor Yellow
& $rscriptPath -e 'print(R.version.string); print(.libPaths())'
if ($LASTEXITCODE -ne 0) {
    throw "R $RVersion sanity check failed with exit code $LASTEXITCODE."
}

$shortCommit = if ([string]::IsNullOrWhiteSpace($env:GITHUB_SHA)) {
    'local'
}
else {
    $env:GITHUB_SHA.Substring(0, [Math]::Min(7, $env:GITHUB_SHA.Length))
}
if ($isGitHubActions -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "short_sha=$shortCommit" -ErrorAction Stop
}
$archivePath = Join-Path $workspaceRoot "R-portable-$RVersion-$shortCommit-x64.zip"
Write-Host "Optimizations complete. Creating archive at '$archivePath'." -ForegroundColor Green
Compress-Archive -Path (Join-Path $portableRoot '*') -DestinationPath $archivePath -CompressionLevel Optimal -ErrorAction Stop