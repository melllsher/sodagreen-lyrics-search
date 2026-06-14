# Deploy sodagreen-lyrics-search to GitHub Pages
# Prerequisites: Git + GitHub CLI (gh), logged in via `gh auth login`

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
Set-Location $ProjectRoot

function Find-Git {
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $portable = Join-Path $ProjectRoot ".tools\mingit\cmd\git.exe"
    if (Test-Path $portable) { return $portable }
    $default = "C:\Program Files\Git\bin\git.exe"
    if (Test-Path $default) { return $default }
    throw "Git not found. Install: winget install Git.Git -e"
}

function Find-Gh {
    $cmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $portable = Join-Path $ProjectRoot ".tools\gh\bin\gh.exe"
    if (Test-Path $portable) { return $portable }
    $default = "C:\Program Files\GitHub CLI\gh.exe"
    if (Test-Path $default) { return $default }
    throw "GitHub CLI not found. Install: winget install GitHub.cli -e"
}

$git = Find-Git
$gh = Find-Gh
$gitDir = Split-Path $git -Parent
$env:Path = "$gitDir;$env:Path"

Write-Host "Using Git: $git"
Write-Host "Using GitHub CLI: $gh"

& $gh auth setup-git 2>$null | Out-Null

& $gh auth status 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Please login first: gh auth login"
}

$repoName = Split-Path $ProjectRoot -Leaf
$user = (& $gh api user -q .login).Trim()
Write-Host "GitHub user: $user"
Write-Host "Repository: $repoName"

if (-not (Test-Path ".git")) {
    & $git init
    & $git branch -M main
}

$files = @(
    ".gitignore",
    "index.html",
    "style.css",
    "script.js",
    "songs-data.js",
    "album-map.json",
    "import_lyrics.ps1",
    "assign_covers.ps1",
    "import_lyrics.py",
    "covers"
)

& $git add @files
$status = & $git status --porcelain
if ($status) {
    if (-not $env:GIT_AUTHOR_NAME) {
        $env:GIT_AUTHOR_NAME = $user
        $env:GIT_AUTHOR_EMAIL = "$user@users.noreply.github.com"
        $env:GIT_COMMITTER_NAME = $env:GIT_AUTHOR_NAME
        $env:GIT_COMMITTER_EMAIL = $env:GIT_AUTHOR_EMAIL
    }
    & $git commit -m "Deploy Sodagreen lyrics search site for GitHub Pages"
} else {
    Write-Host "No changes to commit."
}

$remoteUrl = "https://github.com/$user/$repoName.git"
$remotes = & $git remote 2>$null
if ($remotes -notcontains "origin") {
    & $git remote add origin $remoteUrl
} else {
    & $git remote set-url origin $remoteUrl
}

$repoExists = $false
try {
    & $gh repo view "$user/$repoName" 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) { $repoExists = $true }
} catch {}

if (-not $repoExists) {
    Write-Host "Creating public repository $user/$repoName ..."
    & $gh repo create $repoName --public --description "Sodagreen lyrics search (GitHub Pages)" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Repository may already exist, continuing ..."
    }
}

Write-Host "Pushing to origin main ..."
& $git push -u origin main

Write-Host "Enabling GitHub Pages (branch main, root) ..."
& $gh api --method POST "/repos/$user/$repoName/pages" `
    -f build_type=legacy `
    -f "source[branch]=main" `
    -f "source[path]=/" 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Host "Pages API call skipped (may already be enabled). Enable manually:"
    Write-Host "  Settings -> Pages -> Deploy from branch -> main / (root)"
}

$siteUrl = "https://$user.github.io/$repoName/"
Write-Host ""
Write-Host "Done!"
Write-Host "Site URL (may take 1-3 minutes): $siteUrl"
