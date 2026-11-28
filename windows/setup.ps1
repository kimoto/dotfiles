# One command for a fresh Windows machine: the apps, then Codex and Claude
# config, the secret scan before every commit, the Claude Code hooks, then the
# AutoHotkey keys, the PowerToys settings and the policy that frees Win for
# them. Run from Windows PowerShell, from the main
# checkout the hotkeys should follow (see README.md, step 3):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu\<checkout>\windows\setup.ps1
# Safe to run again; each step skips what is already in place.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Invoke-Step([string]$Name, [scriptblock]$Body) {
    Write-Output "==> $Name"
    & $Body
}

Invoke-Step 'winget import' {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget not found; install App Installer from the Microsoft Store first.'
    }
    # --no-upgrade keeps a re-run from upgrading what is already installed:
    # PowerToys, for one, needs an uninstall to cross a large version gap.
    winget import --import-file (Join-Path $PSScriptRoot 'winget-packages.json') `
        --no-upgrade --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "winget import failed with exit code $LASTEXITCODE."
    }
}

Invoke-Step 'link_codex' {
    & (Join-Path $PSScriptRoot 'link_codex.ps1')
}

Invoke-Step 'install_git_hooks' {
    & (Join-Path $PSScriptRoot 'install_git_hooks.ps1')
}

Invoke-Step 'install_claude_hooks' {
    & (Join-Path $PSScriptRoot 'install_claude_hooks.ps1')
}

Invoke-Step 'install_mac_keys' {
    & (Join-Path $PSScriptRoot 'install_mac_keys.ps1')
}

Invoke-Step 'install_powertoys_settings' {
    & (Join-Path $PSScriptRoot 'install_powertoys_settings.ps1')
}

# Without it the shell takes Win+<key> before AutoHotkey's Ctrl remaps of the
# Mac keyboard's Command key matter (README.md, step 1).
Invoke-Step 'NoWinKeys' {
    $policy = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    # Not New-Item -Force: on a key that exists it drops the key's other values.
    if (-not (Test-Path -LiteralPath $policy)) {
        New-Item -Path $policy -Force | Out-Null
    }
    $current = (Get-ItemProperty -LiteralPath $policy -Name NoWinKeys -ErrorAction SilentlyContinue).NoWinKeys
    if ($current -ne 1) {
        New-ItemProperty -LiteralPath $policy -Name NoWinKeys -PropertyType DWord -Value 1 -Force | Out-Null
        Write-Output 'NoWinKeys set; sign out and back in for it to apply.'
    }
}

Write-Output 'setup done'
