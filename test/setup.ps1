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

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output "not ok: $_" }
    exit 1
}
Write-Output 'ok setup'
