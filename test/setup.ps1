# Checks the machine windows/setup.ps1 left behind, on the real profile: CI
# runs it on a bare runner first, where it must fail, then after the setup.
$ErrorActionPreference = 'Stop'

$repoDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$failures = [System.Collections.Generic.List[string]]::new()
. (Join-Path $repoDirectory 'windows/git_bash.ps1')

$manifest = Get-Content -Raw -LiteralPath (Join-Path $repoDirectory 'windows/winget-packages.json') | ConvertFrom-Json
foreach ($package in $manifest.Sources.Packages) {
    $id = $package.PackageIdentifier
    winget list --id $id --exact --accept-source-agreements --disable-interactivity | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("winget does not list $id as installed.")
    }
}

$configPath = Join-Path $env:USERPROFILE '.codex/config.toml'
$firstDefault = (Get-Content -LiteralPath (Join-Path $repoDirectory 'codex/config.toml') |
    Where-Object { $_ -match '^\s*[A-Za-z0-9_-]+\s*=' } | Select-Object -First 1)
if (-not (Test-Path -LiteralPath $configPath) -or
    -not @(Get-Content -LiteralPath $configPath).Contains($firstDefault)) {
    $failures.Add("$configPath does not carry '$firstDefault'.")
}

$rulesLink = Join-Path $env:USERPROFILE '.claude/rules/dotfiles'
$rules = Get-Item -LiteralPath $rulesLink -Force -ErrorAction SilentlyContinue
$rulesSource = Join-Path $repoDirectory 'claudecode\rules'
# Windows PowerShell 5.1 reports a link to \\server\share as UNC\server\share.
$rulesTarget = if ($rules) { [string]@($rules.Target)[0] -replace '^UNC\\', '\\' }
if ($null -eq $rules -or $rules.LinkType -ne 'SymbolicLink' -or $rulesTarget -ne $rulesSource) {
    $failures.Add("~/.claude/rules/dotfiles is not a link to $rulesSource.")
}

$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'mac-keys.lnk'
if (-not (Test-Path -LiteralPath $shortcutPath)) {
    $failures.Add("$shortcutPath is missing.")
} else {
    $target = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath).TargetPath
    if ((Split-Path -Leaf $target) -ne 'AutoHotkey64.exe' -or -not (Test-Path -LiteralPath $target -PathType Leaf)) {
        $failures.Add("$shortcutPath starts $target, not an installed AutoHotkey64.exe.")
    }
}

# Read back through PowerToys' own tool, and "run at startup" from the task
# that does the starting: the setting alone would also pass with no task.
. (Join-Path $repoDirectory 'windows/powertoys_dsc.ps1')
$powerToysDsc = Find-PowerToysDsc
if (-not $powerToysDsc) {
    $failures.Add('PowerToys.DSC.exe is not installed.')
} else {
    foreach ($module in Get-PowerToysDrift $powerToysDsc) {
        $failures.Add("PowerToys $module differs from windows/powertoys-settings.json.")
    }
    if (-not (Test-PowerToysAutostart)) {
        $failures.Add('PowerToys has no run-at-startup task.')
    }
    if (-not (Test-CommandPaletteHotkey (Get-CommandPaletteSettingsPath) (Get-CommandPaletteWantedHotkey))) {
        $failures.Add("Command Palette's hotkey differs from windows/powertoys-settings.json.")
    }
}

$explorerPolicy = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
$noWinKeys = (Get-ItemProperty -LiteralPath $explorerPolicy -Name NoWinKeys -ErrorAction SilentlyContinue).NoWinKeys
if ($noWinKeys -ne 1) {
    $failures.Add("NoWinKeys is not 1 under $explorerPolicy; the shell still takes Win+<key>.")
}

# A staged secret must stop a commit: the config alone would also pass with a
# hook that never runs. PATH is read again as a new terminal would have it,
# since winget put gitleaks on it after this process started.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
    [Environment]::GetEnvironmentVariable('Path', 'User')
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("setup-check-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    # Assembled here so that this file holds nothing a scanner would flag.
    $token = 'ghp_' + 'a1B2c3D4e5F6g7H8i9J0' + 'k1L2m3N4o5P6q7R8'
    Set-Content -LiteralPath (Join-Path $scratch 'creds.txt') -Value "token = `"$token`""
    $ErrorActionPreference = 'Continue'
    $commit = @('-C', $scratch, '-c', 'user.name=check', '-c', 'user.email=check@example.invalid',
        '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'check')
    git -C $scratch init --quiet 2>&1 | Out-Null
    # A commit that must go through first, so a refusal below is the scan's
    # and not a repo that cannot commit at all.
    Set-Content -LiteralPath (Join-Path $scratch 'plain.txt') -Value 'nothing to find'
    git -C $scratch add plain.txt 2>&1 | Out-Null
    git @commit 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $failures.Add('git could not commit a harmless file in a scratch repo.')
    }
    git -C $scratch add creds.txt 2>&1 | Out-Null
    $refusal = (git @commit 2>&1 | Out-String)
    if ($LASTEXITCODE -eq 0 -or $refusal -notmatch 'gitleaks: commit refused') {
        $failures.Add('git committed a staged secret; the gitleaks pre-commit hook did not stop it.')
    }

    # The same secret must stop a commit Claude Code would run through its
    # PowerShell tool: the registered command, run as Claude Code runs it, in
    # Git Bash. --no-verify, so the scan is the hook's and not Git's.
    $settingsPath = Join-Path $env:USERPROFILE '.claude/settings.json'
    $scan = $null
    if (Test-Path -LiteralPath $settingsPath) {
        $scan = @((Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json).hooks.PreToolUse |
            Where-Object { ($_.matcher -split '\|') -contains 'PowerShell' } |
            ForEach-Object { $_.hooks } |
            Where-Object { $_.command -like '*claude_commit_secret_scan.sh*' }) | Select-Object -First 1
    }
    if ($null -eq $scan) {
        $failures.Add("$settingsPath runs no secret scan on PowerShell tool calls.")
    } else {
        # A file, not an argument: Windows PowerShell 5.1 drops the quotes
        # inside an argument it hands a native program.
        $hookFile = Join-Path $scratch 'hook.sh'
        [System.IO.File]::WriteAllText($hookFile, $scan.command + "`n")
        $payload = @{ tool_name = 'PowerShell'; cwd = $scratch
            tool_input = @{ command = 'git commit --no-verify -m check' } } | ConvertTo-Json -Compress
        $blocked = ($payload | & (Find-GitBash) ($hookFile -replace '\\', '/') 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 2 -or $blocked -notmatch 'looks like a secret') {
            $failures.Add("the Claude Code secret scan let a staged secret through (exit $LASTEXITCODE): $blocked")
        }
    }
    $ErrorActionPreference = 'Stop'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

# The review gate must stop a push typed through the PowerShell tool, run the
# way Claude Code runs it: the registered command, in Git Bash, with the
# payload on stdin. Registered alone would also pass with a path that does not
# reach the script, or a matcher that never fires.
$gate = $null
if (Test-Path -LiteralPath $settingsPath) {
    $settings = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
    $gate = @($settings.hooks.PreToolUse | Where-Object { @($_.matcher -split '\|') -contains 'PowerShell' } |
        ForEach-Object { $_.hooks } | Where-Object { $_.command -match 'claude_review_gate\.sh' })[0]
}
if ($null -eq $gate) {
    $failures.Add("$settingsPath has no review gate for the PowerShell tool.")
} else {
    $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("gate-check-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $scratch | Out-Null
    $savedState = $env:XDG_STATE_HOME
    try {
        $ErrorActionPreference = 'Continue'
        git -C $scratch init --quiet -b check 2>&1 | Out-Null
        git -C $scratch -c user.name=check -c user.email=check@example.invalid -c commit.gpgsign=false `
            commit --quiet --allow-empty -m check 2>&1 | Out-Null
        # A file, not bash -c: Windows PowerShell 5.1 drops the quotes inside
        # a native argument, and the command is all quotes.
        $hookFile = Join-Path $scratch 'hook.sh'
        [System.IO.File]::WriteAllText($hookFile, $gate.command + "`n")
        $payload = @{ hook_event_name = 'PreToolUse'; session_id = 'check'; cwd = $scratch
            tool_name = 'PowerShell'; tool_input = @{ command = 'git push -u origin check' }
        } | ConvertTo-Json -Compress
        # The gate's memory of stopped pushes stays out of the real profile.
        $env:XDG_STATE_HOME = (Join-Path $scratch 'state') -replace '\\', '/'
        $answer = ($payload | & (Find-GitBash) ($hookFile -replace '\\', '/') 2>&1 | Out-String)
        if ($answer -notmatch '"permissionDecision"\s*:\s*"deny"') {
            $failures.Add("the registered review gate let an unreviewed push through: $answer")
        }
        $ErrorActionPreference = 'Stop'
    } finally {
        $env:XDG_STATE_HOME = $savedState
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output "not ok: $_" }
    exit 1
}
Write-Output 'ok setup'
# Spelled out: the refused commit above left a non-zero $LASTEXITCODE, which
# PowerShell would otherwise hand back as this script's.
exit 0
