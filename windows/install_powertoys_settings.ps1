# Sets PowerToys to powertoys-settings.json: run at startup, and the hotkeys
# that keep clear of the Mac-keyboard remaps (README.md, step 2). Command
# Palette keeps its settings elsewhere and is not covered. Leaves a PowerToys
# that already matches alone, since applying a change restarts it.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'powertoys_dsc.ps1')

$dsc = Find-PowerToysDsc
if (-not $dsc) {
    throw 'PowerToys.DSC.exe not found; PowerToys 0.95 or later is needed.'
}
$drift = @(Get-PowerToysDrift $dsc)
if ($drift.Count -eq 0 -and (Test-PowerToysAutostart)) {
    Write-Output 'PowerToys already matches powertoys-settings.json.'
    return
}

# A running PowerToys, its Settings window included, would write its own copy
# of the settings back over these, and it registers "run at startup" only
# while starting. Started again even when a setting could not be written, so a
# failure does not leave the machine without it.
$running = @(Get-Process -Name 'PowerToys*' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    $running | Stop-Process -Force
    $running | Wait-Process -Timeout 30 -ErrorAction SilentlyContinue
}
try {
    foreach ($entry in Get-PowerToysWanted | Where-Object { $drift -contains $_.Module }) {
        & $dsc set --resource 'settings' --module $entry.Module --input $entry.Argument | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "PowerToys.DSC.exe could not set $($entry.Module) (exit $LASTEXITCODE)."
        }
        Write-Output "PowerToys: set $($entry.Module)."
    }
} finally {
    Start-Process -FilePath (Join-Path (Split-Path -Parent $dsc) 'PowerToys.exe')
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
