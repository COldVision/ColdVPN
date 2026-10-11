# Prepares the project folder as a git repository and, if you agree, pushes it to GitHub
# and publishes a release with the files from dist\.
# Run through publish_to_github.bat.
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
Set-Location $project
$remote = 'https://github.com/ColdVision/ColdVPN.git'

function Step($text) { Write-Host ''; Write-Host "==> $text" -ForegroundColor Cyan }

try {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is not installed. Run install_and_build.bat first.' }

    Step 'Removing files that are no longer used'
    $stale = @(
        'lib\xray_config.dart', 'lib\core_manager.dart', 'assets\install_xray.sh',
        'lib\ui\home_page.dart', 'lib\ui\server_page.dart', 'tool\selection.json',
        'test\widget_test.dart', 'split_vpn.iml'
    )
    foreach ($file in $stale) {
        $path = Join-Path $project $file
        if (Test-Path $path) { Remove-Item $path -Force; Write-Host "removed $file" }
    }

    Step 'Preparing the repository'
    git config --global --add safe.directory ($project -replace '\\', '/')
    if (-not (Test-Path (Join-Path $project '.git'))) {
        git init -b main
        if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
    }
    if (-not (git config user.name)) {
        $name = Read-Host 'Your name for commits (for example ColdVision)'
        git config user.name $name
    }
    if (-not (git config user.email)) {
        $email = Read-Host 'Your e-mail for commits (GitHub shows it publicly; a GitHub noreply address works too)'
        git config user.email $email
    }

    git add -A
    if ($LASTEXITCODE -ne 0) { throw 'git add failed' }

    Step 'Files that will be published'
    git status --short
    $count = (git diff --cached --name-only | Measure-Object).Count
    if ($count -eq 0) {
        Write-Host 'Nothing new to commit.'
    } else {
        $message = Read-Host 'Commit message (Enter = "ColdVPN 0.1.0")'
        if (-not $message) { $message = 'ColdVPN 0.1.0' }
        git commit -m $message
        if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }
    }

    Step 'Publishing'
    Write-Host "Repository: $remote"
    Write-Host 'Everything listed above becomes PUBLIC if the repository is public.'
    $answer = Read-Host 'Push to GitHub now? (y/n)'
    # Also accept the Russian keyboard layout: the letter on the Y key and "da".
    $yes = @('y', 'yes', [string][char]0x43D, [string][char]0x434, ([string][char]0x434 + [string][char]0x430))
    if ($yes -notcontains $answer.Trim().ToLower()) {
        Write-Host 'Not pushed. The commit is saved locally; run this file again when ready.'
    } else {
        if (-not (git remote)) { git remote add origin $remote }
        # The repository on GitHub may already hold files created on the site
        # (README, LICENSE). Take them in first; where the same file exists in
        # both places, the local version wins.
        git fetch origin main
        if ($LASTEXITCODE -eq 0) {
            Write-Host 'Joining with what is already on GitHub...'
            git pull --rebase -X theirs origin main
            if ($LASTEXITCODE -ne 0) {
                git rebase --abort
                throw 'Could not join the local files with the files already on GitHub.'
            }
        }
        git push -u origin main
        if ($LASTEXITCODE -ne 0) { throw 'git push failed.' }
        Write-Host 'Published: https://github.com/ColdVision/ColdVPN' -ForegroundColor Green

        # ------------------------------------------------------------ release
        $version = '0.0.0'
        $match = Select-String -Path (Join-Path $project 'pubspec.yaml') -Pattern '^version:\s*([0-9.]+)' | Select-Object -First 1
        if ($match) { $version = $match.Matches[0].Groups[1].Value }
        $tag = "v$version"
        $notes = Join-Path $project "docs\release-$version.md"
        $files = @(@(
            (Join-Path $project "dist\ColdVPN-Setup-$version.exe"),
            (Join-Path $project "dist\ColdVPN-$version.apk")
        ) | Where-Object { Test-Path $_ })

        Step "Release $tag"
        if ($files.Count -eq 0) {
            Write-Host 'No files in dist\ for this version. Run build_installer.bat and build_android.bat first,'
            Write-Host 'then run this file again to publish the release.'
        } else {
            Write-Host 'Files for the release:'
            $files | ForEach-Object { Write-Host "  $_" }
            if ($files.Count -lt 2) { Write-Host 'Only one of the two files (installer, APK) was found.' -ForegroundColor Yellow }
            $answer = Read-Host "Publish release $tag now? (y/n)"
            if ($yes -contains $answer.Trim().ToLower()) {
                # The tag marks the commit the release was built from.
                git tag -f $tag
                git push -f origin $tag
                if ($LASTEXITCODE -ne 0) { throw 'Could not push the release tag.' }

                $gh = Get-Command gh -ErrorAction SilentlyContinue
                $ghReady = $false
                if ($gh) {
                    # gh writes to the error stream, which must not stop the script here.
                    $ErrorActionPreference = 'Continue'
                    try { gh auth status *> $null; $ghReady = ($LASTEXITCODE -eq 0) } catch { $ghReady = $false }
                    $ErrorActionPreference = 'Stop'
                }
                if ($ghReady) {
                    $ghArgs = @('release', 'create', $tag) + $files + @('--repo', 'ColdVision/ColdVPN', '--title', "ColdVPN $version")
                    if (Test-Path $notes) { $ghArgs += @('--notes-file', $notes) } else { $ghArgs += '--generate-notes' }
                    & gh @ghArgs
                    if ($LASTEXITCODE -ne 0) { throw 'gh could not create the release (it may already exist).' }
                    Write-Host "Release published: https://github.com/ColdVision/ColdVPN/releases/tag/$tag" -ForegroundColor Green
                } else {
                    # Without the GitHub CLI the last step is done in the browser:
                    # the page opens with the tag and title filled in, the text
                    # of the release is in the clipboard, the files are in the
                    # folder that opens next to it.
                    if (Test-Path $notes) { Get-Content $notes -Raw -Encoding UTF8 | Set-Clipboard }
                    Start-Process "https://github.com/ColdVision/ColdVPN/releases/new?tag=$tag&title=ColdVPN%20$version"
                    Start-Process explorer.exe (Join-Path $project 'dist')
                    Write-Host ''
                    Write-Host 'The release page is open in the browser. To finish:' -ForegroundColor Yellow
                    Write-Host '  1. Click into the description field and press Ctrl+V (the text is already copied).'
                    Write-Host '  2. Drag these files from the opened folder onto the page:'
                    $files | ForEach-Object { Write-Host "       $(Split-Path $_ -Leaf)" }
                    Write-Host '  3. Press "Publish release".'
                }
            } else {
                Write-Host 'The release was not published. Run this file again when ready.'
            }
        }
        Step 'All done'
    }
}
catch {
    Write-Host ''
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Copy the text of this window and send it to Claude.'
    exit 1
}
