# One-command setup for "We're All Software Developers Now" on Windows.
#
# It does Session 1's setup and Session 2's "get your copy" steps for you, in order,
# using the same commands as docs/install-github-cli.md and docs/install-claude-code.md:
#   1. Git for Windows
#   2. The GitHub CLI (gh)
#   3. Claude Code
#   4. Signs you in to GitHub (you approve it in your browser)
#   5. Tells Git your name and Opensend email
#   6. Makes your fork, downloads it to your home folder, makes your branch
#   7. Runs the setup check
#
# Anything already done is skipped, so it's safe to run again. You don't need to run it as Administrator.
# It never sees your passwords or one-time codes: you type those yourself when asked.
#
# Run it in PowerShell:
#   irm https://raw.githubusercontent.com/fueled-io/os-claude-advanced-training/main/install.ps1 | iex
# or, from a downloaded copy:
#   powershell -ExecutionPolicy Bypass -File install.ps1

function Install-TrainingSetup {
  $Upstream = 'fueled-io/os-claude-advanced-training'
  $RepoName = 'os-claude-advanced-training'
  $RepoDir  = Join-Path $HOME $RepoName

  function Step($t)  { Write-Host ''; Write-Host "== $t" -ForegroundColor Cyan }
  function Ok($t)    { Write-Host "  OK    $t" -ForegroundColor Green }
  function Doing($t) { Write-Host "  ...   $t" }
  function Note($t)  { Write-Host "  NOTE  $t" -ForegroundColor Yellow }
  function Stop-Setup($what, $fix) { throw [System.Exception]::new("$what`n        $fix") }
  function Have($c)  { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
  function Ask($q, $d) {
    $prompt = if ($d) { "  $q [$d]" } else { "  $q" }
    $a = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($a)) { $d } else { $a.Trim() }
  }
  # New programs only show up in a terminal after it restarts. This makes them show up in this one now.
  function Update-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user;$HOME\.local\bin"
  }
  function Winget-Install($id, $label, $doc) {
    if (-not (Have 'winget')) {
      Stop-Setup "winget isn't available on this computer, so $label can't be installed automatically." "Install it by hand: $doc, then run this again."
    }
    Doing "winget install --id $id --source winget"
    winget install --id $id -e --source winget --accept-source-agreements --accept-package-agreements
    Update-Path
  }

  Write-Host "Setup for $RepoName" -ForegroundColor Cyan
  if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
    Stop-Setup 'This installer is for Windows.' 'On a Mac, use install.sh (see README.md).'
  }
  Update-Path

  Step '1. Git'
  if (-not (Have 'git')) {
    Winget-Install 'Git.Git' 'Git' 'download Git for Windows from https://git-scm.com/install/windows (docs/install-github-cli.md step 3)'
    if (-not (Have 'git')) { Stop-Setup "Git installed, but this window can't find it." 'Close this window, open a new PowerShell window, and run this again.' }
  }
  Ok (git --version)

  Step '2. GitHub CLI (gh)'
  if (-not (Have 'gh')) {
    Winget-Install 'GitHub.cli' 'the GitHub CLI' 'download the .msi from https://github.com/cli/cli/releases/latest (docs/install-github-cli.md step 4)'
    if (-not (Have 'gh')) { Stop-Setup "The GitHub CLI installed, but this window can't find it." 'Close this window, open a new PowerShell window, and run this again.' }
  }
  Ok ((gh --version) | Select-Object -First 1)

  Step '3. Claude Code'
  if (-not (Have 'claude')) {
    Doing 'Installing Claude Code. It shows no progress while it downloads; wait for it.'
    # Runs Anthropic's installer in its own PowerShell, so it can't close this one.
    powershell -NoProfile -ExecutionPolicy Bypass -Command 'irm https://claude.ai/install.ps1 | iex'
    Update-Path
    if (-not (Have 'claude')) { Stop-Setup "Claude Code isn't showing up in this window." 'Close every terminal window, open a new one, and run this again. Otherwise see docs/install-claude-code.md step 3.' }
  }
  Ok ((claude --version) | Select-Object -First 1)
  Note "Claude Desktop isn't installed by this script: download it from https://claude.com/download"

  Step '4. Sign in to GitHub'
  gh auth status *> $null
  if ($LASTEXITCODE -ne 0) {
    Note 'It shows a one-time code. Copy it, press Enter, paste it into the browser page, and approve.'
    Note 'If it asks anything else, press Enter to take the default.'
    gh auth login --hostname github.com --git-protocol https --web
    gh auth status *> $null
    if ($LASTEXITCODE -ne 0) { Stop-Setup "GitHub sign-in didn't finish." 'See docs/install-github-cli.md step 5.' }
  }
  Ok "Signed in as $(gh api user --jq .login)"

  Step '5. Tell Git who you are'
  $name  = git config --global user.name
  $email = git config --global user.email
  if (-not $name) {
    $name = Ask 'Your first and last name (for example: Alex Kim)'
    if (-not $name) { Stop-Setup 'Git needs your name.' 'Run this installer again and type it when asked.' }
    git config --global user.name "$name"
  }
  if ($email -notlike '*@opensend.com') {
    if ($email) { Note "Git's email is $email. The series uses your Opensend email." }
    $email = Ask 'Your Opensend email (for example: alex@opensend.com)' $email
    if (-not $email) { Stop-Setup 'Git needs your email.' 'Run this installer again and type it when asked.' }
    git config --global user.email "$email"
  }
  Ok "Name: $(git config --global user.name)"
  Ok "Email: $(git config --global user.email)"

  Step '6. Your copy of the repo'
  if (Test-Path (Join-Path $RepoDir '.git')) {
    Ok "Already downloaded: $RepoDir"
  } elseif (Test-Path $RepoDir) {
    Stop-Setup "$RepoDir already exists but isn't a copy of the repo." 'Move or rename that folder, then run this again.'
  } else {
    Doing "Making your fork on GitHub and downloading it to $RepoDir"
    Note 'Your fork is public, like Opensend''s repo. See CONTRIBUTING.md before your first commit.'
    Push-Location $HOME
    gh repo fork $Upstream --clone
    $forked = $LASTEXITCODE
    Pop-Location
    if ($forked -ne 0 -or -not (Test-Path (Join-Path $RepoDir '.git'))) {
      Stop-Setup "Making or downloading your fork didn't work." 'See README.md, "Get your copy of the repo".'
    }
    Ok "Downloaded: $RepoDir"
  }
  Set-Location $RepoDir

  $branch = git branch --show-current
  if ($branch -and $branch -ne 'main' -and $branch -ne 'master') {
    Ok "On your branch: $branch"
  } else {
    $suggested = ((git config user.name).ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
    $branch = Ask 'Name for your branch: first-last, lowercase' $suggested
    if (-not $branch) { Stop-Setup 'Your branch needs a name.' 'Run this installer again and type it when asked.' }
    # Use the branch if it exists here or on your fork already; otherwise make it.
    git switch $branch 2>$null
    if ($LASTEXITCODE -ne 0) { git switch -c $branch }
    if ($LASTEXITCODE -ne 0) { Stop-Setup "Couldn't make your branch '$branch'." 'See README.md, "Get your copy of the repo", step 4.' }
    Ok "On your branch: $branch"
  }

  Step '7. Setup check'
  powershell -ExecutionPolicy Bypass -File .claude\skills\check-setup\scripts\check-setup.ps1

  Write-Host ''
  Write-Host 'Done.' -ForegroundColor Green -NoNewline
  Write-Host ' Close this window and open a new PowerShell window, then:'
  Write-Host "  cd $RepoName"
  Write-Host '  claude'
  Write-Host 'The first time, sign in with your Opensend Claude account and say yes to trusting the folder.'
}

try {
  Install-TrainingSetup
} catch {
  Write-Host ''
  Write-Host "  STOP  $($_.Exception.Message)" -ForegroundColor Red
  Write-Host ''
  Write-Host '  Fix that, then run this installer again. It picks up where it left off.'
  Write-Host '  Stuck? Send Sean Larkin a Slack message with what you see above.'
}
