# Installs everything needed to build ColdVPN on Windows, then builds it.
#   Git                      (winget, git-scm.com)                 ~70 MB
#   VS 2022 Build Tools C++  (winget, Microsoft)                   ~2 GB download, ~7 GB on disk
#   Flutter SDK, stable      (github.com/flutter/flutter + Google) ~1 GB download, ~2.5 GB on disk
# Already installed components are skipped, so the script is safe to re-run.
# Use -UseMirror if storage.googleapis.com / pub.dev are not reachable from your network.
param([switch]$UseMirror)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$project = Split-Path $PSScriptRoot -Parent
$flutterDir = 'C:\src\flutter'

function Step($text) { Write-Host ''; Write-Host "==> $text" -ForegroundColor Cyan }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Test-Url($url) {
    try { Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 15 | Out-Null; return $true }
    catch { return ($null -ne $_.Exception.Response) }   # any HTTP answer means the host is reachable
}

try {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget not found. Install "App Installer" from Microsoft Store and run this file again.'
    }

    Step 'Git'
    if (Get-Command git -ErrorAction SilentlyContinue) { Write-Host 'already installed' }
    else {
        winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
        Refresh-Path
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { $env:Path += ';C:\Program Files\Git\cmd' }
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git installation failed.' }
    }

    Step 'Visual Studio C++ build tools (this is the long part, 15-40 minutes)'
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vc = $null
    if (Test-Path $vswhere) {
        $vc = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    }
    if ($vc) { Write-Host "already installed: $vc" }
    else {
        winget install --id Microsoft.VisualStudio.2022.BuildTools -e --source winget `
            --accept-package-agreements --accept-source-agreements `
            --override '--passive --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
        if (-not (Test-Path $vswhere) -or
            -not (& $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)) {
            throw 'Visual Studio Build Tools installation did not finish. Run this file again; if it repeats, send the text above.'
        }
    }

    Step 'Flutter SDK'
    if ($UseMirror) {
        $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
        $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
        [Environment]::SetEnvironmentVariable('FLUTTER_STORAGE_BASE_URL', $env:FLUTTER_STORAGE_BASE_URL, 'User')
        [Environment]::SetEnvironmentVariable('PUB_HOSTED_URL', $env:PUB_HOSTED_URL, 'User')
        Write-Host 'Using the flutter-io.cn mirror for Flutter downloads.'
    } elseif (-not ((Test-Url 'https://storage.googleapis.com') -and (Test-Url 'https://pub.dev'))) {
        throw ('storage.googleapis.com or pub.dev is not reachable from this network, Flutter cannot download its files. ' +
               'Turn on a VPN and run this file again, or run:  install_and_build.bat -UseMirror')
    }
    if (Get-Command flutter -ErrorAction SilentlyContinue) { Write-Host 'already installed' }
    else {
        if (-not (Test-Path "$flutterDir\bin\flutter.bat")) {
            New-Item -ItemType Directory -Force -Path (Split-Path $flutterDir) | Out-Null
            git clone https://github.com/flutter/flutter.git -b stable --depth 1 $flutterDir
            if ($LASTEXITCODE -ne 0) { throw 'Could not download Flutter from GitHub.' }
        }
        git config --global --add safe.directory ($flutterDir -replace '\\', '/')
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath -notlike "*$flutterDir\bin*") {
            [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ";$flutterDir\bin"), 'User')
        }
        $env:Path += ";$flutterDir\bin"
    }
    flutter --version
    if ($LASTEXITCODE -ne 0) { throw 'Flutter did not start.' }
    flutter doctor

    Step 'Building ColdVPN'
    & "$project\tool\setup_windows.ps1"

    Step 'All done'
    Write-Host "The app: $project\build\windows\x64\runner\Release\ColdVPN.exe" -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Copy the text of this window and send it to Claude.'
    exit 1
}
