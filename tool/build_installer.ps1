# Builds the app and packs it into a Windows installer (dist\ColdVPN-Setup-<version>.exe).
# Run through build_installer.bat.
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
Set-Location $project

function Step($text) { Write-Host ''; Write-Host "==> $text" -ForegroundColor Cyan }

try {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'User')

    Step 'Building ColdVPN'
    & "$project\tool\setup_windows.ps1"
    Set-Location $project

    Step 'Inno Setup'
    function Find-Iscc {
        $candidates = @(
            (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
            (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
        )
        foreach ($path in $candidates) { if (Test-Path $path) { return $path } }
        return $null
    }
    $iscc = Find-Iscc
    if (-not $iscc) {
        Write-Host 'Installing Inno Setup...'
        winget install -e --id JRSoftware.InnoSetup --accept-source-agreements --accept-package-agreements --silent
        $iscc = Find-Iscc
    }
    if (-not $iscc) { throw 'Inno Setup was not found. Install it from https://jrsoftware.org/isdl.php and run again.' }
    Write-Host "Using $iscc"

    Step 'Collecting files'
    $release = Join-Path $project 'build\windows\x64\runner\Release'
    if (-not (Test-Path (Join-Path $release 'ColdVPN.exe'))) { throw "ColdVPN.exe was not found in $release" }
    $stage = Join-Path $project 'build\installer\app'
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Copy-Item (Join-Path $release 'ColdVPN.exe') $stage
    Copy-Item (Join-Path $release '*.dll') $stage
    Copy-Item (Join-Path $release 'data') $stage -Recurse
    # Visual C++ runtime next to the app, so that it starts on a clean Windows.
    foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
        $source = Join-Path $env:SystemRoot "System32\$dll"
        if (Test-Path $source) { Copy-Item $source $stage -Force }
        else { Write-Host "Warning: $dll was not found, the installer will not include it." -ForegroundColor Yellow }
    }

    $version = '0.0.0'
    $match = Select-String -Path (Join-Path $project 'pubspec.yaml') -Pattern '^version:\s*([0-9.]+)' | Select-Object -First 1
    if ($match) { $version = $match.Matches[0].Groups[1].Value }

    Step "Packing the installer, version $version"
    & $iscc "/DAppVersion=$version" "/DSourceDir=$stage" (Join-Path $project 'installer\coldvpn.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed.' }

    $setup = Join-Path $project "dist\ColdVPN-Setup-$version.exe"
    Step 'All done'
    Write-Host "The installer: $setup" -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Copy the text of this window and send it to Claude.'
    exit 1
}
