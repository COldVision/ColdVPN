# Prepares the project folder as a git repository and, if you agree, pushes it to GitHub.
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
        $message = Read-Host 'Commit message (Enter = "ColdVPN 0.0.1")'
        if (-not $message) { $message = 'ColdVPN 0.0.1' }
        git commit -m $message
        if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }
    }

    Step 'Publishing'
    Write-Host "Repository: $remote"
    Write-Host 'Everything listed above becomes PUBLIC if the repository is public.'
    $answer = Read-Host 'Push to GitHub now? (y/n)'
    if ($answer -ne 'y') {
        Write-Host 'Not pushed. The commit is saved locally; run this file again when ready.'
    } else {
        if (-not (git remote)) { git remote add origin $remote }
        git push -u origin main
        if ($LASTEXITCODE -ne 0) {
            throw 'git push failed. If the repository on GitHub is not empty (for example it has a README), run: git pull --rebase origin main, then run this file again.'
        }
        Step 'All done'
        Write-Host 'Published: https://github.com/ColdVision/ColdVPN' -ForegroundColor Green
    }
}
catch {
    Write-Host ''
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Copy the text of this window and send it to Claude.'
    exit 1
}
