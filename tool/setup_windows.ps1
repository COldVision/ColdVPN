# One-time project setup and release build for Windows.
# Run from a normal PowerShell window:  powershell -ExecutionPolicy Bypass -File tool\setup_windows.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter SDK is not installed or not in PATH. See https://docs.flutter.dev/get-started/install/windows'
}

# 1. Generate the Windows runner (does not touch lib/ or pubspec.yaml).
if (-not (Test-Path 'windows\runner')) {
    flutter create --platforms=windows --project-name split_vpn --org com.splitvpn .
    if ($LASTEXITCODE -ne 0) { throw 'flutter create failed' }
    if (Test-Path 'test\widget_test.dart') { Remove-Item 'test\widget_test.dart' }
}

# 2. The app must run elevated: the tunnel creates a network adapter and adds routes.
#    The level is set through the linker; a trustInfo block in the manifest
#    would clash with the one the linker generates (LNK1327, mt.exe).
$utf8 = New-Object Text.UTF8Encoding $false
$manifest = Join-Path (Get-Location) 'windows\runner\runner.exe.manifest'
$text = [IO.File]::ReadAllText($manifest)
if ($text -match '<trustInfo') {
    $text = [regex]::Replace($text, '(?s)\s*<trustInfo.*?</trustInfo>', '')
    [IO.File]::WriteAllText($manifest, $text, $utf8)
}
$cmake = Join-Path (Get-Location) 'windows\runner\CMakeLists.txt'
$text = [IO.File]::ReadAllText($cmake)
if ($text -notmatch 'MANIFESTUAC') {
    $text = $text.TrimEnd() + "`r`n`r`n# ColdVPN: run elevated.`r`n" +
        'set_target_properties(${BINARY_NAME} PROPERTIES LINK_FLAGS "/MANIFESTUAC:\"level=''requireAdministrator'' uiAccess=''false''\"")' + "`r`n"
    [IO.File]::WriteAllText($cmake, $text, $utf8)
    Write-Host 'Build settings patched: requireAdministrator'
}

# 3. Window title and size: a tall phone-like window, the same layout as on Android.
$main = Join-Path (Get-Location) 'windows\runner\main.cpp'
$text = [IO.File]::ReadAllText($main)
$patched = [regex]::Replace($text, 'Win32Window::Size size\(\d+, \d+\)', 'Win32Window::Size size(440, 860)')
$patched = [regex]::Replace($patched, 'window\.Create\(L"[^"]*"', 'window.Create(L"ColdVPN"')
if ($patched -ne $text) {
    [IO.File]::WriteAllText($main, $patched, $utf8)
    Write-Host 'Window patched: ColdVPN, 440x860'
}

# 4. Name of the program file: ColdVPN.exe instead of split_vpn.exe. The product
#    and company names stay as they are: the settings folder depends on them.
$top = Join-Path (Get-Location) 'windows\CMakeLists.txt'
$text = [IO.File]::ReadAllText($top)
$patched = $text.Replace('set(BINARY_NAME "split_vpn")', 'set(BINARY_NAME "ColdVPN")')
if ($patched -ne $text) {
    [IO.File]::WriteAllText($top, $patched, $utf8)
    Write-Host 'Program file renamed to ColdVPN.exe'
}
$rc = Join-Path (Get-Location) 'windows\runner\Runner.rc'
$text = [IO.File]::ReadAllText($rc)
$patched = $text.Replace('VALUE "FileDescription", "split_vpn"', 'VALUE "FileDescription", "ColdVPN"')
if ($patched -ne $text) { [IO.File]::WriteAllText($rc, $patched, $utf8) }

# 4b. CMake remembers the install folder by the old target name; with a stale
#     cache the build stops with: No target "split_vpn". Start it clean once.
$cache = Join-Path (Get-Location) 'build\windows\x64\CMakeCache.txt'
if ((Test-Path $cache) -and (Select-String -Path $cache -Pattern 'TARGET_FILE_DIR:split_vpn' -Quiet)) {
    Write-Host 'Clearing the old build cache (the next build takes longer)...'
    Remove-Item (Join-Path (Get-Location) 'build\windows') -Recurse -Force
}

# 4a. Application icon.
$icon = Join-Path (Get-Location) 'assets\app_icon.ico'
if (Test-Path $icon) {
    Copy-Item $icon (Join-Path (Get-Location) 'windows\runner\resources\app_icon.ico') -Force
}

# 5. Close the running app: a running program file cannot be replaced (LNK1104).
#    It may be hidden in the tray. The tunnel is removed too, so that the
#    connection does not stay up without the app.
$running = Get-Process -Name 'ColdVPN', 'split_vpn' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host 'Closing the running ColdVPN...'
    $running | Stop-Process -Force
    $running | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue
    $awg = Join-Path $env:ProgramFiles 'AmneziaWG\amneziawg.exe'
    # Only when the tunnel service exists: otherwise the client shows an error box.
    $tunnel = Get-Service -Name 'AmneziaWGTunnel$ColdVPN' -ErrorAction SilentlyContinue
    if ($tunnel -and (Test-Path $awg)) {
        try {
            Start-Process -FilePath $awg -ArgumentList '/uninstalltunnelservice', 'ColdVPN' -Wait -WindowStyle Hidden
        } catch {}
    }
    Start-Sleep -Seconds 1
}

# 6. Build.
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
# Icons are bundled in full: incremental builds do not refresh the trimmed
# icon font, so newly used icons would be invisible.
flutter build windows --release --no-tree-shake-icons
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

Write-Host ''
# The program file used to be called split_vpn.exe; the old copy is stale.
$old = Join-Path (Get-Location) 'build\windows\x64\runner\Release\split_vpn.exe'
if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }

Write-Host 'Done. The app is in build\windows\x64\runner\Release\ (run ColdVPN.exe).'
