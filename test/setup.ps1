# Checks the machine windows/setup.ps1 left behind, on the real profile: CI
# runs it on a bare runner first, where it must fail, then after the setup.
$ErrorActionPreference = 'Stop'

$repoDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$failures = [System.Collections.Generic.List[string]]::new()

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
if ($null -eq $rules -or $rules.LinkType -ne 'SymbolicLink' -or [string]@($rules.Target)[0] -ne $rulesSource) {
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
    $ErrorActionPreference = 'Stop'
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output "not ok: $_" }
    exit 1
}
Write-Output 'ok setup'
# Spelled out: the refused commit above left a non-zero $LASTEXITCODE, which
# PowerShell would otherwise hand back as this script's.
exit 0
