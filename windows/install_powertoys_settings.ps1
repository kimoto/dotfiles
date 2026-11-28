# Sets PowerToys to powertoys-settings.json: run at startup, and the hotkeys
# that keep clear of the Mac-keyboard remaps (README.md, step 2), Command
# Palette's among them. Leaves a PowerToys that already matches alone, since
# applying a change restarts it.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'powertoys_dsc.ps1')

$dsc = Find-PowerToysDsc
if (-not $dsc) {
    throw 'PowerToys.DSC.exe not found; PowerToys 0.95 or later is needed.'
}
$powerToys = Join-Path (Split-Path -Parent $dsc) 'PowerToys.exe'
$paletteSettings = Get-CommandPaletteSettingsPath
$paletteHotkey = Get-CommandPaletteWantedHotkey
$drift = @(Get-PowerToysDrift $dsc)
$settingsMatch = $drift.Count -eq 0 -and (Test-PowerToysAutostart)
$paletteMatches = Test-CommandPaletteHotkey $paletteSettings $paletteHotkey
if ($settingsMatch -and $paletteMatches) {
    Write-Output 'PowerToys already matches powertoys-settings.json.'
    return
}

# A running PowerToys, its Settings window and Command Palette included, would
# write its own copy of the settings back over these, and it registers "run at
# startup" only while starting. Started again even when a setting could not be
# written, so a failure does not leave the machine without it.
function Invoke-WithPowerToysStopped([scriptblock]$Change) {
    $running = @(Get-Process -Name 'PowerToys*', 'Microsoft.CmdPal*' -ErrorAction SilentlyContinue)
    try {
        if ($running.Count -gt 0) {
            $running | Stop-Process -Force -ErrorAction SilentlyContinue
            $running | Wait-Process -Timeout 30 -ErrorAction SilentlyContinue
            $alive = @($running | Where-Object { -not $_.HasExited } | ForEach-Object { $_.Name })
            if ($alive.Count -gt 0) {
                throw "PowerToys did not stop ($($alive -join ', ')); close it and run this again."
            }
        }
        & $Change
    } finally {
        # A warning, so that it does not replace the error that got here.
        try {
            Start-Process -FilePath $powerToys
        } catch {
            Write-Warning "PowerToys could not be started again: $_"
        }
    }
}

if (-not $settingsMatch) {
    Invoke-WithPowerToysStopped {
        foreach ($entry in Get-PowerToysWanted | Where-Object { $drift -contains $_.Module }) {
            & $dsc set --resource 'settings' --module $entry.Module --input $entry.Argument | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "PowerToys.DSC.exe could not set $($entry.Module) (exit $LASTEXITCODE)."
            }
            Write-Output "PowerToys: set $($entry.Module)."
        }
    }
}

# After the settings above, which are what turn Command Palette on. It writes
# its settings file the first time PowerToys runs it, so on a new machine this
# waits for a whole file with a hotkey in it before stopping it to edit that.
if (-not $paletteMatches) {
    if (-not (Get-Process -Name PowerToys -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath $powerToys
    }
    $deadline = (Get-Date).AddSeconds(60)
    while ($null -eq (Get-CommandPaletteHotkey $paletteSettings)) {
        if ((Get-Date) -gt $deadline) {
            throw "Command Palette did not write $paletteSettings within 60 seconds of PowerToys starting."
        }
        Start-Sleep -Seconds 1
    }
    Invoke-WithPowerToysStopped {
        Set-CommandPaletteHotkey $paletteSettings $paletteHotkey
        Write-Output 'PowerToys: set the Command Palette hotkey.'
    }
}

# PowerToys registers its startup task a few seconds into starting, so this
# waits on it rather than returning before the setup's result can be checked.
$deadline = (Get-Date).AddSeconds(60)
while (-not (Test-PowerToysAutostart)) {
    if ((Get-Date) -gt $deadline) {
        throw 'PowerToys started but did not register its run-at-startup task within 60 seconds.'
    }
    Start-Sleep -Seconds 1
}
Write-Output 'PowerToys: runs at startup.'
