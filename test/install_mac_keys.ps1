$ErrorActionPreference = 'Stop'

$repoDirectory = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-install-mac-keys-{0}" -f [guid]::NewGuid())

# A copy of windows/ under a fake checkout, so the result does not depend on
# whether this test itself runs from a main checkout or a worktree.
function New-Checkout([string]$path, [bool]$isWorktree) {
    Copy-Item -Recurse -LiteralPath (Join-Path $repoDirectory 'windows') -Destination (Join-Path $path 'windows')
    if ($isWorktree) {
        Set-Content -LiteralPath (Join-Path $path '.git') -Value 'gitdir: elsewhere'
    } else {
        New-Item -ItemType Directory -Path (Join-Path $path '.git') | Out-Null
    }
}

try {
    New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
    # A runner's TEMP can be an 8.3 short path, and a shortcut reads back long.
    $sandbox = (Get-Item -LiteralPath $sandbox).FullName
    $binDirectory = Join-Path $sandbox 'bin'
    $startupDirectory = Join-Path $sandbox 'Startup'
    $autoHotkey = Join-Path $sandbox 'AutoHotkey64.exe'
    Set-Content -LiteralPath $autoHotkey -Value 'stand-in'

    $main = Join-Path $sandbox 'main'
    New-Checkout $main $false
    & (Join-Path $main 'windows/install_mac_keys.ps1') -BinDirectory $binDirectory `
        -StartupDirectory $startupDirectory -AutoHotkey $autoHotkey 3>$null

    $launcher = Join-Path $binDirectory 'launch-mac-keys.ahk'
    $launcherSource = Join-Path $repoDirectory 'windows/autohotkey/launch-mac-keys.ahk'
    if ((Get-FileHash $launcher).Hash -ne (Get-FileHash $launcherSource).Hash) {
        throw 'The launcher was not copied byte for byte.'
    }
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $startupDirectory 'mac-keys.lnk'))
    # Both sides through Get-Item, so a short and a long spelling of one path compare equal.
    if ((Get-Item -LiteralPath $shortcut.TargetPath).FullName -ne (Get-Item -LiteralPath $autoHotkey).FullName) {
        throw "Shortcut runs $($shortcut.TargetPath), not AutoHotkey."
    }
    $script = Join-Path $main 'windows\autohotkey\mac-keys.ahk'
    $expectedArguments = "`"$launcher`" `"$script`""
    if ($shortcut.Arguments -ne $expectedArguments) {
        throw "Shortcut arguments are $($shortcut.Arguments), expected $expectedArguments."
    }

    # A worktree's .git is a file; a shortcut into one breaks when it is removed.
    $worktree = Join-Path $sandbox 'worktree'
    New-Checkout $worktree $true
    $refused = $false
    try {
        & (Join-Path $worktree 'windows/install_mac_keys.ps1') -BinDirectory $binDirectory `
            -StartupDirectory $startupDirectory -AutoHotkey $autoHotkey -WhatIf 3>$null
    } catch {
        if ($_.Exception.Message -notmatch 'not a main checkout') { throw }
        $refused = $true
    }
    if (-not $refused) {
        throw 'The installer accepted a worktree.'
    }
} finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
