[CmdletBinding()]
param(
    [ValidateSet('4.6.2', '4.5.3', '4.4.3')]
    [string]$RVersion = '4.6.2'
)

$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path -LiteralPath $PSScriptRoot -ErrorAction Stop).Path
$portableRoot = Join-Path $workspaceRoot "R-portable-$RVersion"
$installerPath = Join-Path ([IO.Path]::GetTempPath()) "R-$RVersion-$([guid]::NewGuid().ToString('N'))-win.exe"

if (Test-Path -LiteralPath $portableRoot -ErrorAction Stop) {
    throw "Output directory already exists: $portableRoot. Remove it before running the test again."
}

try {
    $installerUrl = "https://cran.r-project.org/bin/windows/base/R-$RVersion-win.exe"
    Write-Host "Downloading R installer from $installerUrl (progress display disabled)." -ForegroundColor Cyan
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
    }
    catch {
        $statusCode = $null
        if ($null -ne $_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($statusCode -ne 404) {
            throw
        }

        $installerUrl = "https://cran.r-project.org/bin/windows/base/old/$RVersion/R-$RVersion-win.exe"
        Write-Host "R $RVersion not found at the primary endpoint; switching to the CRAN archival fallback repository." -ForegroundColor Yellow
        Write-Host "Downloading R installer from $installerUrl (progress display disabled)." -ForegroundColor Cyan
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
    }

    $installerArguments = @(
        '/SILENT'
        "/DIR=`"$portableRoot`""
        '/COMPONENTS=main,x64'
        '/NOREGISTRY'
        '/SUPPRESSMSGBOXES'
        '/NORESTART'
    )
    Write-Host "Unpacking and extracting R binaries to disk. This will take a moment, please wait..." -ForegroundColor Yellow
    $installer = Start-Process -FilePath $installerPath -ArgumentList $installerArguments -Wait -PassThru -ErrorAction Stop
    if ($installer.ExitCode -eq 0) {
        Write-Host "Extraction complete. Proceeding to environment optimization..." -ForegroundColor Green
    }
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

    $rscriptPath = Join-Path $portableRoot 'bin\x64\Rscript.exe'
    if (-not (Test-Path -LiteralPath $rscriptPath -PathType Leaf -ErrorAction Stop)) {
        throw "Rscript.exe was not found at $rscriptPath."
    }

    $env:R_HOME = $portableRoot
    $env:R_USER = $portableRoot
    $env:R_LIBS_USER = ''
    $validationExpression = "cat('R_VERSION=', as.character(getRversion()), '\n', sep=''); cat('LIB_PATHS=', paste(normalizePath(.libPaths(), winslash='/'), collapse=';'), '\n', sep='')"
    Write-Host 'Running isolated environment sanity verification.' -ForegroundColor Yellow
    $validationOutput = & $rscriptPath -e $validationExpression 2>&1
    $exitCode = $LASTEXITCODE
    $resultText = ($validationOutput | Out-String).Trim()
    Write-Output $resultText

    if ($exitCode -ne 0) {
        throw "R $RVersion sanity check failed with exit code $exitCode."
    }
    if ($resultText -notmatch [regex]::Escape("R_VERSION=$RVersion")) {
        throw 'Sanity check returned an unexpected R version.'
    }

    $libraryLine = $resultText -split "`r?`n" | Where-Object { $_ -like 'LIB_PATHS=*' } | Select-Object -First 1
    $libraryPaths = if ($libraryLine) { $libraryLine.Substring('LIB_PATHS='.Length).Split(';') } else { @() }
    $expectedLibrary = [IO.Path]::GetFullPath((Join-Path $portableRoot 'library')).Replace('/', '\').TrimEnd('\')
    $normalizedLibraryPaths = @($libraryPaths | ForEach-Object {
            [IO.Path]::GetFullPath($_).Replace('/', '\').TrimEnd('\')
        })
    if ($normalizedLibraryPaths.Count -ne 1 -or $normalizedLibraryPaths[0] -ne $expectedLibrary) {
        throw "R library paths are not isolated to the packaged library: $($libraryPaths -join '; ')."
    }

    Write-Output "Portable R $RVersion passed validation at $portableRoot."
}
finally {
    if (Test-Path -LiteralPath $installerPath -PathType Leaf -ErrorAction Stop) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction Stop
    }
}
