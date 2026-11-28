# What PowerToys should be set to (powertoys-settings.json) and how far the
# machine is from it, dot-sourced by the script that applies it and the check
# that reads it back. PowerToys.DSC.exe is PowerToys' own settings tool; it
# does not reach Command Palette, a separate package whose settings file is
# read and written here directly.

function Find-PowerToysDsc {
    # Per-user is what winget installs by default; Program Files is the machine-scope install.
    @((Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.DSC.exe'),
        (Join-Path $env:ProgramFiles 'PowerToys\PowerToys.DSC.exe')) |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

# Each module's wanted settings, as the --input argument PowerToys.DSC.exe takes.
function Get-PowerToysWanted([string]$Path = (Join-Path $PSScriptRoot 'powertoys-settings.json')) {
    $wanted = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    foreach ($module in $wanted.modules.psobject.Properties) {
        $argument = $module.Value | ConvertTo-Json -Depth 10 -Compress
        # Windows PowerShell 5.1 drops the quotes inside an argument it hands a
        # native program unless they are escaped; PowerShell 7 passes them as is.
        if ($PSVersionTable.PSVersion.Major -lt 7) { $argument = $argument -replace '"', '\"' }
        [pscustomobject]@{ Module = $module.Name; Argument = $argument }
    }
}

# The modules whose settings differ from the wanted ones. A module the tool
# cannot answer for counts as differing, so a broken tool is not read as done.
function Get-PowerToysDrift([string]$Dsc, [string]$Path = (Join-Path $PSScriptRoot 'powertoys-settings.json')) {
    foreach ($entry in Get-PowerToysWanted $Path) {
        # The whole output before the exit code: a pipeline cut short at the
        # first line can leave an earlier command's code in $LASTEXITCODE.
        $output = @(& $Dsc test --resource 'settings' --module $entry.Module --input $entry.Argument)
        $inDesiredState = $false
        if ($LASTEXITCODE -eq 0 -and $output.Count -gt 0) {
            try {
                $inDesiredState = [bool]($output[0] | ConvertFrom-Json)._inDesiredState
            } catch {
                $inDesiredState = $false
            }
        }
        if (-not $inDesiredState) { Write-Output $entry.Module }
    }
}

# "Run at startup" is this scheduled task, which PowerToys registers when it
# starts with the setting on; the setting alone starts nothing.
function Test-PowerToysAutostart {
    [bool](Get-ScheduledTask -TaskPath '\PowerToys\' -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -like 'Autorun for *' -and $_.State -ne 'Disabled' })
}

function Get-CommandPaletteSettingsPath {
    Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.CommandPalette_8wekyb3d8bbwe\LocalState\settings.json'
}

function Get-CommandPaletteWantedHotkey([string]$Path = (Join-Path $PSScriptRoot 'powertoys-settings.json')) {
    (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json).commandPaletteHotkey
}

# The hotkey Command Palette's settings file holds, or nothing while the file
# is missing or not yet whole.
function Get-CommandPaletteHotkey([string]$SettingsPath) {
    if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { return }
    try {
        (Get-Content -Raw -LiteralPath $SettingsPath | ConvertFrom-Json).Hotkey
    } catch {
        return
    }
}

# Whether Command Palette's settings file asks for the wanted hotkey. The key's
# name is left out: Command Palette writes the same key with or without it.
function Test-CommandPaletteHotkey([string]$SettingsPath, $Wanted) {
    $hotkey = Get-CommandPaletteHotkey $SettingsPath
    if ($null -eq $hotkey) { return $false }
    foreach ($part in 'win', 'ctrl', 'alt', 'shift', 'code') {
        if ($hotkey.$part -ne $Wanted.$part) { return $false }
    }
    $true
}

# Rewrites the top-level "Hotkey" object and nothing else: the rest of the
# file is Command Palette's own, in whatever shape its version writes, and a
# round trip through ConvertTo-Json would rewrite all of it.
function Set-CommandPaletteHotkey([string]$SettingsPath, $Wanted) {
    $text = [System.IO.File]::ReadAllText($SettingsPath)
    # "$" doubled, since a replacement string reads "$1" and the like as groups.
    $block = ('"Hotkey": ' + ($Wanted | ConvertTo-Json -Compress)).Replace('$', '$$')
    # The first match is the top-level one: Command Palette writes it first,
    # and Test-CommandPaletteHotkey below refuses the result if it was not.
    $pattern = [regex]'"Hotkey"\s*:\s*\{[^{}]*\}'
    $updated = $pattern.Replace($text, $block, 1)
    [System.IO.File]::WriteAllText($SettingsPath, $updated)
    if (-not (Test-CommandPaletteHotkey $SettingsPath $Wanted)) {
        [System.IO.File]::WriteAllText($SettingsPath, $text)
        throw "Could not set Command Palette's hotkey in $SettingsPath; the file is left as it was."
    }
}
