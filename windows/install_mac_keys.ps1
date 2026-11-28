# Run from Windows PowerShell, from the checkout the hotkeys should follow: the
# main checkout over \\wsl.localhost, not a worktree that will be removed.
# Copies the launcher and points the Startup shortcut at it; mac-keys.ahk
# itself stays in the repo.
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BinDirectory = (Join-Path $env:USERPROFILE 'bin'),
    [string]$StartupDirectory = [Environment]::GetFolderPath('Startup'),
    # Per-user is what winget installs by default; Program Files is the machine-scope install.
    [string]$AutoHotkey = (@(
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
)

$ErrorActionPreference = 'Stop'
if (-not $AutoHotkey) {
    throw 'AutoHotkey v2 not found; pass -AutoHotkey <path to AutoHotkey64.exe>.'
}
$checkout = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $checkout '.git') -PathType Container)) {
    throw "$checkout is not a main checkout (a worktree's .git is a file); run this from the checkout that stays."
}
$script = Join-Path $PSScriptRoot 'autohotkey\mac-keys.ahk'
$launcherSource = Join-Path $PSScriptRoot 'autohotkey\launch-mac-keys.ahk'
foreach ($path in @($script, $launcherSource, $AutoHotkey)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing: $path"
    }
}
if ($script -notmatch '^\\\\wsl(\.localhost|\$)\\') {
    Write-Warning "$script is not under \\wsl.localhost; the launcher will refuse it at login."
}

$launcher = Join-Path $BinDirectory 'launch-mac-keys.ahk'
$shortcutPath = Join-Path $StartupDirectory 'mac-keys.lnk'

if ($PSCmdlet.ShouldProcess($launcher, 'Copy launcher')) {
    New-Item -ItemType Directory -Force -Path $BinDirectory | Out-Null
    Copy-Item -LiteralPath $launcherSource -Destination $launcher -Force
}
if ($PSCmdlet.ShouldProcess($shortcutPath, "Start $script at login")) {
    New-Item -ItemType Directory -Force -Path $StartupDirectory | Out-Null
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $AutoHotkey
    $shortcut.Arguments = "`"$launcher`" `"$script`""
    $shortcut.WorkingDirectory = $BinDirectory
    $shortcut.Save()
}

# A shortcut from the copy-it-by-hand setup would start a second, stale copy.
$shell = New-Object -ComObject WScript.Shell
Get-ChildItem -LiteralPath $StartupDirectory -Filter '*.lnk' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $shortcutPath } |
    ForEach-Object {
        $other = $shell.CreateShortcut($_.FullName)
        if ("$($other.TargetPath) $($other.Arguments)" -match 'mac-keys\.ahk') {
            Write-Warning "$($_.FullName) also starts mac-keys.ahk; delete it, or both run."
        }
    }
