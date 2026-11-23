# Registers the secret scan as a Git config-based pre-commit hook for this
# Windows user, as .gitconfig does on macOS and Linux: every commit on the
# machine is scanned, whoever runs it and from whichever shell. A hook inside
# Claude Code would only see the commits Claude makes, and only those typed
# through the tool its matcher names.
# Run from Windows PowerShell, from the checkout that stays (see setup.ps1).
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$HookScript = (Join-Path (Split-Path -Parent $PSScriptRoot) 'bin\git_hook_gitleaks.sh')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $HookScript -PathType Leaf)) {
    throw "Missing: $HookScript"
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git not found; install Git for Windows first.'
}
# Config-based hooks arrived in Git 2.54; an older Git ignores the section and
# nothing would be scanned, silently.
$version = [regex]::Match((git --version), '(\d+)\.(\d+)')
if (-not $version.Success -or
    [version]"$($version.Groups[1].Value).$($version.Groups[2].Value)" -lt [version]'2.54') {
    throw "Git 2.54 or newer is needed for config-based hooks; found '$(git --version)'."
}

# Git runs the command through its own sh, which reads forward slashes;
# \\wsl.localhost\... becomes //wsl.localhost/...
$path = $HookScript -replace '\\', '/'
# The -x guard keeps commits working while the checkout cannot be reached (WSL
# stopped), the same trade .gitconfig makes for a machine without ~/bin.
$command = "[ ! -x `"$path`" ] || `"$path`""

if ($PSCmdlet.ShouldProcess('git config --global hook.dotfiles-gitleaks', 'Register the secret scan')) {
    git config --global hook.dotfiles-gitleaks.event pre-commit
    if ($LASTEXITCODE -ne 0) { throw 'git config failed.' }
    git config --global hook.dotfiles-gitleaks.command $command
    if ($LASTEXITCODE -ne 0) { throw 'git config failed.' }
}
