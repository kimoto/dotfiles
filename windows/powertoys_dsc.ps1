# What PowerToys should be set to (powertoys-settings.json) and how far the
# machine is from it, dot-sourced by the script that applies it and the check
# that reads it back. PowerToys.DSC.exe is PowerToys' own settings tool.

function Find-PowerToysDsc {
    # Per-user is what winget installs by default; Program Files is the machine-scope install.
    @((Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.DSC.exe'),
        (Join-Path $env:ProgramFiles 'PowerToys\PowerToys.DSC.exe')) |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

# Each module's wanted settings, as the --input argument PowerToys.DSC.exe takes.
function Get-PowerToysWanted([string]$Path = (Join-Path $PSScriptRoot 'powertoys-settings.json')) {
    $wanted = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    foreach ($module in $wanted.psobject.Properties) {
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
