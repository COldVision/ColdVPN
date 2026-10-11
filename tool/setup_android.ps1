# Installs what is needed to build for Android (JDK, Android SDK), prepares the
# android/ folder and builds an APK into dist\ColdVPN-<version>.apk.
# Run through build_android.bat.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$project = Split-Path $PSScriptRoot -Parent
Set-Location $project
$utf8 = New-Object Text.UTF8Encoding $false

function Step($text) { Write-Host ''; Write-Host "==> $text" -ForegroundColor Cyan }

try {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw 'Flutter is not installed. Run install_and_build.bat first.'
    }

    # ---------------------------------------------------------------- JDK 17
    Step 'Java (JDK 17)'
    function Find-Jdk {
        $roots = @((Join-Path $env:ProgramFiles 'Microsoft'), (Join-Path $env:ProgramFiles 'Eclipse Adoptium'), (Join-Path $env:ProgramFiles 'Java'))
        foreach ($root in $roots) {
            if (-not (Test-Path $root)) { continue }
            $found = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^jdk-?17' -and (Test-Path (Join-Path $_.FullName 'bin\java.exe')) } |
                Sort-Object Name -Descending | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
        return $null
    }
    $jdk = Find-Jdk
    if (-not $jdk) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            throw 'winget is missing. Install JDK 17 by hand (https://learn.microsoft.com/java/openjdk/download) and run again.'
        }
        Write-Host 'Installing Microsoft OpenJDK 17...'
        winget install -e --id Microsoft.OpenJDK.17 --accept-source-agreements --accept-package-agreements --silent
        $jdk = Find-Jdk
    }
    if (-not $jdk) { throw 'JDK 17 was not found after installation.' }
    Write-Host "JDK: $jdk"
    $env:JAVA_HOME = $jdk
    $env:Path = (Join-Path $jdk 'bin') + ';' + $env:Path
    flutter config --jdk-dir "$jdk" | Out-Null

    # ----------------------------------------------------------- Android SDK
    Step 'Android SDK'
    $sdk = 'C:\Android\sdk'
    $sdkmanager = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
    if (-not (Test-Path $sdkmanager)) {
        Write-Host 'Downloading the Android command-line tools (about 150 MB)...'
        $zip = Join-Path $env:TEMP 'android-cmdline-tools.zip'
        $unpacked = Join-Path $env:TEMP 'android-cmdline-tools'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' -OutFile $zip
        if (Test-Path $unpacked) { Remove-Item $unpacked -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $unpacked -Force
        New-Item -ItemType Directory -Path (Join-Path $sdk 'cmdline-tools') -Force | Out-Null
        $target = Join-Path $sdk 'cmdline-tools\latest'
        if (Test-Path $target) { Remove-Item $target -Recurse -Force }
        Copy-Item (Join-Path $unpacked 'cmdline-tools') $target -Recurse
        Remove-Item $unpacked -Recurse -Force
        Remove-Item $zip -Force
    }
    if (-not (Test-Path $sdkmanager)) { throw 'The Android command-line tools were not installed.' }
    $env:ANDROID_HOME = $sdk
    $env:ANDROID_SDK_ROOT = $sdk
    [Environment]::SetEnvironmentVariable('ANDROID_HOME', $sdk, 'User')

    Write-Host 'Accepting the Android SDK licenses...'
    $answers = 1..100 | ForEach-Object { 'y' }
    $answers | & $sdkmanager "--sdk_root=$sdk" --licenses | Out-Null
    if (-not (Test-Path (Join-Path $sdk 'platform-tools'))) {
        Write-Host 'Installing platform-tools (the rest is downloaded during the build)...'
        & $sdkmanager "--sdk_root=$sdk" 'platform-tools'
        if ($LASTEXITCODE -ne 0) { throw 'sdkmanager failed to install platform-tools.' }
    }
    flutter config --android-sdk "$sdk" | Out-Null

    # -------------------------------------------------------- android/ folder
    Step 'Preparing the Android project'
    if (-not (Test-Path 'android\app')) {
        flutter create --platforms=android --project-name split_vpn --org com.coldvision .
        if ($LASTEXITCODE -ne 0) { throw 'flutter create failed' }
        if (Test-Path 'test\widget_test.dart') { Remove-Item 'test\widget_test.dart' }
    }

    # The tunnel code: our MainActivity replaces the generated one.
    $activity = Get-ChildItem 'android\app\src\main' -Recurse -Filter 'MainActivity.kt' | Select-Object -First 1
    if (-not $activity) { throw 'MainActivity.kt was not found in the generated Android project.' }
    $package = 'com.coldvision.split_vpn'
    $current = [IO.File]::ReadAllText($activity.FullName)
    if ($current -match '(?m)^package\s+([\w.]+)') { $package = $Matches[1] }
    $template = [IO.File]::ReadAllText((Join-Path $project 'android_src\MainActivity.kt.template'))
    [IO.File]::WriteAllText($activity.FullName, $template.Replace('__PACKAGE__', $package), $utf8)

    # Manifest: name, permissions and the list of launcher apps.
    $manifestPath = Join-Path $project 'android\app\src\main\AndroidManifest.xml'
    $manifest = [IO.File]::ReadAllText($manifestPath)
    $manifest = $manifest.Replace('android:label="split_vpn"', 'android:label="ColdVPN"')
    if ($manifest -notmatch 'coldvpn-permissions') {
        $extra = @'
    <!-- coldvpn-permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <queries>
        <intent>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent>
    </queries>

    <application
'@
        $index = $manifest.IndexOf('<application')
        if ($index -lt 0) { throw 'Unexpected AndroidManifest.xml: no <application> tag.' }
        $lineStart = $manifest.LastIndexOf("`n", $index) + 1
        $manifest = $manifest.Substring(0, $lineStart) + $extra + $manifest.Substring($index + '<application'.Length)
    }
    [IO.File]::WriteAllText($manifestPath, $manifest, $utf8)

    # Gradle: application id, minimum Android version and the tunnel library.
    $gradlePath = Join-Path $project 'android\app\build.gradle.kts'
    if (-not (Test-Path $gradlePath)) { $gradlePath = Join-Path $project 'android\app\build.gradle' }
    if (-not (Test-Path $gradlePath)) { throw 'android\app\build.gradle(.kts) was not found.' }
    $gradle = [IO.File]::ReadAllText($gradlePath)
    $gradle = [regex]::Replace($gradle, '(applicationId\s*=?\s*)"[^"]+"', '$1"com.coldvision.coldvpn"')
    $gradle = [regex]::Replace($gradle, 'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdk = 26')
    if ($gradle -notmatch 'amneziawg-android') {
        $gradle = $gradle.TrimEnd() + "`r`n`r`n// ColdVPN: the AmneziaWG tunnel.`r`ndependencies {`r`n    implementation(`"com.zaneschepke:amneziawg-android:2.3.7`")`r`n}`r`n"
    }
    [IO.File]::WriteAllText($gradlePath, $gradle, $utf8)
    # Rules for the code shrinker: keep the tunnel library intact.
    [IO.File]::WriteAllText((Join-Path $project 'android\app\proguard-rules.pro'),
        "-dontwarn javax.annotation.**`r`n-keep class org.amnezia.awg.** { *; }`r`n", $utf8)

    # Release signing with a permanent key. The key lives outside the project
    # (in Documents), so it survives a fresh clone and can be backed up. An
    # update installs over the old version only when the key is the same.
    $keyDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ColdVPN-signing'
    $keystore = Join-Path $keyDir 'coldvpn-release.jks'
    $passFile = Join-Path $keyDir 'password.txt'
    if (-not (Test-Path $keystore)) {
        Write-Host "Creating the signing key in $keyDir"
        New-Item -ItemType Directory -Path $keyDir -Force | Out-Null
        $chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
        $newPass = -join (1..24 | ForEach-Object { $chars | Get-Random })
        & (Join-Path $jdk 'bin\keytool.exe') -genkeypair -keystore $keystore -storetype PKCS12 `
            -keyalg RSA -keysize 2048 -validity 10000 -alias coldvpn `
            -storepass $newPass -keypass $newPass -dname 'CN=ColdVPN, O=ColdVision'
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $keystore)) { throw 'keytool failed to create the signing key.' }
        [IO.File]::WriteAllText($passFile, $newPass, $utf8)
        Write-Host 'IMPORTANT: back up this folder. Without the key, updates will not install over the old version.' -ForegroundColor Yellow
    }
    if (-not (Test-Path $passFile)) { throw "The key password file is missing: $passFile" }
    $keyPass = [IO.File]::ReadAllText($passFile).Trim()
    $keyPath = $keystore.Replace('\', '/')
    $gradle = [IO.File]::ReadAllText($gradlePath)
    if ($gradle -notmatch 'coldvpn-signing') {
        if ($gradlePath.EndsWith('.kts')) {
            $signing = @"

// coldvpn-signing: the permanent release key.
android {
    signingConfigs {
        create("coldvpn") {
            storeFile = file("$keyPath")
            storePassword = "$keyPass"
            keyAlias = "coldvpn"
            keyPassword = "$keyPass"
        }
    }
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("coldvpn")
        }
    }
}
"@
        } else {
            $signing = @"

// coldvpn-signing: the permanent release key.
android {
    signingConfigs {
        coldvpn {
            storeFile file("$keyPath")
            storePassword "$keyPass"
            keyAlias "coldvpn"
            keyPassword "$keyPass"
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.coldvpn
        }
    }
}
"@
        }
        [IO.File]::WriteAllText($gradlePath, $gradle.TrimEnd() + "`r`n" + $signing + "`r`n", $utf8)
    }

    # Launcher icon.
    Get-ChildItem (Join-Path $project 'android_src\res') -Directory | ForEach-Object {
        $destination = Join-Path $project ("android\app\src\main\res\" + $_.Name)
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item (Join-Path $_.FullName '*') $destination -Force
    }

    # ----------------------------------------------------------------- build
    Step 'Building the APK (the first build downloads a lot and takes a while)'
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
    flutter build apk --release --no-tree-shake-icons --target-platform android-arm,android-arm64
    if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed' }

    $version = '0.0.0'
    $match = Select-String -Path (Join-Path $project 'pubspec.yaml') -Pattern '^version:\s*([0-9.]+)' | Select-Object -First 1
    if ($match) { $version = $match.Matches[0].Groups[1].Value }
    $apk = Join-Path $project 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path $apk)) { throw "The APK was not found: $apk" }
    New-Item -ItemType Directory -Path (Join-Path $project 'dist') -Force | Out-Null
    $out = Join-Path $project "dist\ColdVPN-$version.apk"
    Copy-Item $apk $out -Force

    Step 'All done'
    Write-Host "The APK: $out" -ForegroundColor Green
    Write-Host 'Copy it to the phone and open it there to install.'
    Write-Host "Signed with the key from $keyDir (keep a backup of that folder)."
}
catch {
    Write-Host ''
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Copy the text of this window and send it to Claude.'
    exit 1
}
